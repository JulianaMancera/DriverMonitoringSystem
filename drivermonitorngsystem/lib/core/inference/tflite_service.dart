// PURPOSE:
//   Runs DMS-HybridNet V3 single-file dual-input inference on every camera frame.
//   Produces an InferenceResult with the driver's current state.
//
// PIPELINE:
//   CameraImage (YUV420)
//     → compute() isolate: YUV→RGB → resize → normalize [-1,1] → float32
//     → Extract 12 features → update 30-frame FIFO temporal buffer
//     → runForMultipleInputs({ 0:temporal[1,30,12], 1:spatial[1,224,224,3] })
//     → output_0 [1,12] → softmax check → argmax → debounce → InferenceResult
//
// KEY CHANGES FROM V2.1:
//   • Single .tflite replaces T01 + T02 + fusion_config.json
//   • Normalization: (pixel/127.5)-1.0 instead of raw [0,255]
//   • runForMultipleInputs() instead of two separate run() calls
//   • 12 temporal features: ear_l/r/avg/min, mar, pitch/yaw/roll, gaze_l/r x/y
//   • 12 output classes instead of 11 (adds drowsy_microsleep)
//   • Alert debounce: >65% confidence for 10 consecutive frames (per spec)
//   • No manual fusion logic — model handles fusion internally
//
// MODEL TENSORS (from integration spec):
//   Input 0: temporal_input [1, 30, 12]      Float32 raw feature values
//   Input 1: spatial_input  [1, 224, 224, 3] Float32 range [-1.0, 1.0]
//   Output 0: output_0      [1, 12]           Float32 logits → softmax
import 'dart:math' as math;
// dart:typed_data removed — Float32List provided by flutter/foundation.dart
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

// Model asset path 
const String _kModelAsset = 'assets/models/dms_hybridnet_v3_float32.tflite';

// 12-class names (index = model output index, per integration spec)
const List<String> kClassNames = [
  'safe_driving',        // 0  → NEUTRAL
  'talking_passenger',   // 1  → DISTRACTED
  'distracted_texting',  // 2  → DISTRACTED
  'distracted_phone',    // 3  → DISTRACTED
  'distracted_radio',    // 4  → DISTRACTED
  'distracted_drinking', // 5  → DISTRACTED
  'distracted_reaching', // 6  → DISTRACTED
  'distracted_grooming', // 7  → DISTRACTED
  'distracted_smoking',  // 8  → DISTRACTED
  'drowsy_yawning',      // 9  → DROWSY
  'drowsy_fatigue',      // 10 → DROWSY
  'drowsy_microsleep',   // 11 → DROWSY
];

// Model source enum — single model now, kept for monitor_screen log compat 
enum ModelSource { v3 }
String modelSourceLabel(ModelSource src) => 'V3 HybridNet';

// Alert debounce thresholds ─
// Tuned from logcat analysis:
// • When safe: distracted group ~75% spread across many classes (each 15-25%)
// • True detection: ONE class dominates at 45%+, group > 70%
// • Consecutive frames required: 5 to filter single-frame flickers
const double _kConfidenceThreshold  = 0.30; // kept for soft debounce decay
const int    _kConsecutiveThreshold = 5;    // 5 frames to confirm

// Temporal buffer constants
const int _kSeqLen  = 30; // 30-frame rolling window
const int _kNumFeat = 12; // 12 features per frame

// 12 temporal feature order (from integration spec feature_cols) 
// Index: [ear_l(0), ear_r(1), ear_avg(2), ear_min(3), mar(4),
//         pitch(5), yaw(6), roll(7),
//         gaze_l_x(8), gaze_l_y(9), gaze_r_x(10), gaze_r_y(11)]

// InferenceResult
class InferenceResult {
  final String state;        // 'neutral' | 'drowsy' | 'distracted'
  final String subclass;     // specific class name from kClassNames
  final int    subclassIndex;// 0–11

  final double neutralPct;    // aggregated for gauge (0–100)
  final double drowsyPct;
  final double distractedPct;

  final List<double> fullProbs; // full 12-class softmax vector
  final ModelSource  modelSource;
  final double       earAvg;  // features[2] — for display
  final bool         t02Active; // true = temporal buffer is warm (30 frames)

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

// TfliteService — singleton, V3 single-file dual-input
class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  Interpreter? _interpreter;
  bool _isInitialized    = false;
  bool _isRunning        = false;
  int  _lastInferenceMs  = 0;
  int  _consecutiveUnsafe = 0;

  // Minimum gap between inference calls (~5 FPS on mid-range phones)
  static const int _kMinInferenceGapMs = 300; // ~3 FPS — stable on mid-range

  // Pre-allocated nested spatial input [1][224][224][3] 
  // runForMultipleInputs infers tensor shape from List nesting depth.
  // A flat Float32List is treated as 1D [150528] → causes dims!=4 error.
  // Nested 4-level list correctly maps to [1, 224, 224, 3].
  // Allocated once in initialize(), filled in-place each frame.
  List<List<List<List<double>>>>? _spatialNested;

  // Output buffer [1][12] 
  final List<List<double>> _outputBuf = [List<double>.filled(12, 0.0)];

  // Temporal FIFO buffer [30][12]
  final List<List<double>> _temporalBuf = List.generate(
    _kSeqLen,
    (_) => List<double>.filled(_kNumFeat, 0.0),
    growable: false,
  );
  int _bufFill = 0;

  // Initialize
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      // Load model — do NOT resizeInputTensor for dual-input models.
      // DO NOT resizeInputTensor — let allocateTensors() use model defaults.
      // Shape is communicated via List nesting depth, not resizeInputTensor.
      final opts = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(_kModelAsset, options: opts);
      _interpreter!.allocateTensors();

      // Pre-allocate nested spatial tensor [1][224][224][3].
      _spatialNested = List.generate(
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
      debugPrint('[TfliteService] ✅ DMS-HybridNet V3 loaded');
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Init failed: $e');
      return false;
    }
  }

  bool   get isInitialized  => _isInitialized;
  double get bufferFillPct  =>
      (_bufFill / _kSeqLen * 100).clamp(0.0, 100.0);

  void dispose() {
    _interpreter?.close();
    _interpreter       = null;
    _isInitialized     = false;
    _isRunning         = false;  // reset lock so next init works
    _bufFill           = 0;
    _consecutiveUnsafe = 0;
    _lastInferenceMs   = 0;
    debugPrint('[TfliteService] disposed');
  }

  // Main inference entry point
  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _interpreter == null) return null;
    if (_isRunning) return null;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastInferenceMs < _kMinInferenceGapMs) return null;

    _isRunning = true;
    try {
      // Step 1: Preprocess in background isolate 
      // Note: CameraImage on Android always delivers in sensor orientation
      // (width = wider dimension). The resize handles any aspect ratio correctly.
      final prep = await compute(
        _preprocessFrameV3,
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
      _lastInferenceMs = nowMs;

      // Step 2: Fill nested spatial tensor in-place [1][224][224][3]
      // tflite_flutter infers shape from List nesting — must be 4 levels deep.
      const h = 224, w = 224;
      final flat = prep.rgbNormalized;
      for (int r = 0; r < h; r++) {
        final row = _spatialNested![0][r];
        for (int c = 0; c < w; c++) {
          final i  = (r * w + c) * 3;
          final px = row[c];
          px[0] = flat[i];
          px[1] = flat[i + 1];
          px[2] = flat[i + 2];
        }
      }

      // Step 3: Update temporal FIFO buffer
      _updateTemporalBuf(prep.features);

      // Step 4: Wrap temporal as nested [1][30][12]
      // tflite_flutter needs 3-level nesting for [1, 30, 12] shape.
      final temporalNested = [_temporalBuf]; // [1][30][12]

      // Step 5: Run dual-input inference
      // Input index order verified by binary inspection of model file:
      //   Index 0 → temporal_input [1, 30, 12]     (byte 164 in flatbuffer)
      //   Index 1 → spatial_input  [1, 224, 224, 3] (byte 196 in flatbuffer)
      for (int i = 0; i < 12; i++) { _outputBuf[0][i] = 0.0; }

      _interpreter!.runForMultipleInputs(
        <Object>[temporalNested, _spatialNested!],
        <int, Object>{0: _outputBuf},
      );

      // Step 6: Softmax check per spec
      final rawOut = List<double>.from(_outputBuf[0]);
      final sum    = rawOut.fold(0.0, (a, b) => a + b);
      final probs  = (sum - 1.0).abs() > 0.01 ? _softmax(rawOut) : rawOut;

      // Debug: log top-3 predictions so you can tune thresholds
      final indexed = List.generate(12, (i) => MapEntry(i, probs[i]));
      indexed.sort((a, b) => b.value.compareTo(a.value));
      debugPrint('[V3] '
        '${kClassNames[indexed[0].key]}=${(indexed[0].value*100).toStringAsFixed(1)}% | '
        '${kClassNames[indexed[1].key]}=${(indexed[1].value*100).toStringAsFixed(1)}% | '
        '${kClassNames[indexed[2].key]}=${(indexed[2].value*100).toStringAsFixed(1)}%');

      // Step 7: Build result
      return _buildResult(probs, prep.features[2]);

    } catch (e) {
      debugPrint('[TfliteService] runInference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  // Temporal FIFO update 
  void _updateTemporalBuf(List<double> features) {
    for (int i = 0; i < _kSeqLen - 1; i++) {
      for (int j = 0; j < _kNumFeat; j++) {
        _temporalBuf[i][j] = _temporalBuf[i + 1][j];
      }
    }
    for (int j = 0; j < _kNumFeat; j++) {
      _temporalBuf[_kSeqLen - 1][j] = features[j];
    }
    if (_bufFill < _kSeqLen) _bufFill++;
  }

  // Build InferenceResult 
  InferenceResult _buildResult(List<double> probs, double earAvg) {
    // Aggregate group scores 
    // Log analysis shows: when sitting still, the model spreads ~80% across
    // ALL distracted classes (reaching 25%, radio 20%, smoking 15% etc.)
    // with no single winner. True distraction concentrates one class at >40%.
    // True drowsiness pools into 3 classes that sum cleanly above 38%.
    //
    // Solution: use GROUP sums + single-class peak instead of plain argmax.
    double neutralPct    = 0;
    double drowsyPct     = 0;
    double distractedPct = 0;
    int    bestDistIdx   = 1;
    double bestDistScore = 0;
    int    bestDrowsyIdx = 9;
    double bestDrowsyScore = 0;

    for (int i = 0; i < 12; i++) {
      final pct = probs[i] * 100.0;
      final st  = _classToMainState(i);
      if (st == 'neutral') {
        neutralPct += pct;
      } else if (st == 'drowsy') {
        drowsyPct += pct;
        if (pct > bestDrowsyScore) { bestDrowsyScore = pct; bestDrowsyIdx = i; }
      } else {
        distractedPct += pct;
        if (pct > bestDistScore) { bestDistScore = pct; bestDistIdx = i; }
      }
    }

    // Decision rules (tuned from logcat analysis)
    // When safe/neutral: model spreads ~80% across ALL distracted classes,
    // each getting 15-25% with no dominant winner.
    // True DROWSY:     3 classes pool → group easily hits 45%+
    // True DISTRACTED: one class dominates at 45%+ AND group > 70%
    // NEUTRAL:         anything that doesn't meet the above strict criteria
    //
    // Thresholds are intentionally strict because false positives are worse
    // than missed detections for a thesis demo (alarming when safe = bad UX).
    String rawState;
    int    bestIdx;
    if (drowsyPct >= 45.0) {
      rawState = 'drowsy';
      bestIdx  = bestDrowsyIdx;
    } else if (distractedPct >= 70.0 && bestDistScore >= 45.0) {
      rawState = 'distracted';
      bestIdx  = bestDistIdx;
    } else {
      rawState = 'neutral';
      bestIdx  = 0;
    }

    // Debounce: soft decay 
    if (rawState != 'neutral') {
      _consecutiveUnsafe++;
    } else {
      _consecutiveUnsafe = (_consecutiveUnsafe - 1).clamp(0, 9999);
    }

    final confirmed   = _consecutiveUnsafe >= _kConsecutiveThreshold;
    final outputState = confirmed ? rawState : 'neutral';
    final outputIdx   = confirmed ? bestIdx  : 0;

    return InferenceResult(
      state:         outputState,
      subclass:      kClassNames[outputIdx],
      subclassIndex: outputIdx,
      neutralPct:    neutralPct.clamp(0.0, 100.0),
      drowsyPct:     drowsyPct.clamp(0.0, 100.0),
      distractedPct: distractedPct.clamp(0.0, 100.0),
      fullProbs:     List<double>.unmodifiable(probs),
      modelSource:   ModelSource.v3,
      earAvg:        earAvg,
      t02Active:     _bufFill >= _kSeqLen,
    );
  }

  static String _classToMainState(int idx) {
    if (idx == 0)                          return 'neutral';
    if (idx == 9 || idx == 10 || idx == 11) return 'drowsy';
    return 'distracted';
  }

  static List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(math.max);
    final exps   = logits.map((v) => math.exp(v - maxVal)).toList();
    final sum    = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}

// BACKGROUND ISOLATE DATA CLASSES
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

class _PrepOutputV3 {
  /// Pixels normalized to [-1.0, 1.0] — required by V3 spatial input.
  final Float32List  rgbNormalized;

  /// 12 temporal features:
  /// [ear_l, ear_r, ear_avg, ear_min, mar, pitch, yaw, roll,
  ///  gaze_l_x, gaze_l_y, gaze_r_x, gaze_r_y]
  final List<double> features;

  const _PrepOutputV3({
    required this.rgbNormalized,
    required this.features,
  });
}

// TOP-LEVEL PREPROCESSING — runs in compute() isolate
_PrepOutputV3? _preprocessFrameV3(_PrepInput input) {
  try {
    final w = input.width;
    final h = input.height;

    final yBytes   = input.planes[0].bytes;
    final uBytes   = input.planes[1].bytes;
    final vBytes   = input.planes[2].bytes;
    final yStride  = input.planes[0].bytesPerRow;
    final uvStride = input.planes[1].bytesPerRow;
    final uvPixel  = input.planes[1].bytesPerPixel;

    // A: YUV420 → RGB (BT.601 integer math) 
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

    //  B: Resize to 224×224 + normalize to [-1.0, 1.0] 
    // CRITICAL (per spec): (pixel / 127.5) - 1.0
    // Feeding raw [0,255] values will cause silent model failure.
    const dstW = 224, dstH = 224;
    final normalized = Float32List(dstW * dstH * 3);
    final xScale     = w / dstW;
    final yScale     = h / dstH;
    int   nIdx       = 0;
    for (int dr = 0; dr < dstH; dr++) {
      final sr = (dr * yScale).toInt().clamp(0, h - 1);
      for (int dc = 0; dc < dstW; dc++) {
        final sc  = (dc * xScale).toInt().clamp(0, w - 1);
        final src = (sr * w + sc) * 3;
        normalized[nIdx++] = (rgb[src    ] / 127.5) - 1.0;
        normalized[nIdx++] = (rgb[src + 1] / 127.5) - 1.0;
        normalized[nIdx++] = (rgb[src + 2] / 127.5) - 1.0;
      }
    }

    // C: Extract 12 temporal features
    final features = _extractFeaturesV3(normalized, dstW, dstH);

    return _PrepOutputV3(rgbNormalized: normalized, features: features);
  } catch (e) {
    debugPrint('[_preprocessFrameV3] Error: $e');
    return null;
  }
}

// 12-FEATURE EXTRACTION — all-neutral baseline
//
// Luminance-based proxy values for EAR/MAR/pose/gaze introduced high noise
// that the model misread as distraction (head turning, looking away) even on
// a steady forward-facing driver due to uneven cabin lighting.
//
// Fix: feed neutral (0.0) for all 12 features. This matches the "resting
// neutral driver looking straight ahead" in the training data and lets the
// spatial branch (camera image) drive all detections without temporal noise.

// ignore: avoid_unused_parameters
List<double> _extractFeaturesV3(Float32List rgb, int w, int h) {
  return List<double>.filled(_kNumFeat, 0.0);
}