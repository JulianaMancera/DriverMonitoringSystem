import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../core/providers.dart';
import '../utils/responsive.dart';

Color _scoreColor(double score) {
  if (score >= 90) return const Color(0xFF10b981);
  if (score >= 75) return const Color(0xFF22d3ee);
  if (score >= 60) return const Color(0xFFf59e0b);
  return const Color(0xFFef4444);
}

// PROVIDER
final dashboardProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(dbChangeCounterProvider);
  return await DatabaseHelper.instance.getDashboardSummary();
});
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(dashboardProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashAsync = ref.watch(dashboardProvider);
    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Column(children: [
        Expanded(
          child: dashAsync.when(
            loading: () => const _DashboardSkeleton(),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline,
                    color: const Color(0xFF64748b), size: context.ri(48)),
                SizedBox(height: context.rs(12)),
                Text('Error loading dashboard: $e',
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center),
                SizedBox(height: context.rs(12)),
                TextButton(
                  onPressed: () => ref.invalidate(dashboardProvider),
                  child: const Text('Retry',
                      style: TextStyle(color: Color(0xFF22d3ee))),
                ),
              ]),
            ),
            data: (data) => _buildContent(context, data),
          ),
        ),
      ]),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> data) {
    final safetyScore       = (data['safety_score']      as double? ?? 100.0)
        .clamp(0.0, 100.0);
    final totalDriveHrs     = data['total_drive_hrs']    as double? ?? 0.0;
    final alertsLast24h     = data['alerts_last_24h']    as int?    ?? 0;
    final safetyStreak      = data['safety_streak_days'] as int?    ?? 0;
    final avgAlertness      = (data['avg_alertness_pct'] as double? ?? 100.0)
        .clamp(0.0, 100.0);
    final dailyScores       = (data['daily_safety_scores'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];
    final alertnessSnapshots = (data['alertness_snapshots'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];

    final double? lastSessionScore = data['last_session_score'] as double?;
    final double? prevSessionScore = data['prev_session_score'] as double?;
    final double? trendDelta = (lastSessionScore != null && prevSessionScore != null)
        ? lastSessionScore - prevSessionScore
        : null;

    final bool isRecording    = ref.watch(isRecordingProvider);
    final bool hasAnySessions = dailyScores.isNotEmpty;

    String scoreLabel = 'EXCELLENT';
     if (safetyScore < 60) {
          scoreLabel = "POOR";
      } else if (safetyScore < 75) {
          scoreLabel = "FAIR";
      } else if (safetyScore < 90) {
          scoreLabel = "GOOD";
      }

    return RefreshIndicator(
      color:           const Color(0xFF22d3ee),
      backgroundColor: const Color(0xFF0f172a),
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
            horizontal: context.hPad, vertical: context.rs(10)),
        child: Column(children: [

          // Safety score + stat cards
          Column(children: [
            _buildSafetyScoreCard(
                context, safetyScore, scoreLabel, hasAnySessions,
                trendDelta: trendDelta),
            SizedBox(height: context.rs(24)),
            hasAnySessions
                ? _buildQuickStatsGrid(context,
                    totalDriveHrs: totalDriveHrs,
                    alertsLast24h: alertsLast24h,
                    safetyStreak:  safetyStreak,
                    avgAlertness:  avgAlertness)
                : _buildEmptyStatsGrid(context),
          ]),

          SizedBox(height: context.rs(24)),
          _buildSafetyScoreHistory(
              context, dailyScores, hasAnySessions,
              isRecording: isRecording,
              alertnessSnapshots: alertnessSnapshots),
          SizedBox(height: context.rs(20)),
        ]),
      ),
    );
  }

  // SAFETY SCORE CARD
  Widget _buildSafetyScoreCard(
    BuildContext context,
    double score,
    String label,
    bool hasAnySessions, {
    double? trendDelta,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(20)),
        border: Border.all(color: const Color(0xFF1E2D45), width: 1),
      ),
      child: Stack(children: [
        Positioned(top: 0, left: 0, right: 0,
          child: Container(
            height: context.rs(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)]),
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(context.rp(20)),
                topRight: Radius.circular(context.rp(20)),
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.all(context.forTier(
                base: 40.0, compact: 28.0, small: 32.0, large: 44.0)),
            child: Column(
              mainAxisAlignment:  MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('SAFETY SCORE',
                    style: TextStyle(
                      color:         const Color(0xFF94a3b8),
                      fontSize:      context.sp(15),
                      fontWeight:    FontWeight.w500,
                      letterSpacing: 1.5,
                    )),
                SizedBox(height: context.rs(20)),
                _buildCircularScoreIndicator(
                    context, hasAnySessions ? score : 100.0,
                    hasAnySessions ? label : '—', hasAnySessions,
                    trendDelta: hasAnySessions ? trendDelta : null),
                if (!hasAnySessions) ...[
                  SizedBox(height: context.rs(12)),
                  Text('Start a session to see your score',
                      style: TextStyle(
                          color:    const Color(0xFF475569),
                          fontSize: context.sp(11)),
                      textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildCircularScoreIndicator(
    BuildContext context,
    double score,
    String label,
    bool hasAnySessions, {
    double? trendDelta,
  }) {
    final outerSize = context.forTier<double>(
        base: 160.0, compact: 130.0, small: 140.0, large: 170.0,
        xlarge: 180.0);
    final progressSize = outerSize * 0.88;
    final innerSize    = outerSize * 0.73;
    final scoreColor   = hasAnySessions ? _scoreColor(score) : const Color(0xFF1e293b);

    return SizedBox(
      width: outerSize, height: outerSize,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: outerSize, height: outerSize,
          decoration: BoxDecoration(
            color:  const Color(0xFF0f172a),
            shape:  BoxShape.circle,
            boxShadow: [
              BoxShadow(color: const Color(0xFF0b1120).withValues(alpha: 0.8),
                  offset: const Offset(6, 6), blurRadius: 12),
              BoxShadow(color: const Color(0xFF1e293b).withValues(alpha: 0.8),
                  offset: const Offset(-6, -6), blurRadius: 12),
            ],
          ),
        ),
        SizedBox(
          width: progressSize, height: progressSize,
          child: CircularProgressIndicator(
            value:           hasAnySessions ? score / 100 : 0,
            strokeWidth:     context.forTier(
                base: 6.0, compact: 5.0, large: 7.0),
            backgroundColor: const Color(0xFF1e293b),
            valueColor:      AlwaysStoppedAnimation<Color>(scoreColor),
            strokeCap: StrokeCap.round,
          ),
        ),
        Container(
          width: innerSize, height: innerSize,
          decoration: const BoxDecoration(
            color:  Color(0xFF0f172a),
            shape:  BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Color(0xFF0b1120),
                  offset: Offset(6, 6), blurRadius: 12),
              BoxShadow(color: Color(0xFF1e293b),
                  offset: Offset(-6, -6), blurRadius: 12),
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              hasAnySessions ? score.toStringAsFixed(0) : '—',
              style: TextStyle(
                fontSize:   context.forTier(
                    base: 34.0, compact: 26.0, small: 30.0, large: 38.0),
                fontWeight: FontWeight.bold,
                color:      scoreColor,
              ),
            ),
            SizedBox(height: context.rs(2)),
            Text(label,
                style: TextStyle(
                  fontSize:      context.sp(9),
                  color:         const Color(0xFF64748b),
                  letterSpacing: 1,
                )),
            if (hasAnySessions && trendDelta != null) ...[
              SizedBox(height: context.rs(4)),
              _buildTrendRow(context, trendDelta),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildTrendRow(BuildContext context, double delta) {
    final improved = delta > 0.5;
    final declined = delta < -0.5;
    final color = improved ? const Color(0xFF10b981)
                : declined ? const Color(0xFFef4444)
                : const Color(0xFF64748b);
    final icon  = improved ? Icons.arrow_upward_rounded
                : declined ? Icons.arrow_downward_rounded
                : Icons.remove_rounded;
    final text  = delta.abs() < 0.5
        ? 'same'
        : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)} pts';

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: context.ri(9), color: color),
      SizedBox(width: context.rp(2)),
      Text(text, style: TextStyle(
        fontSize:   context.sp(9),
        color:      color,
        fontWeight: FontWeight.w600,
      )),
    ]);
  }

  // SHARED STATS GRID HELPER — single source of truth for GridView layout config
  Widget _buildStatsGrid(BuildContext context, {required List<Widget> children}) {
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final int    crossCount;
    final double mainSpacing;
    final double crossSpacing;
    final double aspect;

    if (isPortrait) {
      crossCount   = 2;
      mainSpacing  = context.rs(12);
      crossSpacing = context.rp(12);
      aspect       = context.forTier(
          base: 1.0, compact: 0.90, small: 0.95, large: 1.05);
    } else {
      crossCount   = 4;
      mainSpacing  = context.rs(10);
      crossSpacing = context.rp(10);
      final gapCount = crossCount - 1;
      final screenW  = context.sw;
      final hPad     = context.hPad * 2;
      final spacing  = crossSpacing * gapCount;
      final cardW    = (screenW - hPad - spacing) / crossCount;
      aspect         = (cardW / 130).clamp(1.0, 2.2);
    }

    return GridView.count(
      crossAxisCount:   crossCount,
      shrinkWrap:       true,
      physics:          const NeverScrollableScrollPhysics(),
      mainAxisSpacing:  mainSpacing,
      crossAxisSpacing: crossSpacing,
      childAspectRatio: aspect,
      children: children,
    );
  }

  // QUICK STATS GRID — delegates layout to _buildStatsGrid
  Widget _buildQuickStatsGrid(
    BuildContext context, {
    required double totalDriveHrs,
    required int    alertsLast24h,
    required int    safetyStreak,
    required double avgAlertness,
  }) =>
      _buildStatsGrid(context, children: [
        _StatCard(
          icon: Icons.access_time_outlined, label: 'Total Drive Time',
          value: '${totalDriveHrs.toStringAsFixed(1)} hrs',
          subtext: 'Last 30 days', accent: false,
        ),
        _StatCard(
          icon: Icons.shield_outlined, label: 'Alert Triggered',
          value: '$alertsLast24h',
          subtext: 'Last 24 hours', accent: alertsLast24h > 0,
        ),
        _StatCard(
          icon: Icons.local_fire_department_outlined, label: 'Safety Streak',
          value: '$safetyStreak days',
          subtext: safetyStreak > 0 ? 'Keep it up!' : 'Stay alert!',
          accent: false,
        ),
        _StatCard(
          icon: Icons.trending_up, label: 'Avg Alertness',
          value: '${avgAlertness.toStringAsFixed(0)}%',
          subtext: 'Last 7 days', accent: false,
        ),
      ]);

  // EMPTY STATS GRID — delegates layout to _buildStatsGrid
  Widget _buildEmptyStatsGrid(BuildContext context) =>
      _buildStatsGrid(context, children: const [
        _EmptyStatCard(icon: Icons.access_time_outlined,           label: 'Total Drive Time'),
        _EmptyStatCard(icon: Icons.shield_outlined,                label: 'Alert Triggered'),
        _EmptyStatCard(icon: Icons.local_fire_department_outlined, label: 'Safety Streak'),
        _EmptyStatCard(icon: Icons.trending_up,                    label: 'Avg Alertness'),
      ]);

  // SAFETY SCORE HISTORY
  Widget _buildSafetyScoreHistory(
    BuildContext context,
    List<Map<String, dynamic>> dailyScores,
    bool hasAnySessions, {
    bool isRecording = false,
    List<Map<String, dynamic>> alertnessSnapshots = const [],
  }) {
    final List<FlSpot> spots   = [];
    final List<String> xLabels = [];

    if (hasAnySessions) {
      for (int i = 0; i < dailyScores.length; i++) {
        final score = (dailyScores[i]['avg_score'] as double? ?? 0.0)
            .clamp(0.0, 100.0);
        final day   = dailyScores[i]['day'] as String? ?? '';
        String label;
        try {
          final d = DateTime.parse(day).toLocal();
          const mo = ['','Jan','Feb','Mar','Apr','May','Jun',
                         'Jul','Aug','Sep','Oct','Nov','Dec'];
          label = '${mo[d.month]} ${d.day}';
        } catch (_) {
          label = day.length >= 7 ? day.substring(5) : day;
        }
        spots.add(FlSpot(i.toDouble(), score));
        xLabels.add(label);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color:        const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(20)),
        border: Border.all(color: const Color(0xFF1E2D45), width: 1),
      ),
      padding: EdgeInsets.fromLTRB(
          context.hPad, context.rs(16), context.hPad, context.rs(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text('Safety Score History',
              style: TextStyle(
                color:         const Color(0xFFe2e8f0),
                fontSize:      context.sp(16),
                fontWeight:    FontWeight.bold,
                letterSpacing: 0.1,
              ))),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: context.rp(12), vertical: context.rs(6)),
            decoration: BoxDecoration(
              color:  const Color(0xFF22d3ee).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(context.rp(20)),
              border: Border.all(
                  color: const Color(0xFF22d3ee).withValues(alpha: 0.65),
                  width: 1.4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.show_chart_rounded,
                  size: context.ri(13), color: const Color(0xFF22d3ee)),
              SizedBox(width: context.rp(5)),
              Text('30 Days',
                  style: TextStyle(
                      fontSize:   context.sp(11),
                      fontWeight: FontWeight.w600,
                      color:      const Color(0xFF22d3ee))),
            ]),
          ),
        ]),

        SizedBox(height: context.rs(5)),

        Text(
          hasAnySessions
              ? 'Avg safety score per drive day · swipe to explore'
              : isRecording
                  ? 'Alertness % · updates every 5 s'
                  : 'Start your first session to begin tracking',
          style: TextStyle(
              color: const Color(0xFF475569), fontSize: context.sp(12)),
        ),

        SizedBox(height: context.rs(16)),

        if (!hasAnySessions && isRecording && alertnessSnapshots.isNotEmpty)
          SizedBox(
            height: context.rs(context.isSmallPhone ? 210 : 240),
            child: _AlertnessSparkline(snapshots: alertnessSnapshots),
          )
        else if (!hasAnySessions)
          _buildEmptyChartState(context)
        else
          SizedBox(
            height: context.rs(context.isSmallPhone ? 210 : 240),
            child: _SafetyScoreChartInner(
                spots: spots, xLabels: xLabels),
          ),
      ]),
    );
  }

  Widget _buildEmptyChartState(BuildContext context) {
    return Container(
      height: context.rs(context.isSmallPhone ? 160 : 190),
      decoration: BoxDecoration(
        color:        const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(context.rp(12)),
        border: Border.all(color: const Color(0xFF1e293b), width: 1),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: EdgeInsets.all(context.rp(12)),
            decoration: BoxDecoration(
              color:        const Color(0xFF1e293b),
              borderRadius: BorderRadius.circular(context.rp(12)),
            ),
            child: Icon(Icons.show_chart_rounded,
                color: const Color(0xFF334155), size: context.ri(28)),
          ),
          SizedBox(height: context.rs(14)),
          Text('No drive history yet',
              style: TextStyle(
                  color:      const Color(0xFF475569),
                  fontSize:   context.sp(14),
                  fontWeight: FontWeight.w600)),
          SizedBox(height: context.rs(5)),
          Text('Complete a session in Monitor to begin tracking',
              style: TextStyle(
                  color:    const Color(0xFF334155),
                  fontSize: context.sp(11)),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── SAFETY SCORE CHART ────────────────────────────────────────────────────────
class _SafetyScoreChartInner extends StatefulWidget {
  final List<FlSpot> spots;
  final List<String> xLabels;
  const _SafetyScoreChartInner({
    required this.spots, required this.xLabels,
  });
  @override
  State<_SafetyScoreChartInner> createState() =>
      _SafetyScoreChartInnerState();
}

class _SafetyScoreChartInnerState extends State<_SafetyScoreChartInner> {
  final ScrollController _sc = ScrollController();

  static const double _chartMin = 0.0;
  static const double _chartMax = 112.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients && _sc.position.maxScrollExtent > 0) {
        _sc.jumpTo(_sc.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<FlSpot> spots;
    final List<String> labels;
    final double       maxX;

    if (widget.spots.length == 1) {
      spots  = [FlSpot(0, widget.spots[0].y), FlSpot(1, widget.spots[0].y)];
      labels = ['', widget.xLabels[0]];
      maxX   = 1.5;
    } else {
      spots  = widget.spots;
      labels = widget.xLabels;
      maxX   = (widget.spots.length - 1).toDouble() + 0.4;
    }

    final pointSpacing = context.rp(46);
    final yAxisWidth   = context.rp(40);
    final rightPad     = context.rp(40);
    final chartW = yAxisWidth + ((spots.length - 1) * pointSpacing) + rightPad;

    return SingleChildScrollView(
      controller:      _sc,
      scrollDirection: Axis.horizontal,
      physics:         const BouncingScrollPhysics(),
      child: SizedBox(
        width: chartW,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              horizontalInterval: 20,
              getDrawingHorizontalLine: (_) => FlLine(
                  color: const Color(0xFF1e293b), strokeWidth: 1,
                  dashArray: [4, 4]),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   false,
                  reservedSize: context.rs(12),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  reservedSize: context.rs(34),
                  interval:     1,
                  getTitlesWidget: (value, meta) {
                    if ((value - value.roundToDouble()).abs() > 0.01) {
                      return const SizedBox.shrink();
                    }
                    final idx = value.toInt();
                    if (idx < 0 || idx >= widget.xLabels.length) {
                      return const SizedBox.shrink();
                    }
                    final text = labels[idx];
                    if (text.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: EdgeInsets.only(top: context.rs(8)),
                      child: Text(text, style: TextStyle(
                          color: const Color(0xFF64748b),
                          fontSize: context.sp(10))),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  interval:     20,
                  reservedSize: yAxisWidth,
                  getTitlesWidget: (value, meta) {
                    final v = value.toInt();
                    if (v < 0 || v > 100 || v % 20 != 0) {
                      return const SizedBox.shrink();
                    }
                    return Text('$v', style: TextStyle(
                      color:    const Color(0xFF64748b),
                      fontSize: context.sp(10),
                    ));
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0, maxX: maxX,
            minY: _chartMin, maxY: _chartMax,
            lineBarsData: [
              LineChartBarData(
                spots:            spots,
                isCurved:         spots.length > 2,
                curveSmoothness:  0.3,
                color:            const Color(0xFF22d3ee),
                barWidth:         2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius:      3.5,
                        color:       const Color(0xFF22d3ee),
                        strokeWidth: 1.5,
                        strokeColor: const Color(0xFF0f172a)),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF22d3ee).withValues(alpha: 0.25),
                      const Color(0xFF22d3ee).withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF0f172a),
                tooltipBorderRadius: BorderRadius.circular(context.rp(12)),
                tooltipPadding: EdgeInsets.symmetric(
                    horizontal: context.rp(12), vertical: context.rs(8)),
                fitInsideHorizontally: true,
                fitInsideVertically:   true,
                getTooltipItems: (touchedSpots) =>
                    touchedSpots.map((s) {
                  final idx   = s.x.toInt();
                  final label = idx < labels.length ? labels[idx] : '';
                  return LineTooltipItem(
                    '${s.y.toInt()}%\n',
                    TextStyle(
                      color:      const Color(0xFF22d3ee),
                      fontWeight: FontWeight.bold,
                      fontSize:   context.sp(13),
                    ),
                    children: [
                      TextSpan(text: label,
                          style: TextStyle(
                            color:      const Color(0xFF64748b),
                            fontSize:   context.sp(10),
                            fontWeight: FontWeight.normal)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── LIVE ALERTNESS SPARKLINE ──────────────────────────────────────────────────
class _AlertnessSparkline extends StatelessWidget {
  final List<Map<String, dynamic>> snapshots;
  const _AlertnessSparkline({required this.snapshots});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < snapshots.length; i++) {
      final v = (snapshots[i]['alertness_pct'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(i.toDouble(), v.clamp(0.0, 100.0)));
    }

    if (spots.isEmpty) return const SizedBox.shrink();

    final maxX = (spots.length - 1).toDouble().clamp(1.0, double.infinity);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(
              color: Color(0xFF10b981), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('Live — current session  (${snapshots.length} snapshots)',
            style: TextStyle(
                color: const Color(0xFF10b981),
                fontSize: context.sp(11),
                fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              horizontalInterval: 20,
              getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0xFF1e293b), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 20,
                  reservedSize: context.rp(36),
                  getTitlesWidget: (value, _) {
                    final v = value.toInt();
                    if (v < 0 || v > 100 || v % 20 != 0) {
                      return const SizedBox.shrink();
                    }
                    return Text('$v',
                        style: TextStyle(
                            color: const Color(0xFF64748b),
                            fontSize: context.sp(10)));
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0, maxX: maxX,
            minY: 0, maxY: 112,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: spots.length > 2,
                curveSmoothness: 0.3,
                color: const Color(0xFF10b981),
                barWidth: 2.0,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF10b981).withValues(alpha: 0.20),
                      const Color(0xFF10b981).withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ── STAT CARD ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String   label, value, subtext;
  final bool     accent;

  const _StatCard({
    required this.icon, required this.label,
    required this.value, required this.subtext,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve:    Curves.easeInOut,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
        border: Border.all(color: const Color(0xFF1E2D45), width: 1),
      ),
      padding: EdgeInsets.all(context.rp(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              padding: EdgeInsets.all(context.rp(7)),
              decoration: BoxDecoration(
                color: const Color(0xFF22d3ee).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(context.rp(8)),
              ),
              child: Icon(icon,
                  size: context.ri(17),
                  color: const Color(0xFF22d3ee)),
            ),
            if (accent)
              Padding(
                padding: EdgeInsets.only(left: context.rp(6)),
                child: Container(
                  width:  context.ri(8),
                  height: context.ri(8),
                  decoration: BoxDecoration(
                    color:  const Color(0xFF22d3ee),
                    shape:  BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:      const Color(0xFF22d3ee).withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 2),
                    ],
                  ),
                ),
              ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              color:      const Color(0xFF64748b),
              fontSize:   context.sp(11),
              fontWeight: FontWeight.w500,
            ), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: context.rs(2)),
            Text(value, style: TextStyle(
              fontSize: context.forTier(base: 20.0, compact: 16.0, small: 18.0, large: 22.0),
              fontWeight: FontWeight.bold,
              color:      const Color(0xFFe2e8f0),
            ), overflow: TextOverflow.ellipsis),
            SizedBox(height: context.rs(1)),
            Text(subtext, style: TextStyle(
              fontSize: context.sp(10),
              color:    const Color(0xFF475569),
            ), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ],
      ),
    );
  }
}

// ── EMPTY STAT CARD ───────────────────────────────────────────────────────────
class _EmptyStatCard extends StatelessWidget {
  final IconData icon;
  final String   label;

  const _EmptyStatCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
        border: Border.all(color: const Color(0xFF1E2D45), width: 1),
      ),
      padding: EdgeInsets.all(context.rp(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: EdgeInsets.all(context.rp(7)),
            decoration: BoxDecoration(
              color:        const Color(0xFF1e293b),
              borderRadius: BorderRadius.circular(context.rp(8))),
            child: Icon(icon,
                size: context.ri(17),
                color: const Color(0xFF334155)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              color: const Color(0xFF334155),
              fontSize: context.sp(11),
              fontWeight: FontWeight.w500,
            ), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: context.rs(2)),
            Text('—', style: TextStyle(
              fontSize: context.forTier(base: 20.0, compact: 16.0, small: 18.0, large: 22.0),
              fontWeight: FontWeight.bold,
              color:      const Color(0xFF1e293b))),
            SizedBox(height: context.rs(1)),
            Text('No data', style: TextStyle(
              fontSize: context.sp(10),
              color:    const Color(0xFF1e293b))),
          ]),
        ],
      ),
    );
  }
}

// ── DASHBOARD SKELETON ────────────────────────────────────────────────────────
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      const Color(0xFF1A2235),
      highlightColor: const Color(0xFF263350),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
            horizontal: context.hPad, vertical: context.rs(10)),
        child: Column(children: [
          // Safety score card
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: context.rs(36)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(context.rp(20)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _box(context, context.rp(90), context.rs(10)),
              SizedBox(height: context.rs(20)),
              Container(
                width:  context.ri(140),
                height: context.ri(140),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
              SizedBox(height: context.rs(12)),
              _box(context, context.rp(48), context.rs(12)),
            ]),
          ),
          SizedBox(height: context.rs(24)),
          // Stats grid — 2 × 2
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount:   2,
            mainAxisSpacing:  context.rs(12),
            crossAxisSpacing: context.rp(12),
            childAspectRatio: context.forTier(
                base: 1.0, compact: 0.90, small: 0.95, large: 1.05),
            children: List.generate(
                4, (_) => _box(context, double.infinity, double.infinity)),
          ),
          SizedBox(height: context.rs(24)),
          // Chart card
          _box(context, double.infinity, context.rs(210)),
          SizedBox(height: context.rs(20)),
        ]),
      ),
    );
  }

  Widget _box(BuildContext ctx, double w, double h, {double r = 14}) =>
      Container(
        width: w, height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ctx.rp(r)),
        ),
      );
}