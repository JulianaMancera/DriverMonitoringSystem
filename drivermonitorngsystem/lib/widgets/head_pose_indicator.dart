import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Circular camera-tilt gauge (wiper-style).
///
/// [roll]    — camera roll in degrees (eulerAngleZ from ML Kit).
///             0 = straight, + = tilted right, - = tilted left.
/// [hasFace] — whether a face was detected in the current frame.
/// [size]    — diameter of the gauge in logical pixels.
class HeadPoseIndicator extends StatelessWidget {
  final double roll;
  final bool   hasFace;
  final double size;

  const HeadPoseIndicator({
    super.key,
    required this.roll,
    required this.hasFace,
    this.size = 140,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(roll: roll, hasFace: hasFace),
      ),
    );
  }
}

// Zone helpers 
  Color zoneColorFromRoll(double rollDeg) {
    final r = rollDeg.abs();
    // Widened to match 30–45° side-mount normal operating angle.
    // Green:  |roll| < 30°  (was 20°) — optimal
    // Yellow: 30–55°        (was 45°) — side mount normal range, still detects
    // Red:    > 55°         (was 45°) — extreme tilt, accuracy drops significantly
    if (r < 30) return const Color(0xFF22c55e);
    if (r < 55) return const Color(0xFFfbbf24);
    return const Color(0xFFef4444);
  }

// Painter 

class _GaugePainter extends CustomPainter {
  final double roll;
  final bool   hasFace;

  _GaugePainter({required this.roll, required this.hasFace});

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width  / 2;
    final cy     = size.height / 2;
    final center = Offset(cx, cy);
    final radius = cx - 3.0;
    final rect   = Rect.fromCircle(center: center, radius: radius);

    // ── Background sectors ─────────────────────────────────────────────────────

    // Red fills the full circle first
    canvas.drawCircle(center, radius,
        Paint()..color = const Color(0xFFef4444).withValues(alpha: 0.75));

    // Yellow arcs: ±20°–45° from 12 o'clock (two symmetric slices)
    final yellowPaint = Paint()
      ..color = const Color(0xFFfbbf24).withValues(alpha: 0.82);
    final yellowStart = 30 * math.pi / 180; // 30° (was 20°)
    final yellowSpan  = 25 * math.pi / 180; // 30°→55° (was 20°→45°)
    canvas.drawArc(rect, -math.pi / 2 - yellowStart - yellowSpan,
        yellowSpan, true, yellowPaint);
    canvas.drawArc(rect, -math.pi / 2 + yellowStart,
        yellowSpan, true, yellowPaint);
 
    // Green arc: ±30° from 12 o'clock (was ±20°)
    // At 30–45° side mount, the camera icon now lands in green/yellow.
    final greenSpan = 30 * math.pi / 180 * 2; // total 60° (was 40°)
    canvas.drawArc(
      rect,
      -math.pi / 2 - greenSpan / 2,
      greenSpan,
      true,
      Paint()..color = const Color(0xFF22c55e).withValues(alpha: 0.88),
    );

    // Outer border — color matches current tilt zone 
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color       = hasFace ? zoneColorFromRoll(roll) : Colors.white38
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    // Inner reference dot 
    canvas.drawCircle(center, 3, Paint()..color = Colors.white54);

    // Person silhouette (head + body arc) 
    final personY     = cy + radius * 0.38;
    final headRadius  = size.width * 0.072;
    final personPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, personY), headRadius, personPaint);
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, personY + headRadius * 2.2),
      width:  headRadius * 3.2,
      height: headRadius * 2.6,
    );
    canvas.drawArc(bodyRect, math.pi, math.pi, false, personPaint);

    // ── Camera icon — wiper-style arc movement ─────────────────────────────────
    // Icon sweeps along a fixed arc like a windshield wiper.
    // roll = 0° → centered (green). roll = ±75° → edge of arc (red zone).
    // ML Kit eulerZ: + = face tilts right (camera tilted left) → icon swings left.
    if (hasFace) {
      const maxSwingDeg = 75.0;
      const maxSwing    = maxSwingDeg * math.pi / 180; // 75° in radians
      final arcRadius   = radius * 0.52;

      // ML Kit eulerZ: + = face appears CCW = camera tilted right → icon right.
      final clampedAngle =
          (roll * math.pi / 180).clamp(-maxSwing, maxSwing);

      final iconX = cx + arcRadius * math.sin(clampedAngle);
      final iconY = cy - arcRadius * math.cos(clampedAngle);

      // Guide arc — shows the wiper path
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: arcRadius),
        -math.pi / 2 - maxSwing,
        maxSwing * 2,
        false,
        Paint()
          ..color       = Colors.white24
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      _drawCameraIcon(canvas, Offset(iconX, iconY), size.width * 0.11);
    } else {
      _drawDashedRing(canvas, center, radius * 0.28);
    }
  }

  void _drawCameraIcon(Canvas canvas, Offset pos, double s) {
    final white  = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final shadow = Paint()
      ..color      = Colors.black38
      ..style      = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos.translate(1, 1), width: s * 1.9, height: s * 1.3),
        Radius.circular(s * 0.22),
      ),
      shadow,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: s * 1.9, height: s * 1.3),
        Radius.circular(s * 0.22),
      ),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - s * 0.65, pos.dy - s * 0.78, s * 0.52, s * 0.32),
        Radius.circular(s * 0.1),
      ),
      white,
    );
    canvas.drawCircle(pos, s * 0.44, Paint()..color = const Color(0xFF1e293b));
    canvas.drawCircle(pos, s * 0.28, Paint()..color = const Color(0xFF475569));
    canvas.drawCircle(pos.translate(-s * 0.1, -s * 0.1), s * 0.09,
        Paint()..color = Colors.white54);
  }

  void _drawDashedRing(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color       = Colors.white38
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const segments = 10;
    const gap       = 2 * math.pi / segments;
    for (int i = 0; i < segments; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * gap, gap * 0.72, false, paint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.roll != roll || old.hasFace != hasFace;
}