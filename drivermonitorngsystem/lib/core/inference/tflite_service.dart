import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ─── INFERENCE RESULT ────────────────────────────────────────────────────────

class InferenceResult {
  final String state;
  final double alertnessPct;
  final double drowsyPct;
  final double distractedPct;
  final int subclassId;
  final String subclassLabel;
  final List<double> rawScores;

  const InferenceResult({
    required this.state,
    required this.alertnessPct,
    required this.drowsyPct,
    required this.distractedPct,
    required this.subclassId,
    required this.subclassLabel,
    required this.rawScores,
  });
}

// ─── V2 TAXONOMY ─────────────────────────────────────────────────────────────

class _SubclassMeta {
  final int id;
  final String label;
  final String mainClass;
  const _SubclassMeta(this.id, this.label, this.mainClass);
}

const List<_SubclassMeta> _kSubclasses = [
  _SubclassMeta(0,  'Safe Driving',          'neutral'),
  _SubclassMeta(1,  'Yawning',               'drowsy'),
  _SubclassMeta(2,  'Fatigue Head Droop',    'drowsy'),
  _SubclassMeta(3,  'Texting',               'distracted'),
  _SubclassMeta(4,  'Phone Call',            'distracted'),
  _SubclassMeta(5,  'Adjusting Radio',       'distracted'),
  _SubclassMeta(6,  'Drinking',              'distracted'),
  _SubclassMeta(7,  'Reaching Behind',       'distracted'),
  _SubclassMeta(8,  'Hair / Makeup',         'distracted'),
  _SubclassMeta(9,  'Talking to Passenger',  'distracted'),
  _SubclassMeta(12, 'Eyes Closed (PERCLOS)', 'drowsy'),
];

// ─── TFLITE SERVICE ───────────────────────────────────────────────────────────

class TfliteService {
  TfliteService._();
  static final TfliteService instance = TfliteService._();

  Interpreter? _interpreter;
  bool _initialized = false;
  bool get isReady => _initialized;

  static const String _assetPath     = 'assets/dms_hybridnet.tflite';
  static const String _modelFileName = 'dms_hybridnet.tflite';
  static const String _tag           = 'TfliteService';

  static const int _inputH     = 224;
  static const int _inputW     = 224;
  static const int _numClasses = 10;

  late List<List<List<List<double>>>> _inputBuffer;
  late List<List<double>>            _outputBuffer;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      // Step 1: Load asset bytes
      debugPrint('[$_tag] Step 1: Loading asset bytes from $_assetPath');
      final ByteData modelData;
      try {
        modelData = await rootBundle.load(_assetPath);
      } catch (e) {
        debugPrint('[$_tag] FAILED at Step 1 — asset not found: $e');
        debugPrint('[$_tag] Check pubspec.yaml has: - $_assetPath');
        return false;
      }

      final Uint8List modelBytes = modelData.buffer.asUint8List();
      debugPrint('[$_tag] Step 1 OK — loaded ${modelBytes.length} bytes');

      // Step 2: Write to temp file
      debugPrint('[$_tag] Step 2: Writing model to temp directory');
      final File modelFile;
      try {
        final Directory tempDir = await getTemporaryDirectory();
        modelFile = File('${tempDir.path}/$_modelFileName');
        await modelFile.writeAsBytes(modelBytes, flush: true);
        debugPrint('[$_tag] Step 2 OK — written to ${modelFile.path}');
      } catch (e) {
        debugPrint('[$_tag] FAILED at Step 2 — temp file write error: $e');
        return false;
      }

      // Step 3: Create interpreter
      debugPrint('[$_tag] Step 3: Creating interpreter from file');
      try {
        final options = InterpreterOptions()..threads = 2;
        _interpreter = Interpreter.fromFile(modelFile, options: options);
        debugPrint('[$_tag] Step 3 OK — interpreter created');
      } catch (e) {
        debugPrint('[$_tag] FAILED at Step 3 — interpreter creation: $e');
        debugPrint('[$_tag] This usually means flex ops are not linked.');
        debugPrint('[$_tag] Verify build.gradle.kts has tensorflow-lite-select-tf-ops');
        return false;
      }

      // Step 4: Allocate tensors
      debugPrint('[$_tag] Step 4: Allocating tensors');
      try {
        _interpreter!.allocateTensors();
        final inp = _interpreter!.getInputTensor(0);
        final out = _interpreter!.getOutputTensor(0);
        debugPrint('[$_tag] Step 4 OK — input shape: ${inp.shape}, output shape: ${out.shape}');

        if (out.shape.last != _numClasses) {
          debugPrint('[$_tag] WARNING: expected $_numClasses output classes, got ${out.shape.last}');
          debugPrint('[$_tag] Update _numClasses to match your model output.');
        }
      } catch (e) {
        debugPrint('[$_tag] FAILED at Step 4 — allocateTensors: $e');
        return false;
      }

      // Step 5: Allocate I/O buffers
      debugPrint('[$_tag] Step 5: Allocating I/O buffers');
      final int actualClasses = _interpreter!.getOutputTensor(0).shape.last;
      _inputBuffer = List.generate(
        1,
        (_) => List.generate(
          _inputH,
          (_) => List.generate(
            _inputW,
            (_) => List<double>.filled(3, 0.0),
          ),
        ),
      );
      _outputBuffer = List.generate(
        1,
        (_) => List<double>.filled(actualClasses, 0.0),
      );
      debugPrint('[$_tag] Step 5 OK — buffers ready, output size: $actualClasses');

      // Step 6: Warm-up
      debugPrint('[$_tag] Step 6: Running warm-up inference');
      try {
        _interpreter!.run(_inputBuffer, _outputBuffer);
        debugPrint('[$_tag] Step 6 OK — warm-up passed, output: ${_outputBuffer[0]}');
      } catch (e) {
        debugPrint('[$_tag] FAILED at Step 6 — warm-up inference: $e');
        return false;
      }

      _initialized = true;
      debugPrint('[$_tag] ✅ Initialization COMPLETE — AI mode active');
      return true;

    } catch (e, stack) {
      debugPrint('[$_tag] UNEXPECTED ERROR during initialize(): $e');
      debugPrint('[$_tag] Stack: $stack');
      _initialized = false;
      return false;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _initialized = false;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  Future<InferenceResult?> runInference(CameraImage frame) async {
    if (!_initialized || _interpreter == null) return null;
    try {
      if (!_preprocessYuv420(frame)) return null;
      _interpreter!.run(_inputBuffer, _outputBuffer);
      return _postprocess(_outputBuffer[0]);
    } catch (e) {
      debugPrint('[$_tag] runInference error: $e');
      return null;
    }
  }

  // ── Pre-processing ────────────────────────────────────────────────────────

  bool _preprocessYuv420(CameraImage frame) {
    try {
      final int srcW = frame.width;
      final int srcH = frame.height;

      final Uint8List yPlane  = frame.planes[0].bytes;
      final Uint8List uvPlane = frame.planes[1].bytes;
      final Uint8List vPlane  = frame.planes[2].bytes;

      final int yRowStride  = frame.planes[0].bytesPerRow;
      final int uvRowStride = frame.planes[1].bytesPerRow;
      final int uvPixStride = frame.planes[1].bytesPerPixel ?? 1;

      final double scaleX = srcW / _inputW;
      final double scaleY = srcH / _inputH;

      for (int dstY = 0; dstY < _inputH; dstY++) {
        final int srcRow = (dstY * scaleY).toInt().clamp(0, srcH - 1);
        for (int dstX = 0; dstX < _inputW; dstX++) {
          final int srcCol = (dstX * scaleX).toInt().clamp(0, srcW - 1);

          final int yVal = yPlane[srcRow * yRowStride + srcCol] & 0xFF;

          final int uvRow = (srcRow >> 1).clamp(0, (srcH >> 1) - 1);
          final int uvCol = (srcCol >> 1).clamp(0, (srcW >> 1) - 1);
          final int uvIdx = uvRow * uvRowStride + uvCol * uvPixStride;

          final int uVal;
          final int vVal;
          if (uvPixStride == 2) {
            uVal = uvPlane[uvIdx]     & 0xFF;
            vVal = uvPlane[uvIdx + 1] & 0xFF;
          } else {
            uVal = uvPlane[uvIdx] & 0xFF;
            vVal = vPlane [uvIdx] & 0xFF;
          }

          final double y = yVal.toDouble();
          final double u = uVal.toDouble() - 128.0;
          final double v = vVal.toDouble() - 128.0;

          _inputBuffer[0][dstY][dstX][0] = (y + 1.402    * v               ).clamp(0.0, 255.0) / 255.0;
          _inputBuffer[0][dstY][dstX][1] = (y - 0.344136 * u - 0.714136 * v).clamp(0.0, 255.0) / 255.0;
          _inputBuffer[0][dstY][dstX][2] = (y + 1.772    * u               ).clamp(0.0, 255.0) / 255.0;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[$_tag] _preprocessYuv420 error: $e');
      return false;
    }
  }

  // ── Post-processing ───────────────────────────────────────────────────────

  InferenceResult _postprocess(List<double> raw) {
    final double maxVal      = raw.reduce(math.max);
    final List<double> exps  = raw.map((v) => math.exp(v - maxVal)).toList();
    final double sumExp      = exps.reduce((a, b) => a + b);
    final List<double> probs = exps.map((e) => e / sumExp).toList();

    int topIdx     = 0;
    double topProb = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > topProb) { topProb = probs[i]; topIdx = i; }
    }

    final _SubclassMeta winner = _kSubclasses[topIdx];

    double neutralScore    = 0.0;
    double drowsyScore     = 0.0;
    double distractedScore = 0.0;

    for (int i = 0; i < raw.length && i < _kSubclasses.length; i++) {
      switch (_kSubclasses[i].mainClass) {
        case 'neutral':    neutralScore    += probs[i];
        case 'drowsy':     drowsyScore     += probs[i];
        case 'distracted': distractedScore += probs[i];
      }
    }

    final double alertness = (
      0.70 * neutralScore +
      0.30 * (1.0 - math.max(drowsyScore, distractedScore))
    ).clamp(0.0, 1.0) * 100.0;

    return InferenceResult(
      state:         winner.mainClass,
      alertnessPct:  alertness,
      drowsyPct:     (drowsyScore     * 100.0).clamp(0.0, 100.0),
      distractedPct: (distractedScore * 100.0).clamp(0.0, 100.0),
      subclassId:    winner.id,
      subclassLabel: winner.label,
      rawScores:     List.unmodifiable(probs),
    );
  }
}