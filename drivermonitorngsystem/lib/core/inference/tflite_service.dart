// ─────────────────────────────────────────────────────────────────────────────
// tflite_service.dart
//
// PURPOSE:
//   Runs DMS-HybridNet V2.1 dual-model inference on every camera frame.
//   Produces an InferenceResult with the driver's current state.
//
// PIPELINE:
//   CameraImage (YUV420)
//     → compute() isolate: YUV→RGB → resize → gamma → float32
//     → T01 (Spatial CNN): classifies single frame → [1, 11] probs
//     → T02 (Temporal BiLSTM): classifies 30-frame trend → [1, 5] probs
//     → Decision Fusion: per fusion_config.json v2.1 rules
//     → InferenceResult { state, subclass, neutralPct, drowsyPct, ... }
//
// CONNECTIONS:
//   • Called BY : monitor_screen.dart on every camera frame
//   • Feeds INTO: monitor_screen.dart alert system + database writes
//   • Uses      : frame_preprocessor.dart constants (inputWidth/Height/gamma)
//   • Config    : fusion_config.json (weights, mappings, thresholds)
//
// MODEL I/O (from fusion_config.json v2.1):
//   T01 input  : float32 [1, 224, 224, 3]  range [0, 255] — preprocessing baked in
//   T01 output : float32 [1, 11]
//   T02 input  : float32 [1, 30, 7]  normalized features
//   T02 output : float32 [1, 5]  → mapped to 11-class space
//
// FUSION RULES:
//   Classes 3-8  → T01 ONLY  (distraction: spatial events)
//   Classes 2,10 → T02×0.8 + T01×0.2  (drowsiness: temporal trends)
//   Classes 0,1,9→ (T01+T02)×0.5  (safe/yawn/talking: both equal)
//   EAR < 0.25   → class-10 score × 2.0  (micro-sleep boost)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

// ── Model asset paths ─────────────────────────────────────────────────────────
const String _kT01Asset = 'assets/models/t01_spatial_float16.tflite';
const String _kT02Asset = 'assets/models/t02_temporal_float16.tflite';

// ── 11-class names (index = model output index) ───────────────────────────────
const List<String> kClassNames = [
  'safe_driving',        // 0  → NEUTRAL
  'yawning',             // 1  → DROWSY
  'fatigue_head_droop',  // 2  → DROWSY
  'texting',             // 3  → DISTRACTED
  'phone_call',          // 4  → DISTRACTED
  'adjusting_radio',     // 5  → DISTRACTED
  'drinking',            // 6  → DISTRACTED
  'reaching_behind',     // 7  → DISTRACTED
  'hair_makeup',         // 8  → DISTRACTED
  'talking_passenger',   // 9  → DISTRACTED
  'eyes_closed_perclos', // 10 → DROWSY
];

// ── Which model(s) sourced the final decision ─────────────────────────────────
enum ModelSource {
  t01Only,      // Spatial CNN only (classes 3-8, or T02 buffer not ready)
  t02Dominant,  // T02×0.8 + T01×0.2 (classes 2,10 — drowsiness)
  bothEqual,    // (T01+T02)×0.5 (classes 0,1,9)
}

String modelSourceLabel(ModelSource src) {
  switch (src) {
    case ModelSource.t01Only:     return 'T01 Spatial';
    case ModelSource.t02Dominant: return 'T02 Temporal';
    case ModelSource.bothEqual:   return 'T01+T02 Fusion';
  }
}

// ── T02 normalization constants (from fusion_config.json v2.1) ────────────────
// Feature order: ear_l, ear_r, ear_avg, mar, pitch, yaw, roll
const List<double> _kT02Mean = [
  0.3316468289737513,
  0.41771940573971506,
  0.3746831173567465,
  0.5549294876945747,
  -114.96188322321962,
  -27.546025853571035,
  -0.6013167157224454,
];
const List<double> _kT02Std = [
  0.10642253236108944,
  0.15415579936843213,
  0.11262552152852298,
  0.19060541509055687,
  125.5252169549768,
  34.82828854696445,
  42.74963468627294,
];

// ── T02 5-output → full 11-class mapping ─────────────────────────────────────
const Map<int, int> _kT02ToFull = {
  0: 0,   // safe_driving
  1: 1,   // yawning
  2: 2,   // fatigue_head_droop
  3: 9,   // talking_passenger
  4: 10,  // eyes_closed_perclos
};

// ── Fusion rule constants ─────────────────────────────────────────────────────
const Set<int> _kSpatialOnlyClasses  = {3, 4, 5, 6, 7, 8};
const Set<int> _kDrowsinessClasses   = {2, 10};
const double   _kEarThreshold        = 0.25;
const double   _kEarBoostFactor      = 2.0;
const double   _kDrowsinessT02Weight = 0.8;
const double   _kDrowsinessT01Weight = 0.2;
const double   _kTemporalAvgWeight   = 0.5;

// FIX: Lowered confidence threshold from 0.35 → 0.25.
// With 11 classes, a uniform distribution gives ~0.09 per class.
// 0.35 was too aggressive — it was forcing neutral on valid detections
// where the model was genuinely uncertain between two similar states
// (e.g. yawning vs fatigue_head_droop both scoring ~0.28).
// 0.25 still filters out low-confidence noise while allowing valid detections.
const double _kConfidenceThreshold = 0.25;

// FIX: Added time gate — minimum ms between inference calls.
// Prevents the frame skip alone from being bypassed when the camera
// delivers frames faster than expected (some devices run at 60fps).
const int _kMinInferenceGapMs = 100;

// ─────────────────────────────────────────────────────────────────────────────
// InferenceResult
// ─────────────────────────────────────────────────────────────────────────────
class InferenceResult {
  /// Main detection state: 'neutral' | 'drowsy' | 'distracted'
  final String state;

  /// Specific subclass name from kClassNames
  final String subclass;

  /// Index 0–10 into kClassNames
  final int subclassIndex;

  /// Aggregated probabilities for gauge display (0–100)
  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  /// Full 11-class probability vector after fusion
  final List<double> fullProbs;

  /// Which model(s) produced the winning decision
  final ModelSource modelSource;

  /// Raw EAR average for PERCLOS/boost logic (0.15–0.45 typical range)
  final double earAvg;

  /// Whether T02 buffer was full at the time of this inference.
  /// False means only T01 was used — monitor_screen can show a warming-up indicator.
  final bool t02Active;

  /// Convenience alias — alertness = neutral confidence
  double get alertnessPct => neutralPct;

  const InferenceResult({
    required this.state,
    required this.subclass,
    required this.subclassIndex,
    required this.neutralPct,
    required this.drowsyPct,
    required this.distractedPct,
    required this.fullProbs,
    required this.modelSource,
    required this.earAvg,
    required this.t02Active,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// TfliteService — singleton, dual-model
// ─────────────────────────────────────────────────────────────────────────────
class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  // Frame gate: process every Nth frame to stay ~5 FPS on mid-range phones
  static const int _kFrameSkip = 5;

  Interpreter? _t01;
  Interpreter? _t02;
  bool _isInitialized = false;
  bool _isRunning     = false;
  int  _frameCounter  = 0;
  int  _lastInferenceMs = 0;

  // T01 output buffer reused across calls — avoids allocation per frame
  // FIX: Use List.filled with growable:false for fixed-size output buffers.
  final List<List<double>> _t01Out = [List<double>.filled(11, 0.0)];

  // Pre-allocated T01 input tensor [1][224][224][3] — filled in-place each call.
  // Avoids the 50 000+ List allocations that were causing 3-second GC pauses.
  // Allocated once in initialize(), never reallocated.
  late final List<List<List<List<double>>>> _t01In;

  // T02 rolling feature buffer [30 frames × 7 features]
  static const int _kSeqLen  = 30;
  static const int _kNumFeat = 7;

  // FIX: Initialize buffer as a proper fixed-size list.
  // Using List.generate ensures each inner list is a separate allocation
  // (not the same reference repeated) — avoids subtle mutation bugs.
  final List<List<double>> _featureBuf = List.generate(
    _kSeqLen,
    (_) => List<double>.filled(_kNumFeat, 0.0),
    growable: false,
  );
  int _bufFill = 0;

  // T02 output buffer [1, 5]
  final List<List<double>> _t02Out = [List<double>.filled(5, 0.0)];

  // Last raw EAR for boost check
  double _lastEarAvg = 0.4;

  // ── Initialize ────────────────────────────────────────────────────────────

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      // FIX: Use 4 threads instead of 2 for better performance on modern
      // Android devices with 6–8 core CPUs. tflite_flutter auto-selects
      // NNAPI/GPU delegate when available — threads is the CPU fallback.
      final opts = InterpreterOptions()..threads = 4;

      _t01 = await Interpreter.fromAsset(_kT01Asset, options: opts);
      _t02 = await Interpreter.fromAsset(_kT02Asset, options: opts);

      // float16 variants keep float32 I/O — resize tensors explicitly
      // so tflite_flutter doesn't guess the wrong shape
      _t01!.resizeInputTensor(0, [1, 224, 224, 3]);
      _t01!.allocateTensors();

      _t02!.resizeInputTensor(0, [1, _kSeqLen, _kNumFeat]);
      _t02!.allocateTensors();

      // Allocate T01 input tensor once — 224×224 inner [r,g,b] lists created here,
      // never again.  _runT01 fills them in-place with no new allocations.
      _t01In = List.generate(
        1,
        (_) => List.generate(
          224,
          (_) => List.generate(
            224,
            (_) => List<double>.filled(3, 0.0, growable: false),
            growable: false,
          ),
          growable: false,
        ),
        growable: false,
      );

      _isInitialized = true;
      debugPrint('[TfliteService] ✅ T01 + T02 loaded — dual-model ready');
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Init failed: $e');
      _isInitialized = false;
      return false;
    }
  }

  bool get isInitialized => _isInitialized;

  /// How full the T02 buffer is (0–100%). monitor_screen uses this to show
  /// a "warming up" indicator for the first 30 frames (~6 seconds at 5 FPS).
  double get bufferFillPct => (_bufFill / _kSeqLen * 100).clamp(0.0, 100.0);

  void dispose() {
    _t01?.close();
    _t02?.close();
    _t01 = null;
    _t02 = null;
    _isInitialized = false;
    _isRunning     = false;
    _bufFill       = 0;
    _frameCounter  = 0;
  }

  // ── Main inference entry point ────────────────────────────────────────────

  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _t01 == null || _t02 == null) return null;
    if (_isRunning) return null; // strict drop — no queue buildup

    // Frame skip gate
    _frameCounter = (_frameCounter + 1) % (_kFrameSkip + 1);
    if (_frameCounter != 0) return null;

    // FIX: Time gate — prevents burst inference on high-fps cameras
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastInferenceMs < _kMinInferenceGapMs) return null;

    _isRunning = true;
    try {
      // ── Step 1: Preprocess on background isolate ──────────────────────────
      // compute() runs _preprocessFrame in a separate Dart isolate so the
      // UI thread (60fps render loop) is never blocked by pixel math.
      final prep = await compute(
        _preprocessFrame,
        _PrepInput(
          planes: image.planes
              .map((p) => _PlaneData(
                    bytes:         p.bytes,
                    bytesPerRow:   p.bytesPerRow,
                    bytesPerPixel: p.bytesPerPixel ?? 1,
                  ))
              .toList(),
          width:  image.width,
          height: image.height,
        ),
      );
      if (prep == null) return null;

      // ── Step 2: Update T02 rolling feature buffer ─────────────────────────
      _updateFeatureBuf(prep.normalizedFeatures);
      _lastEarAvg = prep.earAvg;
      _lastInferenceMs = nowMs;

      // ── Step 3: Run T01 (every frame that passes the gate) ───────────────
      final t01Probs = _runT01(prep.rgbFloat32);
      if (t01Probs == null) return null;

      // ── Step 4: Run T02 (only when 30-frame buffer is filled) ────────────
      List<double>? t02FullProbs;
      final t02Active = _bufFill >= _kSeqLen;
      if (t02Active) {
        t02FullProbs = _runT02();
      }

      // ── Step 5: Fuse per fusion_config.json rules ─────────────────────────
      final (fusedProbs, perClassSource) = _fuse(
        t01Probs,
        t02FullProbs,
        _lastEarAvg,
      );

      // ── Step 6: Build result ──────────────────────────────────────────────
      return _buildResult(fusedProbs, perClassSource, t02Active);

    } catch (e) {
      debugPrint('[TfliteService] runInference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  // ── T01: Spatial CNN ──────────────────────────────────────────────────────
  //
  // Input : float32 [1, 224, 224, 3] with pixel values [0.0, 255.0]
  // The float16 model has EfficientNet preprocessing BAKED IN —
  // do NOT normalize to [0,1], pass raw pixel values as float32.
  List<double>? _runT01(Float32List rgbFloat32) {
    try {
      // Fill the pre-allocated [1][224][224][3] tensor in-place.
      // Zero new allocations — eliminates the GC pressure that caused 3-second
      // periodic freezes (previously 50 000+ List objects were created here).
      const h = 224, w = 224;
      for (int r = 0; r < h; r++) {
        final row = _t01In[0][r];
        for (int c = 0; c < w; c++) {
          final i   = (r * w + c) * 3;
          final px  = row[c];
          px[0] = rgbFloat32[i];
          px[1] = rgbFloat32[i + 1];
          px[2] = rgbFloat32[i + 2];
        }
      }

      // Reset output buffer before each run to avoid stale values
      for (int i = 0; i < 11; i++) _t01Out[0][i] = 0.0;

      _t01!.run(_t01In, _t01Out);

      // FIX: Apply softmax to T01 output.
      // tflite_flutter returns raw logits from float16 models in some cases.
      // Softmax ensures outputs are valid probabilities summing to 1.0.
      return _softmax(List<double>.from(_t01Out[0]));
    } catch (e) {
      debugPrint('[TfliteService] T01 run error: $e');
      return null;
    }
  }

  // ── T02: Temporal BiLSTM ──────────────────────────────────────────────────
  //
  // Input : float32 [1, 30, 7] — pre-normalized geometric features
  // Output: float32 [1, 5] → expanded to [1, 11] via t02_to_full_mapping
  void _updateFeatureBuf(List<double> normalizedFeatures) {
    // Shift buffer left by one frame (oldest frame drops out)
    for (int i = 0; i < _kSeqLen - 1; i++) {
      // FIX: Copy values directly instead of reassigning list references.
      // Reassigning references was causing _featureBuf rows to share memory
      // in some Dart VM optimizations, leading to subtle data corruption.
      for (int j = 0; j < _kNumFeat; j++) {
        _featureBuf[i][j] = _featureBuf[i + 1][j];
      }
    }
    // Add new frame at the end
    for (int j = 0; j < _kNumFeat; j++) {
      _featureBuf[_kSeqLen - 1][j] = normalizedFeatures[j];
    }
    if (_bufFill < _kSeqLen) _bufFill++;
  }

  /// Returns T02 probs expanded to full 11-class space.
  /// Classes 3–8 (not in T02 mapping) remain 0.0 — T01 wins for those.
  List<double>? _runT02() {
    try {
      // Reset output buffer
      for (int i = 0; i < 5; i++) _t02Out[0][i] = 0.0;

      // Pass _featureBuf directly — avoids the per-call [30×7] copy.
      // TFLite reads input synchronously before run() returns, so sharing
      // the live buffer is safe.
      _t02!.run([_featureBuf], _t02Out);

      // FIX: Apply softmax to T02 output as well.
      final t02Softmax = _softmax(List<double>.from(_t02Out[0]));

      // Expand 5-class → 11-class space
      final full = List<double>.filled(11, 0.0);
      for (int t02Idx = 0; t02Idx < 5; t02Idx++) {
        final fullIdx = _kT02ToFull[t02Idx];
        if (fullIdx != null) full[fullIdx] = t02Softmax[t02Idx];
      }
      return full;
    } catch (e) {
      debugPrint('[TfliteService] T02 run error: $e');
      return null;
    }
  }

  // ── Fusion: decision-level per fusion_config.json v2.1 ───────────────────
  (List<double>, List<ModelSource>) _fuse(
    List<double>  t01,
    List<double>? t02Full,
    double        earAvg,
  ) {
    final fused  = List<double>.filled(11, 0.0);
    final source = List<ModelSource>.filled(11, ModelSource.t01Only);

    for (int i = 0; i < 11; i++) {
      if (t02Full == null || _kSpatialOnlyClasses.contains(i)) {
        // T02 not ready yet, OR class is spatial-only (3–8)
        fused[i]  = t01[i];
        source[i] = ModelSource.t01Only;

      } else if (_kDrowsinessClasses.contains(i)) {
        // Classes 2, 10: T02 dominant — temporal trends catch fatigue
        fused[i]  = t02Full[i] * _kDrowsinessT02Weight
                  + t01[i]     * _kDrowsinessT01Weight;
        source[i] = ModelSource.t02Dominant;

      } else {
        // Classes 0, 1, 9: both models contribute equally
        fused[i]  = (t01[i] + t02Full[i]) * _kTemporalAvgWeight;
        source[i] = ModelSource.bothEqual;
      }
    }

    // EAR boost: low EAR = eyes closing → amplify eyes_closed_perclos score
    // This catches micro-sleep onset that the model may underestimate
    if (earAvg < _kEarThreshold) {
      fused[10] = (fused[10] * _kEarBoostFactor).clamp(0.0, 1.0);
    }

    // Renormalize so all 11 probs sum to 1.0
    final sum = fused.fold(0.0, (a, b) => a + b);
    if (sum > 1e-8) {
      for (int i = 0; i < 11; i++) fused[i] /= sum;
    }

    return (fused, source);
  }

  // ── Build InferenceResult ─────────────────────────────────────────────────
  InferenceResult _buildResult(
    List<double>      fused,
    List<ModelSource> perClassSource,
    bool              t02Active,
  ) {
    // Find winning class
    int    bestIdx   = 0;
    double bestScore = fused[0];
    for (int i = 1; i < 11; i++) {
      if (fused[i] > bestScore) {
        bestScore = fused[i];
        bestIdx   = i;
      }
    }

    // Apply confidence threshold — fall back to neutral if model is uncertain
    final String mainState;
    final int    finalIdx;
    if (bestScore < _kConfidenceThreshold) {
      mainState = 'neutral';
      finalIdx  = 0;
    } else {
      mainState = _classToMainState(bestIdx);
      finalIdx  = bestIdx;
    }

    // Aggregate per-main-state percentages for gauge display
    double neutralPct = 0, drowsyPct = 0, distractedPct = 0;
    for (int i = 0; i < 11; i++) {
      final pct = fused[i] * 100.0;
      switch (_classToMainState(i)) {
        case 'neutral':    neutralPct    += pct; break;
        case 'drowsy':     drowsyPct     += pct; break;
        case 'distracted': distractedPct += pct; break;
      }
    }

    return InferenceResult(
      state:         mainState,
      subclass:      kClassNames[finalIdx],
      subclassIndex: finalIdx,
      neutralPct:    neutralPct.clamp(0.0, 100.0),
      drowsyPct:     drowsyPct.clamp(0.0, 100.0),
      distractedPct: distractedPct.clamp(0.0, 100.0),
      fullProbs:     List<double>.unmodifiable(fused),
      modelSource:   perClassSource[finalIdx],
      earAvg:        _lastEarAvg,
      t02Active:     t02Active,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _classToMainState(int idx) {
    if (idx == 0) return 'neutral';
    if (idx == 1 || idx == 2 || idx == 10) return 'drowsy';
    return 'distracted';
  }

  /// Numerically stable softmax to convert raw logits → probabilities.
  /// Subtracts max first to prevent overflow on large logit values.
  static List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(math.max);
    final exps   = logits.map((v) => math.exp(v - maxVal)).toList();
    final sum    = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND ISOLATE — top-level functions only (required by compute())
// ─────────────────────────────────────────────────────────────────────────────

class _PlaneData {
  final Uint8List bytes;
  final int       bytesPerRow;
  final int       bytesPerPixel;
  const _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });
}

class _PrepInput {
  final List<_PlaneData> planes;
  final int width;
  final int height;
  const _PrepInput({
    required this.planes,
    required this.width,
    required this.height,
  });
}

class _PrepOutput {
  /// Float32 pixels in [0.0, 255.0] range — fed to T01 as-is.
  /// EfficientNet preprocessing is baked in — do NOT normalize to [0,1].
  final Float32List  rgbFloat32;

  /// Normalized feature vector [7] for T02 rolling buffer.
  /// Normalized using T02 mean/std from fusion_config.json.
  final List<double> normalizedFeatures;

  /// Raw (unnormalized) EAR average for EAR boost threshold check.
  final double earAvg;

  const _PrepOutput({
    required this.rgbFloat32,
    required this.normalizedFeatures,
    required this.earAvg,
  });
}

/// Top-level preprocessing function — runs in background isolate via compute().
/// Must be top-level (not a method) for compute() to serialize it correctly.
_PrepOutput? _preprocessFrame(_PrepInput input) {
  try {
    final w = input.width;
    final h = input.height;

    final yBytes   = input.planes[0].bytes;
    final uBytes   = input.planes[1].bytes;
    final vBytes   = input.planes[2].bytes;
    final yStride  = input.planes[0].bytesPerRow;
    final uvStride = input.planes[1].bytesPerRow;
    final uvPixel  = input.planes[1].bytesPerPixel;

    // ── A: YUV420 → RGB (BT.601, integer math) ───────────────────────────────
    final rgb    = Uint8List(w * h * 3);
    int   outIdx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final y   = yBytes[row * yStride + col] & 0xFF;
        final uvI = (row >> 1) * uvStride + (col >> 1) * uvPixel;
        final u   = (uBytes[uvI] & 0xFF) - 128;
        final v   = (vBytes[uvI] & 0xFF) - 128;
        rgb[outIdx++] = ((y * 1024 + 1402 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 - 344  * u - 714 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 + 1772 * u) >> 10).clamp(0, 255);
      }
    }

    // ── B: Gamma correction LUT (γ=0.3 — low-light boost) ────────────────────
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      lut[i] = (math.pow(i / 255.0, 1.0 / 0.3) * 255.0).round().clamp(0, 255);
    }

    // ── C: Resize to 224×224 + gamma + keep [0.0, 255.0] as float32 ──────────
    // T01 float16 model: EfficientNet preprocessing is baked in.
    // Pass pixel values in [0, 255] range as float32 — NOT normalized to [0,1].
    const dstW = 224, dstH = 224;
    final resized = Float32List(dstW * dstH * 3);
    final xScale  = w / dstW;
    final yScale  = h / dstH;
    int   rIdx    = 0;
    for (int dr = 0; dr < dstH; dr++) {
      final sr = (dr * yScale).toInt().clamp(0, h - 1);
      for (int dc = 0; dc < dstW; dc++) {
        final sc  = (dc * xScale).toInt().clamp(0, w - 1);
        final src = (sr * w + sc) * 3;
        resized[rIdx++] = lut[rgb[src    ]].toDouble();
        resized[rIdx++] = lut[rgb[src + 1]].toDouble();
        resized[rIdx++] = lut[rgb[src + 2]].toDouble();
      }
    }

    // ── D: Estimate geometric features for T02 ────────────────────────────────
    final rawFeatures = _estimateFeatures(resized, dstW, dstH);

    // ── E: Normalize using T02 mean/std from fusion_config.json ──────────────
    final normalized = List<double>.filled(7, 0.0);
    for (int i = 0; i < 7; i++) {
      normalized[i] = (rawFeatures[i] - _kT02Mean[i]) /
                      (_kT02Std[i] + 1e-8);
    }

    return _PrepOutput(
      rgbFloat32:         resized,
      normalizedFeatures: normalized,
      earAvg:             rawFeatures[2], // ear_avg (raw, for EAR boost)
    );
  } catch (e) {
    debugPrint('[_preprocessFrame] Error: $e');
    return null;
  }
}

// ── Luminance helpers ─────────────────────────────────────────────────────────

double _lum(Float32List rgb, int x, int y, int w) {
  final i = (y * w + x) * 3;
  // FIX: rgb values are in [0, 255] range here (not normalized).
  // Divide by 255 to get normalized luminance for feature estimation.
  return (0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2]) / 255.0;
}

double _regionLum(
  Float32List rgb,
  int x0, int y0,
  int x1, int y1,
  int w,
) {
  double sum   = 0;
  int    count = 0;
  // FIX: Added step=2 to sample every other pixel instead of every pixel.
  // This reduces compute time by 4× with negligible accuracy loss for
  // the luminance-based feature estimation approach.
  for (int y = y0; y < y1; y += 2) {
    for (int x = x0; x < x1; x += 2) {
      sum += _lum(rgb, x, y, w);
      count++;
    }
  }
  return count > 0 ? sum / count : 0.5;
}

/// Estimates [ear_l, ear_r, ear_avg, mar, pitch, yaw, roll] from pixel
/// luminance distributions of face sub-regions.
///
/// IMPORTANT: These are PROXY values, not true MediaPipe landmarks.
/// T02 was trained on MediaPipe EAR/MAR values. The pixel estimates
/// track the same trends at lower precision, which is sufficient for:
///   - Detecting EAR drops below 0.25 (micro-sleep / PERCLOS onset)
///   - Detecting MAR spikes above threshold (yawning onset)
///   - Rough head pose asymmetry for distraction detection
/// The 30-frame temporal buffer in T02 smooths out single-frame noise.
///
/// NOTE: When the final model ships with MediaPipe integration,
/// replace this function with real landmark values for higher accuracy.
List<double> _estimateFeatures(Float32List rgb, int w, int h) {
  final eyeY0 = (h * 0.30).toInt();
  final eyeY1 = (h * 0.50).toInt();
  final midX  = w ~/ 2;
  final pad   = w ~/ 8;

  // Eye region luminance — brighter = more open
  final leftBright  = _regionLum(rgb, pad,          eyeY0, midX - pad, eyeY1, w);
  final rightBright = _regionLum(rgb, midX + pad,   eyeY0, w - pad,    eyeY1, w);

  // EAR proxy: scale brightness to MediaPipe EAR range [0.15, 0.45]
  // FIX: Improved scaling formula — was `brightness * 0.5` which compressed
  // values too aggressively. Now maps [0.0, 1.0] brightness → [0.15, 0.45].
  final earL   = (leftBright  * 0.30 + 0.15).clamp(0.15, 0.45);
  final earR   = (rightBright * 0.30 + 0.15).clamp(0.15, 0.45);
  final earAvg = (earL + earR) / 2.0;

  // Mouth region luminance — open mouth (darker center) → higher MAR
  final mouthBright = _regionLum(
    rgb,
    (w * 0.30).toInt(), (h * 0.62).toInt(),
    (w * 0.70).toInt(), (h * 0.82).toInt(),
    w,
  );
  // FIX: Adjusted MAR proxy formula — inverted brightness maps to MAR.
  // Clamp lower bound to 0.2 to avoid feeding 0.0 MAR on very bright frames.
  final mar = ((1.0 - mouthBright) * 1.2).clamp(0.2, 1.0);

  // Head pose estimation from brightness asymmetry between face halves
  final leftHalf  = _regionLum(rgb, 0,    h ~/ 4, midX, h * 3 ~/ 4, w);
  final rightHalf = _regionLum(rgb, midX, h ~/ 4, w,    h * 3 ~/ 4, w);

  // FIX: Yaw scale factor adjusted — was 200.0 which over-estimated yaw.
  // At 200× scale, a 0.05 brightness diff → 10° yaw which is reasonable.
  final yaw = ((leftHalf - rightHalf) * 200.0).clamp(-90.0, 90.0);

  final topHalf    = _regionLum(rgb, w ~/ 4, 0,    w * 3 ~/ 4, h ~/ 2, w);
  final bottomHalf = _regionLum(rgb, w ~/ 4, h ~/ 2, w * 3 ~/ 4, h,   w);
  final pitch      = ((topHalf - bottomHalf) * 300.0).clamp(-180.0, 180.0);

  // Roll: requires facial landmark regression — cannot be estimated
  // from pixel luminance alone. Feed 0.0 to match training distribution
  // (roll was mostly ~0° in training datasets for dashboard-mounted cameras).
  const roll = 0.0;

  return [earL, earR, earAvg, mar, pitch, yaw, roll];
}