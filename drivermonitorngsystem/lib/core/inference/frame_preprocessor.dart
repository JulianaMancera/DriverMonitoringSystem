import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;


// Key optimizations:
//   1. Returns Float32List (flat buffer) instead of nested List<List<List>>
//      → tflite_flutter accepts this directly, skipping a full copy
//   2. YUV→RGB uses integer arithmetic only (no floating point per pixel)
//   3. Gamma LUT stored as Uint8List (1 byte per entry, cache-friendly)
//   4. Single-pass: resize + normalize done together where possible
//   5. processRaw() is a static top-level function so compute() can call it

class FramePreprocessor {
  static final FramePreprocessor instance = FramePreprocessor._init();
  FramePreprocessor._init() {
    _buildGammaLut();
  }

  static const int   inputWidth    = 224;
  static const int   inputHeight   = 224;
  static const double gamma        = 0.3;

  late final Uint8List _gammaLut;

  // PUBLIC API 
  /// Shape: [1 * 224 * 224 * 3] flat — tflite_flutter reshapes internally.
  Float32List? processToFloat32(CameraImage image) {
    try {
      // Step 1 — decode to raw RGB bytes (uint8, no allocation of img.Image)
      final Uint8List? rgbBytes = _toRgbBytes(image);
      if (rgbBytes == null) return null;

      // Step 2 — resize + gamma + normalize in one pass → Float32List
      return _resizeGammaNormalize(
        rgbBytes,
        srcWidth:  image.width,
        srcHeight: image.height,
      );
    } catch (_) {
      return null;
    }
  }

  // STEP 1: FAST YUV/BGRA → RAW RGB BYTES 
  /// Returns flat RGB bytes: [R, G, B, R, G, B, ...] length = w * h * 3
  Uint8List? _toRgbBytes(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        return _yuv420ToRgbBytes(image);
      case ImageFormatGroup.bgra8888:
        return _bgra8888ToRgbBytes(image);
      case ImageFormatGroup.jpeg:
        final decoded = img.decodeJpg(image.planes[0].bytes);
        if (decoded == null) return null;
        return _imgToRgbBytes(decoded);
      default:
        return null;
    }
  }

  /// YUV420 → RGB using integer math only (no double per pixel)
  Uint8List _yuv420ToRgbBytes(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final out = Uint8List(w * h * 3);

    final yBytes  = image.planes[0].bytes;
    final uBytes  = image.planes[1].bytes;
    final vBytes  = image.planes[2].bytes;

    final yStride  = image.planes[0].bytesPerRow;
    final uvStride = image.planes[1].bytesPerRow;
    final uvPixel  = image.planes[1].bytesPerPixel ?? 1;

    int outIdx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final yVal = yBytes[row * yStride + col] & 0xFF;
        final uvIdx = (row >> 1) * uvStride + (col >> 1) * uvPixel;
        final uVal  = (uBytes[uvIdx] & 0xFF) - 128;
        final vVal  = (vBytes[uvIdx] & 0xFF) - 128;

        // Integer YUV→RGB (multiply by 1024 to avoid floats, shift back)
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

  Uint8List _bgra8888ToRgbBytes(CameraImage image) {
    final w     = image.width;
    final h     = image.height;
    final bytes = image.planes[0].bytes;
    final out   = Uint8List(w * h * 3);
    int outIdx  = 0;
    for (int i = 0; i < w * h; i++) {
      final idx = i * 4;
      out[outIdx++] = bytes[idx + 2]; // R
      out[outIdx++] = bytes[idx + 1]; // G
      out[outIdx++] = bytes[idx];     // B
    }
    return out;
  }

  Uint8List _imgToRgbBytes(img.Image image) {
    final w = image.width; final h = image.height;
    final out = Uint8List(w * h * 3);
    int outIdx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final pixel = image.getPixel(col, row);
        out[outIdx++] = pixel.r.toInt() & 0xFF;
        out[outIdx++] = pixel.g.toInt() & 0xFF;
        out[outIdx++] = pixel.b.toInt() & 0xFF;
      }
    }
    return out;
  }

  // STEP 2: RESIZE + GAMMA + NORMALIZE IN ONE PASS
  /// Nearest-neighbour resize (fast) + gamma LUT + /255.0 → Float32List
  /// Shape: flat [inputHeight * inputWidth * 3]
  Float32List _resizeGammaNormalize(
    Uint8List rgbBytes, {
    required int srcWidth,
    required int srcHeight,
  }) {
    final out    = Float32List(inputWidth * inputHeight * 3);
    final xScale = srcWidth  / inputWidth;
    final yScale = srcHeight / inputHeight;

    int outIdx = 0;
    for (int dstRow = 0; dstRow < inputHeight; dstRow++) {
      final srcRow = (dstRow * yScale).toInt().clamp(0, srcHeight - 1);
      for (int dstCol = 0; dstCol < inputWidth; dstCol++) {
        final srcCol = (dstCol * xScale).toInt().clamp(0, srcWidth - 1);
        final srcIdx = (srcRow * srcWidth + srcCol) * 3;

        // Apply gamma LUT then normalize to [0, 1]
        out[outIdx++] = _gammaLut[rgbBytes[srcIdx    ]] / 255.0;
        out[outIdx++] = _gammaLut[rgbBytes[srcIdx + 1]] / 255.0;
        out[outIdx++] = _gammaLut[rgbBytes[srcIdx + 2]] / 255.0;
      }
    }
    return out;
  }

  // GAMMA LUT 
  void _buildGammaLut() {
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final normalized = i / 255.0;
      final corrected  = math.pow(normalized, 1.0 / gamma).toDouble();
      lut[i] = (corrected * 255.0).round().clamp(0, 255);
    }
    _gammaLut = lut;
  }
}