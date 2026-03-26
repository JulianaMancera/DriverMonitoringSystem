import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// frame_preprocessor.dart
// Bantay Drive — Frame Preprocessing
//
// Place at: lib/core/inference/frame_preprocessor.dart
//
// Responsibilities:
//   1. Convert CameraImage (YUV420 / BGRA8888 / JPEG) → RGB img.Image
//   2. Resize to model input size (224 × 224)
//   3. Apply gamma correction (γ = 0.3) for low-light simulation
//   4. Normalize pixels to Float32 [0.0 – 1.0]
//   5. Return tensor shaped [1, 224, 224, 3] ready for TFLite
//
// Partner specs:
//   • Input shape : [1, 224, 224, 3]
//   • Gamma value : 0.3  (low-light simulation)
//   • Data type   : Float32 normalized (0.0 – 1.0)
// ─────────────────────────────────────────────────────────────────────────────

class FramePreprocessor {
  // ── SINGLETON ─────────────────────────────────────────────────────────────
  static final FramePreprocessor instance = FramePreprocessor._init();
  FramePreprocessor._init() {
    _buildGammaLut();
  }

  // ── CONFIG ────────────────────────────────────────────────────────────────

  /// Model input spatial dimensions
  static const int inputWidth  = 224;
  static const int inputHeight = 224;

  /// Gamma exponent — partner confirmed γ = 0.3 for low-light simulation.
  /// Applied as: corrected = pixel ^ (1 / γ)
  /// γ = 0.3 → aggressive brightening (tunnels, night roads)
  static const double gamma = 0.3;

  // ── INTERNAL ──────────────────────────────────────────────────────────────
  late final Uint8List _gammaLut; // precomputed [0–255] → corrected [0–255]

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Full preprocessing pipeline:
  ///   CameraImage → RGB → resize → gamma → Float32 tensor [1, 224, 224, 3]
  ///
  /// Returns null if the image format is unsupported or conversion fails.
  List<List<List<List<double>>>>? process(CameraImage image) {
    try {
      // Step 1 — Convert camera format to RGB
      final rgb = _convertToRgb(image);
      if (rgb == null) return null;

      // Step 2 — Resize to 224 × 224
      final resized = img.copyResize(
        rgb,
        width: inputWidth,
        height: inputHeight,
        interpolation: img.Interpolation.linear,
      );

      // Step 3 — Gamma correction via LUT
      final corrected = _applyGamma(resized);

      // Step 4 — Normalize to Float32 [0.0, 1.0] and build tensor
      return _buildTensor(corrected);

    } catch (e) {
      return null;
    }
  }

  // ── STEP 1: FORMAT CONVERSION ─────────────────────────────────────────────

  img.Image? _convertToRgb(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
        return _yuv420ToRgb(image);
      case ImageFormatGroup.bgra8888:
        return _bgra8888ToRgb(image);
      case ImageFormatGroup.jpeg:
        return img.decodeJpg(image.planes[0].bytes);
      default:
        return null;
    }
  }

  /// YUV420 → RGB  (standard Android camera format)
  img.Image _yuv420ToRgb(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final out = img.Image(width: w, height: h);

    final yBytes = image.planes[0].bytes;
    final uBytes = image.planes[1].bytes;
    final vBytes = image.planes[2].bytes;

    final yRowStride  = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixStride = image.planes[1].bytesPerPixel ?? 1;

    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final yVal = yBytes[row * yRowStride + col] & 0xFF;
        final uvIdx = (row >> 1) * uvRowStride + (col >> 1) * uvPixStride;
        final uVal  = (uBytes[uvIdx] & 0xFF) - 128;
        final vVal  = (vBytes[uvIdx] & 0xFF) - 128;

        final r = (yVal + 1.370705 * vVal).round().clamp(0, 255);
        final g = (yVal - 0.337633 * uVal - 0.698001 * vVal).round().clamp(0, 255);
        final b = (yVal + 1.732446 * uVal).round().clamp(0, 255);

        out.setPixelRgb(col, row, r, g, b);
      }
    }
    return out;
  }

  /// BGRA8888 → RGB  (iOS camera format)
  img.Image _bgra8888ToRgb(CameraImage image) {
    final w     = image.width;
    final h     = image.height;
    final bytes = image.planes[0].bytes;
    final out   = img.Image(width: w, height: h);

    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final idx = (row * w + col) * 4;
        // BGRA → RGB
        out.setPixelRgb(col, row, bytes[idx + 2], bytes[idx + 1], bytes[idx]);
      }
    }
    return out;
  }

  // ── STEP 2 (handled by caller via img.copyResize) ─────────────────────────

  // ── STEP 3: GAMMA CORRECTION ──────────────────────────────────────────────

  /// Build LUT once at construction — dart:math.pow for accuracy.
  void _buildGammaLut() {
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final normalized = i / 255.0;
      // Apply inverse gamma: x^(1/γ) brightens dark pixels
      final corrected  = math.pow(normalized, 1.0 / gamma).toDouble();
      lut[i] = (corrected * 255.0).round().clamp(0, 255);
    }
    _gammaLut = lut;
  }

  /// Apply precomputed gamma LUT to every RGB pixel.
  img.Image _applyGamma(img.Image source) {
    final out = img.Image(width: source.width, height: source.height);
    for (int row = 0; row < source.height; row++) {
      for (int col = 0; col < source.width; col++) {
        final pixel = source.getPixel(col, row);
        out.setPixelRgb(
          col, row,
          _gammaLut[pixel.r.toInt() & 0xFF],
          _gammaLut[pixel.g.toInt() & 0xFF],
          _gammaLut[pixel.b.toInt() & 0xFF],
        );
      }
    }
    return out;
  }

  // ── STEP 4: FLOAT32 TENSOR ────────────────────────────────────────────────

  /// Normalize pixel values to [0.0, 1.0] and pack into shape [1, H, W, 3].
  List<List<List<List<double>>>> _buildTensor(img.Image image) {
    return List.generate(1, (_) =>
      List.generate(inputHeight, (row) =>
        List.generate(inputWidth, (col) {
          final pixel = image.getPixel(col, row);
          return [
            (pixel.r.toInt() & 0xFF) / 255.0, // R
            (pixel.g.toInt() & 0xFF) / 255.0, // G
            (pixel.b.toInt() & 0xFF) / 255.0, // B
          ];
        }),
      ),
    );
  }
}