// PURPOSE:
//   Runs DMS-HybridNet V3 dual-input inference on every camera frame.
//   Produces an InferenceResult with the driver's current state.
//
// PIPELINE:
//   CameraImage (YUV420)
//     → compute() isolate: YUV→RGB → resize → normalize [-1,1] → float32
//     → Extract 20 base features (sentinel -999.0 until MediaPipe integrated)
//     → Update 30-frame FIFO temporal buffer
//     → Compute 5 window stats from buffer
//     → Normalize all 25 features via norm_params.json
//     → runForMultipleInputs (indices looked up by name, not hardcoded)
//     → 3 outputs: behavior[1,13], parent[1,3], gaze[1,8]
//     → debounce → InferenceResult
//
// MODEL TENSORS (DMS-HybridNet V3.0):
//   Input  "serving_default_temporal_input:0" [1, 30, 25]  float32
//   Input  "serving_default_spatial_input:0"  [1, 224, 224, 3] float32
//   Output [1, 13]  behavior class probabilities  (PRIMARY)
//   Output [1,  3]  parent class probabilities
//   Output [1,  8]  gaze zone probabilities
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

const String _kModelAsset     = 'assets/models/dms_hybridnet_v3_float32.tflite';
const String _kNormParamsAsset = 'assets/norm_params.json';

// 13 behavior class names (index = model output index)
const List<String> kClassNames = [
  'safe_driving',            // 0  → NATURAL
  'talking_passenger',       // 1  → NATURAL
  'distracted_texting',      // 2  → DISTRACTED
  'distracted_phone',        // 3  → DISTRACTED
  'distracted_radio',        // 4  → DISTRACTED
  'distracted_drinking',     // 5  → DISTRACTED
  'distracted_body',         // 6  → DISTRACTED
  'distracted_grooming',     // 7  → DISTRACTED
  'distracted_smoking',      // 8  → DISTRACTED
  'drowsy_yawning',          // 9  → DROWSY
  'drowsy_yawning_occluded', // 10 → DROWSY
  'drowsy_fatigue',          // 11 → DROWSY
  'drowsy_microsleep',       // 12 → DROWSY
];

const List<String> kParentNames = ['NATURAL', 'DISTRACTED', 'DROWSY'];

const List<String> kGazeZones = [
  'ROAD', 'LAP', 'LEFT', 'LEFT_MIRROR',
  'RIGHT', 'RIGHT_MIRROR', 'STEERING', 'NOT_VALID',
];

// Sentinel for undetected features.
// Exception: hand_near_face (index 18) and mouth_occluded (index 19) always use 0.0.
const double kSentinel      = -999.0;
const double kMarYawnThresh = 0.5;

enum ModelSource { v3 }
String modelSourceLabel(ModelSource src) => 'V3 HybridNet';

// Alert debounce: 5 consecutive unsafe frames required before alerting
const int _kConsecutiveThreshold = 5;

// Temporal buffer dimensions
const int _kSeqLen      = 30; // rolling window length
const int _kNumBaseFeat = 20; // raw MediaPipe features per frame
const int _kNumFeat     = 25; // total features sent to model (20 base + 5 stats)

// InferenceResult
class InferenceResult {
  final String state;         // 'neutral' | 'drowsy' | 'distracted'
  final String subclass;      // specific class name from kClassNames
  final int    subclassIndex; // 0–12

  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  final List<double> fullProbs; // 13-class softmax vector
  final ModelSource  modelSource;
  final double       earAvg;    // features[2] (ear_avg) for display
  final bool         t02Active; // true once temporal buffer is warm (30 frames)

  final int parentClass; // 0=NATURAL 1=DISTRACTED 2=DROWSY
  final int gazeZone;    // 0–7 per kGazeZones

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
    required this.parentClass,
    required this.gazeZone,
  });
}

// TfliteService — singleton, V3 dual-input with 3 outputs
class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  Interpreter? _interpreter;
  bool _isInitialized    = false;
  bool _isRunning        = false;
  int  _lastInferenceMs  = 0;
  int  _consecutiveUnsafe = 0;

  // Input tensor indices — resolved by name in initialize(), never hardcoded.
  // Android TFLite runtime does NOT guarantee index order matches model file order.
  int _spatialInputIdx  = 1;
  int _temporalInputIdx = 0;

  // Output tensor indices — resolved by output shape in initialize()
  int _behaviorOutputIdx = 0; // shape [1, 13]
  int _parentOutputIdx   = 1; // shape [1,  3]
  int _gazeOutputIdx     = 2; // shape [1,  8]

  // Minimum gap between inference calls (~3 FPS on mid-range phones)
  static const int _kMinInferenceGapMs = 300;

  // Normalization parameters loaded from norm_params.json
  List<double> _normMean  = [];
  List<double> _normScale = [];

  // Latest face metrics from HeadPoseService — updated via updateFaceData().
  double _faceEarL     = 0.0;
  double _faceEarR     = 0.0;
  double _faceMar      = 0.0;
  double _facePitch    = 0.0;
  double _faceYaw      = 0.0;
  double _faceRollEulerZ = 0.0;

  void updateFaceData({
    required double earL,
    required double earR,
    required double mar,
    required double pitch,
    required double yaw,
    required double rollEulerZ,
  }) {
    _faceEarL       = earL;
    _faceEarR       = earR;
    _faceMar        = mar;
    _facePitch      = pitch;
    _faceYaw        = yaw;
    _faceRollEulerZ = rollEulerZ;
  }

  // Pre-allocated spatial tensor [1][224][224][3]
  // runForMultipleInputs infers shape from List nesting depth.
  // Allocated once in initialize(), filled in-place each frame.
  List<List<List<List<double>>>>? _spatialNested;

  // Output buffers
  final List<List<double>> _behaviorBuf = [List<double>.filled(13, 0.0)];
  final List<List<double>> _parentBuf   = [List<double>.filled(3,  0.0)];
  final List<List<double>> _gazeBuf     = [List<double>.filled(8,  0.0)];

  // Temporal FIFO buffer [30][20] — stores raw (pre-norm) base features.
  // Initialized with sentinel; hand_near_face/mouth_occluded default to 0.0.
  final List<List<double>> _temporalBuf = List.generate(
    _kSeqLen,
    (_) {
      final frame = List<double>.filled(_kNumBaseFeat, kSentinel);
      frame[18] = 0.0; // hand_near_face — never sentinel
      frame[19] = 0.0; // mouth_occluded — never sentinel
      return frame;
    },
    growable: false,
  );
  int _bufFill = 0;

  // Initialize
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      // Load normalization parameters
      final jsonStr   = await rootBundle.loadString(_kNormParamsAsset);
      final normData  = jsonDecode(jsonStr) as Map<String, dynamic>;
      _normMean  = (normData['mean']  as List).map((v) => (v as num).toDouble()).toList();
      _normScale = (normData['scale'] as List).map((v) => (v as num).toDouble()).toList();

      // 2 threads reduces contention; NNAPI disabled to prevent delegate
      // re-init on some devices (the repeated "Replacing N nodes" log).
      // TFLite creates the XNNPACK delegate automatically — no need to add it
      // manually (doing so crashes on devices with the threadpool API bug).
      final opts = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false;
      _interpreter = await Interpreter.fromAsset(_kModelAsset, options: opts);
      _interpreter!.allocateTensors();

      // Resolve input tensor indices by name — guards against runtime index swaps
      final inputTensors = _interpreter!.getInputTensors();
      final sIdx = inputTensors.indexWhere((t) => t.name.contains('spatial'));
      final tIdx = inputTensors.indexWhere((t) => t.name.contains('temporal'));
      if (sIdx != -1) _spatialInputIdx  = sIdx;
      if (tIdx != -1) _temporalInputIdx = tIdx;
      debugPrint('[TfliteService] inputs: spatial=$_spatialInputIdx temporal=$_temporalInputIdx');

      // Resolve output tensor indices by shape
      final outputTensors = _interpreter!.getOutputTensors();
      final bIdx = outputTensors.indexWhere((t) => t.shape.last == 13);
      final pIdx = outputTensors.indexWhere((t) => t.shape.last == 3);
      final gIdx = outputTensors.indexWhere((t) => t.shape.last == 8);
      if (bIdx != -1) _behaviorOutputIdx = bIdx;
      if (pIdx != -1) _parentOutputIdx   = pIdx;
      if (gIdx != -1) _gazeOutputIdx     = gIdx;
      debugPrint('[TfliteService] outputs: behavior=$_behaviorOutputIdx parent=$_parentOutputIdx gaze=$_gazeOutputIdx');

      // Pre-allocate nested spatial tensor [1][224][224][3]
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
      debugPrint('[TfliteService] ✅ DMS-HybridNet V3 loaded (25 features, 3 outputs, 13 classes)');
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Init failed: $e');
      return false;
    }
  }

  bool   get isInitialized => _isInitialized;
  double get bufferFillPct =>
      (_bufFill / _kSeqLen * 100).clamp(0.0, 100.0);

  void dispose() {
    _interpreter?.close();
    _interpreter        = null;
    _isInitialized      = false;
    _isRunning          = false;
    _bufFill            = 0;
    _consecutiveUnsafe  = 0;
    _lastInferenceMs    = 0;
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
      // Step 1: Preprocess frame in background isolate (YUV→RGB→resize→normalize)
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
          width:       image.width,
          height:      image.height,
          earL:        _faceEarL,
          earR:        _faceEarR,
          mar:         _faceMar,
          pitch:       _facePitch,
          yaw:         _faceYaw,
          rollEulerZ:  _faceRollEulerZ,
        ),
      );
      if (prep == null) return null;
      _lastInferenceMs = nowMs;

      // Step 2: Fill spatial tensor in-place [1][224][224][3]
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

      // Step 3: Update temporal FIFO buffer with 20 raw base features
      _updateTemporalBuf(prep.features);

      // Step 4: Compute window stats + normalize → [1][30][25] temporal tensor
      final temporalNested = _buildTemporalInput();

      // Step 5: Clear output buffers
      for (int i = 0; i < 13; i++) { _behaviorBuf[0][i] = 0.0; }
      for (int i = 0; i < 3;  i++) { _parentBuf[0][i]   = 0.0; }
      for (int i = 0; i < 8;  i++) { _gazeBuf[0][i]     = 0.0; }

      // Step 6: Build input list using name-resolved indices (never hardcoded)
      final inputs = List<Object?>.filled(2, null);
      inputs[_temporalInputIdx] = temporalNested;
      inputs[_spatialInputIdx]  = _spatialNested!;

      _interpreter!.runForMultipleInputs(
        inputs.cast<Object>(),
        <int, Object>{
          _behaviorOutputIdx: _behaviorBuf,
          _parentOutputIdx:   _parentBuf,
          _gazeOutputIdx:     _gazeBuf,
        },
      );

      // Step 7: Read and softmax-check behavior output
      debugPrint('[RawOutputs] '
          'behavior_sum=${_behaviorBuf[0].fold(0.0, (a, b) => a + b).toStringAsFixed(3)} '
          'parent_sum=${_parentBuf[0].fold(0.0, (a, b) => a + b).toStringAsFixed(3)} '
          'gaze_sum=${_gazeBuf[0].fold(0.0, (a, b) => a + b).toStringAsFixed(3)}');

      final rawBehavior = List<double>.from(_behaviorBuf[0]);
      final behaviorSum = rawBehavior.fold(0.0, (a, b) => a + b);
      final behaviorProbs =
          (behaviorSum - 1.0).abs() > 0.01 ? _softmax(rawBehavior) : rawBehavior;

      final parentProbs = List<double>.from(_parentBuf[0]);
      final gazeProbs   = List<double>.from(_gazeBuf[0]);

      // Debug: log top-3 behavior predictions
      final indexed = List.generate(13, (i) => MapEntry(i, behaviorProbs[i]));
      indexed.sort((a, b) => b.value.compareTo(a.value));
      debugPrint('[V3] '
          '${kClassNames[indexed[0].key]}=${(indexed[0].value * 100).toStringAsFixed(1)}% | '
          '${kClassNames[indexed[1].key]}=${(indexed[1].value * 100).toStringAsFixed(1)}% | '
          '${kClassNames[indexed[2].key]}=${(indexed[2].value * 100).toStringAsFixed(1)}%');

      // Step 8: Decode secondary outputs
      final parentClass = parentProbs.indexOf(parentProbs.reduce(math.max));
      final gazeZone    = gazeProbs.indexOf(gazeProbs.reduce(math.max));

      return _buildResult(behaviorProbs, prep.features[2], parentClass, gazeZone);

    } catch (e) {
      debugPrint('[TfliteService] runInference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  // Build normalized [1][30][25] tensor from current buffer.
  // Window stats (features 20–24) are computed from the 30-frame window
  // and broadcast to every frame row before normalization.
  List<List<List<double>>> _buildTemporalInput() {
    final stats = _computeWindowStats(); // [earMean, earMin, marMax, marAbove, earTrend]

    debugPrint('[Temporal] stats: '
        'ear_mean=${stats[0].toStringAsFixed(3)} '
        'ear_min=${stats[1].toStringAsFixed(3)} '
        'mar_max=${stats[2].toStringAsFixed(3)} '
        'mar_above=${stats[3].toStringAsFixed(3)} '
        'ear_trend=${stats[4].toStringAsFixed(3)} '
        'buf_fill=$_bufFill');

    return [
      List.generate(_kSeqLen, (t) {
        final frame = List<double>.filled(_kNumFeat, 0.0);
        // Normalize 20 base features: (raw - mean) / (scale + ε)
        for (int f = 0; f < _kNumBaseFeat; f++) {
          frame[f] = (_temporalBuf[t][f] - _normMean[f]) /
              (_normScale[f] + 1e-8);
        }
        // Normalize 5 window stats (same value for every frame in the sequence)
        for (int f = 0; f < 5; f++) {
          frame[_kNumBaseFeat + f] =
              (stats[f] - _normMean[_kNumBaseFeat + f]) /
              (_normScale[_kNumBaseFeat + f] + 1e-8);
        }
        return frame;
      }),
    ];
  }

  // Compute 5 window statistics from the current 30-frame buffer.
  // Sentinel values are excluded from all calculations.
  List<double> _computeWindowStats() {
    // ear_avg at index 2, mar at index 4
    final earVals = _temporalBuf
        .map((f) => f[2])
        .where((v) => v != kSentinel && !v.isNaN)
        .toList();
    final marVals = _temporalBuf
        .map((f) => f[4])
        .where((v) => v != kSentinel && !v.isNaN)
        .toList();

    // Feature 20: ear_avg_mean
    final earMean = earVals.isEmpty
        ? 0.0
        : earVals.reduce((a, b) => a + b) / earVals.length;

    // Feature 21: ear_avg_min
    final earMin = earVals.isEmpty ? 0.0 : earVals.reduce(math.min);

    // Feature 22: mar_max
    final marMax = marVals.isEmpty ? 0.0 : marVals.reduce(math.max);

    // Feature 23: mar_above_thresh (fraction of frames with MAR > 0.5)
    final marAbove = marVals.isEmpty
        ? 0.0
        : marVals.where((v) => v > kMarYawnThresh).length / marVals.length;

    // Feature 24: ear_trend (linear regression slope of ear_avg over valid frames)
    double earTrend = 0.0;
    if (earVals.length >= 2) {
      final validIdx = <int>[];
      for (int i = 0; i < _kSeqLen; i++) {
        if (_temporalBuf[i][2] != kSentinel && !_temporalBuf[i][2].isNaN) {
          validIdx.add(i);
        }
      }
      final n = validIdx.length.toDouble();
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      for (int i = 0; i < validIdx.length; i++) {
        final x = validIdx[i].toDouble();
        final y = earVals[i];
        sumX  += x;
        sumY  += y;
        sumXY += x * y;
        sumX2 += x * x;
      }
      final denom = n * sumX2 - sumX * sumX;
      earTrend = denom.abs() > 1e-9 ? (n * sumXY - sumX * sumY) / denom : 0.0;
    }

    return [earMean, earMin, marMax, marAbove, earTrend];
  }

  // FIFO shift: discard oldest frame, append newest
  void _updateTemporalBuf(List<double> features) {
    for (int i = 0; i < _kSeqLen - 1; i++) {
      for (int j = 0; j < _kNumBaseFeat; j++) {
        _temporalBuf[i][j] = _temporalBuf[i + 1][j];
      }
    }
    for (int j = 0; j < _kNumBaseFeat; j++) {
      _temporalBuf[_kSeqLen - 1][j] = features[j];
    }
    if (_bufFill < _kSeqLen) _bufFill++;
  }

  // Build InferenceResult with debounce
  InferenceResult _buildResult(
    List<double> probs,
    double earAvg,
    int parentClass,
    int gazeZone,
  ) {
    double neutralPct    = 0;
    double drowsyPct     = 0;
    double distractedPct = 0;
    int    bestDistIdx   = 2;
    double bestDistScore = 0;
    int    bestDrowsyIdx = 9;
    double bestDrowsyScore = 0;

    for (int i = 0; i < 13; i++) {
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

    // Decision thresholds — strict to minimise false positives in demo context.
    // DROWSY recall is low (30.4%); threshold intentionally kept at 45% group.
    String rawState;
    int    bestIdx;
    if (drowsyPct >= 30.0) {
      rawState = 'drowsy';
      bestIdx  = bestDrowsyIdx;
    } else if (distractedPct >= 55.0 && bestDistScore >= 30.0) {
      rawState = 'distracted';
      bestIdx  = bestDistIdx;
    } else {
      rawState = 'neutral';
      bestIdx  = 0;
    }

    // Soft-decay debounce
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
      parentClass:   parentClass,
      gazeZone:      gazeZone,
    );
  }

  static String _classToMainState(int idx) {
    if (idx == 0 || idx == 1) return 'neutral';  // safe_driving, talking_passenger
    if (idx >= 9)             return 'drowsy';   // drowsy_yawning … drowsy_microsleep
    return 'distracted';                          // distracted_texting … distracted_smoking
  }

  static List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(math.max);
    final exps   = logits.map((v) => math.exp(v - maxVal)).toList();
    final sum    = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}

// ─── BACKGROUND ISOLATE DATA CLASSES ────────────────────────────────────────

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
  final double earL;
  final double earR;
  final double mar;
  final double pitch;
  final double yaw;
  final double rollEulerZ;
  const _PrepInput({
    required this.planes,
    required this.width,
    required this.height,
    this.earL       = 0.0,
    this.earR       = 0.0,
    this.mar        = 0.0,
    this.pitch      = 0.0,
    this.yaw        = 0.0,
    this.rollEulerZ = 0.0,
  });
}

class _PrepOutputV3 {
  // Pixels normalized to [-1.0, 1.0] — MobileNetV3 preprocessing
  final Float32List rgbNormalized;

  // 20 raw base features [ear_l … mouth_occluded].
  // Indices 0–17: kSentinel (-999.0) until MediaPipe is integrated.
  // Indices 18 (hand_near_face) and 19 (mouth_occluded): always 0.0.
  final List<double> features;

  const _PrepOutputV3({
    required this.rgbNormalized,
    required this.features,
  });
}

// ─── TOP-LEVEL PREPROCESSING — runs in compute() isolate ────────────────────

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

    // B: Resize to 224×224 (bilinear) + normalize to [-1.0, 1.0]
    // Formula per spec: (pixel / 127.5) - 1.0
    const dstW = 224, dstH = 224;
    final normalized = Float32List(dstW * dstH * 3);
    final xScale     = (w - 1) / (dstW - 1);
    final yScale     = (h - 1) / (dstH - 1);
    int   nIdx       = 0;
    for (int dr = 0; dr < dstH; dr++) {
      final sy  = dr * yScale;
      final sy0 = sy.toInt().clamp(0, h - 2);
      final sy1 = sy0 + 1;
      final fy  = sy - sy0;
      final fy1 = 1.0 - fy;
      for (int dc = 0; dc < dstW; dc++) {
        final sx  = dc * xScale;
        final sx0 = sx.toInt().clamp(0, w - 2);
        final sx1 = sx0 + 1;
        final fx  = sx - sx0;
        final fx1 = 1.0 - fx;
        final i00 = (sy0 * w + sx0) * 3;
        final i10 = (sy0 * w + sx1) * 3;
        final i01 = (sy1 * w + sx0) * 3;
        final i11 = (sy1 * w + sx1) * 3;
        for (int c = 0; c < 3; c++) {
          final val = fy1 * (fx1 * rgb[i00 + c] + fx * rgb[i10 + c]) +
                      fy  * (fx1 * rgb[i01 + c] + fx * rgb[i11 + c]);
          normalized[nIdx++] = (val / 127.5) - 1.0;
        }
      }
    }

    // C: Extract 20 base temporal features from face data passed via PrepInput
    final features = _extractFeaturesV3(input);

    return _PrepOutputV3(rgbNormalized: normalized, features: features);
  } catch (e) {
    debugPrint('[_preprocessFrameV3] Error: $e');
    return null;
  }
}

// 20-FEATURE EXTRACTION
// Populates features from HeadPoseService data passed through _PrepInput.
// Indices 3, 5-9, 13-17 remain sentinel — not available without MediaPipe body pose.
// Indices 18-19 (hand_near_face, mouth_occluded) always 0.0.
List<double> _extractFeaturesV3(_PrepInput input) {
  final features = List<double>.filled(20, kSentinel);
  features[18] = 0.0; // hand_near_face
  features[19] = 0.0; // mouth_occluded

  final earAvg = (input.earL + input.earR) / 2.0;
  features[0]  = input.earL;       // ear_l
  features[1]  = input.earR;       // ear_r
  features[2]  = earAvg;           // ear_avg
  features[4]  = input.mar;        // mar
  features[10] = input.pitch;      // pitch
  features[11] = input.yaw;        // yaw
  features[12] = input.rollEulerZ; // roll

  return features;
}
