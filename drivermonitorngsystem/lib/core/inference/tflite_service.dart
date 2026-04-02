import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'frame_preprocessor.dart';

// Model output: [1, 10] softmax over 10 subclasses
// Mapping back to 3 main states by summing grouped subclass probabilities:
//
//   Index  Subclass                  Main Class
//   ─────  ───────────────────────   ──────────
//     0    sub00_safe_driving        NEUTRAL
//     1    sub01_yawning             DROWSY
//     2    sub02_fatigue_head_droop  DROWSY
//     3    sub03_texting             DISTRACTED
//     4    sub04_phone_call          DISTRACTED
//     5    sub05_adjusting_radio     DISTRACTED
//     6    sub06_drinking            DISTRACTED
//     7    sub07_reaching_behind     DISTRACTED
//     8    sub08_hair_makeup         DISTRACTED
//     9    sub12_eyes_closed_perclos    DROWSY
//
// Confirmed: array is 10 elements (0–9). Sub12 is just a label name —
// it occupies index 9 in the output array.

class InferenceResult {
  /// Rolled-up main state: 'neutral' | 'drowsy' | 'distracted'
  final String state;

  /// Rolled-up probabilities × 100 (sum of grouped subclass probs)
  final double neutralPct;
  final double drowsyPct;
  final double distractedPct;

  /// Winning subclass index (0–9) and its name — useful for logging/debugging
  final int    topSubclassIndex;
  final String topSubclassName;

  /// Raw 10-class softmax probabilities × 100
  final List<double> subclassPcts;

  double get alertnessPct => neutralPct;

  const InferenceResult({
    required this.state,
    required this.neutralPct,
    required this.drowsyPct,
    required this.distractedPct,
    required this.topSubclassIndex,
    required this.topSubclassName,
    required this.subclassPcts,
  });

  @override
  String toString() =>
      'InferenceResult(state: $state | '
      'N: ${neutralPct.toStringAsFixed(1)}% '
      'D: ${drowsyPct.toStringAsFixed(1)}% '
      'X: ${distractedPct.toStringAsFixed(1)}% | '
      'top: $topSubclassName)';
}

class TfliteService {
  static final TfliteService instance = TfliteService._init();
  TfliteService._init();

  static const String _modelAsset = 'assets/dms_hybridnet.tflite';

  // V2 TAXONOMY MAPPING 
  // Maps each output index (0–9) to its main class.
  // 'N' = Neutral, 'D' = Drowsy, 'X' = Distracted

  // Confirmed with partner: 10-element array, sub12 is at index 9.
  static const List<String> _subclassMainClass = [
    'N', // 0 — sub00_safe_driving
    'D', // 1 — sub01_yawning
    'D', // 2 — sub02_fatigue_head_droop
    'X', // 3 — sub03_texting
    'X', // 4 — sub04_phone_call
    'X', // 5 — sub05_adjusting_radio
    'X', // 6 — sub06_drinking
    'X', // 7 — sub07_reaching_behind
    'X', // 8 — sub08_hair_makeup
    'D', // 9 — sub12_eyes_closed_perclos (DROWSY) — confirmed index 9
  ];

  static const List<String> _subclassNames = [
    'safe_driving',         // 0
    'yawning',              // 1
    'fatigue_head_droop',   // 2
    'texting',              // 3
    'phone_call',           // 4
    'adjusting_radio',      // 5
    'drinking',             // 6
    'reaching_behind',      // 7
    'hair_makeup',          // 8
    'eyes_closed_perclos',  // 9 — sub12 
  ];

  // INFERENCE CONFIG 

  /// Infer every Nth frame. 3 = every 4th frame ≈ 7.5 FPS at 30 FPS camera.
  static const int _frameSkip = 3;

  /// Minimum confidence for the winning subclass to be accepted.
  /// Below this, output is 'neutral' regardless of the top class.
  static const double _confidenceThreshold = 0.35;

  // STATE 
  Interpreter? _interpreter;
  bool         _isInitialized = false;
  bool         _isRunning     = false;
  int          _frameCounter  = 0;

  /// Pre-allocated output buffer — reused every call to avoid GC pressure.
  final List<List<double>> _outputBuffer = [List<double>.filled(10, 0.0)];

  String? lastError;
  bool get isInitialized => _isInitialized;

  // INITIALIZE 

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    lastError = null;

    // Attempt 1: NNAPI delegate (NPU/DSP)
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
    debugPrint('[TfliteService] ✅ Model loaded (V2 taxonomy — 10 subclasses)');
    debugPrint('[TfliteService]    Input  → shape: ${inp.shape}  type: ${inp.type}');
    debugPrint('[TfliteService]    Output → shape: ${out.shape}  type: ${out.type}');
    debugPrint('[TfliteService]    Expected output shape: [1, 10]');
  }

  String _friendlyError(String raw) {
    if (raw.contains('Unable to open asset')) {
      return 'Asset not found: assets/dms_hybridnet.tflite\nCheck pubspec.yaml assets section.';
    }
    if (raw.contains('flatbuffer')) {
      return 'Model file corrupt or wrong format.';
    }
    if (raw.contains('noCompress')) {
      return 'Add noCompress "tflite" to android/app/build.gradle aaptOptions.';
    }
    return raw.length > 200 ? raw.substring(0, 200) : raw;
  }

  // INFERENCE 

  Future<InferenceResult?> runInference(CameraImage image) async {
    if (!_isInitialized || _interpreter == null) return null;

    // Frame-skip gate
    _frameCounter = (_frameCounter + 1) % (_frameSkip + 1);
    if (_frameCounter != 0) return null;

    // Busy gate — drop frame immediately if still processing
    if (_isRunning) return null;
    _isRunning = true;

    try {
      // Step 1 — Preprocessing on background isolate
      final Float32List? inputData = await compute(
        _preprocessInIsolate,
        _PreprocessArgs(
          planes: image.planes
              .map((p) => _PlaneData(
                    bytes:         p.bytes,
                    bytesPerRow:   p.bytesPerRow,
                    bytesPerPixel: p.bytesPerPixel,
                  ))
              .toList(),
          width:       image.width,
          height:      image.height,
          formatGroup: image.format.group.index,
        ),
      );

      if (inputData == null) return null;

      // Step 2 — Reshape to [1, H, W, 3]
      final input = _float32ToNestedList(inputData);

      // Step 3 — Run inference (output: [1, 10])
      for (int i = 0; i < 10; i++) { _outputBuffer[0][i] = 0.0; }
      _interpreter!.run(input, _outputBuffer);

      // Step 4 — Map 10 subclasses → 3 main states
      return _parseOutput(_outputBuffer[0]);

    } catch (e) {
      debugPrint('[TfliteService] ⚠️ Inference error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  // OUTPUT PARSING — 10 subclasses → 3 main states 

  InferenceResult _parseOutput(List<double> probs) {
    // Safety check — ensure we have 10 outputs
    if (probs.length < 10) {
      debugPrint('[TfliteService] ⚠️ Unexpected output length: ${probs.length} (expected 10)');
      return _neutralResult(probs);
    }

    // Clamp all probabilities
    final p = List<double>.generate(10, (i) => probs[i].clamp(0.0, 1.0));

    // Find winning subclass (highest individual probability)
    int    topIdx  = 0;
    double topProb = p[0];
    for (int i = 1; i < 10; i++) {
      if (p[i] > topProb) { topProb = p[i]; topIdx = i; }
    }

    // Roll up probabilities by main class
    double neutralProb    = 0.0;
    double drowsyProb     = 0.0;
    double distractedProb = 0.0;

    for (int i = 0; i < 10; i++) {
      switch (_subclassMainClass[i]) {
        case 'N': neutralProb    += p[i]; break;
        case 'D': drowsyProb     += p[i]; break;
        case 'X': distractedProb += p[i]; break;
      }
    }

    // Determine winning main class from rolled-up probabilities
    String state   = 'neutral';
    double maxProb = neutralProb;

    if (drowsyProb     > maxProb) { maxProb = drowsyProb;     state = 'drowsy';     }
    if (distractedProb > maxProb) { maxProb = distractedProb; state = 'distracted'; }

    // Confidence gate on the top individual subclass
    // If no single subclass is confident, stay neutral
    if (state != 'neutral' && topProb < _confidenceThreshold) {
      state = 'neutral';
    }

    final subclassPcts = List<double>.generate(10, (i) => p[i] * 100.0);

    debugPrint('[TfliteService] → $state | top: ${_subclassNames[topIdx]} '
        '(${(topProb * 100).toStringAsFixed(1)}%) | '
        'N:${(neutralProb * 100).toStringAsFixed(0)}% '
        'D:${(drowsyProb * 100).toStringAsFixed(0)}% '
        'X:${(distractedProb * 100).toStringAsFixed(0)}%');

    return InferenceResult(
      state:             state,
      neutralPct:        neutralProb    * 100.0,
      drowsyPct:         drowsyProb     * 100.0,
      distractedPct:     distractedProb * 100.0,
      topSubclassIndex:  topIdx,
      topSubclassName:   _subclassNames[topIdx],
      subclassPcts:      subclassPcts,
    );
  }

  InferenceResult _neutralResult(List<double> probs) {
    return InferenceResult(
      state: 'neutral', neutralPct: 100.0,
      drowsyPct: 0.0, distractedPct: 0.0,
      topSubclassIndex: 0, topSubclassName: 'safe_driving',
      subclassPcts: List<double>.filled(10, 0.0),
    );
  }

  // TENSOR HELPER 

  List<List<List<List<double>>>> _float32ToNestedList(Float32List flat) {
    const h = FramePreprocessor.inputHeight;
    const w = FramePreprocessor.inputWidth;
    int idx = 0;
    return [
      List.generate(h, (_) =>
        List.generate(w, (_) => [flat[idx++], flat[idx++], flat[idx++]])),
    ];
  }

  void dispose() {
    _interpreter?.close();
    _interpreter   = null;
    _isInitialized = false;
    _isRunning     = false;
  }
}

// ISOLATE HELPERS — top-level functions, no class state
class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  const _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });
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

Float32List? _preprocessInIsolate(_PreprocessArgs args) {
  try {
    const inputW = FramePreprocessor.inputWidth;
    const inputH = FramePreprocessor.inputHeight;
    const gamma  = FramePreprocessor.gamma;

    // Build gamma LUT locally in the isolate
    final gammaLut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final c = math.pow(i / 255.0, 1.0 / gamma).toDouble();
      gammaLut[i] = (c * 255.0).round().clamp(0, 255);
    }

    Uint8List? rgbBytes;
    final fmtGroup = ImageFormatGroup.values[args.formatGroup];

    if (fmtGroup == ImageFormatGroup.yuv420 && args.planes.length >= 2) {
      final w = args.width; final h = args.height;
      final yBytes   = args.planes[0].bytes;
      final uBytes   = args.planes[1].bytes;
      final vBytes   = args.planes.length > 2
          ? args.planes[2].bytes
          : args.planes[1].bytes;
      final yStride  = args.planes[0].bytesPerRow;
      final uvStride = args.planes[1].bytesPerRow;
      final uvPixel  = args.planes[1].bytesPerPixel ?? 1;

      rgbBytes = Uint8List(w * h * 3);
      int outIdx = 0;
      for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
          final yVal = yBytes[row * yStride + col] & 0xFF;
          final uvIdx = (row >> 1) * uvStride + (col >> 1) * uvPixel;
          final uVal  = (uBytes[uvIdx] & 0xFF) - 128;
          final vVal  = (vBytes[uvIdx] & 0xFF) - 128;

          rgbBytes[outIdx++] = ((yVal * 1024 + 1402 * vVal) >> 10).clamp(0, 255);
          rgbBytes[outIdx++] = ((yVal * 1024 -  344 * uVal - 714 * vVal) >> 10).clamp(0, 255);
          rgbBytes[outIdx++] = ((yVal * 1024 + 1772 * uVal) >> 10).clamp(0, 255);
        }
      }
    } else if (fmtGroup == ImageFormatGroup.bgra8888 &&
               args.planes.isNotEmpty) {
      final bytes = args.planes[0].bytes;
      final total = args.width * args.height;
      rgbBytes    = Uint8List(total * 3);
      for (int i = 0; i < total; i++) {
        rgbBytes[i * 3    ] = bytes[i * 4 + 2];
        rgbBytes[i * 3 + 1] = bytes[i * 4 + 1];
        rgbBytes[i * 3 + 2] = bytes[i * 4    ];
      }
    } else {
      return null;
    }

    // Nearest-neighbour resize + gamma + normalize in one pass
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