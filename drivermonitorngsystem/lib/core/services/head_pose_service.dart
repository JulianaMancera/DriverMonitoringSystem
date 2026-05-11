import 'dart:math' as math;
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class HeadPoseResult {
  final double normalizedX;
  final double normalizedY;
  final double pitch;
  final double yaw;
  final double roll;
  final double earL;
  final double earR;
  final double mar;

  const HeadPoseResult({
    required this.normalizedX,
    required this.normalizedY,
    required this.pitch,
    required this.yaw,
    required this.roll,
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

  double _smoothedRoll = 0.0;
  double _smoothedEarL = 0.3;
  double _smoothedEarR = 0.3;
  double _smoothedMar  = 0.0;

  // EAR α=0.4: τ≈195ms — damps blinks, preserves sustained closure.
  // MAR α=0.5: τ≈144ms — damps brief opens, passes yawns (>200ms).
  static const double _alpha    = 0.5;
  static const double _earAlpha = 0.4;
  static const double _marAlpha = 0.5;

  static const _rotationMap = {
    0:   InputImageRotation.rotation0deg,
    90:  InputImageRotation.rotation90deg,
    180: InputImageRotation.rotation180deg,
  };

  void init(int sensorOrientation) {
    _smoothedRoll = 0.0;
    _smoothedEarL = 0.3;
    _smoothedEarR = 0.3;
    _smoothedMar  = 0.0;
    _rotation = _rotationMap[sensorOrientation] ??
        InputImageRotation.rotation270deg;
    _detector?.close();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode:      FaceDetectorMode.fast,
        enableClassification: true,  // required for leftEyeOpenProbability / rightEyeOpenProbability
        enableLandmarks:      true,  // required for mouth landmarks (MAR)
        enableTracking:       false,
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
        yBytes:        image.planes[0].bytes,
        uBytes:        image.planes[1].bytes,
        vBytes:        image.planes[2].bytes,
        yRowStride:    image.planes[0].bytesPerRow,
        uvRowStride:   image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        width:  image.width,
        height: image.height,
      ));

      final inputImage = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size:        Size(image.width.toDouble(), image.height.toDouble()),
          rotation:    _rotation,
          format:      InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );

      final faces = await _detector!.processImage(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.first;
      final box  = face.boundingBox;
      final cx   = box.left + box.width  / 2;
      final cy   = box.top  + box.height / 2;
      final nx   = ((cx / image.width)  * 2 - 1).clamp(-1.0, 1.0);
      final ny   = ((cy / image.height) * 2 - 1).clamp(-1.0, 1.0);

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

      // ML Kit eye open probability (0=closed, 1=open) mapped to EAR scale:
      // EAR = prob × 0.35 + 0.05  →  open≈0.40, drowsy≈0.225, closed≈0.05
      final leftProb  = (face.leftEyeOpenProbability  ?? 1.0).clamp(0.0, 1.0);
      final rightProb = (face.rightEyeOpenProbability ?? 1.0).clamp(0.0, 1.0);
      final earL = leftProb  * 0.35 + 0.05;
      final earR = rightProb * 0.35 + 0.05;

      double mar = 0.0;
      final mouthLeft   = face.landmarks[FaceLandmarkType.leftMouth];
      final mouthRight  = face.landmarks[FaceLandmarkType.rightMouth];
      final mouthBottom = face.landmarks[FaceLandmarkType.bottomMouth];
      final noseBase    = face.landmarks[FaceLandmarkType.noseBase];

      if (mouthLeft != null && mouthRight != null && mouthBottom != null) {
        final mouthW = (mouthRight.position.x - mouthLeft.position.x).abs().toDouble();
        if (mouthW > 1.0) {
          final mouthMidY = (mouthLeft.position.y + mouthRight.position.y) / 2.0;
          final upperY = noseBase != null
              ? (noseBase.position.y.toDouble() + mouthMidY) / 2.0
              : mouthMidY;
          final vertical = (mouthBottom.position.y.toDouble() - upperY).abs();
          mar = (vertical / mouthW).clamp(0.0, 2.0);
        }
      }

      _smoothedEarL = _earAlpha * earL + (1 - _earAlpha) * _smoothedEarL;
      _smoothedEarR = _earAlpha * earR + (1 - _earAlpha) * _smoothedEarR;
      _smoothedMar  = _marAlpha * mar  + (1 - _marAlpha) * _smoothedMar;

      return HeadPoseResult(
        normalizedX: nx,
        normalizedY: ny,
        pitch: face.headEulerAngleX ?? 0.0,
        yaw:   face.headEulerAngleY ?? 0.0,
        roll:  _smoothedRoll,
        earL:  _smoothedEarL,
        earR:  _smoothedEarR,
        mar:   _smoothedMar,
      );
    } catch (e) {
      debugPrint('[HeadPoseService] $e');
      return null;
    } finally {
      _isRunning = false;
    }
  }
}

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

  for (int row = 0; row < h; row++) {
    nv21.setRange(row * w, (row + 1) * w, i.yBytes, row * i.yRowStride);
  }

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
