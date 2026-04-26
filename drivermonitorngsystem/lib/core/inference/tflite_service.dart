// PURPOSE:
//   Runs DMS-HybridNet V3 dual-input inference on every camera frame.
//   Produces an InferenceResult with the driver's current state.
//
// CAMERA MOUNT GEOMETRY:
//   Phone mounted to the RIGHT of the driver at 30–45° angle.
//   Front camera faces left toward the driver's face.
//   At this angle ML Kit eulerAngleY (yaw) ≈ +30° to +45° for a driver
//   looking straight ahead at the road.
//   kSideMountYawOffset = +35.0 (midpoint of 30–45° range).
//
// ROOT CAUSE OF "DETECTION NOT WORKING" (all screenshots showed 0%):
//   The previous version had gates that were TOO STRICT:
//   - _kDistractedThreshold = 22 frames × 200 ms = 4.4 seconds continuous
//   - distractedPct gate    = 78% (model rarely outputs this high from side angle)
//   - farLeftVeto at -20°   was vetoing all normal forward-driving detections
//   These combined made detection practically impossible.
//
// STRATEGY FOR RIGHT-SIDE MOUNT (30–45°):
//   1. The roll angle (eulerZ) affects the CIRCLE UI only — NOT detection logic.
//      Detection is based on yaw (face left/right) and the model's class probs.
//   2. Drowsy: EAR/MAR are angle-invariant → keep sensitive, fast response.
//   3. Distracted: Use a 2-stage approach:
//      Stage 1 — high confidence, triggers quickly (15 frames / ~3 s)
//      Stage 2 — moderate confidence, requires more stability (20 frames / ~4 s)
//   4. Yaw compensation: subtract mount offset so the model sees ~0 for
//      driver looking straight, negative for looking left, positive for right.
//   5. Remove the aggressive far-left veto — at 35° mount, the driver's face
//      pointing at the road IS slightly to the left of camera center, and that
//      is EXACTLY when we need to detect eyes-closed / yawning / phone use.

import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

const String _kModelAsset       = 'assets/models/dms_hybridnet_v3_float32.tflite';
const String _kNormParamsAsset  = 'assets/norm_params.json';

// 13 behavior class names (index = model output index)
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

const double kSentinel      = -999.0;
const double kMarYawnThresh = 0.5;

enum ModelSource { v3 }
String modelSourceLabel(ModelSource src) => 'V3 HybridNet';

// ══════════════════════════════════════════════════════════════════════════════
// TUNED CONSTANTS — RIGHT SIDE MOUNT 30–45°
// ══════════════════════════════════════════════════════════════════════════════

// Mount offset: midpoint of 30–45° range. Compensated yaw ≈ 0 when
// driver looks straight ahead. Negative = looking left (toward road center).
// Positive = looking right (toward window, likely distracted).
const double kSideMountYawOffset = 35.0;

// Yaw gate: driver is "on road" if |compensatedYaw| ≤ this value.
// At 35° mount, normal driving yaw variance is ±15°, so ±25° gives headroom.
const double _kOnRoadYawGate = 25.0;

// ── Drowsy thresholds ────────────────────────────────────────────────────────
// NOW WITH REAL EAR/MAR from head_pose_service.dart (enableClassification=true).
//
// EAR values:  wide open=0.40, normal=0.25-0.35, drowsy=0.15-0.22, closed=0.05
// MAR values:  closed=0.0-0.3, yawning=0.5-1.2
//
// With real EAR, the model's temporal buffer will show EAR DECREASING over
// time when driver gets drowsy — the earTrend feature becomes meaningful.
// Lower the gates to catch early drowsiness signals.
//
// 4 frames × 200ms = 0.8s — fast response for safety.
const int    _kDrowsyThreshold  = 4;
const double _kDrowsyPctGate    = 18.0; // lower — real EAR gives stronger signal
const double _kDrowsyBestScore  =  8.0;

// ── Distracted thresholds — THREE-STAGE (calibrated to session 109 output) ───
//
// ROOT CAUSE OF CONTINUED FAILURE (session 109):
//   distPct peaked at only 46–56% even for obvious actions (grooming 41–48%).
//   Gates of 65% (stage 2) and 85% (stage 1) are NEVER reachable for this model
//   from the 35° side-mount angle.
//
// ACTUAL MODEL OUTPUT RANGES (from session 109 logs):
//   Normal driving:     distPct  5–15%,  bestClass  2–9%
//   Mild distraction:   distPct 15–35%,  bestClass 10–24%
//   Clear distraction:  distPct 35–56%,  bestClass 25–48%
//
// THREE-STAGE based on actual signal levels:
//   Stage 1 HIGH    distPct ≥ 40%,  bestClass ≥ 25% →  6 frames (~1.2s)
//   Stage 2 MOD     distPct ≥ 22%,  bestClass ≥ 12% → 12 frames (~2.4s)
//   Stage 3 LOW     distPct ≥ 15%,  bestClass ≥  8% → 22 frames (~4.4s)
//
// Stage 1 fires without parent model agreement (model is clearly confident).
// Stages 2 and 3 require parent model agreement.
//
const double _kDistPctHigh    = 40.0;
const double _kDistBestHigh   = 25.0;
const int    _kDistThreshHigh =  6;   // 1.2s

const double _kDistPctMod     = 22.0;
const double _kDistBestMod    = 12.0;
const int    _kDistThreshMod  = 12;   // 2.4s

const double _kDistPctLow     = 15.0;
const double _kDistBestLow    =  8.0;
const int    _kDistThreshLow  = 22;   // 4.4s


// ── Per-class minimum confidence thresholds ──────────────────────────────────
//
// GROOMING FALSE POSITIVE FIX (session 111/112 analysis):
//   distracted_grooming fires constantly during safe driving:
//   - Normal driving baseline: grooming 2–27% (very wide noise floor!)
//   - Actual grooming action:  grooming 40–97%
//
//   ROOT CAUSE: From 35° side mount, glasses + hair partially occlude the face,
//   making it look like "hand near face" to the model — same visual signature as
//   grooming. This is a geometry artifact of the side-mount angle.
//
//   FIX 1: Raise grooming threshold from 8% → 35%.
//     Observed false-positive baseline peaks at ~27%. Real grooming peaks at 40%+.
//     Setting 35% puts us above the noise but below real detections.
//
//   FIX 2: Add grooming dominance check in detection logic (see below).
//     If grooming wins but radio/texting are within 15% of it, it's likely noise.
//     Real grooming dominates clearly (60–100% vs others <10%).
//
// Other classes tuned from session logs:
//   radio:   noise ~8–18% during side-mount normal driving → raise to 25%
//   texting: noise ~5–15% → raise to 20%
//   phone:   noise ~5–10% → raise to 15%
//
const Map<int, double> _kBehaviorClassThresholds = {
  // Neutral
  0:  40.0, // safe_driving
  1:  15.0, // talking_passenger

  // Distracted — thresholds set well above observed noise floor
  2:  20.0, // distracted_texting      ↑ from 5  — noise ~5–15%
  3:  15.0, // distracted_phone        ↑ from 5  — noise ~5–10%
  4:  25.0, // distracted_radio        ↑ from 8  — noise ~8–18%
  5:   5.0, // distracted_drinking     — very distinctive, almost no noise
  6:  50.0, // distracted_body         — catch-all, keep high
  7:  35.0, // distracted_grooming     ↑ from 8  — noise ~2–27%, real ~40%+
  8:   5.0, // distracted_smoking      — hand-to-mouth, almost no noise

  // Drowsy — EAR/MAR carry the weight after head_pose_service fix
  9:   6.0, // drowsy_yawning
  10:  8.0, // drowsy_yawning_occluded
  11:  5.0, // drowsy_fatigue
  12: 12.0, // drowsy_microsleep
};

// Inference gap: 150ms ≈ 6.7 FPS inference, camera preview unaffected.
const int _kMinInferenceGapMs = 150;

// ══════════════════════════════════════════════════════════════════════════════

// InferenceResult
class InferenceResult {
  final String state;
  final String subclass;
  final int    subclassIndex;

  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  final List<double> fullProbs;
  final ModelSource  modelSource;
  final double       earAvg;
  final bool         t02Active;

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

// TfliteService ───────────────────────────────────────────────────────────────
class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  Interpreter?         _interpreter;
  IsolateInterpreter?  _isolateInterpreter;
  bool _isInitialized    = false;
  bool _isRunning        = false;
  int  _lastInferenceMs  = 0;

  int _consecutiveDrowsy     = 0;
  int _consecutiveDistracted = 0;

  int _lastDistractedClass   = -1;
  int _stableDistractedCount = 0;
  int _peakDistStage         = 0;

  // Score accumulation window for subclass stability (replaces consecutive check)
  final Map<int, double> _classScoreAccum = {};
  int _classScoreFrames = 0;

  int _spatialInputIdx  = 1;
  int _temporalInputIdx = 0;

  int _behaviorOutputIdx = 0;
  int _parentOutputIdx   = 1;
  int _gazeOutputIdx     = 2;

  List<double> _normMean  = [];
  List<double> _normScale = [];

  double _faceEarL       = 0.0;
  double _faceEarR       = 0.0;
  double _faceMar        = 0.0;
  double _facePitch      = 0.0;
  double _faceYaw        = 0.0;
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

  final List<List<double>> _behaviorBuf = [List<double>.filled(13, 0.0)];
  final List<List<double>> _parentBuf   = [List<double>.filled(3,  0.0)];
  final List<List<double>> _gazeBuf     = [List<double>.filled(8,  0.0)];

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

  // ── Initialise ──────────────────────────────────────────────────────────────
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      final jsonStr  = await rootBundle.loadString(_kNormParamsAsset);
      final normData = jsonDecode(jsonStr) as Map<String, dynamic>;
      _normMean  = (normData['mean']  as List).map((v) => (v as num).toDouble()).toList();
      _normScale = (normData['scale'] as List).map((v) => (v as num).toDouble()).toList();

      final opts = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false;
      _interpreter = await Interpreter.fromAsset(_kModelAsset, options: opts);
      _interpreter!.allocateTensors();
      _isolateInterpreter = await IsolateInterpreter.create(
          address: _interpreter!.address);

      final inputTensors = _interpreter!.getInputTensors();
      final sIdx = inputTensors.indexWhere((t) => t.name.contains('spatial'));
      final tIdx = inputTensors.indexWhere((t) => t.name.contains('temporal'));
      if (sIdx != -1) _spatialInputIdx  = sIdx;
      if (tIdx != -1) _temporalInputIdx = tIdx;

      final outputTensors = _interpreter!.getOutputTensors();
      final bIdx = outputTensors.indexWhere((t) => t.shape.last == 13);
      final pIdx = outputTensors.indexWhere((t) => t.shape.last == 3);
      final gIdx = outputTensors.indexWhere((t) => t.shape.last == 8);
      if (bIdx != -1) _behaviorOutputIdx = bIdx;
      if (pIdx != -1) _parentOutputIdx   = pIdx;
      if (gIdx != -1) _gazeOutputIdx     = gIdx;

      _isInitialized = true;
      debugPrint('[TfliteService] ✅ DMS-HybridNet V3 loaded');
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Init failed: $e');
      return false;
    }
  }

  bool   get isInitialized => _isInitialized;
  double get bufferFillPct => (_bufFill / _kSeqLen * 100).clamp(0.0, 100.0);

  // ── Session reset ────────────────────────────────────────────────────────────
  void resetSession() {
    _bufFill               = 0;
    _consecutiveDrowsy     = 0;
    _consecutiveDistracted = 0;
    _lastDistractedClass   = -1;
    _stableDistractedCount = 0;
    _peakDistStage         = 0;
    _classScoreAccum.clear();
    _classScoreFrames      = 0;
    _lastInferenceMs       = 0;
    _isRunning             = false;

    for (int t = 0; t < _kSeqLen; t++) {
      for (int f = 0; f < _kNumBaseFeat; f++) {
        _temporalBuf[t][f] = kSentinel;
      }
      _temporalBuf[t][18] = 0.0;
      _temporalBuf[t][19] = 0.0;
    }

    _faceEarL       = 0.0;
    _faceEarR       = 0.0;
    _faceMar        = 0.0;
    _facePitch      = 0.0;
    _faceYaw        = 0.0;
    _faceRollEulerZ = 0.0;

    debugPrint('[TfliteService] session reset');
  }

  void dispose() {
    _isolateInterpreter?.close();
    _isolateInterpreter = null;
    _interpreter?.close();
    _interpreter   = null;
    _isInitialized = false;
    resetSession();
  }

  // ── Main inference entry point ───────────────────────────────────────────────
  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _interpreter == null || _isolateInterpreter == null) return null;
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
                    bytes:         p.bytes,
                    bytesPerRow:   p.bytesPerRow,
                    bytesPerPixel: p.bytesPerPixel ?? 1,
                  ))
              .toList(),
          width:      image.width,
          height:     image.height,
          earL:       _faceEarL,
          earR:       _faceEarR,
          mar:        _faceMar,
          pitch:      _facePitch,
          yaw:        _faceYaw,
          rollEulerZ: _faceRollEulerZ,
        ),
      );
      if (prep == null) return null;
      _lastInferenceMs = nowMs;
      final tPrep = DateTime.now().millisecondsSinceEpoch;

      _updateTemporalBuf(prep.features);
      final temporalFlat = _buildTemporalInput();

      for (int i = 0; i < 13; i++) {
        _behaviorBuf[0][i] = 0.0;
      }
      for (int i = 0; i < 3;  i++) {
        _parentBuf[0][i]   = 0.0;
      }
      for (int i = 0; i < 8;  i++) {
        _gazeBuf[0][i]     = 0.0;
      }

      // Pass raw byte buffers — hits the O(1) Uint8List fast path in
      // convertObjectToBytes, and the isolate copy is a flat memcpy (~0.6ms).
      // The actual TFLite forward pass runs in the background isolate, so the
      // main thread is NOT blocked during inference (~100–200ms saved per call).
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
      debugPrint('[TfliteService] prep=${tPrep - t0}ms infer=${tInfer - tPrep}ms total=${tInfer - t0}ms');

      final rawBehavior   = List<double>.from(_behaviorBuf[0]);
      final behaviorSum   = rawBehavior.fold(0.0, (a, b) => a + b);
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

  // ── Temporal buffer ──────────────────────────────────────────────────────────
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

    final earMean  = earVals.isEmpty ? 0.0 : earVals.reduce((a, b) => a + b) / earVals.length;
    final earMin   = earVals.isEmpty ? 0.0 : earVals.reduce(math.min);
    final marMax   = marVals.isEmpty ? 0.0 : marVals.reduce(math.max);
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

  // ── Core classification logic ────────────────────────────────────────────────
  InferenceResult _buildResult(
    List<double> probs,
    double       earAvg,
    int          parentClass,
    int          gazeZone,
  ) {
    // ── Accumulate probabilities by group ─────────────────────────────────────
    double neutralPct    = 0;
    double drowsyPct     = 0;
    double distractedPct = 0;

    int    bestDistIdx     = 2;
    double bestDistScore   = 0;
    int    bestDrowsyIdx   = 9;
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

    // ── Cross-class: demote body/reaching (class 6) catch-all ────────────────
    // If body wins with moderate confidence, check if a more specific class
    // is close behind and passes its own threshold.
    if (bestDistIdx == 6 && bestDistScore < 72.0) {
      double secondScore = 0.0;
      int    secondIdx   = 6;
      for (int i = 2; i <= 8; i++) {
        if (i == 6) continue;
        final pct = probs[i] * 100.0;
        if (pct > secondScore) { secondScore = pct; secondIdx = i; }
      }
      final secThresh = _kBehaviorClassThresholds[secondIdx] ?? 30.0;
      if (secondScore >= secThresh && secondScore >= bestDistScore * 0.60) {
        debugPrint('[CrossClass] Demoted body → ${kClassNames[secondIdx]} '
            '($secondScore% vs body $bestDistScore%)');
        bestDistIdx  = secondIdx;
        bestDistScore = secondScore;
      }
    }

    // ── Yaw geometry (informational — not a hard gate) ───────────────────────
    final compensatedYaw      = _faceYaw - kSideMountYawOffset;
    final driverLookingAtRoad = compensatedYaw.abs() <= _kOnRoadYawGate;

    final parentSaysDistracted = parentClass == 1;

    // ── GROOMING DOMINANCE CHECK ──────────────────────────────────────────────
    // From session 111/112: grooming (class 7) is a persistent false positive
    // because glasses+hair from 35° side angle looks like "hand near face".
    //
    // Real grooming: grooming dominates clearly (60–100%), others < 15%.
    // False positive: grooming 14–40% with radio/texting close behind (10–25%).
    //
    // FIX: If grooming wins but 2nd place is within 20% of it, demote to neutral.
    // This catches the noise pattern where grooming barely leads a crowded field.
    bool groomingIsFP = false;
    if (bestDistIdx == 7 && bestDistScore < 55.0) {
      // Find second-best distracted class score
      double secondBestScore = 0.0;
      for (int i = 2; i <= 8; i++) {
        if (i == 7) continue;
        final pct = probs[i] * 100.0;
        if (pct > secondBestScore) secondBestScore = pct;
      }
      // If 2nd place is within 20% of grooming, it's likely noise
      if (secondBestScore >= bestDistScore - 20.0) {
        groomingIsFP = true;
        debugPrint('[GroomingFP] demoted: grooming=${bestDistScore.toStringAsFixed(1)}% '
            'vs 2nd=${secondBestScore.toStringAsFixed(1)}% — too close, treating as noise');
      }
    }

    // Apply FP suppression
    if (groomingIsFP) {
      // Find next best non-grooming class
      int    altIdx   = 2;
      double altScore = 0.0;
      for (int i = 2; i <= 8; i++) {
        if (i == 7) continue;
        final pct = probs[i] * 100.0;
        if (pct > altScore) { altScore = pct; altIdx = i; }
      }
      final altThresh = _kBehaviorClassThresholds[altIdx] ?? 5.0;
      if (altScore >= altThresh) {
        bestDistIdx   = altIdx;
        bestDistScore = altScore;
        // Recalculate meets-threshold for new winner
      } else {
        // No valid alternative — suppress distraction entirely this frame
        bestDistScore = 0.0;
      }
    }

    // Recheck threshold with potentially updated bestDist
    final finalClassMinThreshold = _kBehaviorClassThresholds[bestDistIdx] ?? 5.0;
    final finalBestDistMeetsMin  = bestDistScore >= finalClassMinThreshold;

    // ── Raw state: DROWSY ─────────────────────────────────────────────────────
    String rawState    = 'neutral';
    int    rawBestIdx  = 0;
    int    activeStage = 0;

    if (drowsyPct >= _kDrowsyPctGate &&
        bestDrowsyScore >= _kDrowsyBestScore) {
      rawState   = 'drowsy';
      rawBestIdx = bestDrowsyIdx;
    }

    // ── Raw state: DISTRACTED — THREE-STAGE ──────────────────────────────────
    //
    // Stages calibrated to ACTUAL session output range:
    //   Normal driving:     distPct  5–15%, bestClass  2–9%
    //   Mild distraction:   distPct 15–35%, bestClass 10–24%
    //   Clear distraction:  distPct 35–56%, bestClass 25–48%
    //
    // Stage 1: High  distPct≥40%  bestClass≥25%  6 frames  no parent needed
    // Stage 2: Mod   distPct≥22%  bestClass≥12%  12 frames parent required
    // Stage 3: Low   distPct≥15%  bestClass≥ 8%  22 frames parent+not on road
    //
    // Grooming (class 7) is excluded from stages 2 and 3 unless it clearly
    // dominates (handled by groomingIsFP check above — if it's a FP, bestDistScore=0).
    //
    else if (finalBestDistMeetsMin &&
        distractedPct >= _kDistPctHigh &&
        bestDistScore >= _kDistBestHigh) {
      rawState    = 'distracted';
      rawBestIdx  = bestDistIdx;
      activeStage = 1;
    }
    else if (finalBestDistMeetsMin &&
        distractedPct >= _kDistPctMod &&
        bestDistScore >= _kDistBestMod &&
        parentSaysDistracted &&
        bestDistIdx != 6) {
      rawState    = 'distracted';
      rawBestIdx  = bestDistIdx;
      activeStage = 2;
    }
    else if (finalBestDistMeetsMin &&
        distractedPct >= _kDistPctLow &&
        bestDistScore >= _kDistBestLow &&
        parentSaysDistracted &&
        bestDistIdx != 6 &&
        !driverLookingAtRoad) {
      rawState    = 'distracted';
      rawBestIdx  = bestDistIdx;
      activeStage = 3;
    }

    // ── Subclass stability — accumulated score approach ───────────────────────
    // PROBLEM: grooming/radio/texting alternate every frame → consecutive
    // same-class requirement (2 frames) resets constantly → counter stays at 1.
    //
    // FIX: Remove per-subclass consecutive requirement entirely for stages 1+2.
    // Instead, any distracted class that passes its threshold contributes to the
    // consecutive counter. The class label for the OUTPUT is the one with the
    // highest accumulated score across the last 3 frames (rolling window).
    //
    // For stage 3 (low confidence), keep the 2-frame requirement since it's
    // a weaker signal and we need more certainty about which class it is.
    //
    if (rawState == 'distracted') {
      // Accumulate scores per class in rolling window (class index → score sum)
      _classScoreAccum[bestDistIdx] =
          (_classScoreAccum[bestDistIdx] ?? 0.0) + bestDistScore;
      _classScoreFrames++;

      // Every 3 frames, pick the dominant class and reset window
      if (_classScoreFrames >= 3) {
        int    dominantIdx   = bestDistIdx;
        double dominantScore = 0.0;
        _classScoreAccum.forEach((idx, score) {
          if (score > dominantScore) { dominantScore = score; dominantIdx = idx; }
        });
        _lastDistractedClass = dominantIdx;
        _classScoreAccum.clear();
        _classScoreFrames = 0;
      }

      // For stage 3 only: require 2 consecutive same-class frames
      if (activeStage == 3) {
        if (rawBestIdx != _lastDistractedClass) {
          rawState    = 'neutral';
          rawBestIdx  = 0;
          activeStage = 0;
          debugPrint('[Stability-s3] class mismatch, waiting');
        }
      } else {
        // Stages 1 and 2: use accumulated dominant class as output label
        rawBestIdx = _lastDistractedClass;
      }
    } else {
      _stableDistractedCount = (_stableDistractedCount - 1).clamp(0, 99);
      // Decay the score window gradually when neutral
      if (_classScoreFrames > 0) _classScoreFrames--;
    }

    // ── Consecutive-frame debounce ────────────────────────────────────────────
    //
    // STAGE PERSISTENCE FIX:
    //   When one neutral frame interrupts a distracted run, activeStage drops
    //   to 0 (stage low = 22 frames threshold), making the counter appear far
    //   from threshold even though distraction resumes next frame.
    //
    //   Solution: track _peakStage — the highest stage seen while consecutive
    //   counter is > 0. Use peakStage for the threshold. Only reset peakStage
    //   when counter fully decays to 0.
    //
    if (rawState == 'drowsy') {
      _consecutiveDrowsy++;
      _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 9999);
      if (_consecutiveDistracted == 0) _peakDistStage = 0;
    } else if (rawState == 'distracted') {
      _consecutiveDistracted++;
      _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 9999);
      // Track the highest stage seen in this distraction run
      if (activeStage > _peakDistStage) _peakDistStage = activeStage;
    } else {
      _consecutiveDrowsy     = (_consecutiveDrowsy     - 1).clamp(0, 9999);
      _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 9999);
      if (_consecutiveDistracted == 0) _peakDistStage = 0;
    }

    // Use peak stage for threshold so one neutral frame doesn't switch to slow gate
    final int effectiveStage    = _consecutiveDistracted > 0 ? _peakDistStage : 0;
    final int effectiveDistThreshold = switch (effectiveStage) {
      1 => _kDistThreshHigh,
      2 => _kDistThreshMod,
      _ => _kDistThreshLow,
    };

    final bool drowsyConfirmed     = _consecutiveDrowsy     >= _kDrowsyThreshold;
    final bool distractedConfirmed = _consecutiveDistracted >= effectiveDistThreshold;

    String outputState;
    int    outputIdx;

    if (rawState == 'drowsy' && drowsyConfirmed) {
      outputState = 'drowsy';
      outputIdx   = rawBestIdx;
    } else if (distractedConfirmed) {
      // Sustain distracted output even during brief neutral frames (1–2 frame gaps)
      // as long as counter hasn't decayed below threshold.
      // rawBestIdx may be 0 if this frame is neutral — use last known class.
      outputState = 'distracted';
      outputIdx   = rawBestIdx != 0
          ? rawBestIdx
          : (_lastDistractedClass >= 0 ? _lastDistractedClass : 0);
    } else {
      outputState = 'neutral';
      outputIdx   = 0;
    }

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

// ─── CONSTANTS (unchanged) ───────────────────────────────────────────────────
const int _kSeqLen      = 30;
const int _kNumBaseFeat = 20;
const int _kNumFeat     = 25;

// ─── BACKGROUND ISOLATE DATA CLASSES ─────────────────────────────────────────

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
  final int    width;
  final int    height;
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
  final Float32List  rgbNormalized;
  final List<double> features;
  const _PrepOutputV3({required this.rgbNormalized, required this.features});
}

// ─── TOP-LEVEL PREPROCESSING — runs in compute() isolate ─────────────────────

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

    // YUV → RGB
    final rgb  = Uint8List(w * h * 3);
    int outIdx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final y   = yBytes[row * yStride + col] & 0xFF;
        final uvI = (row >> 1) * uvStride + (col >> 1) * uvPixel;
        final u   = (uBytes[uvI] & 0xFF) - 128;
        final v   = (vBytes[uvI] & 0xFF) - 128;
        rgb[outIdx++] = ((y * 1024 + 1402 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 - 344 * u - 714 * v) >> 10).clamp(0, 255);
        rgb[outIdx++] = ((y * 1024 + 1772 * u) >> 10).clamp(0, 255);
      }
    }

    // Bilinear resize → 224×224 and normalise to [-1, 1]
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
  // Subtract mount offset so model sees ~0 when driver looks straight.
  // Range: -35° (far left/road) to +35° (far right/window).
  features[6] = input.yaw - kSideMountYawOffset;
  features[7] = input.rollEulerZ;

  return features;
}