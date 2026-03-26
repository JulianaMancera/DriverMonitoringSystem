import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import '../inference/frame_preprocessor.dart';

// ─────────────────────────────────────────────────────────────────────────────
// tflite_service.dart
// Bantay Drive — TFLite Model Service
//
// Place at: lib/core/inference/tflite_service.dart
//
// Responsibilities:
//   1. Load dms_hybridnet.tflite from assets
//   2. Accept CameraImage frames from monitor_screen
//   3. Call FramePreprocessor to convert + preprocess each frame
//   4. Run inference on the TFLite interpreter
//   5. Parse softmax output → InferenceResult
//   6. Apply frame-skip (every 3rd frame ≈ 10 FPS at 30 FPS camera)
//   7. Apply confidence gate to suppress jittery predictions
//
// Partner specs:
//   • Model file  : assets/dms_hybridnet.tflite
//   • Input shape : [1, 224, 224, 3]
//   • Output shape: [1, 3]  →  [Neutral, Drowsy, Distracted]
//   • Data type   : Float32 normalized (0.0 – 1.0)
// ─────────────────────────────────────────────────────────────────────────────

/// Result of one inference pass — passed directly to onModelOutput()
class InferenceResult {
  /// Winning class: 'neutral' | 'drowsy' | 'distracted'
  final String state;

  /// Softmax probabilities scaled to percentage (× 100)
  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  /// Convenience alias used by alertnessPctProvider
  double get alertnessPct => neutralPct;

  const InferenceResult({
    required this.state,
    required this.neutralPct,
    required this.drowsyPct,
    required this.distractedPct,
  });

  @override
  String toString() =>
      'InferenceResult(state: $state | '
      'N: ${neutralPct.toStringAsFixed(1)}% '
      'D: ${drowsyPct.toStringAsFixed(1)}% '
      'X: ${distractedPct.toStringAsFixed(1)}%)';
}

// ─────────────────────────────────────────────────────────────────────────────

class TfliteService {
  // ── SINGLETON ─────────────────────────────────────────────────────────────
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  // ── CONFIG ────────────────────────────────────────────────────────────────

  /// Asset path — matches the file shown in your assets/ folder
  static const String _modelAsset = 'assets/dms_hybridnet.tflite';

  /// Skip N frames between inferences.
  /// _frameSkip = 2 at 30 FPS camera → infer every 3rd frame ≈ 10 FPS
  static const int _frameSkip = 2;

  /// Minimum confidence to accept a non-neutral prediction.
  /// Prevents a single borderline frame from triggering an alert.
  static const double _confidenceThreshold = 0.45;

  // ── STATE ─────────────────────────────────────────────────────────────────
  Interpreter? _interpreter;
  bool         _isInitialized = false;
  bool         _isRunning     = false;   // prevents concurrent inference
  int          _frameCounter  = 0;

  bool get isInitialized => _isInitialized;

  // ── INITIALIZE ────────────────────────────────────────────────────────────

  /// Call once in MonitorScreen._loadPreferencesAndInit()
  /// Returns true on success, false if model file is missing.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final options = InterpreterOptions()
        ..threads = 2                  // safe for mid-range Android
        ..useNnApiForAndroid = true;   // use NPU/DSP delegate if available

      _interpreter = await Interpreter.fromAsset(
        _modelAsset,
        options: options,
      );
      _interpreter!.allocateTensors();
      _isInitialized = true;

      _logModelInfo();
      return true;

    } catch (e) {
      debugPrint('[TfliteService] ❌ Failed to load model: $e');
      debugPrint('[TfliteService]    → Check assets/dms_hybridnet.tflite exists');
      debugPrint('[TfliteService]    → Check pubspec.yaml includes assets/');
      return false;
    }
  }

  void _logModelInfo() {
    if (_interpreter == null) return;
    final inp = _interpreter!.getInputTensor(0);
    final out = _interpreter!.getOutputTensor(0);
    debugPrint('[TfliteService] ✅ dms_hybridnet.tflite loaded');
    debugPrint('[TfliteService]    Input  → shape: ${inp.shape}  type: ${inp.type}');
    debugPrint('[TfliteService]    Output → shape: ${out.shape}  type: ${out.type}');
    debugPrint('[TfliteService]    Expected input:  [1, 224, 224, 3]  float32');
    debugPrint('[TfliteService]    Expected output: [1, 3]            float32');
  }

  // ── INFERENCE ─────────────────────────────────────────────────────────────

  /// Main entry point — call from startImageStream() callback.
  ///
  /// Returns [InferenceResult] on inferred frames.
  /// Returns null on skipped frames or if not initialized.
  ///
  /// Usage in monitor_screen.dart:
  /// ```dart
  /// _cameraController!.startImageStream((CameraImage frame) async {
  ///   final result = await TfliteService.instance.runInference(frame);
  ///   if (result != null && mounted && ref.read(isRecordingProvider)) {
  ///     onModelOutput(
  ///       state:          result.state,
  ///       alertnessPct:   result.alertnessPct,
  ///       drowsinessPct:  result.drowsyPct,
  ///       distractionPct: result.distractedPct,
  ///     );
  ///   }
  /// });
  /// ```
  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _isRunning || _interpreter == null) return null;

    // Frame-skip gate — only infer every (_frameSkip + 1)th frame
    _frameCounter = (_frameCounter + 1) % (_frameSkip + 1);
    if (_frameCounter != 0) return null;

    _isRunning = true;
    try {
      // Preprocessing: convert → resize → gamma → float32 tensor
      final inputTensor = FramePreprocessor.instance.process(image);
      if (inputTensor == null) return null;

      // Run inference — output shape [1, 3]: [Neutral, Drowsy, Distracted]
      final outputBuffer = [List<double>.filled(3, 0.0)];
      _interpreter!.run(inputTensor, outputBuffer);

      return _parseOutput(outputBuffer[0]);

    } catch (e) {
      debugPrint('[TfliteService] ⚠️ Inference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  // ── OUTPUT PARSING ────────────────────────────────────────────────────────

  InferenceResult _parseOutput(List<double> probs) {
    // Clamp to valid probability range
    final neutral    = probs[0].clamp(0.0, 1.0);
    final drowsy     = probs[1].clamp(0.0, 1.0);
    final distracted = probs[2].clamp(0.0, 1.0);

    // Find winning class by highest probability
    String state   = 'neutral';
    double maxProb = neutral;

    if (drowsy > maxProb)     { maxProb = drowsy;     state = 'drowsy';     }
    if (distracted > maxProb) { maxProb = distracted; state = 'distracted'; }

    // Confidence gate — suppress low-confidence non-neutral predictions
    // Prevents jittery state changes on borderline frames
    if (state != 'neutral' && maxProb < _confidenceThreshold) {
      state = 'neutral';
    }

    return InferenceResult(
      state:         state,
      neutralPct:    neutral    * 100.0,
      drowsyPct:     drowsy     * 100.0,
      distractedPct: distracted * 100.0,
    );
  }

  // ── DISPOSE ───────────────────────────────────────────────────────────────

  /// Call in MonitorScreen.dispose()
  void dispose() {
    _interpreter?.close();
    _interpreter   = null;
    _isInitialized = false;
  }
}