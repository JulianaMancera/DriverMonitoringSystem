import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'frame_preprocessor.dart';

// Key optimizations:
//   1. Preprocessing runs via compute() → background isolate, UI never blocks
//   2. Strict single-frame gate: if inference is running, new frame is DROPPED
//      immediately (no queue, no backlog)
//   3. Frame skip increased to every 4th frame (≈7.5 FPS) — reduces CPU load
//      while still detecting drowsiness onset reliably
//   4. Input tensor uses flat Float32List (no nested List copies)
//   5. Output buffer pre-allocated once and reused across calls

class InferenceResult {
  final String state;          // 'neutral' | 'drowsy' | 'distracted'
  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;
  double get alertnessPct => neutralPct;

  const InferenceResult({
    required this.state,
    required this.neutralPct,
    required this.drowsyPct,
    required this.distractedPct,
  });
}

class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  static const String _modelAsset = 'assets/dms_hybridnet.tflite';

  /// Infer every Nth frame. 5 = every 6th frame ≈ 5 FPS at 30 FPS camera.
  /// Drowsiness onset is gradual — 5 FPS is sufficient for reliable detection
  /// and significantly reduces CPU/heat on mid-range phones.
  static const int _frameSkip = 5;

  /// Minimum confidence to accept a non-neutral prediction.
  static const double _confidenceThreshold = 0.45;

  Interpreter? _interpreter;
  bool         _isInitialized = false;

  /// STRICT gate — if true, drop the incoming frame immediately.
  /// Prevents any queue from building up.
  bool         _isRunning     = false;

  int          _frameCounter  = 0;

  /// Pre-allocated output buffer — reused every inference call.
  final List<List<double>> _outputBuffer = [List<double>.filled(3, 0.0)];

  /// Pre-allocated input tensor buffer — reused every inference call.
  /// Avoids allocating 150k doubles on every frame (224*224*3).
  /// Shape: [1][H][W][3] — matches tflite_flutter's run() expectation.
  static const int _h = FramePreprocessor.inputHeight;
  static const int _w = FramePreprocessor.inputWidth;
  final List<List<List<List<double>>>> _inputBuffer = List.generate(
    1, (_) => List.generate(
      FramePreprocessor.inputHeight, (_) => List.generate(
        FramePreprocessor.inputWidth, (_) => List.filled(3, 0.0),
      ),
    ),
  );

  String? lastError;
  bool get isInitialized => _isInitialized;

  // INITIALIZE

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    lastError = null;

    // Attempt 1: NNAPI (NPU/DSP delegate)
    try {
      final opts = InterpreterOptions()
        ..threads = 2
        ..useNnApiForAndroid = true;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: opts);
      _interpreter!.allocateTensors();
      _isInitialized = true;
      _logModelInfo();
      return true;
    } catch (_) {}

    // Attempt 2: CPU only
    try {
      final opts = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: opts);
      _interpreter!.allocateTensors();
      _isInitialized = true;
      _logModelInfo();
      return true;
    } catch (_) {}

    // Attempt 3: bare defaults
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
      _interpreter!.allocateTensors();
      _isInitialized = true;
      _logModelInfo();
      return true;
    } catch (e) {
      lastError = _friendlyError(e.toString());
      debugPrint('[TfliteService] ❌ All init attempts failed: $e');
      return false;
    }
  }

  void _logModelInfo() {
    if (_interpreter == null) return;
    final inp = _interpreter!.getInputTensor(0);
    final out = _interpreter!.getOutputTensor(0);
    debugPrint('[TfliteService] ✅ Model loaded');
    debugPrint('[TfliteService]    Input  → shape: ${inp.shape}  type: ${inp.type}');
    debugPrint('[TfliteService]    Output → shape: ${out.shape}  type: ${out.type}');
  }

  String _friendlyError(String raw) {
    if (raw.contains('Unable to open asset'))  return 'Asset not found: assets/dms_hybridnet.tflite\nCheck pubspec.yaml assets section.';
    if (raw.contains('flatbuffer'))            return 'Model file corrupt or wrong format.';
    if (raw.contains('noCompress'))            return 'Add noCompress "tflite" to android/app/build.gradle aaptOptions.';
    return raw.length > 200 ? raw.substring(0, 200) : raw;
  }

  // ── INFERENCE ──────────────────────────────────────────────────────────────

  /// Call from startImageStream() callback.
  ///
  /// Returns InferenceResult on inferred frames.
  /// Returns null immediately if:
  ///   - model not loaded
  ///   - frame is being skipped (frame-skip gate)
  ///   - previous inference still running (dropped — prevents backlog)
  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _interpreter == null) return null;

    // Frame-skip gate — process every (_frameSkip+1)th frame
    _frameCounter = (_frameCounter + 1) % (_frameSkip + 1);
    if (_frameCounter != 0) return null;

    // Busy gate — DROP immediately if still processing previous frame
    // This is the key fix: no queue, no backlog, no lag
    if (_isRunning) return null;
    _isRunning = true;

    try {
      // ── Step 1: Preprocessing on background isolate ──────────────────────
      // compute() sends the work to a separate Dart isolate so the UI thread
      // (and camera preview) is never blocked.
      final Float32List? inputData = await compute(
        _preprocessInIsolate,
        _PreprocessArgs(
          planes: image.planes
              .map((p) => _PlaneData(
                    bytes:        p.bytes,
                    bytesPerRow:  p.bytesPerRow,
                    bytesPerPixel: p.bytesPerPixel,
                  ))
              .toList(),
          width:       image.width,
          height:      image.height,
          formatGroup: image.format.group.index,
        ),
      );

      if (inputData == null) return null;

      // ── Step 2: Fill pre-allocated input buffer in-place ───────────────
      // Reusing _inputBuffer avoids 150k+ double allocations per frame.
      int idx = 0;
      for (int r = 0; r < _h; r++) {
        for (int c = 0; c < _w; c++) {
          _inputBuffer[0][r][c][0] = inputData[idx++];
          _inputBuffer[0][r][c][1] = inputData[idx++];
          _inputBuffer[0][r][c][2] = inputData[idx++];
        }
      }

      // ── Step 3: Run inference ─────────────────────────────────────────────
      for (int i = 0; i < 3; i++) { _outputBuffer[0][i] = 0.0; }
      _interpreter!.run(_inputBuffer, _outputBuffer);

      return _parseOutput(_outputBuffer[0]);

    } catch (e) {
      debugPrint('[TfliteService] ⚠️ Inference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  /// Convert flat Float32List [H*W*3] → nested [1][H][W][3]
  /// This is required by tflite_flutter's run() method.
  List<List<List<List<double>>>> _float32ToNestedList(Float32List flat) {
    const h = FramePreprocessor.inputHeight;
    const w = FramePreprocessor.inputWidth;
    int idx = 0;
    return [
      List.generate(h, (_) =>
        List.generate(w, (_) => [flat[idx++], flat[idx++], flat[idx++]])),
    ];
  }

  InferenceResult _parseOutput(List<double> probs) {
    final neutral    = probs[0].clamp(0.0, 1.0);
    final drowsy     = probs[1].clamp(0.0, 1.0);
    final distracted = probs[2].clamp(0.0, 1.0);

    String state   = 'neutral';
    double maxProb = neutral;

    if (drowsy     > maxProb) { maxProb = drowsy;     state = 'drowsy';     }
    if (distracted > maxProb) { maxProb = distracted; state = 'distracted'; }

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

  void dispose() {
    _interpreter?.close();
    _interpreter   = null;
    _isInitialized = false;
    _isRunning     = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ISOLATE HELPERS
// These must be top-level functions (not methods) so compute() can send them
// to a background isolate. They cannot access any class state.
// ─────────────────────────────────────────────────────────────────────────────

/// Data class passed to the background isolate.
/// Must be simple/serializable — no CameraImage (it's not sendable).
class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  const _PlaneData({required this.bytes, required this.bytesPerRow, required this.bytesPerPixel});
}

class _PreprocessArgs {
  final List<_PlaneData> planes;
  final int width, height, formatGroup;
  const _PreprocessArgs({
    required this.planes,
    required this.width,
    required this.height,
    required this.formatGroup,
  });
}

/// Top-level function — runs in background isolate via compute().
/// Re-creates the preprocessor state needed (gamma LUT) locally.
Float32List? _preprocessInIsolate(_PreprocessArgs args) {
  try {
    const inputW  = FramePreprocessor.inputWidth;
    const inputH  = FramePreprocessor.inputHeight;
    const gamma   = FramePreprocessor.gamma;

    // Build gamma LUT locally in the isolate
    final gammaLut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final c = math.pow(i / 255.0, 1.0 / gamma).toDouble();
      gammaLut[i] = (c * 255.0).round().clamp(0, 255);
    }

    // Convert to raw RGB bytes based on format
    Uint8List? rgbBytes;
    final fmtGroup = ImageFormatGroup.values[args.formatGroup];

    if (fmtGroup == ImageFormatGroup.yuv420 && args.planes.length >= 2) {
      final w = args.width; final h = args.height;
      final yBytes  = args.planes[0].bytes;
      final uBytes  = args.planes[1].bytes;
      final vBytes  = args.planes.length > 2 ? args.planes[2].bytes : args.planes[1].bytes;
      final yStride = args.planes[0].bytesPerRow;
      final uvStride= args.planes[1].bytesPerRow;
      final uvPixel = args.planes[1].bytesPerPixel ?? 1;

      rgbBytes = Uint8List(w * h * 3);
      int outIdx = 0;
      for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
          final yVal = yBytes[row * yStride + col] & 0xFF;
          final uvIdx= (row >> 1) * uvStride + (col >> 1) * uvPixel;
          final uVal = (uBytes[uvIdx] & 0xFF) - 128;
          final vVal = (vBytes[uvIdx] & 0xFF) - 128;

          rgbBytes[outIdx++] = ((yVal * 1024 + 1402 * vVal) >> 10).clamp(0, 255);
          rgbBytes[outIdx++] = ((yVal * 1024 - 344  * uVal - 714 * vVal) >> 10).clamp(0, 255);
          rgbBytes[outIdx++] = ((yVal * 1024 + 1772 * uVal) >> 10).clamp(0, 255);
        }
      }
    } else {
      return null; // Unrecognised format on Android — skip frame
    }

    // Resize (nearest-neighbour) + gamma + normalize in single pass
    final out    = Float32List(inputW * inputH * 3);
    final xScale = args.width  / inputW;
    final yScale = args.height / inputH;
    int outIdx   = 0;

    for (int dstRow = 0; dstRow < inputH; dstRow++) {
      final srcRow = (dstRow * yScale).toInt().clamp(0, args.height - 1);
      for (int dstCol = 0; dstCol < inputW; dstCol++) {
        final srcCol = (dstCol * xScale).toInt().clamp(0, args.width - 1);
        final srcIdx = (srcRow * args.width + srcCol) * 3;

        out[outIdx++] = gammaLut[rgbBytes[srcIdx    ]] / 255.0;
        out[outIdx++] = gammaLut[rgbBytes[srcIdx + 1]] / 255.0;
        out[outIdx++] = gammaLut[rgbBytes[srcIdx + 2]] / 255.0;
      }
    }
    return out;

  } catch (_) {
    return null;
  }
}