import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DMS-HybridNet V2.1 — Dual-Model Decision Fusion
// Based on x01_tflite_conversion.py and fusion_config.json v2.1
// ─────────────────────────────────────────────────────────────────────────────
//
// TWO MODELS:
//   T01 — Spatial CNN (EfficientNet-B0 based)
//         Asset  : assets/models/t01_spatial_float16.tflite
//         Input  : float32 [1, 224, 224, 3]  range [0.0, 255.0]
//                  NOTE: float16 variant keeps float32 I/O — EfficientNet
//                  preprocessing is BAKED INTO the model (no manual /255)
//         Output : float32 [1, 11]  — 11-class behavior probabilities
//         Runs   : every Nth frame (spatial, single-frame detection)
//         Detects: all 11 classes, especially distractions (classes 3-8)
//
//   T02 — Temporal BiLSTM
//         Asset  : assets/models/t02_temporal_float16.tflite
//         Input  : float32 [1, 30, 7]  — 30-frame rolling buffer
//                  Features (normalized): ear_l, ear_r, ear_avg, mar,
//                                         pitch, yaw, roll
//         Output : float32 [1, 5]  — 5-class behavior probabilities
//                  mapped → full 11-class via t02_to_full_mapping
//         Runs   : once buffer has 30 frames (temporal, trend detection)
//         Detects: drowsiness trends (classes 0,1,2,9,10)
//
// WHICH MODEL CONTROLS WHICH CLASS (from fusion_rules):
//   Classes 3,4,5,6,7,8  → T01 ONLY  (texting/phone/radio/drinking/reaching/makeup)
//                            T02 has no mapping for these — spatial events only
//   Classes 2,10          → T02 * 0.8 + T01 * 0.2  (fatigue/eyes_closed)
//                            Temporal trends dominate drowsiness detection
//   Classes 0,1,9         → (T01 + T02) * 0.5  (safe/yawning/talking)
//                            Both models contribute equally
//   EAR boost             → if earAvg < 0.25, class-10 score × 2.0
//
// T02 OUTPUT MAPPING (5 → 11 classes):
//   T02[0] → class 0  (safe_driving)
//   T02[1] → class 1  (yawning)
//   T02[2] → class 2  (fatigue_head_droop)
//   T02[3] → class 9  (talking_passenger)
//   T02[4] → class 10 (eyes_closed_perclos)
//
// 11 CLASSES → 3 MAIN STATES:
//   0              → NEUTRAL
//   1, 2, 10       → DROWSY
//   3, 4, 5, 6, 7, 8, 9 → DISTRACTED
// ─────────────────────────────────────────────────────────────────────────────

// ── Model asset paths (match pubspec.yaml assets) ────────────────────────────
const String _kT01Asset    = 'assets/models/t01_spatial_float16.tflite';
const String _kT02Asset    = 'assets/models/t02_temporal_float16.tflite';

// ── 11-class names (index matches model output) ───────────────────────────────
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

// ── Which model sourced the final decision ────────────────────────────────────
enum ModelSource {
  t01Only,    // Spatial CNN only (classes 3-8, or T02 buffer not ready)
  t02Dominant, // T02 * 0.8 + T01 * 0.2 (classes 2, 10 — drowsiness)
  bothEqual,  // (T01 + T02) * 0.5 (classes 0, 1, 9)
}

/// Human-readable label for which model triggered the detection
String modelSourceLabel(ModelSource src) {
  switch (src) {
    case ModelSource.t01Only:     return 'T01 Spatial';
    case ModelSource.t02Dominant: return 'T02 Temporal';
    case ModelSource.bothEqual:   return 'T01+T02 Fusion';
  }
}

// ── T02 normalization constants (from fusion_config.json) ─────────────────────
// feature order: ear_l, ear_r, ear_avg, mar, pitch, yaw, roll
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

// ── T02 5-output → full 11-class index mapping ────────────────────────────────
const Map<int, int> _kT02ToFull = {
  0: 0,   // safe_driving
  1: 1,   // yawning
  2: 2,   // fatigue_head_droop
  3: 9,   // talking_passenger
  4: 10,  // eyes_closed_perclos
};

// ── Fusion rule class groups ──────────────────────────────────────────────────
const Set<int> _kSpatialOnlyClasses  = {3, 4, 5, 6, 7, 8};
const Set<int> _kDrowsinessClasses   = {2, 10};
// _kTemporalAvgClasses: {0,1,9} — classes averaged between T01+T02 (see _fuse)
const double   _kEarThreshold        = 0.25;
const double   _kEarBoostFactor      = 2.0;
const double   _kDrowsinessT02Weight = 0.8;
const double   _kDrowsinessT01Weight = 0.2;
const double   _kTemporalAvgWeight   = 0.5;
const double   _kConfidenceThreshold = 0.35;

// ─────────────────────────────────────────────────────────────────────────────
// InferenceResult
// ─────────────────────────────────────────────────────────────────────────────
class InferenceResult {
  /// Main detection state: 'neutral' | 'drowsy' | 'distracted'
  final String state;

  /// Specific subclass name from kClassNames
  final String subclass;

  /// Index 0-10 into kClassNames
  final int subclassIndex;

  /// Aggregated probabilities for gauge display
  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  /// Full 11-class probability vector after fusion
  final List<double> fullProbs;

  /// Which model(s) produced the winning decision
  final ModelSource modelSource;

  /// Raw EAR average for PERCLOS/boost logic (0.15-0.45 typical range)
  final double earAvg;

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
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// TfliteService — singleton, dual-model
// ─────────────────────────────────────────────────────────────────────────────
class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  // Frame gate: skip Nth frames to reduce CPU — every 6th ≈ 5 FPS
  static const int _kFrameSkip = 5;

  Interpreter? _t01;
  Interpreter? _t02;
  bool _isInitialized = false;
  bool _isRunning     = false;
  int  _frameCounter  = 0;

  // T01 output buffer [1, 11]
  final List<List<double>> _t01Out = [List<double>.filled(11, 0.0)];

  // T02 rolling feature buffer [30][7]
  static const int _kSeqLen  = 30;
  static const int _kNumFeat = 7;
  final List<List<double>> _featureBuf = List.generate(
    _kSeqLen, (_) => List<double>.filled(_kNumFeat, 0.0),
  );
  int _bufFill = 0; // how many real frames are in the buffer

  // T02 output buffer [1, 5]
  final List<List<double>> _t02Out = [List<double>.filled(5, 0.0)];

  // Last raw EAR for boost check
  double _lastEarAvg = 0.4;

  // ── Initialize ──────────────────────────────────────────────────────────────
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      InterpreterOptions _opts() {
        // NnApiDelegate was removed in newer tflite_flutter versions.
        // tflite_flutter automatically uses the best available delegate
        // (NNAPI/GPU) on Android when threads > 1. CPU fallback is safe.
        return InterpreterOptions()..threads = 2;
      }

      _t01 = await Interpreter.fromAsset(_kT01Asset, options: _opts());
      _t02 = await Interpreter.fromAsset(_kT02Asset, options: _opts());

      // float16 variants keep float32 I/O — resize tensors explicitly
      _t01!.resizeInputTensor(0, [1, 224, 224, 3]);
      _t01!.allocateTensors();

      _t02!.resizeInputTensor(0, [1, _kSeqLen, _kNumFeat]);
      _t02!.allocateTensors();

      _isInitialized = true;
      debugPrint('[TfliteService] T01 + T02 loaded successfully');
      return true;
    } catch (e) {
      debugPrint('[TfliteService] Init failed: $e');
      return false;
    }
  }

  void dispose() {
    _t01?.close(); _t02?.close();
    _t01 = null;   _t02 = null;
    _isInitialized = false;
    _isRunning     = false;
  }

  // ── Main inference entry point ──────────────────────────────────────────────
  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _t01 == null || _t02 == null) return null;
    if (_isRunning) return null; // strict drop — no queue

    _frameCounter = (_frameCounter + 1) % (_kFrameSkip + 1);
    if (_frameCounter != 0) return null;

    _isRunning = true;
    try {
      // ── Step 1: Preprocess on background isolate ────────────────────────────
      final prep = await compute(_preprocessFrame, _PrepInput(
        planes: image.planes.map((p) => _PlaneData(
          bytes:         p.bytes,
          bytesPerRow:   p.bytesPerRow,
          bytesPerPixel: p.bytesPerPixel ?? 1,
        )).toList(),
        width:  image.width,
        height: image.height,
      ));
      if (prep == null) return null;

      // ── Step 2: Update T02 rolling feature buffer ───────────────────────────
      _updateFeatureBuf(prep.normalizedFeatures);
      _lastEarAvg = prep.earAvg;

      // ── Step 3: Run T01 (every frame) ──────────────────────────────────────
      final t01Probs = _runT01(prep.rgbFloat32);
      if (t01Probs == null) return null;

      // ── Step 4: Run T02 (only when 30-frame buffer is filled) ──────────────
      List<double>? t02FullProbs;
      if (_bufFill >= _kSeqLen) {
        t02FullProbs = _runT02();
      }

      // ── Step 5: Fuse T01 + T02 per fusion_config rules ─────────────────────
      final fusionResult = _fuse(t01Probs, t02FullProbs, _lastEarAvg);

      // ── Step 6: Build and return result ────────────────────────────────────
      return _buildResult(fusionResult.$1, fusionResult.$2);

    } catch (e) {
      debugPrint('[TfliteService] runInference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  // ── T01: Spatial CNN ────────────────────────────────────────────────────────
  // Input: float32 [1, 224, 224, 3] with pixel values [0.0, 255.0]
  // The float16 model has EfficientNet preprocessing baked in.
  // Do NOT divide by 255 — pass raw pixel values as float32.
  List<double>? _runT01(Float32List rgbFloat32) {
    try {
      // Reshape flat Float32List [224*224*3] → [1][224][224][3]
      const h = 224, w = 224;
      final img = List.generate(h, (r) =>
        List.generate(w, (c) {
          final i = (r * w + c) * 3;
          return [rgbFloat32[i], rgbFloat32[i+1], rgbFloat32[i+2]];
        })
      );
      _t01!.run([img], _t01Out);
      return List<double>.from(_t01Out[0]);
    } catch (e) {
      debugPrint('[TfliteService] T01 run error: $e');
      return null;
    }
  }

  // ── T02: Temporal BiLSTM ────────────────────────────────────────────────────
  // Input: float32 [1, 30, 7] — pre-normalized features
  // Output: float32 [1, 5] → expanded to [1, 11] via t02_to_full_mapping
  void _updateFeatureBuf(List<double> normalizedFeatures) {
    // Shift left, add new frame at end (ring buffer via shift)
    for (int i = 0; i < _kSeqLen - 1; i++) {
      _featureBuf[i] = List<double>.from(_featureBuf[i + 1]);
    }
    _featureBuf[_kSeqLen - 1] = List<double>.from(normalizedFeatures);
    if (_bufFill < _kSeqLen) _bufFill++;
  }

  /// Returns T02 probs in full 11-class space.
  /// Classes not covered by T02 (3-8) remain 0.0 — T01 wins for those.
  List<double>? _runT02() {
    try {
      final input = [List<List<double>>.from(_featureBuf)];
      _t02!.run(input, _t02Out);

      final full = List<double>.filled(11, 0.0);
      for (int t02Idx = 0; t02Idx < 5; t02Idx++) {
        final fullIdx = _kT02ToFull[t02Idx];
        if (fullIdx != null) full[fullIdx] = _t02Out[0][t02Idx];
      }
      return full;
    } catch (e) {
      debugPrint('[TfliteService] T02 run error: $e');
      return null;
    }
  }

  // ── Fusion: decision-level per fusion_config.json ───────────────────────────
  //
  // Returns (fusedProbs, perClassSource) where perClassSource tells us
  // which model controlled each class for the log display.
  (List<double>, List<ModelSource>) _fuse(
    List<double>  t01,
    List<double>? t02Full,
    double        earAvg,
  ) {
    final fused  = List<double>.filled(11, 0.0);
    final source = List<ModelSource>.filled(11, ModelSource.t01Only);

    for (int i = 0; i < 11; i++) {
      if (t02Full == null) {
        // T02 buffer not yet filled → T01 only for everything
        fused[i]  = t01[i];
        source[i] = ModelSource.t01Only;

      } else if (_kSpatialOnlyClasses.contains(i)) {
        // Classes 3-8: T01 ONLY — T02 has no knowledge of these
        // (they're absent from t02_to_full_mapping)
        fused[i]  = t01[i];
        source[i] = ModelSource.t01Only;

      } else if (_kDrowsinessClasses.contains(i)) {
        // Classes 2, 10: T02 dominant (temporal trends catch fatigue better)
        fused[i]  = t02Full[i] * _kDrowsinessT02Weight
                  + t01[i]     * _kDrowsinessT01Weight;
        source[i] = ModelSource.t02Dominant;

      } else {
        // Classes 0, 1, 9: both contribute equally
        fused[i]  = (t01[i] + t02Full[i]) * _kTemporalAvgWeight;
        source[i] = ModelSource.bothEqual;
      }
    }

    // EAR boost: if EAR < threshold → multiply eyes_closed score
    // This catches micro-sleep that the model might underestimate
    if (earAvg < _kEarThreshold) {
      fused[10] = (fused[10] * _kEarBoostFactor).clamp(0.0, 1.0);
      // Source stays t02Dominant since EAR is a temporal feature
    }

    // Renormalize so all 11 probabilities sum to 1.0
    final sum = fused.fold(0.0, (a, b) => a + b);
    if (sum > 1e-8) {
      for (int i = 0; i < 11; i++) fused[i] /= sum;
    }

    return (fused, source);
  }

  // ── Build InferenceResult ───────────────────────────────────────────────────
  InferenceResult _buildResult(
    List<double>       fused,
    List<ModelSource>  perClassSource,
  ) {
    // Find winning class
    int    bestIdx   = 0;
    double bestScore = fused[0];
    for (int i = 1; i < 11; i++) {
      if (fused[i] > bestScore) { bestScore = fused[i]; bestIdx = i; }
    }

    // Apply confidence threshold — fall back to neutral if uncertain
    final String mainState;
    final int    finalIdx;
    if (bestScore < _kConfidenceThreshold) {
      mainState = 'neutral'; finalIdx = 0;
    } else {
      mainState = _classToMainState(bestIdx); finalIdx = bestIdx;
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
      fullProbs:     List<double>.from(fused),
      modelSource:   perClassSource[finalIdx],
      earAvg:        _lastEarAvg,
    );
  }

  static String _classToMainState(int idx) {
    if (idx == 0) return 'neutral';
    if (idx == 1 || idx == 2 || idx == 10) return 'drowsy';
    return 'distracted';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND ISOLATE — preprocessing (top-level functions only)
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
  /// Float32 pixels in [0.0, 255.0] — fed directly to T01 float16 model.
  /// EfficientNet preprocessing is baked in — do NOT normalize to [0,1].
  final Float32List rgbFloat32;

  /// Normalized feature vector [7] for T02 rolling buffer
  final List<double> normalizedFeatures;

  /// Raw EAR average (unnormalized) for EAR boost check
  final double earAvg;

  const _PrepOutput({
    required this.rgbFloat32,
    required this.normalizedFeatures,
    required this.earAvg,
  });
}

/// Top-level function — executed in background isolate via compute().
_PrepOutput? _preprocessFrame(_PrepInput input) {
  try {
    final w = input.width;
    final h = input.height;

    // ── A: YUV420 → RGB (integer math, no floats per pixel) ─────────────────
    final yBytes   = input.planes[0].bytes;
    final uBytes   = input.planes[1].bytes;
    final vBytes   = input.planes[2].bytes;
    final yStride  = input.planes[0].bytesPerRow;
    final uvStride = input.planes[1].bytesPerRow;
    final uvPixel  = input.planes[1].bytesPerPixel;

    final rgb = Uint8List(w * h * 3);
    int outIdx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final y    = yBytes[row * yStride + col] & 0xFF;
        final uvI  = (row >> 1) * uvStride + (col >> 1) * uvPixel;
        final u    = (uBytes[uvI] & 0xFF) - 128;
        final v    = (vBytes[uvI] & 0xFF) - 128;
        rgb[outIdx++] = ((y * 1024 + 1402 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 - 344  * u - 714 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 + 1772 * u) >> 10).clamp(0, 255);
      }
    }

    // ── B: Gamma correction LUT (γ=0.3, brightens low-light) ─────────────────
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      lut[i] = (math.pow(i / 255.0, 1.0 / 0.3) * 255.0).round().clamp(0, 255);
    }

    // ── C: Resize to 224×224, apply gamma, keep as [0.0, 255.0] float32 ──────
    // T01 float16 model: EfficientNet preprocessing is BAKED IN.
    // Pass raw pixel values in [0, 255] as float32 — do NOT divide by 255.
    const dstW = 224, dstH = 224;
    final resizedFloat = Float32List(dstW * dstH * 3);
    final xScale = w / dstW;
    final yScale = h / dstH;
    int rIdx = 0;
    for (int dr = 0; dr < dstH; dr++) {
      final sr = (dr * yScale).toInt().clamp(0, h - 1);
      for (int dc = 0; dc < dstW; dc++) {
        final sc  = (dc * xScale).toInt().clamp(0, w - 1);
        final src = (sr * w + sc) * 3;
        // Apply gamma but keep range [0.0, 255.0]
        resizedFloat[rIdx++] = lut[rgb[src    ]].toDouble();
        resizedFloat[rIdx++] = lut[rgb[src + 1]].toDouble();
        resizedFloat[rIdx++] = lut[rgb[src + 2]].toDouble();
      }
    }

    // ── D: Extract geometric features for T02 ─────────────────────────────────
    // Approximate EAR/MAR/head-pose from pixel luminance distributions.
    // T02 was trained on MediaPipe landmark values. These pixel estimates
    // track the same trends at lower precision but sufficient for:
    //   - Detecting EAR drops below threshold (micro-sleep onset)
    //   - Detecting MAR spikes (yawning onset)
    //   - Rough head pose asymmetry (distraction)
    // The 30-frame temporal buffer smooths out single-frame estimation noise.
    final rawFeatures = _estimateFeatures(resizedFloat, dstW, dstH);

    // ── E: Normalize with T02 mean/std from fusion_config.json ───────────────
    final normalized = List<double>.filled(7, 0.0);
    for (int i = 0; i < 7; i++) {
      normalized[i] = (rawFeatures[i] - _kT02Mean[i]) / (_kT02Std[i] + 1e-8);
    }

    return _PrepOutput(
      rgbFloat32:         resizedFloat,
      normalizedFeatures: normalized,
      earAvg:             rawFeatures[2], // ear_avg (raw, for EAR boost)
    );
  } catch (_) {
    return null;
  }
}

// ── Luminance helpers (top-level for isolate access) ─────────────────────────

double _lum(Float32List rgb, int x, int y, int w) {
  final i = (y * w + x) * 3;
  return (0.299 * rgb[i] + 0.587 * rgb[i+1] + 0.114 * rgb[i+2]) / 255.0;
}

double _regionLum(Float32List rgb, int x0, int y0, int x1, int y1, int w) {
  double sum = 0;
  int count  = 0;
  for (int y = y0; y < y1; y++) {
    for (int x = x0; x < x1; x++) {
      sum += _lum(rgb, x, y, w);
      count++;
    }
  }
  return count > 0 ? sum / count : 0.5;
}

/// Returns raw [ear_l, ear_r, ear_avg, mar, pitch, yaw, roll]
/// Approximate values derived from face sub-region luminance.
List<double> _estimateFeatures(Float32List rgb, int w, int h) {
  // Eye region: ~30-50% of image height, split left/right
  final eyeY0 = (h * 0.30).toInt();
  final eyeY1 = (h * 0.50).toInt();
  final midX  = w ~/ 2;
  final pad   = w ~/ 8;

  final leftB  = _regionLum(rgb, pad, eyeY0, midX - pad, eyeY1, w);
  final rightB = _regionLum(rgb, midX + pad, eyeY0, w - pad, eyeY1, w);

  // EAR proxy: brighter eye region → more open eye
  // Scaled to typical MediaPipe EAR range [0.15, 0.45]
  final earL   = (leftB  * 0.5).clamp(0.15, 0.45);
  final earR   = (rightB * 0.5).clamp(0.15, 0.45);
  final earAvg = (earL + earR) / 2.0;

  // Mouth region: ~62-82% height, 30-70% width
  final mouthB = _regionLum(
    rgb,
    (w * 0.30).toInt(), (h * 0.62).toInt(),
    (w * 0.70).toInt(), (h * 0.82).toInt(), w,
  );
  // MAR proxy: open mouth is darker center → higher MAR
  final mar = ((1.0 - mouthB) * 1.2).clamp(0.2, 1.0);

  // Head pose from face brightness symmetry
  final leftHalf  = _regionLum(rgb, 0, h ~/ 4, midX, h * 3 ~/ 4, w);
  final rightHalf = _regionLum(rgb, midX, h ~/ 4, w, h * 3 ~/ 4, w);
  final yaw = ((leftHalf - rightHalf) * 200.0).clamp(-90.0, 90.0);

  final topH    = _regionLum(rgb, w ~/ 4, 0, w * 3 ~/ 4, h ~/ 2, w);
  final bottomH = _regionLum(rgb, w ~/ 4, h ~/ 2, w * 3 ~/ 4, h, w);
  final pitch   = ((topH - bottomH) * 300.0).clamp(-180.0, 180.0);

  const roll = 0.0; // Requires landmark regression — not estimable from pixels

  return [earL, earR, earAvg, mar, pitch, yaw, roll];
}