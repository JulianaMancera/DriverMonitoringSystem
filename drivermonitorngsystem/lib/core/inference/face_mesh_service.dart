import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FaceMeshService  (lightweight — face_detection contours, not 468-pt mesh)
//
// 468-point face mesh was too heavy for real-time on POCO hardware.
// face_detection with contours gives ~35 pts per facial region (face oval,
// eyes, eyebrows, lips, nose) — clean mesh overlay at ~5 FPS, ~10x lighter.
// ─────────────────────────────────────────────────────────────────────────────

class FaceContourResult {
  final Map<FaceContourType, List<Offset>> contours;
  final Map<FaceLandmarkType, Offset>      landmarks;
  final Path   contourPath;  // pre-built in 0–1 space
  final Rect   boundingBox;

  const FaceContourResult({
    required this.contours,
    required this.landmarks,
    required this.contourPath,
    required this.boundingBox,
  });
}

class FaceMeshService {
  static final FaceMeshService instance = FaceMeshService._init();
  FaceMeshService._init();

  FaceDetector? _detector;
  bool _isInitialized = false;
  bool _isRunning     = false;

  bool get isInitialized => _isInitialized;

  void initialize() {
    if (_isInitialized) return;
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode:      FaceDetectorMode.fast,
        enableContours:       true,
        enableLandmarks:      true,
        enableClassification: false,
        enableTracking:       false,
        minFaceSize:          0.15,
      ),
    );
    _isInitialized = true;
    debugPrint('[FaceMesh] initialized — contour mode (lightweight)');
  }

  Future<FaceContourResult?> processFrame(
      CameraImage image, int sensorOrientation) async {
    if (!_isInitialized || _detector == null) return null;
    if (_isRunning) return null;
    _isRunning = true;

    try {
      final inputImage = _buildInputImage(image, sensorOrientation);
      if (inputImage == null) return null;

      final faces = await _detector!.processImage(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.reduce((a, b) =>
          a.boundingBox.width > b.boundingBox.width ? a : b);

      final bool isRotated = sensorOrientation == 90 || sensorOrientation == 270;
      final imgW = isRotated ? image.height.toDouble() : image.width.toDouble();
      final imgH = isRotated ? image.width.toDouble()  : image.height.toDouble();

      // Normalise + flip X for front-camera mirror
      Offset norm(Point<int> p) => Offset(1.0 - (p.x / imgW), p.y / imgH);

      // Contour map
      final Map<FaceContourType, List<Offset>> contours = {};
      for (final type in FaceContourType.values) {
        final c = face.contours[type];
        if (c != null && c.points.isNotEmpty) {
          contours[type] = c.points.map(norm).toList();
        }
      }

      // Landmark map
      final Map<FaceLandmarkType, Offset> landmarks = {};
      for (final type in FaceLandmarkType.values) {
        final lm = face.landmarks[type];
        if (lm != null) landmarks[type] = norm(lm.position);
      }

      // Pre-build path in 0–1 normalised space
      final path = Path();
      for (final entry in contours.entries) {
        final pts = entry.value;
        if (pts.isEmpty) continue;
        path.moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        final t = entry.key;
        if (t == FaceContourType.face          ||
            t == FaceContourType.leftEye        ||
            t == FaceContourType.rightEye       ||
            t == FaceContourType.upperLipTop    ||
            t == FaceContourType.lowerLipBottom) {
          path.close();
        }
      }

      return FaceContourResult(
        contours:    contours,
        landmarks:   landmarks,
        contourPath: path,
        boundingBox: Rect.fromLTRB(
          1.0 - (face.boundingBox.right  / imgW),
          face.boundingBox.top    / imgH,
          1.0 - (face.boundingBox.left   / imgW),
          face.boundingBox.bottom / imgH,
        ),
      );
    } catch (e) {
      debugPrint('[FaceMesh] processFrame error: $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  InputImage? _buildInputImage(CameraImage image, int sensorOrientation) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        return InputImage.fromBytes(
          bytes: _yuv420ToNv21(image),
          metadata: InputImageMetadata(
            size:        Size(image.width.toDouble(), image.height.toDouble()),
            rotation:    _rotationFromDegrees(sensorOrientation),
            format:      InputImageFormat.nv21,
            bytesPerRow: image.width,
          ),
        );
      }
      return null;
    } catch (_) { return null; }
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final ySize  = image.width * image.height;
    final nv21   = Uint8List(ySize + (image.width ~/ 2) * (image.height ~/ 2) * 2);

    for (int i = 0; i < image.height; i++) {
      nv21.setRange(i * image.width, i * image.width + image.width,
          yPlane.bytes, i * yPlane.bytesPerRow);
    }
    int outIdx = ySize;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixStride = uPlane.bytesPerPixel ?? 1;
    for (int row = 0; row < image.height ~/ 2; row++) {
      for (int col = 0; col < image.width ~/ 2; col++) {
        final uvIdx = row * uvRowStride + col * uvPixStride;
        nv21[outIdx++] = vPlane.bytes[uvIdx];
        nv21[outIdx++] = uPlane.bytes[uvIdx];
      }
    }
    return nv21;
  }

  InputImageRotation _rotationFromDegrees(int degrees) {
    switch (degrees) {
      case  90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  void dispose() {
    _detector?.close();
    _detector = null;
    _isInitialized = false;
    _isRunning = false;
  }
}