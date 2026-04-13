// ─────────────────────────────────────────────────────────────────────────────
// frame_preprocessor.dart
//
// PURPOSE:
//   Converts raw Android camera frames into the float tensor that
//   T01 (spatial model) expects as input.
//
// PIPELINE:
//   CameraImage (YUV420)
//     → Step 1: YUV420 → flat RGB bytes (integer math, no floats per pixel)
//     → Step 2: Nearest-neighbour resize to 224×224
//     → Step 3: Gamma correction via precomputed LUT (γ=0.3, low-light boost)
//     → Step 4: Normalize to [0.0, 1.0]
//     → Float32List [1 × 224 × 224 × 3] ready for tflite_flutter
//
// CONNECTIONS:
//   • Called BY: tflite_service.dart inside a compute() isolate
//   • Does NOT touch: database, providers, or UI
//   • Model it feeds: T01 spatial model (t01_spatial_float16.tflite)
//     Input shape per fusion_config.json: [224, 224, 3], dtype: uint8→float32
//
// KEY OPTIMIZATIONS:
//   1. Returns Float32List (flat buffer) — tflite_flutter accepts directly,
//      no nested List<List<List>> copy needed
//   2. YUV→RGB uses integer arithmetic only (no floating point per pixel)
//   3. Gamma LUT stored as Uint8List (1 byte/entry, cache-friendly)
//   4. Single-pass resize + normalize where possible
//   5. processRaw() is isolate-safe (no Flutter engine references)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';

class FramePreprocessor {
  static final FramePreprocessor instance = FramePreprocessor._init();

  FramePreprocessor._init() {
    _buildGammaLut();
  }

  // ── CONSTANTS ─────────────────────────────────────────────────────────────

  /// T01 spatial model input size per fusion_config.json: [224, 224, 3]
  static const int inputWidth  = 224;
  static const int inputHeight = 224;

  /// Gamma correction exponent for low-light enhancement.
  /// γ=0.3 brightens dark frames so the model can detect closed eyes / yawns
  /// even in poor cabin lighting conditions.
  static const double gamma = 0.3;

  late final Uint8List _gammaLut;

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Converts a CameraImage to a flat Float32List ready for T01 inference.
  /// Returns null if the frame format is unsupported or processing fails.
  /// Shape: [inputHeight * inputWidth * 3] = [150528] floats
  Float32List? processToFloat32(CameraImage image) {
    try {
      final Uint8List? rgbBytes = _toRgbBytes(image);
      if (rgbBytes == null) return null;

      return _resizeGammaNormalize(
        rgbBytes,
        srcWidth:  image.width,
        srcHeight: image.height,
      );
    } catch (_) {
      return null;
    }
  }

  /// Isolate-safe version — accepts raw byte data instead of CameraImage.
  /// Called by tflite_service.dart via compute() for background processing.
  /// [args] = [yBytes, uBytes, vBytes, width, height, yStride, uvStride, uvPixel]
  static Float32List? processRaw(List<dynamic> args) {
    try {
      final Uint8List yBytes   = args[0] as Uint8List;
      final Uint8List uBytes   = args[1] as Uint8List;
      final Uint8List vBytes   = args[2] as Uint8List;
      final int       w        = args[3] as int;
      final int       h        = args[4] as int;
      final int       yStride  = args[5] as int;
      final int       uvStride = args[6] as int;
      final int       uvPixel  = args[7] as int;

      // Build gamma LUT inline for isolate (no shared state across isolates)
      final lut = _buildGammaLutStatic();

      final rgb = _yuv420ToRgbBytesStatic(
        yBytes, uBytes, vBytes, w, h, yStride, uvStride, uvPixel,
      );

      return _resizeGammaNormalizeStatic(rgb, lut, srcWidth: w, srcHeight: h);
    } catch (_) {
      return null;
    }
  }

  // ── STEP 1: YUV420 → RAW RGB BYTES ───────────────────────────────────────

  Uint8List? _toRgbBytes(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        return _yuv420ToRgbBytes(image);
      // FIX: Added bgra8888 handling for completeness — iOS uses this format.
      // Although Bantay Drive targets Android only, this prevents a silent
      // null return if the format group ever changes (e.g. emulator quirks).
      case ImageFormatGroup.bgra8888:
        return _bgra8888ToRgbBytes(image);
      default:
        return null;
    }
  }

  /// YUV420 → RGB using integer math only (no double per pixel).
  /// Android camera always delivers YUV420 from the front-facing camera.
  Uint8List _yuv420ToRgbBytes(CameraImage image) {
    return _yuv420ToRgbBytesStatic(
      image.planes[0].bytes,
      image.planes[1].bytes,
      image.planes[2].bytes,
      image.width,
      image.height,
      image.planes[0].bytesPerRow,
      image.planes[1].bytesPerRow,
      image.planes[1].bytesPerPixel ?? 1,
    );
  }

  /// BGRA8888 → RGB (iOS / emulator fallback).
  /// Simply reorders channels: B=0, G=1, R=2, A=3 → R, G, B
  Uint8List _bgra8888ToRgbBytes(CameraImage image) {
    final bytes = image.planes[0].bytes;
    final w     = image.width;
    final h     = image.height;
    final out   = Uint8List(w * h * 3);
    int outIdx  = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      out[outIdx++] = bytes[i + 2]; // R
      out[outIdx++] = bytes[i + 1]; // G
      out[outIdx++] = bytes[i];     // B
    }
    return out;
  }

  // ── STEP 2 + 3 + 4: RESIZE + GAMMA + NORMALIZE ───────────────────────────

  /// Nearest-neighbour resize + gamma LUT + /255.0 → Float32List
  /// All three steps combined in one pass for cache efficiency.
  Float32List _resizeGammaNormalize(
    Uint8List rgbBytes, {
    required int srcWidth,
    required int srcHeight,
  }) {
    return _resizeGammaNormalizeStatic(
      rgbBytes,
      _gammaLut,
      srcWidth:  srcWidth,
      srcHeight: srcHeight,
    );
  }

  // ── STATIC HELPERS (isolate-safe) ────────────────────────────────────────

  static Uint8List _yuv420ToRgbBytesStatic(
    Uint8List yBytes,
    Uint8List uBytes,
    Uint8List vBytes,
    int w,
    int h,
    int yStride,
    int uvStride,
    int uvPixel,
  ) {
    final out    = Uint8List(w * h * 3);
    int   outIdx = 0;

    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final yVal  = yBytes[row * yStride + col] & 0xFF;
        final uvIdx = (row >> 1) * uvStride + (col >> 1) * uvPixel;
        final uVal  = (uBytes[uvIdx] & 0xFF) - 128;
        final vVal  = (vBytes[uvIdx] & 0xFF) - 128;

        // BT.601 YUV→RGB, scaled by 1024 to stay in integer arithmetic
        final r = ((yVal * 1024 + 1402 * vVal) >> 10).clamp(0, 255);
        final g = ((yVal * 1024 - 344  * uVal - 714 * vVal) >> 10).clamp(0, 255);
        final b = ((yVal * 1024 + 1772 * uVal) >> 10).clamp(0, 255);

        out[outIdx++] = r;
        out[outIdx++] = g;
        out[outIdx++] = b;
      }
    }
    return out;
  }

  static Float32List _resizeGammaNormalizeStatic(
    Uint8List rgbBytes,
    Uint8List gammaLut, {
    required int srcWidth,
    required int srcHeight,
  }) {
    final out    = Float32List(inputWidth * inputHeight * 3);
    final xScale = srcWidth  / inputWidth;
    final yScale = srcHeight / inputHeight;
    int   outIdx = 0;

    for (int dstRow = 0; dstRow < inputHeight; dstRow++) {
      final srcRow = (dstRow * yScale).toInt().clamp(0, srcHeight - 1);
      for (int dstCol = 0; dstCol < inputWidth; dstCol++) {
        final srcCol = (dstCol * xScale).toInt().clamp(0, srcWidth - 1);
        final srcIdx = (srcRow * srcWidth + srcCol) * 3;

        // Apply gamma LUT then normalize to [0.0, 1.0]
        out[outIdx++] = gammaLut[rgbBytes[srcIdx    ]] / 255.0;
        out[outIdx++] = gammaLut[rgbBytes[srcIdx + 1]] / 255.0;
        out[outIdx++] = gammaLut[rgbBytes[srcIdx + 2]] / 255.0;
      }
    }
    return out;
  }

  // ── GAMMA LUT ─────────────────────────────────────────────────────────────

  void _buildGammaLut() {
    _gammaLut = _buildGammaLutStatic();
  }

  /// Builds a 256-entry lookup table for gamma correction.
  /// γ=0.3 → brightens dark pixels aggressively (good for night driving).
  /// Each pixel lookup is O(1) — no math.pow() per pixel during inference.
  static Uint8List _buildGammaLutStatic() {
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final normalized = i / 255.0;
      final corrected  = math.pow(normalized, 1.0 / gamma).toDouble();
      lut[i] = (corrected * 255.0).round().clamp(0, 255);
    }
    return lut;
  }
}