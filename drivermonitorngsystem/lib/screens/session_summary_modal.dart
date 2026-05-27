import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SessionSummaryModal extends StatefulWidget {
  final int durationSec;
  final double safetyScore;
  final int drowsyAlerts;
  final int distractedAlerts;

  const SessionSummaryModal({
    super.key,
    required this.durationSec,
    required this.safetyScore,
    required this.drowsyAlerts,
    required this.distractedAlerts,
  });

  @override
  State<SessionSummaryModal> createState() => _SessionSummaryModalState();
}

class _SessionSummaryModalState extends State<SessionSummaryModal>
    with SingleTickerProviderStateMixin {
  static const Color _bg       = AppColors.surface;
  static const Color _surface  = AppColors.surfaceAlt;
  static const Color _divider  = AppColors.divider;
  static const Color _cyan     = AppColors.cyan;
  static const Color _green    = AppColors.green;
  static const Color _amber    = AppColors.amber;
  static const Color _red      = AppColors.redAlert;
  static const Color _drowsy   = AppColors.amber;
  static const Color _dist     = AppColors.purple;
  static const Color _txtPri   = AppColors.textPrimary;
  static const Color _txtMuted = AppColors.textMuted;
  static const Color _txtDim   = AppColors.textDim;

  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _scoreColor {
    if (widget.safetyScore >= 80) return _green;
    if (widget.safetyScore >= 50) return _amber;
    return _red;
  }

  String _formatDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m ${sec}s';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    final totalAlerts = widget.drowsyAlerts + widget.distractedAlerts;
    final allClear = totalAlerts == 0;
    final headerColor = _scoreColor;

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(_scale),
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 40,
                  offset: const Offset(0, -8)),
              BoxShadow(
                  color: headerColor.withValues(alpha: 0.05),
                  blurRadius: 60,
                  spreadRadius: 4),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: _divider,
                        borderRadius: BorderRadius.circular(2))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 14),
                child: Row(children: [
                  Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: headerColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: headerColor.withValues(alpha: 0.35),
                              width: 2)),
                      child: Icon(
                          allClear
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          color: headerColor,
                          size: 24)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Session Complete',
                            style: TextStyle(
                                color: _txtPri,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(_formatDuration(widget.durationSec),
                            style: TextStyle(color: _txtMuted, fontSize: 13)),
                      ])),
                  GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: _surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: _divider, width: 1)),
                          child: Icon(Icons.close_rounded,
                              color: _txtMuted, size: 18))),
                ]),
              ),
              Divider(color: _divider, height: 1, thickness: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: headerColor.withValues(alpha: 0.25), width: 1),
                    ),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('SAFETY SCORE',
                                style: TextStyle(
                                    color: _txtDim,
                                    fontSize: 11,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${widget.safetyScore.toInt()}',
                                      style: TextStyle(
                                          color: headerColor,
                                          fontSize: 42,
                                          fontWeight: FontWeight.w800,
                                          height: 1)),
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 6, left: 3),
                                      child: Text('%',
                                          style: TextStyle(
                                              color: headerColor.withValues(
                                                  alpha: 0.7),
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600))),
                                ]),
                          ])),
                      _ScoreRing(score: widget.safetyScore, color: headerColor),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: _AlertChip(
                      label: 'Drowsy',
                      count: widget.drowsyAlerts,
                      color: _drowsy,
                      icon: Icons.bedtime_outlined,
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _AlertChip(
                      label: 'Distracted',
                      count: widget.distractedAlerts,
                      color: _dist,
                      icon: Icons.visibility_off_outlined,
                    )),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cyan.withValues(alpha: 0.12),
                        foregroundColor: _cyan,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: _cyan.withValues(alpha: 0.35),
                                width: 1)),
                      ),
                      child: const Text('Done',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;
  final Color color;
  const _ScoreRing({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 5,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
            strokeCap: StrokeCap.round,
          ),
        ),
        Text('${score.toInt()}%',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _AlertChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlerts = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: hasAlerts
                ? color.withValues(alpha: 0.30)
                : AppColors.divider,
            width: 1),
      ),
      child: Row(children: [
        Icon(icon,
            color: hasAlerts ? color : AppColors.textDim, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 1),
          Text('$count alert${count == 1 ? '' : 's'}',
              style: TextStyle(
                  color: hasAlerts ? color : AppColors.textDim,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ])),
      ]),
    );
  }
}
