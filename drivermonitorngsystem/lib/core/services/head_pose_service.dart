import 'dart:math' as math;
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class HeadPoseResult {
  final double normalizedX; // -1 (left) to +1 (right) — face center offset in frame
  final double normalizedY; // -1 (top)  to +1 (bottom)
  final double pitch;       // eulerX: + = looking down
  final double yaw;         // eulerY: + = turning right
  final double roll;        // geometry-based roll for UI indicator
  final double rawEulerZ;   // raw headEulerAngleZ fed to TFLite feature[7]
  final double earL;        // left eye open probability × 0.35 (EAR proxy)
  final double earR;        // right eye open probability × 0.35 (EAR proxy)
  final double mar;         // mouth aspect ratio from landmarks
  const HeadPoseResult({
    required this.normalizedX,
    required this.normalizedY,
    required this.pitch,
    required this.yaw,
    required this.roll,
    required this.rawEulerZ,
    required this.earL,
    required this.earR,
    required this.mar,
  });
}

class HeadPoseService {
  HeadPoseService._();
  static final HeadPoseService instance = HeadPoseService._();

  FaceDetector? _detector;
  bool _isRunning = false;
  InputImageRotation _rotation = InputImageRotation.rotation270deg;

  // EMA smoothing — reduces jitter so the indicator stays consistent
  double _smoothedRoll = 0.0;
  static const double _alpha = 0.5; // 0 = frozen, 1 = raw. 0.5 = fast enough for camera tilt

  void init(int sensorOrientation) {
    _smoothedRoll = 0.0;
    _rotation = _rotationFromSensor(sensorOrientation);
    _detector?.close();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: false,
      ),
    );
  }

  void dispose() {
    _detector?.close();
    _detector = null;
    _isRunning = false;
  }

  Future<HeadPoseResult?> detectPose(CameraImage image) async {
    if (_detector == null || _isRunning) return null;
    _isRunning = true;
    try {
      final nv21 = await compute(_toNv21, _Nv21Input(
        yBytes:       image.planes[0].bytes,
        uBytes:       image.planes[1].bytes,
        vBytes:       image.planes[2].bytes,
        yRowStride:   image.planes[0].bytesPerRow,
        uvRowStride:  image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        width:  image.width,
        height: image.height,
      ));

      final inputImage = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size:       Size(image.width.toDouble(), image.height.toDouble()),
          rotation:   _rotation,
          format:     InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );

      final faces = await _detector!.processImage(inputImage);
      if (faces.isEmpty) return null;

      final face   = faces.first;
      final box    = face.boundingBox;
      final cx     = box.left + box.width  / 2;
      final cy     = box.top  + box.height / 2;
      // Normalize to [-1, 1] relative to frame center
      final nx = ((cx / image.width)  * 2 - 1).clamp(-1.0, 1.0);
      final ny = ((cy / image.height) * 2 - 1).clamp(-1.0, 1.0);

      // Prefer eye-landmark geometry — eulerAngleZ in fast mode is unreliable.
      // In ML Kit's corrected image space, dy/dx between eyes directly gives tilt.
      final leftEye  = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      double rawRoll;
      if (leftEye != null && rightEye != null) {
        final dx = (rightEye.position.x - leftEye.position.x).toDouble();
        final dy = (rightEye.position.y - leftEye.position.y).toDouble();
        rawRoll = math.atan2(-dy, dx) * 180 / math.pi;
      } else {
        rawRoll = face.headEulerAngleZ ?? 0.0;
      }
      _smoothedRoll = _alpha * rawRoll + (1 - _alpha) * _smoothedRoll;

      // EAR proxy: eye open probability × 0.35 maps [0,1] → [0, 0.35],
      // matching the training distribution (mean ear_l ≈ 0.29, mean ear_r ≈ 0.27).
      final earL = (face.leftEyeOpenProbability  ?? 0.5) * 0.35;
      final earR = (face.rightEyeOpenProbability ?? 0.5) * 0.35;

      // MAR from mouth landmarks: 2 × vertical opening / horizontal width.
      final leftMouth   = face.landmarks[FaceLandmarkType.leftMouth];
      final rightMouth  = face.landmarks[FaceLandmarkType.rightMouth];
      final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth];
      double mar = 0.0;
      if (leftMouth != null && rightMouth != null && bottomMouth != null) {
        final mouthW = (rightMouth.position.x - leftMouth.position.x).abs().toDouble();
        if (mouthW > 0) {
          final midY = (leftMouth.position.y + rightMouth.position.y) / 2.0;
          mar = 2.0 * (bottomMouth.position.y - midY).abs() / mouthW;
        }
      }

      return HeadPoseResult(
        normalizedX: nx,
        normalizedY: ny,
        pitch:      face.headEulerAngleX ?? 0.0,
        yaw:        face.headEulerAngleY ?? 0.0,
        roll:       _smoothedRoll,
        rawEulerZ:  face.headEulerAngleZ ?? 0.0,
        earL:       earL,
        earR:       earR,
        mar:        mar,
      );
    } catch (e) {
      debugPrint('[HeadPoseService] $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }

  static InputImageRotation _rotationFromSensor(int degrees) {
    switch (degrees) {
      case 0:   return InputImageRotation.rotation0deg;
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      default:  return InputImageRotation.rotation270deg;
    }
  }
}

// ── Isolate helpers ────────────────────────────────────────────────────────────

class _Nv21Input {
  final Uint8List yBytes, uBytes, vBytes;
  final int yRowStride, uvRowStride, uvPixelStride, width, height;
  _Nv21Input({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.width,
    required this.height,
  });
}

Uint8List _toNv21(_Nv21Input i) {
  final w = i.width, h = i.height;
  final nv21 = Uint8List(w * h * 3 ~/ 2);

  // Y plane — copy row by row to skip padding
  for (int row = 0; row < h; row++) {
    nv21.setRange(row * w, (row + 1) * w, i.yBytes, row * i.yRowStride);
  }

  // VU interleaved (NV21 = Y + V/U pairs)
  int offset = w * h;
  for (int row = 0; row < h ~/ 2; row++) {
    for (int col = 0; col < w ~/ 2; col++) {
      final vIdx = row * i.uvRowStride + col * i.uvPixelStride;
      final uIdx = row * i.uvRowStride + col * i.uvPixelStride;
      nv21[offset++] = i.vBytes[vIdx];
      nv21[offset++] = i.uBytes[uIdx];
    }
  }
  return nv21;
}
