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

  // Model shape info
  List<int> _inputShape  = [1, 224, 224, 3];
  List<int> _outputShape = [1, 3];

  // Settings
  final double _confidenceThreshold = 0.5;
  int _frameCounter = 0;
  final int _frameSkip = 5;

  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    if (await _tryLoad('CPU', () async {
      final options = InterpreterOptions()
        ..useNnApiForAndroid = false
        ..threads = 2;
      return Interpreter.fromAsset(
        'assets/dms_hybridnet.tflite',
        options: options,
      );
    })) {
      return true;
    }

    if (await _tryLoad('Bare CPU', () async {
      return Interpreter.fromAsset('assets/dms_hybridnet.tflite');
    })) {
      return true;
    }

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

      _inputShape  = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;

      debugPrint('[TfliteService] ✅ Strategy "$strategyName" succeeded!');
      debugPrint('[TfliteService] 📥 Input Shape:  $_inputShape');
      debugPrint('[TfliteService] 📤 Output Shape: $_outputShape');

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[TfliteService] ❌ Strategy "$strategyName" failed: $e');
      _interpreter = null;
      return false;
    }
  }

  InferenceResult? runInferenceSync(CameraImage cameraImage) {
    if (!_isInitialized || _interpreter == null || _isRunning) return null;

    _frameCounter++;
    if (_frameCounter % _frameSkip != 0) return null;

    _isRunning = true;

    try {
      // 1. Get target dimensions from model input shape [1, H, W, 3]
      final targetH = _inputShape[1];
      final targetW = _inputShape[2];

      // 2. Preprocess — returns flat Float32List of size H*W*3
      final flatTensor = FramePreprocessor.instance.process(
        cameraImage,
        targetWidth:  targetW,
        targetHeight: targetH,
      );

      // 3. ✅ Reshape flat [H*W*3] into [1, H, W, 3] nested list
      final input = _reshapeToInput(flatTensor, targetH, targetW);

      // 4. Build output buffer dynamically
      final output = _buildOutputBuffer();

      // 5. Run inference
      _interpreter!.run(input, output);

      // 6. Extract result
      final rawOutput = _extractOutput(output);
      debugPrint('[TfliteService] 🔍 Raw output: $rawOutput');

      return _parseOutput(rawOutput);
    } catch (e) {
      debugPrint('[TfliteService] ⚠️ Inference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  /// Reshape flat Float32List → [1][H][W][3] nested List
  List _reshapeToInput(List<double> flat, int h, int w) {
    int idx = 0;
    return [
      List.generate(h, (y) =>
        List.generate(w, (x) =>
          List.generate(3, (c) => flat[idx++])
        )
      )
    ];
  }

  /// Build output buffer matching model output shape
  dynamic _buildOutputBuffer() {
    if (_outputShape.length == 1) {
      // Shape [3]
      return List<double>.filled(_outputShape[0], 0.0);
    } else if (_outputShape.length == 2) {
      // Shape [1, 3]
      return List.generate(
        _outputShape[0], (_) => List<double>.filled(_outputShape[1], 0.0)
      );
    } else {
      // Fallback
      return List.generate(1, (_) => List<double>.filled(3, 0.0));
    }
  }

  /// Extract flat output from buffer
  List<double> _extractOutput(dynamic output) {
    if (output is List<double>) {
      return output; // Shape [3]
    } else if (output is List && output[0] is List<double>) {
      return output[0] as List<double>; // Shape [1, 3]
    }
    return [1.0, 0.0, 0.0]; // fallback neutral
  }

  Future<InferenceResult?> runInference(CameraImage cameraImage) async {
    return runInferenceSync(cameraImage);
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

    if (state != 'neutral' && maxProb < _confidenceThreshold) {
      state = 'neutral';
    }

    debugPrint('[TfliteService] 🎯 State: $state | N:${(neutral*100).toInt()}% D:${(drowsy*100).toInt()}% X:${(distracted*100).toInt()}%');

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