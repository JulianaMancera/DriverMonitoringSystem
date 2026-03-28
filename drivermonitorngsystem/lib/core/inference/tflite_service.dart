import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'frame_preprocessor.dart';

class InferenceResult {
  final String state;
  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  InferenceResult({
    required this.state,
    required this.neutralPct,
    required this.drowsyPct,
    required this.distractedPct,
  });
}

class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  Interpreter? _interpreter;
  bool _isInitialized = false;
  bool _isRunning = false;

  // Settings
  final double _confidenceThreshold = 0.6;
  int _frameCounter = 0;
  final int _frameSkip = 3;

  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('[TfliteService] 🔄 Loading model from assets/dms_hybridnet.tflite...');

      // ✅ FORCE CPU ONLY — explicitly disables NNAPI/MirrorManager
      final options = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = false;

      _interpreter = await Interpreter.fromAsset(
        'assets/dms_hybridnet.tflite',
        options: options,
      );

      final inputShape  = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      debugPrint('[TfliteService] ✅ Model Loaded.');
      debugPrint('[TfliteService] 📥 Input Shape: $inputShape');
      debugPrint('[TfliteService] 📤 Output Shape: $outputShape');

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Primary load failed: $e');

      // ✅ FALLBACK: bare minimum CPU, no options at all
      try {
        debugPrint('[TfliteService] 🔄 Retrying with bare CPU fallback...');
        _interpreter = await Interpreter.fromAsset('assets/dms_hybridnet.tflite');

        final inputShape  = _interpreter!.getInputTensor(0).shape;
        final outputShape = _interpreter!.getOutputTensor(0).shape;

        debugPrint('[TfliteService] ✅ Fallback load successful.');
        debugPrint('[TfliteService] 📥 Input Shape: $inputShape');
        debugPrint('[TfliteService] 📤 Output Shape: $outputShape');

        _isInitialized = true;
        return true;
      } catch (e2) {
        debugPrint('[TfliteService] ❌ Fallback also failed: $e2');
        _isInitialized = false;
        return false;
      }
    }
  }

  Future<InferenceResult?> runInference(CameraImage cameraImage) async {
    if (!_isInitialized || _interpreter == null || _isRunning) return null;

    // Frame skip logic to save CPU
    _frameCounter++;
    if (_frameCounter % _frameSkip != 0) return null;

    _isRunning = true;

    try {
      // 1. Preprocess
      final inputShape  = _interpreter!.getInputTensor(0).shape;
      final inputTensor = FramePreprocessor.instance.process(
        cameraImage,
        targetWidth:  inputShape[1],
        targetHeight: inputShape[2],
      );

      // 2. Prepare Output Buffer [1, 3]
      var outputBuffer = List.generate(1, (_) => List<double>.filled(3, 0.0));

      // 3. Run Inference
      _interpreter!.run(inputTensor, outputBuffer);

      return _parseOutput(outputBuffer[0]);
    } catch (e) {
      debugPrint('[TfliteService] ⚠️ Inference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  InferenceResult _parseOutput(List<double> probs) {
    final neutral    = probs[0].clamp(0.0, 1.0);
    final drowsy     = probs[1].clamp(0.0, 1.0);
    final distracted = probs[2].clamp(0.0, 1.0);

    String state   = 'neutral';
    double maxProb = neutral;

    if (drowsy > maxProb) {
      maxProb = drowsy;
      state   = 'drowsy';
    }
    if (distracted > maxProb) {
      maxProb = distracted;
      state   = 'distracted';
    }

    // Confidence gate
    if (state != 'neutral' && maxProb < _confidenceThreshold) {
      state = 'neutral';
    }

    return InferenceResult(
      state:         state,
      neutralPct:    neutral    * 100,
      drowsyPct:     drowsy     * 100,
      distractedPct: distracted * 100,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter   = null;
    _isInitialized = false;
    _isRunning     = false;
    debugPrint('[TfliteService] 🗑️ Interpreter disposed.');
  }
}