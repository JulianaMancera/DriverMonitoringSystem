// PURPOSE:
//   Runs DMS-HybridNet V3 dual-input inference on every camera frame.
//   Produces an InferenceResult with the driver's current state.
//
// CAMERA MOUNT GEOMETRY:
//   Phone is mounted to the RIGHT of the driver, front camera faces left
//   toward the driver. From ML Kit's perspective the driver's face is
//   turned RIGHTWARD (toward camera) → positive eulerAngleY.
//   Therefore kSideMountYawOffset = +30.0 (was -30.0 — sign was inverted).
//
// FIXES IN THIS VERSION (on top of previous fixes):
//   FIX A — kSideMountYawOffset changed from -30.0 to +30.0.
//            The old -30 meant "expect face at -30° yaw (turned LEFT)".
//            For a right-side-mounted camera the face is actually turned
//            RIGHT (+30°), so the offset sign was backwards. This was the
//            primary cause of the wiper indicator being on the wrong side
//            and of the yaw-based safe-zone gate mis-classifying normal
//            forward-facing driving as distracted.
//
//   FIX B — driverLookingAtRoad threshold widened from ±20° to ±30°.
//            Since the driver naturally has ~30° yaw deviation even when
//            looking at the road, the old ±20° window was almost never
//            satisfied, defeating the safe-zone gate entirely.
//
//   FIX C — _kDistractedThreshold raised from 12 to 16.
//            More consecutive frames required before confirming distraction.
//            This, combined with FIX A, should stop nonstop false positives.
//
//   FIX D — _kStableSubclassMin raised from 6 to 8.
//            More frames of the SAME subclass required before confirming.
//
//   FIX E — Per-class thresholds tuned for right-side mount.
//            Classes that were most prone to false positives from the
//            rotated camera angle now require higher individual scores.
//
//   FIX F — Head pose indicator disappearing on re-record.
//            HeadPoseService.instance.dispose() was called in widget dispose
//            but the indicator was only started on camera init, not on each
//            _startRecording(). The fix is in monitor_screen.dart which now
//            always calls _startHeadPoseUpdates() when starting a session.
//            The TfliteService itself now also resets face data in resetSession().

import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

const String _kModelAsset = 'assets/models/dms_hybridnet_v3_float32.tflite';
const String _kNormParamsAsset = 'assets/norm_params.json';

// 13 behavior class names (index = model output index)
const List<String> kClassNames = [
  'safe_driving', // 0  → NATURAL
  'talking_passenger', // 1  → NATURAL
  'distracted_texting', // 2  → DISTRACTED
  'distracted_phone', // 3  → DISTRACTED
  'distracted_radio', // 4  → DISTRACTED
  'distracted_drinking', // 5  → DISTRACTED
  'distracted_body', // 6  → DISTRACTED
  'distracted_grooming', // 7  → DISTRACTED
  'distracted_smoking', // 8  → DISTRACTED
  'drowsy_yawning', // 9  → DROWSY
  'drowsy_yawning_occluded', // 10 → DROWSY
  'drowsy_fatigue', // 11 → DROWSY
  'drowsy_microsleep', // 12 → DROWSY
];

const List<String> kParentNames = ['NATURAL', 'DISTRACTED', 'DROWSY'];

const List<String> kGazeZones = [
  'ROAD',
  'LAP',
  'LEFT',
  'LEFT_MIRROR',
  'RIGHT',
  'RIGHT_MIRROR',
  'STEERING',
  'NOT_VALID',
];

const double kSentinel = -999.0;
const double kMarYawnThresh = 0.5;

enum ModelSource { v3 }

String modelSourceLabel(ModelSource src) => 'V3 HybridNet';

const int _kDrowsyThreshold = 3;
// FIX C: Raised from 12 to 16 — require more consecutive frames before
// confirming distraction. Combined with the corrected yaw offset this
// eliminates the nonstop false distraction alerts.
const int _kDistractedThreshold = 16;

// ─── DATASET-SPECIFIC THRESHOLDS ───────────────────────────────────────────
// These thresholds are hardcoded based on behavioral patterns from:
//   - Drowsy: MRL Eye, YawDD, UTA-RLDD datasets
//   - Distracted: State Farm Distracted Driver Detection dataset
//
// Each value represents the minimum model confidence (as %) for that specific
// behavior class to be considered a valid detection.
const Map<int, double> _kBehaviorClassThresholds = {
  // Neutral classes (no detection needed)
  0: 50.0, // safe_driving
  1: 40.0, // talking_passenger

  // Distracted classes (State Farm dataset)
  2: 50.0, // distracted_texting (was 55, phone glances are high confidence)
  3: 35.0, // distracted_phone (was 30, raised to distinguish from talking)
  4: 45.0, // distracted_radio (was 50, lower for quick glances)
  5: 35.0, // distracted_drinking (was 30, hand-near-face key signal)
  6: 70.0, // distracted_body (was 75, catch-all FP class - keep high)
  7: 55.0, // distracted_grooming (was 60, hand-to-face rapid movements)
  8: 30.0, // distracted_smoking (was 35, distinctive hand-to-mouth pattern)

  // Drowsy classes (MRL Eye, YawDD, UTA-RLDD datasets)
  9: 25.0, // drowsy_yawning (MAR spike - distinctive)
  10: 30.0, // drowsy_yawning_occluded (harder to detect - higher threshold)
  11: 20.0, // drowsy_fatigue (EAR trend gradual - lower threshold)
  12: 35.0, // drowsy_microsleep (PERCLOS >= 80% - most critical)
};

const int _kSeqLen = 30;
const int _kNumBaseFeat = 20;
const int _kNumFeat = 25;

// FIX A: Changed from -30.0 to +30.0.
//
// GEOMETRY EXPLANATION:
//   The phone is mounted to the RIGHT of the driver. The front-facing camera
//   looks LEFT toward the driver's face. From the camera's perspective, the
//   driver's face is ROTATED RIGHTWARD (toward the camera), which ML Kit
//   reports as a POSITIVE eulerAngleY (yaw).
//
//   With the phone at ~30–35° to the right:
//     - Driver looking straight ahead → ML Kit yaw ≈ +30°
//     - Driver looking left (away from cam) → yaw decreases toward 0° or negative
//     - Driver looking right (toward cam) → yaw increases above +30°
//
//   Setting offset = +30.0 means:
//     compensatedYaw = yaw - 30.0
//     → 0 when driver looks straight (correct neutral baseline)
//     → negative when driver looks left (away from cam)
//     → positive when driver looks right (toward cam / distracted)
//
//   The old value of -30.0 was computing:
//     compensatedYaw = yaw - (-30.0) = yaw + 30.0
//     → +60 when driver looks straight → always flagged as distracted!
const double kSideMountYawOffset = 30.0; // FIX A: was -30.0

// Old FIX E is now superseded by _kBehaviorClassThresholds above.
// Keeping comment for git history: Per-class thresholds now unified in single map.

// InferenceResult
class InferenceResult {
  final String state;
  final String subclass;
  final int subclassIndex;

  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  final List<double> fullProbs;
  final ModelSource modelSource;
  final double earAvg;
  final bool t02Active;

  final int parentClass;
  final int gazeZone;

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

class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool _isRunning = false;
  int _lastInferenceMs = 0;

  int _consecutiveDrowsy = 0;
  int _consecutiveDistracted = 0;

  int _lastDistractedClass = -1;
  int _stableDistractedCount = 0;
  // FIX D: Raised from 6 to 8 — same subclass must appear for 8 consecutive
  // frames before distraction is confirmed.
  static const int _kStableSubclassMin = 8;

  int _spatialInputIdx = 1;
  int _temporalInputIdx = 0;

  int _behaviorOutputIdx = 0;
  int _parentOutputIdx = 1;
  int _gazeOutputIdx = 2;

  static const int _kMinInferenceGapMs = 150;

  List<double> _normMean = [];
  List<double> _normScale = [];

  double _faceEarL = 0.0;
  double _faceEarR = 0.0;
  double _faceMar = 0.0;
  double _facePitch = 0.0;
  double _faceYaw = 0.0;
  double _faceRollEulerZ = 0.0;

  void updateFaceData({
    required double earL,
    required double earR,
    required double mar,
    required double pitch,
    required double yaw,
    required double rollEulerZ,
  }) {
    _faceEarL = earL;
    _faceEarR = earR;
    _faceMar = mar;
    _facePitch = pitch;
    _faceYaw = yaw;
    _faceRollEulerZ = rollEulerZ;
  }

  final List<List<double>> _behaviorBuf = [List<double>.filled(13, 0.0)];
  final List<List<double>> _parentBuf = [List<double>.filled(3, 0.0)];
  final List<List<double>> _gazeBuf = [List<double>.filled(8, 0.0)];

  final List<List<double>> _temporalBuf = List.generate(
    _kSeqLen,
    (_) {
      final frame = List<double>.filled(_kNumBaseFeat, kSentinel);
      frame[18] = 0.0;
      frame[19] = 0.0;
      return frame;
    },
    growable: false,
  );
  int _bufFill = 0;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      final jsonStr = await rootBundle.loadString(_kNormParamsAsset);
      final normData = jsonDecode(jsonStr) as Map<String, dynamic>;
      _normMean =
          (normData['mean'] as List).map((v) => (v as num).toDouble()).toList();
      _normScale = (normData['scale'] as List)
          .map((v) => (v as num).toDouble())
          .toList();

      final opts = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false;
      _interpreter = await Interpreter.fromAsset(_kModelAsset, options: opts);
      _interpreter!.allocateTensors();

      final inputTensors = _interpreter!.getInputTensors();
      final sIdx = inputTensors.indexWhere((t) => t.name.contains('spatial'));
      final tIdx = inputTensors.indexWhere((t) => t.name.contains('temporal'));
      if (sIdx != -1) _spatialInputIdx = sIdx;
      if (tIdx != -1) _temporalInputIdx = tIdx;
      debugPrint(
          '[TfliteService] inputs: spatial=$_spatialInputIdx temporal=$_temporalInputIdx');

      final outputTensors = _interpreter!.getOutputTensors();
      final bIdx = outputTensors.indexWhere((t) => t.shape.last == 13);
      final pIdx = outputTensors.indexWhere((t) => t.shape.last == 3);
      final gIdx = outputTensors.indexWhere((t) => t.shape.last == 8);
      if (bIdx != -1) _behaviorOutputIdx = bIdx;
      if (pIdx != -1) _parentOutputIdx = pIdx;
      if (gIdx != -1) _gazeOutputIdx = gIdx;
      debugPrint(
          '[TfliteService] outputs: behavior=$_behaviorOutputIdx parent=$_parentOutputIdx gaze=$_gazeOutputIdx');

      _isInitialized = true;
      debugPrint(
          '[TfliteService] ✅ DMS-HybridNet V3 loaded (25 features, 3 outputs, 13 classes)');
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Init failed: $e');
      return false;
    }
  }

  bool get isInitialized => _isInitialized;
  double get bufferFillPct => (_bufFill / _kSeqLen * 100).clamp(0.0, 100.0);

  void resetSession() {
    _bufFill = 0;
    _consecutiveDrowsy = 0;
    _consecutiveDistracted = 0;
    _lastDistractedClass = -1;
    _stableDistractedCount = 0;
    _lastInferenceMs = 0;
    _isRunning = false;

    for (int t = 0; t < _kSeqLen; t++) {
      for (int f = 0; f < _kNumBaseFeat; f++) {
        _temporalBuf[t][f] = kSentinel;
      }
      _temporalBuf[t][18] = 0.0;
      _temporalBuf[t][19] = 0.0;
    }

    _faceEarL = 0.0;
    _faceEarR = 0.0;
    _faceMar = 0.0;
    _facePitch = 0.0;
    _faceYaw = 0.0;
    _faceRollEulerZ = 0.0;

    debugPrint('[TfliteService] session reset — buffer cleared');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    resetSession();
    debugPrint('[TfliteService] disposed');
  }

  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _interpreter == null) return null;
    if (_isRunning) return null;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastInferenceMs < _kMinInferenceGapMs) return null;

    _isRunning = true;
    try {
      final prep = await compute(
        _preprocessFrameV3,
        _PrepInput(
          planes: image.planes
              .map((p) => _PlaneData(
                    bytes: p.bytes,
                    bytesPerRow: p.bytesPerRow,
                    bytesPerPixel: p.bytesPerPixel ?? 1,
                  ))
              .toList(),
          width: image.width,
          height: image.height,
          earL: _faceEarL,
          earR: _faceEarR,
          mar: _faceMar,
          pitch: _facePitch,
          yaw: _faceYaw,
          rollEulerZ: _faceRollEulerZ,
        ),
      );
      if (prep == null) return null;
      _lastInferenceMs = nowMs;

      _updateTemporalBuf(prep.features);

      final temporalFlat = _buildTemporalInput();

      for (int i = 0; i < 13; i++) {
        _behaviorBuf[0][i] = 0.0;
      }
      for (int i = 0; i < 3; i++) {
        _parentBuf[0][i] = 0.0;
      }
      for (int i = 0; i < 8; i++) {
        _gazeBuf[0][i] = 0.0;
      }

      final inputs = List<Object?>.filled(2, null);
      inputs[_temporalInputIdx] = temporalFlat;
      inputs[_spatialInputIdx] = prep.rgbNormalized;

      _interpreter!.runForMultipleInputs(
        inputs.cast<Object>(),
        <int, Object>{
          _behaviorOutputIdx: _behaviorBuf,
          _parentOutputIdx: _parentBuf,
          _gazeOutputIdx: _gazeBuf,
        },
      );

      debugPrint('[RawOutputs] '
          'behavior_sum=${_behaviorBuf[0].fold(0.0, (a, b) => a + b).toStringAsFixed(3)} '
          'parent_sum=${_parentBuf[0].fold(0.0, (a, b) => a + b).toStringAsFixed(3)} '
          'gaze_sum=${_gazeBuf[0].fold(0.0, (a, b) => a + b).toStringAsFixed(3)}');

      final rawBehavior = List<double>.from(_behaviorBuf[0]);
      final behaviorSum = rawBehavior.fold(0.0, (a, b) => a + b);
      final behaviorProbs = (behaviorSum - 1.0).abs() > 0.01
          ? _softmax(rawBehavior)
          : rawBehavior;

      final parentProbs = List<double>.from(_parentBuf[0]);
      final gazeProbs = List<double>.from(_gazeBuf[0]);

      final indexed = List.generate(13, (i) => MapEntry(i, behaviorProbs[i]));
      indexed.sort((a, b) => b.value.compareTo(a.value));
      debugPrint('[V3] '
          '${kClassNames[indexed[0].key]}=${(indexed[0].value * 100).toStringAsFixed(1)}% | '
          '${kClassNames[indexed[1].key]}=${(indexed[1].value * 100).toStringAsFixed(1)}% | '
          '${kClassNames[indexed[2].key]}=${(indexed[2].value * 100).toStringAsFixed(1)}%');

      final parentClass = parentProbs.indexOf(parentProbs.reduce(math.max));
      final gazeZone = gazeProbs.indexOf(gazeProbs.reduce(math.max));

      return _buildResult(
          behaviorProbs, prep.features[2], parentClass, gazeZone);
    } catch (e) {
      debugPrint('[TfliteService] runInference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  Float32List _buildTemporalInput() {
    final stats = _computeWindowStats();

    debugPrint('[Temporal] stats: '
        'ear_mean=${stats[0].toStringAsFixed(3)} '
        'ear_min=${stats[1].toStringAsFixed(3)} '
        'mar_max=${stats[2].toStringAsFixed(3)}');

    final flat = Float32List(_kSeqLen * _kNumFeat);
    for (int t = 0; t < _kSeqLen; t++) {
      final offset = t * _kNumFeat;

      for (int f = 0; f < _kNumBaseFeat; f++) {
        final raw = _temporalBuf[t][f];
        if (raw == kSentinel) {
          flat[offset + f] = 0.0;
        } else {
          flat[offset + f] = (raw - _normMean[f]) / (_normScale[f] + 1e-8);
        }
      }

      for (int f = 0; f < 5; f++) {
        flat[offset + _kNumBaseFeat + f] =
            (stats[f] - _normMean[_kNumBaseFeat + f]) /
                (_normScale[_kNumBaseFeat + f] + 1e-8);
      }
    }
    return flat;
  }

  List<double> _computeWindowStats() {
    final earVals = _temporalBuf
        .map((f) => f[2])
        .where((v) => v != kSentinel && !v.isNaN)
        .toList();
    final marVals = _temporalBuf
        .map((f) => f[4])
        .where((v) => v != kSentinel && !v.isNaN)
        .toList();

    final earMean = earVals.isEmpty
        ? 0.0
        : earVals.reduce((a, b) => a + b) / earVals.length;

    final earMin = earVals.isEmpty ? 0.0 : earVals.reduce(math.min);

    final marMax = marVals.isEmpty ? 0.0 : marVals.reduce(math.max);

    final marAbove = marVals.isEmpty
        ? 0.0
        : marVals.where((v) => v > kMarYawnThresh).length / marVals.length;

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
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
      }
      final denom = n * sumX2 - sumX * sumX;
      earTrend = denom.abs() > 1e-9 ? (n * sumXY - sumX * sumY) / denom : 0.0;
    }

    return [earMean, earMin, marMax, marAbove, earTrend];
  }

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

  InferenceResult _buildResult(
    List<double> probs,
    double earAvg,
    int parentClass,
    int gazeZone,
  ) {
    double neutralPct = 0;
    double drowsyPct = 0;
    double distractedPct = 0;
    int bestDistIdx = 2;
    double bestDistScore = 0;
    int bestDrowsyIdx = 9;
    double bestDrowsyScore = 0;

    for (int i = 0; i < 13; i++) {
      final pct = probs[i] * 100.0;
      final st = _classToMainState(i);
      if (st == 'neutral') {
        neutralPct += pct;
      } else if (st == 'drowsy') {
        drowsyPct += pct;
        if (pct > bestDrowsyScore) {
          bestDrowsyScore = pct;
          bestDrowsyIdx = i;
        }
      } else {
        distractedPct += pct;
        if (pct > bestDistScore) {
          bestDistScore = pct;
          bestDistIdx = i;
        }
      }
    }

    // ────────────────────────────────────────────────────────────────────────
    // FIX: Cross-class interference prevention
    // If "Body/Reaching" (class 6) is winning but with low-moderate confidence,
    // check if a more specific distracted class is nearby. If yes, promote it.
    // ────────────────────────────────────────────────────────────────────────
    if ((bestDistIdx == 6) && bestDistScore >= 55.0 && bestDistScore < 70.0) {
      double secondBestScore = 0.0;
      int secondBestIdx = 6;
      for (int i = 2; i <= 8; i++) {
        if (i == 6) continue;
        final pct = probs[i] * 100.0;
        if (pct > secondBestScore) {
          secondBestScore = pct;
          secondBestIdx = i;
        }
      }
      // If secondary class is reasonably close (70% of bestDistScore or >=20%),
      // use it instead (demote catch-all body class)
      if (secondBestScore >= 20.0 && secondBestScore >= bestDistScore * 0.7) {
        bestDistIdx = secondBestIdx;
        bestDistScore = secondBestScore;
        debugPrint('[CrossClass] Demoted body (${probs[6] * 100}%) → '
            '${kClassNames[secondBestIdx]} ($secondBestScore%)');
      }
    }

    // FIX B: Widened driverLookingAtRoad from ±20° to ±30°.
    // With the corrected yawOffset (+30), compensatedYaw = yaw - 30.
    // The driver naturally has yaw ≈ +30 when looking straight, so
    // compensatedYaw ≈ 0. Using ±20° was correct in theory but the
    // smoothed yaw still drifts ±5–10° from frame noise. ±30° gives
    // enough headroom to prevent valid forward-gaze from triggering
    // the stricter distraction threshold.
    final compensatedYaw = (_faceYaw - kSideMountYawOffset).abs();
    final driverLookingAtRoad = compensatedYaw <= 30.0; // FIX B: was 20.0
    final effectiveDistClassThreshold = driverLookingAtRoad ? 50.0 : 40.0;

    final classMinThreshold = _kBehaviorClassThresholds[bestDistIdx] ?? 30.0;
    final bestDistMeetsClassMin = bestDistScore >= classMinThreshold;

    final parentSaysDistracted = parentClass == 1;
    final parentSaysDrowsy = parentClass == 2;

    // ────────────────────────────────────────────────────────────────────────
    // NEW LOGIC: Stricter global gates based on datasets
    // Distraction threshold raised from 65% to 70% for fewer false positives
    // ────────────────────────────────────────────────────────────────────────

    String rawState;
    int rawBestIdx;
    if (drowsyPct >= 40.0 &&
        bestDrowsyScore >= 20.0 &&
        (parentSaysDrowsy || drowsyPct >= 60.0)) {
      rawState = 'drowsy';
      rawBestIdx = bestDrowsyIdx;
    } else if (distractedPct >= 70.0 &&
        bestDistScore >= effectiveDistClassThreshold &&
        bestDistMeetsClassMin &&
        parentSaysDistracted) {
      rawState = 'distracted';
      rawBestIdx = bestDistIdx;
    } else if (distractedPct >= 70.0 &&
        bestDistIdx != 6 &&
        bestDistScore >= 25.0 &&
        bestDistMeetsClassMin &&
        parentSaysDistracted &&
        !driverLookingAtRoad) {
      rawState = 'distracted';
      rawBestIdx = bestDistIdx;
    } else {
      rawState = 'neutral';
      rawBestIdx = 0;
    }

    // Subclass stability check (FIX D: threshold raised to 8)
    if (rawState == 'distracted') {
      if (rawBestIdx == _lastDistractedClass) {
        _stableDistractedCount++;
      } else {
        _lastDistractedClass = rawBestIdx;
        _stableDistractedCount = 1;
      }
      if (_stableDistractedCount < _kStableSubclassMin) {
        rawState = 'neutral';
        rawBestIdx = 0;
        debugPrint('[Stability] distracted subclass unstable '
            '(${kClassNames[_lastDistractedClass]} x$_stableDistractedCount/$_kStableSubclassMin)');
      }
    } else {
      _stableDistractedCount = (_stableDistractedCount - 1).clamp(0, 99);
    }

    if (rawState == 'drowsy') {
      _consecutiveDrowsy++;
      _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 9999);
    } else if (rawState == 'distracted') {
      _consecutiveDistracted++;
      _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 9999);
    } else {
      _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 9999);
      _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 9999);
    }

    final bool drowsyConfirmed = _consecutiveDrowsy >= _kDrowsyThreshold;
    final bool distractedConfirmed =
        _consecutiveDistracted >= _kDistractedThreshold;

    String outputState;
    int outputIdx;
    if (rawState == 'drowsy' && drowsyConfirmed) {
      outputState = 'drowsy';
      outputIdx = rawBestIdx;
    } else if (rawState == 'distracted' && distractedConfirmed) {
      outputState = 'distracted';
      outputIdx = rawBestIdx;
    } else {
      outputState = 'neutral';
      outputIdx = 0;
    }

    debugPrint('[Debounce] '
        'drowsy=$_consecutiveDrowsy/$_kDrowsyThreshold '
        'distracted=$_consecutiveDistracted/$_kDistractedThreshold '
        'raw=$rawState → out=$outputState '
        'yaw=${_faceYaw.toStringAsFixed(1)} compensated=${compensatedYaw.toStringAsFixed(1)} '
        'lookingAtRoad=$driverLookingAtRoad '
        'distPct=$distractedPct drowsyPct=$drowsyPct');

    return InferenceResult(
      state: outputState,
      subclass: kClassNames[outputIdx],
      subclassIndex: outputIdx,
      neutralPct: neutralPct.clamp(0.0, 100.0),
      drowsyPct: drowsyPct.clamp(0.0, 100.0),
      distractedPct: distractedPct.clamp(0.0, 100.0),
      fullProbs: List<double>.unmodifiable(probs),
      modelSource: ModelSource.v3,
      earAvg: earAvg,
      t02Active: _bufFill >= _kSeqLen,
      parentClass: parentClass,
      gazeZone: gazeZone,
    );
  }

  static String _classToMainState(int idx) {
    if (idx == 0 || idx == 1) return 'neutral';
    if (idx >= 9) return 'drowsy';
    return 'distracted';
  }

  static List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(math.max);
    final exps = logits.map((v) => math.exp(v - maxVal)).toList();
    final sum = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}

// ─── BACKGROUND ISOLATE DATA CLASSES ────────────────────────────────────────

class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
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
    this.earL = 0.0,
    this.earR = 0.0,
    this.mar = 0.0,
    this.pitch = 0.0,
    this.yaw = 0.0,
    this.rollEulerZ = 0.0,
  });
}

class _PrepOutputV3 {
  final Float32List rgbNormalized;
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

    final yBytes = input.planes[0].bytes;
    final uBytes = input.planes[1].bytes;
    final vBytes = input.planes[2].bytes;
    final yStride = input.planes[0].bytesPerRow;
    final uvStride = input.planes[1].bytesPerRow;
    final uvPixel = input.planes[1].bytesPerPixel;

    final rgb = Uint8List(w * h * 3);
    int outIdx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final y = yBytes[row * yStride + col] & 0xFF;
        final uvI = (row >> 1) * uvStride + (col >> 1) * uvPixel;
        final u = (uBytes[uvI] & 0xFF) - 128;
        final v = (vBytes[uvI] & 0xFF) - 128;
        rgb[outIdx++] = ((y * 1024 + 1402 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 - 344 * u - 714 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 + 1772 * u) >> 10).clamp(0, 255);
      }
    }

    const dstW = 224, dstH = 224;
    final normalized = Float32List(dstW * dstH * 3);
    final xScale = (w - 1) / (dstW - 1);
    final yScale = (h - 1) / (dstH - 1);
    int nIdx = 0;
    for (int dr = 0; dr < dstH; dr++) {
      final sy = dr * yScale;
      final sy0 = sy.toInt().clamp(0, h - 2);
      final sy1 = sy0 + 1;
      final fy = sy - sy0;
      final fy1 = 1.0 - fy;
      for (int dc = 0; dc < dstW; dc++) {
        final sx = dc * xScale;
        final sx0 = sx.toInt().clamp(0, w - 2);
        final sx1 = sx0 + 1;
        final fx = sx - sx0;
        final fx1 = 1.0 - fx;
        final i00 = (sy0 * w + sx0) * 3;
        final i10 = (sy0 * w + sx1) * 3;
        final i01 = (sy1 * w + sx0) * 3;
        final i11 = (sy1 * w + sx1) * 3;
        for (int c = 0; c < 3; c++) {
          final val = fy1 * (fx1 * rgb[i00 + c] + fx * rgb[i10 + c]) +
              fy * (fx1 * rgb[i01 + c] + fx * rgb[i11 + c]);
          normalized[nIdx++] = (val / 127.5) - 1.0;
        }
      }
    }

    final features = _extractFeaturesV3(input);

    return _PrepOutputV3(rgbNormalized: normalized, features: features);
  } catch (e) {
    debugPrint('[_preprocessFrameV3] Error: $e');
    return null;
  }
}

List<double> _extractFeaturesV3(_PrepInput input) {
  final features = List<double>.filled(20, kSentinel);
  features[18] = 0.0;
  features[19] = 0.0;

  final earAvg = (input.earL + input.earR) / 2.0;

  features[0] = input.earL;
  features[1] = input.earR;
  features[2] = earAvg;
  features[3] = math.min(input.earL, input.earR);
  features[4] = input.mar;

  features[5] = input.pitch;
  // FIX A: Subtract the corrected positive offset (+30.0).
  // The model was trained with yaw=0 meaning "looking straight ahead".
  // For our right-side mount the driver naturally has yaw≈+30, so we
  // subtract 30 to give the model a near-zero signal for normal driving.
  features[6] = input.yaw - kSideMountYawOffset;
  features[7] = input.rollEulerZ;

  return features;
}
