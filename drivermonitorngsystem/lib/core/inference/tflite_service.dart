import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

const String _kModelAsset = 'assets/model/dms_hybridnet_v3_float32.tflite';
const String _kNormParamsAsset = 'assets/norm_params.json';

// 13 behavior class names — index matches model output index.
const List<String> kClassNames = [
  'safe_driving',             // 0  → NATURAL
  'talking_passenger',        // 1  → NATURAL
  'distracted_texting',       // 2  → DISTRACTED
  'distracted_phone',         // 3  → DISTRACTED
  'distracted_radio',         // 4  → DISTRACTED
  'distracted_drinking',      // 5  → DISTRACTED
  'distracted_body',          // 6  → DISTRACTED
  'distracted_grooming',      // 7  → DISTRACTED
  'distracted_smoking',       // 8  → DISTRACTED
  'drowsy_yawning',           // 9  → DROWSY
  'drowsy_yawning_occluded',  // 10 → DROWSY
  'drowsy_fatigue',           // 11 → DROWSY
  'drowsy_microsleep',        // 12 → DROWSY
];

const List<String> kParentNames = ['NATURAL', 'DISTRACTED', 'DROWSY'];

const List<String> kGazeZones = [
  'ROAD', 'LAP', 'LEFT', 'LEFT_MIRROR',
  'RIGHT', 'RIGHT_MIRROR', 'STEERING', 'NOT_VALID',
];

const double kSentinel    = -999.0;
const double kMarYawnThresh = 0.5;

enum ModelSource { v3 }

String modelSourceLabel(ModelSource src) => 'V3 HybridNet';

// ── Sequence constants ────────────────────────────────────────────────────────
const int _kSeqLen      = 30;
const int _kNumBaseFeat = 20;
const int _kNumFeat     = 25;

// ── Mount geometry ────────────────────────────────────────────────────────────
// Phone mounted to the right of the driver at 30–45°. The yaw offset
// compensates so the model sees ~0° for a driver looking straight ahead.
const double kSideMountYawOffset = 35.0;
const double _kOnRoadYawGate     = 25.0;

// ── Drowsy thresholds ─────────────────────────────────────────────────────────
// EAR: wide-open≈0.40, normal=0.25–0.35, drowsy=0.15–0.22, closed≈0.05
// MAR: closed=0.0–0.3, yawning=0.5–1.2
const int    _kDrowsyThreshold = 3;    // 0.6 s at 200 ms/frame
const double _kDrowsyPctGate   = 15.0;

// ── Distracted thresholds — three stages calibrated to 35° side-mount output ──
// Actual model output ranges observed from real sessions at this mount angle:
//   Normal driving:    distPct  5–15%,  bestClass  2– 9%
//   Mild distraction:  distPct 15–35%,  bestClass 10–24%
//   Clear distraction: distPct 35–56%,  bestClass 25–48%
//
// Stage 1 HIGH  — distPct≥40%  bestClass≥25%  6 frames  no parent needed
// Stage 2 MOD   — distPct≥22%  bestClass≥12%  12 frames parent required
// Stage 3 LOW   — distPct≥15%  bestClass≥ 8%  22 frames parent+off-road required
const double _kDistPctHigh   = 40.0;
const double _kDistBestHigh  = 25.0;
const int    _kDistThreshHigh = 6;   // ~1.2 s

const double _kDistPctMod   = 22.0;
const double _kDistBestMod  = 12.0;
const int    _kDistThreshMod = 12;   // ~2.4 s

const double _kDistPctLow   = 15.0;
const double _kDistBestLow  = 8.0;
const int    _kDistThreshLow = 22;   // ~4.4 s

// ── Per-class minimum thresholds (set above observed noise floor) ─────────────
// Side-mount geometry inflates noise for grooming/radio/texting.
// Thresholds are tuned to sit between noise peaks and real-action peaks.
const Map<int, double> _kBehaviorClassThresholds = {
  0: 40.0,  // safe_driving
  1: 15.0,  // talking_passenger
  2: 20.0,  // distracted_texting       noise ~5–15%
  3: 15.0,  // distracted_phone         noise ~5–10%
  4: 25.0,  // distracted_radio         noise ~8–18%
  5: 5.0,   // distracted_drinking
  6: 50.0,  // distracted_body
  7: 35.0,  // distracted_grooming      noise ~2–27%, real ~40%+
  8: 5.0,   // distracted_smoking
  9: 4.0,   // drowsy_yawning
  10: 6.0,  // drowsy_yawning_occluded
  11: 3.5,  // drowsy_fatigue
  12: 8.0,  // drowsy_microsleep
};

// 200 ms gap ≈ 5 FPS inference; camera preview runs unaffected.
const int _kMinInferenceGapMs = 200;

// ── InferenceResult ───────────────────────────────────────────────────────────

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

// ── TfliteService ─────────────────────────────────────────────────────────────

class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  bool _isInitialized = false;
  bool _isRunning = false;
  int _lastInferenceMs = 0;

  int _consecutiveDrowsy = 0;
  int _consecutiveDistracted = 0;

  int _lastDistractedClass = -1;
  int _stableDistractedCount = 0;
  int _peakDistStage = 0;

  final Map<int, double> _classScoreAccum = {};
  int _classScoreFrames = 0;

  int _spatialInputIdx = 1;
  int _temporalInputIdx = 0;

  int _behaviorOutputIdx = 0;
  int _parentOutputIdx = 1;
  int _gazeOutputIdx = 2;

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
  final List<List<double>> _parentBuf   = [List<double>.filled(3, 0.0)];
  final List<List<double>> _gazeBuf     = [List<double>.filled(8, 0.0)];

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
      _normMean  = (normData['mean']  as List).map((v) => (v as num).toDouble()).toList();
      _normScale = (normData['scale'] as List).map((v) => (v as num).toDouble()).toList();

      final opts = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false;
      _interpreter = await Interpreter.fromAsset(_kModelAsset, options: opts);
      _interpreter!.allocateTensors();
      _isolateInterpreter =
          await IsolateInterpreter.create(address: _interpreter!.address);

      final inputTensors = _interpreter!.getInputTensors();
      final sIdx = inputTensors.indexWhere((t) => t.name.contains('spatial'));
      final tIdx = inputTensors.indexWhere((t) => t.name.contains('temporal'));
      if (sIdx != -1) _spatialInputIdx = sIdx;
      if (tIdx != -1) _temporalInputIdx = tIdx;

      final outputTensors = _interpreter!.getOutputTensors();
      final bIdx = outputTensors.indexWhere((t) => t.shape.last == 13);
      final pIdx = outputTensors.indexWhere((t) => t.shape.last == 3);
      final gIdx = outputTensors.indexWhere((t) => t.shape.last == 8);
      if (bIdx != -1) _behaviorOutputIdx = bIdx;
      if (pIdx != -1) _parentOutputIdx = pIdx;
      if (gIdx != -1) _gazeOutputIdx = gIdx;

      _isInitialized = true;
      debugPrint('[TfliteService] ✅ DMS-HybridNet V3 loaded');
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
    _peakDistStage = 0;
    _classScoreAccum.clear();
    _classScoreFrames = 0;
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

    debugPrint('[TfliteService] session reset');
  }

  void dispose() {
    _isolateInterpreter?.close();
    _isolateInterpreter = null;
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    resetSession();
  }

  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _interpreter == null || _isolateInterpreter == null) {
      return null;
    }
    if (_isRunning) return null;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastInferenceMs < _kMinInferenceGapMs) return null;

    _isRunning = true;
    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
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
      final tPrep = DateTime.now().millisecondsSinceEpoch;

      _updateTemporalBuf(prep.features);
      final temporalFlat = _buildTemporalInput();

      for (int i = 0; i < 13; i++) { _behaviorBuf[0][i] = 0.0; }
      for (int i = 0; i < 3;  i++) { _parentBuf[0][i]   = 0.0; }
      for (int i = 0; i < 8;  i++) { _gazeBuf[0][i]     = 0.0; }

      // Pass raw Uint8List buffers — hits the O(1) fast path in
      // convertObjectToBytes; the isolate copy is a flat memcpy (~0.6 ms).
      final inputs = List<Object?>.filled(2, null);
      inputs[_temporalInputIdx] = temporalFlat.buffer.asUint8List();
      inputs[_spatialInputIdx]  = prep.rgbNormalized.buffer.asUint8List();

      await _isolateInterpreter!.runForMultipleInputs(
        inputs.cast<Object>(),
        <int, Object>{
          _behaviorOutputIdx: _behaviorBuf,
          _parentOutputIdx:   _parentBuf,
          _gazeOutputIdx:     _gazeBuf,
        },
      );
      final tInfer = DateTime.now().millisecondsSinceEpoch;
      debugPrint(
          '[TfliteService] prep=${tPrep - t0}ms infer=${tInfer - tPrep}ms total=${tInfer - t0}ms');

      final rawBehavior = List<double>.from(_behaviorBuf[0]);
      final behaviorSum = rawBehavior.fold(0.0, (a, b) => a + b);
      final behaviorProbs = (behaviorSum - 1.0).abs() > 0.01
          ? _softmax(rawBehavior)
          : rawBehavior;

      final parentProbs = List<double>.from(_parentBuf[0]);
      final gazeProbs   = List<double>.from(_gazeBuf[0]);

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

  Float32List _buildTemporalInput() {
    final stats = _computeWindowStats();
    final flat  = Float32List(_kSeqLen * _kNumFeat);
    for (int t = 0; t < _kSeqLen; t++) {
      final offset = t * _kNumFeat;
      for (int f = 0; f < _kNumBaseFeat; f++) {
        final raw = _temporalBuf[t][f];
        flat[offset + f] = raw == kSentinel
            ? 0.0
            : (raw - _normMean[f]) / (_normScale[f] + 1e-8);
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
    final earMin  = earVals.isEmpty ? 0.0 : earVals.reduce(math.min);
    final marMax  = marVals.isEmpty ? 0.0 : marVals.reduce(math.max);
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
        sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x;
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
    double neutralPct = 0, drowsyPct = 0, distractedPct = 0;

    int bestDistIdx = 2, bestDrowsyIdx = 9;
    double bestDistScore = 0, bestDrowsyScore = 0;

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
        if (pct > bestDistScore)  { bestDistScore = pct;  bestDistIdx = i;  }
      }
    }

    // Demote distracted_body (class 6) if a more specific class is close behind.
    if (bestDistIdx == 6 && bestDistScore < 72.0) {
      double secondScore = 0.0;
      int secondIdx = 6;
      for (int i = 2; i <= 8; i++) {
        if (i == 6) continue;
        final pct = probs[i] * 100.0;
        if (pct > secondScore) { secondScore = pct; secondIdx = i; }
      }
      final secThresh = _kBehaviorClassThresholds[secondIdx] ?? 30.0;
      if (secondScore >= secThresh && secondScore >= bestDistScore * 0.60) {
        if (kDebugMode) {
          debugPrint('[CrossClass] demoted body → ${kClassNames[secondIdx]} '
              '($secondScore% vs body $bestDistScore%)');
        }
        bestDistIdx  = secondIdx;
        bestDistScore = secondScore;
      }
    }

    final compensatedYaw    = _faceYaw - kSideMountYawOffset;
    final driverLookingAtRoad = compensatedYaw.abs() <= _kOnRoadYawGate;
    final parentSaysDistracted = parentClass == 1;

    // Grooming false-positive suppression: from the 35° side mount, glasses and
    // hair can look like "hand near face". Suppress if grooming barely leads a
    // crowded field (2nd place within 20% of it).
    bool groomingIsFP = false;
    if (bestDistIdx == 7 && bestDistScore < 55.0) {
      double secondBestScore = 0.0;
      for (int i = 2; i <= 8; i++) {
        if (i == 7) continue;
        final pct = probs[i] * 100.0;
        if (pct > secondBestScore) secondBestScore = pct;
      }
      if (secondBestScore >= bestDistScore - 20.0) {
        groomingIsFP = true;
        if (kDebugMode) {
          debugPrint('[GroomingFP] suppressed: grooming=${bestDistScore.toStringAsFixed(1)}% '
              '2nd=${secondBestScore.toStringAsFixed(1)}% — too close, treating as noise');
        }
      }
    }

    if (groomingIsFP) {
      int altIdx = 2; double altScore = 0.0;
      for (int i = 2; i <= 8; i++) {
        if (i == 7) continue;
        final pct = probs[i] * 100.0;
        if (pct > altScore) { altScore = pct; altIdx = i; }
      }
      final altThresh = _kBehaviorClassThresholds[altIdx] ?? 5.0;
      if (altScore >= altThresh) {
        bestDistIdx  = altIdx;
        bestDistScore = altScore;
      } else {
        bestDistScore = 0.0;
      }
    }

    final finalClassMinThreshold = _kBehaviorClassThresholds[bestDistIdx] ?? 5.0;
    final finalBestDistMeetsMin  = bestDistScore >= finalClassMinThreshold;

    String rawState = 'neutral';
    int rawBestIdx = 0, activeStage = 0;

    final finalDrowsyMinThreshold = _kBehaviorClassThresholds[bestDrowsyIdx] ?? 6.0;
    final finalBestDrowsyMeetsMin = bestDrowsyScore >= finalDrowsyMinThreshold;

    if (drowsyPct >= _kDrowsyPctGate && finalBestDrowsyMeetsMin) {
      rawState = 'drowsy';
      rawBestIdx = bestDrowsyIdx;
    } else if (finalBestDistMeetsMin &&
        distractedPct >= _kDistPctHigh && bestDistScore >= _kDistBestHigh) {
      rawState = 'distracted'; rawBestIdx = bestDistIdx; activeStage = 1;
    } else if (finalBestDistMeetsMin &&
        distractedPct >= _kDistPctMod && bestDistScore >= _kDistBestMod &&
        parentSaysDistracted && bestDistIdx != 6) {
      rawState = 'distracted'; rawBestIdx = bestDistIdx; activeStage = 2;
    } else if (finalBestDistMeetsMin &&
        distractedPct >= _kDistPctLow && bestDistScore >= _kDistBestLow &&
        parentSaysDistracted && bestDistIdx != 6 && !driverLookingAtRoad) {
      rawState = 'distracted'; rawBestIdx = bestDistIdx; activeStage = 3;
    }

    // Subclass stability: accumulate scores over a 3-frame rolling window and
    // output the dominant class rather than requiring consecutive same-class
    // frames (which resets constantly when grooming/radio/texting alternate).
    if (rawState == 'distracted') {
      _classScoreAccum[bestDistIdx] =
          (_classScoreAccum[bestDistIdx] ?? 0.0) + bestDistScore;
      _classScoreFrames++;

      if (_classScoreFrames >= 3) {
        int dominantIdx = bestDistIdx;
        double dominantScore = 0.0;
        _classScoreAccum.forEach((idx, score) {
          if (score > dominantScore) { dominantScore = score; dominantIdx = idx; }
        });
        _lastDistractedClass = dominantIdx;
        _classScoreAccum.clear();
        _classScoreFrames = 0;
      }

      if (activeStage == 3) {
        if (rawBestIdx != _lastDistractedClass) {
          rawState = 'neutral'; rawBestIdx = 0; activeStage = 0;
          if (kDebugMode) debugPrint('[Stability-s3] class mismatch, waiting');
        }
      } else {
        rawBestIdx = _lastDistractedClass;
      }
    } else {
      _stableDistractedCount = (_stableDistractedCount - 1).clamp(0, 99);
      if (_classScoreFrames > 0) _classScoreFrames--;
    }

    // Consecutive-frame debounce with peak-stage persistence: track the highest
    // stage seen while the counter is > 0 so a single neutral frame doesn't
    // downgrade the threshold (e.g. stage 1→stage 3 = 22-frame gate).
    if (rawState == 'drowsy') {
      _consecutiveDrowsy++;
      _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 9999);
      if (_consecutiveDistracted == 0) _peakDistStage = 0;
    } else if (rawState == 'distracted') {
      _consecutiveDistracted++;
      _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 9999);
      if (activeStage > _peakDistStage) _peakDistStage = activeStage;
    } else {
      _consecutiveDrowsy     = (_consecutiveDrowsy     - 1).clamp(0, 9999);
      _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 9999);
      if (_consecutiveDistracted == 0) _peakDistStage = 0;
    }

    final int effectiveStage = _consecutiveDistracted > 0 ? _peakDistStage : 0;
    final int effectiveDistThreshold = switch (effectiveStage) {
      1 => _kDistThreshHigh,
      2 => _kDistThreshMod,
      _ => _kDistThreshLow,
    };

    final bool drowsyConfirmed     = _consecutiveDrowsy     >= _kDrowsyThreshold;
    final bool distractedConfirmed = _consecutiveDistracted >= effectiveDistThreshold;

    String outputState;
    int outputIdx;

    if (rawState == 'drowsy' && drowsyConfirmed) {
      outputState = 'drowsy';
      outputIdx   = rawBestIdx;
    } else if (distractedConfirmed) {
      outputState = 'distracted';
      outputIdx   = rawBestIdx != 0
          ? rawBestIdx
          : (_lastDistractedClass >= 0 ? _lastDistractedClass : 0);
    } else {
      outputState = 'neutral';
      outputIdx   = 0;
    }

    return InferenceResult(
      state:          outputState,
      subclass:       kClassNames[outputIdx],
      subclassIndex:  outputIdx,
      neutralPct:     neutralPct.clamp(0.0, 100.0),
      drowsyPct:      drowsyPct.clamp(0.0, 100.0),
      distractedPct:  distractedPct.clamp(0.0, 100.0),
      fullProbs:      List<double>.unmodifiable(probs),
      modelSource:    ModelSource.v3,
      earAvg:         earAvg,
      t02Active:      _bufFill >= _kSeqLen,
      parentClass:    parentClass,
      gazeZone:       gazeZone,
    );
  }

  static String _classToMainState(int idx) {
    if (idx == 0 || idx == 1) return 'neutral';
    if (idx >= 9)             return 'drowsy';
    return 'distracted';
  }

  static List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(math.max);
    final exps   = logits.map((v) => math.exp(v - maxVal)).toList();
    final sum    = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}

// ── Background isolate data classes ──────────────────────────────────────────

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
  const _PrepOutputV3({required this.rgbNormalized, required this.features});
}

// ── Frame preprocessing (runs in compute() isolate) ───────────────────────────

_PrepOutputV3? _preprocessFrameV3(_PrepInput input) {
  try {
    final w = input.width;
    final h = input.height;

    final yBytes  = input.planes[0].bytes;
    final uBytes  = input.planes[1].bytes;
    final vBytes  = input.planes[2].bytes;
    final yStride = input.planes[0].bytesPerRow;
    final uvStride = input.planes[1].bytesPerRow;
    final uvPixel  = input.planes[1].bytesPerPixel;

    final rgb = Uint8List(w * h * 3);
    int outIdx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final y  = yBytes[row * yStride + col] & 0xFF;
        final uvI = (row >> 1) * uvStride + (col >> 1) * uvPixel;
        final u  = (uBytes[uvI] & 0xFF) - 128;
        final v  = (vBytes[uvI] & 0xFF) - 128;
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
  // Subtract mount offset so ~0 = driver looking straight ahead.
  features[6] = input.yaw - kSideMountYawOffset;
  features[7] = input.rollEulerZ;

  return features;
}
