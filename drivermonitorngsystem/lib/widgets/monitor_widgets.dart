import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import 'head_pose_indicator.dart';

class MetricGauge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final bool tapHint;
  const MetricGauge(
      {super.key,
      required this.label,
      required this.value,
      required this.color,
      required this.icon,
      this.tapHint = false});

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 100.0);
    final gaugeD = context.ri(context.isSmallPhone ? 60.0 : 68.0);
    final fSize = context.sp(context.isSmallPhone ? 18.0 : 20.0);
    final pSize = context.sp(9.0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(context.rp(14)),
        border: Border.all(
          color: clamped >= 100.0
              ? color.withValues(alpha: 0.5)
              : AppColors.divider,
          width: 1,
        ),
      ),
      padding: EdgeInsets.symmetric(
          vertical: context.rs(10), horizontal: context.rp(5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: context.ri(11), color: color),
          SizedBox(width: context.rp(3)),
          Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: context.sp(9),
                      fontWeight: FontWeight.w500))),
          if (tapHint) ...[
            SizedBox(width: context.rp(3)),
            Icon(Icons.touch_app_rounded,
                size: context.ri(9), color: color.withValues(alpha: 0.6)),
          ],
        ]),
        SizedBox(height: context.rs(8)),
        SizedBox(
          width: gaugeD,
          height: gaugeD,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
                width: gaugeD,
                height: gaugeD,
                child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: context.isSmallPhone ? 3.0 : 4.0,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        color.withValues(alpha: 0.18)),
                    strokeCap: StrokeCap.round)),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (_, v, __) =>
                  Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${v.toInt()}',
                    style: TextStyle(
                        color: color,
                        fontSize: fSize,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace')),
                Text('%',
                    style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: pSize,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class CameraOverlayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  const CameraOverlayButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.isActive,
      required this.activeColor,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
            horizontal: context.rp(12), vertical: context.rs(7)),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(context.rp(18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: context.ri(16),
              color: isActive ? activeColor : Colors.white60),
          SizedBox(width: context.rp(5)),
          Text(label,
              style: TextStyle(
                  color: isActive ? activeColor : Colors.white60,
                  fontSize: context.sp(11),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class CameraGuideDialog extends StatelessWidget {
  final ValueNotifier<(double, bool)> headPose;
  const CameraGuideDialog({super.key, required this.headPose});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: Color(0xFFe2e8f0), shape: BoxShape.circle),
                child:
                    const Icon(Icons.close, size: 20, color: AppColors.surfaceSlate),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<(double, bool)>(
            valueListenable: headPose,
            builder: (_, pose, __) => HeadPoseIndicator(
              roll: pose.$1,
              hasFace: pose.$2,
              size: 170,
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<(double, bool)>(
            valueListenable: headPose,
            builder: (_, pose, __) {
              final inGreen = pose.$2 && pose.$1.abs() < 30.0;
              return Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: inGreen
                        ? const Color(0xFF22c55e)
                        : const Color(0xFFe2e8f0),
                    width: 2.5,
                  ),
                ),
                child: Column(children: [
                  const Text(
                    'Position your phone to the right side of the driver at '
                    '30–45°. The camera icon should be in the green or yellow zone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.surfaceSlate,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22c55e),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('OK',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}
