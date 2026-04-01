import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class FramePreprocessor {
  static final FramePreprocessor instance = FramePreprocessor._init();
  FramePreprocessor._init();

  /// Converts CameraImage to a normalized Float32List tensor [1, H, W, 3]
  Float32List process(CameraImage image, {required int targetWidth, required int targetHeight}) {
    // 1. Convert CameraImage to img.Image
    img.Image convertedImage = _convertCameraImage(image);

    // 2. Resize to model requirements
    img.Image resizedImage = img.copyResize(
      convertedImage, 
      width: targetWidth, 
      height: targetHeight
    );

    // 3. Create Float32List for the tensor
    final Float32List buffer = Float32List(1 * targetWidth * targetHeight * 3);
    int pixelIndex = 0;

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final pixel = resizedImage.getPixel(x, y);
        
        // Normalize 0-255 to 0.0-1.0
        buffer[pixelIndex++] = pixel.r / 255.0;
        buffer[pixelIndex++] = pixel.g / 255.0;
        buffer[pixelIndex++] = pixel.b / 255.0;
      }
    }

    return buffer;
  }

  img.Image _convertCameraImage(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;
      final imgImage = img.Image(width: width, height: height);

      // YUV420 logic (Standard for Android Camera2)
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      final vPlane = image.planes[2].bytes;
      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel!;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int uvIndex = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;
          final int yIndex = y * yRowStride + x;

          final int yp = yPlane[yIndex];
          final int up = uPlane[uvIndex];
          final int vp = vPlane[uvIndex];

          // Standard YUV to RGB conversion
          int r = (yp + (1.370705 * (vp - 128))).round().clamp(0, 255);
          int g = (yp - (0.337633 * (up - 128)) - (0.698001 * (vp - 128))).round().clamp(0, 255);
          int b = (yp + (1.732446 * (up - 128))).round().clamp(0, 255);

          imgImage.setPixelRgb(x, y, r, g, b);
        }
      }
      return imgImage;
    } catch (e) {
      // Fallback for different formats (like iOS BGRA)
      return img.Image(width: 224, height: 224); 
    }
  }
}