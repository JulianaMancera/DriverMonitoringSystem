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

    // Strategy 1: CPU only, NNAPI off
    // The gradle dep (tensorflow-lite-select-tf-ops) handles Select TF Ops natively
    if (await _tryLoad('CPU + Select TF Ops', () async {
      final options = InterpreterOptions()
        ..useNnApiForAndroid = false
        ..threads = 2;
      return Interpreter.fromAsset(
        'assets/dms_hybridnet.tflite',
        options: options,
      );
    })) return true;

    // Strategy 2: XNNPack delegate
    if (await _tryLoad('XNNPack', () async {
      final options = InterpreterOptions()
        ..useNnApiForAndroid = false
        ..addDelegate(XNNPackDelegate(
          options: XNNPackDelegateOptions(numThreads: 2),
        ));
      return Interpreter.fromAsset(
        'assets/dms_hybridnet.tflite',
        options: options,
      );
    })) return true;

    // Strategy 3: Bare minimum
    if (await _tryLoad('Bare CPU', () async {
      return Interpreter.fromAsset('assets/dms_hybridnet.tflite');
    })) return true;

    debugPrint('[TfliteService] ❌ All strategies failed. Running in Demo Mode.');
    return false;
  }

  Future<bool> _tryLoad(
    String strategyName,
    Future<Interpreter> Function() loader,
  ) async {
    try {
      debugPrint('[TfliteService] 🔄 Trying strategy: $strategyName...');
      _interpreter = await loader();

      final inputShape  = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      debugPrint('[TfliteService] ✅ Strategy "$strategyName" succeeded!');
      debugPrint('[TfliteService] 📥 Input Shape: $inputShape');
      debugPrint('[TfliteService] 📤 Output Shape: $outputShape');

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Strategy "$strategyName" failed: $e');
      _interpreter = null;
      return false;
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