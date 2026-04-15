// dashboard_screen.dart — fully responsive
// All Responsive.responsiveFont/Spacing/Padding/Value/BorderRadius/IconSize
// replaced with context.sp() / context.rp() / context.rs() / context.ri()
// All const EdgeInsets / const SizedBox → responsive equivalents
// Chart hardcoded sizes → responsive
// Phones + tablets only (no desktop per project scope)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../utils/responsive.dart';

// ─── PROVIDER ─────────────────────────────────────────────────────────────────
final dashboardProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(dbChangeCounterProvider);
  return await DatabaseHelper.instance.getDashboardSummary();
});

// ─────────────────────────────────────────────────────────────────────────────
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
            loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF22d3ee))),
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
    final safetyScore   = (data['safety_score']      as double? ?? 100.0)
        .clamp(0.0, 100.0);
    final totalDriveHrs = data['total_drive_hrs']    as double? ?? 0.0;
    final alertsLast24h = data['alerts_last_24h']    as int?    ?? 0;
    final safetyStreak  = data['safety_streak_days'] as int?    ?? 0;
    final avgAlertness  = (data['avg_alertness_pct'] as double? ?? 100.0)
        .clamp(0.0, 100.0);
    final dailyScores   = (data['daily_safety_scores'] as List?)
        ?.cast<Map<String, dynamic>>() ?? [];

    final bool hasAnySessions = dailyScores.isNotEmpty;

    String scoreLabel = 'EXCELLENT';
    if (safetyScore < 60)      scoreLabel = 'POOR';
    else if (safetyScore < 75) scoreLabel = 'FAIR';
    else if (safetyScore < 90) scoreLabel = 'GOOD';

    final isMobile = Responsive.isMobile(context);

    return RefreshIndicator(
      color:           const Color(0xFF22d3ee),
      backgroundColor: const Color(0xFF0f172a),
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
            horizontal: context.hPad, vertical: context.rs(10)),
        child: Column(children: [

          // ── Safety score + stat cards ──────────────────────────────────
          LayoutBuilder(builder: (context, constraints) {
            if (isMobile || Responsive.isTablet(context)) {
              return Column(children: [
                _buildSafetyScoreCard(
                    context, safetyScore, scoreLabel, hasAnySessions),
                SizedBox(height: context.rs(24)),
                hasAnySessions
                    ? _buildQuickStatsGrid(context,
                        totalDriveHrs: totalDriveHrs,
                        alertsLast24h: alertsLast24h,
                        safetyStreak:  safetyStreak,
                        avgAlertness:  avgAlertness)
                    : _buildEmptyStatsGrid(context),
              ]);
            } else {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4,
                      child: _buildSafetyScoreCard(
                          context, safetyScore, scoreLabel, hasAnySessions)),
                  SizedBox(width: context.rp(24)),
                  Expanded(flex: 8,
                      child: hasAnySessions
                          ? _buildQuickStatsGrid(context,
                              totalDriveHrs: totalDriveHrs,
                              alertsLast24h: alertsLast24h,
                              safetyStreak:  safetyStreak,
                              avgAlertness:  avgAlertness)
                          : _buildEmptyStatsGrid(context)),
                ],
              );
            }
          }),

          SizedBox(height: context.rs(24)),
          _buildSafetyScoreHistory(context, dailyScores, hasAnySessions),
          SizedBox(height: context.rs(20)),
        ]),
      ),
    );
  }

  // ── SAFETY SCORE CARD ──────────────────────────────────────────────────────

  Widget _buildSafetyScoreCard(
    BuildContext context,
    double score,
    String label,
    bool hasAnySessions,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        // FIX: was Responsive.responsiveBorderRadius(mobile:20)
        borderRadius: BorderRadius.circular(context.rp(20)),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(6, 6), blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-6, -6), blurRadius: 16),
        ],
      ),
      child: Stack(children: [
        Positioned(top: 0, left: 0, right: 0,
          child: Container(
            // FIX: was Responsive.responsiveValue(mobile:6.0)
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
            // FIX: was Responsive.responsivePadding(mobile: isMobile ? 48 : 60)
            // compact phones need less padding so the ring doesn't get clipped
            padding: EdgeInsets.all(context.forTier(
                base: 40.0, compact: 28.0, small: 32.0, large: 44.0)),
            child: Column(
              mainAxisAlignment:  MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('SAFETY SCORE',
                    style: TextStyle(
                      color:         const Color(0xFF94a3b8),
                      // FIX: was Responsive.responsiveFont(mobile:18)
                      fontSize:      context.sp(15),
                      fontWeight:    FontWeight.w500,
                      letterSpacing: 1.5,
                    )),
                // FIX: was Responsive.responsiveSpacing(mobile:24)
                SizedBox(height: context.rs(20)),
                _buildCircularScoreIndicator(
                    context, hasAnySessions ? score : 100.0,
                    hasAnySessions ? label : '—', hasAnySessions),
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
    bool hasAnySessions,
  ) {
    // FIX: outer ring size — was (sw * 0.42).clamp(140, 220)
    // On compact 360dp phones sw*0.42 = 151px which was fine but the padding
    // around it was too large. Now use forTier for both size and padding.
    final outerSize = context.forTier<double>(
        base: 160.0, compact: 130.0, small: 140.0, large: 170.0,
        xlarge: 180.0);
    // progress ring slightly smaller than outer
    final progressSize = outerSize * 0.88;
    // inner circle (score text area)
    final innerSize    = outerSize * 0.73;

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
            // FIX: was Responsive.responsiveValue(mobile:6.0)
            strokeWidth:     context.forTier(
                base: 6.0, compact: 5.0, large: 7.0),
            backgroundColor: const Color(0xFF1e293b),
            valueColor:      AlwaysStoppedAnimation<Color>(
                hasAnySessions
                    ? const Color(0xFF22d3ee)
                    : const Color(0xFF1e293b)),
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
                // FIX: was Responsive.responsiveFont(mobile:38)
                fontSize:   context.forTier(
                    base: 34.0, compact: 26.0, small: 30.0, large: 38.0),
                fontWeight: FontWeight.bold,
                color:      hasAnySessions
                    ? const Color(0xFF22d3ee)
                    : const Color(0xFF1e293b),
              ),
            ),
            SizedBox(height: context.rs(2)),
            Text(label,
                style: TextStyle(
                  // FIX: was Responsive.responsiveFont(mobile:9)
                  fontSize:      context.sp(9),
                  color:         const Color(0xFF64748b),
                  letterSpacing: 1,
                )),
          ]),
        ),
      ]),
    );
  }

  // ── QUICK STATS GRID ───────────────────────────────────────────────────────

  Widget _buildQuickStatsGrid(
    BuildContext context, {
    required double totalDriveHrs,
    required int    alertsLast24h,
    required int    safetyStreak,
    required double avgAlertness,
  }) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap:     true,
      physics:        const NeverScrollableScrollPhysics(),
      // FIX: was Responsive.responsiveSpacing(mobile:12)
      mainAxisSpacing:  context.rs(12),
      crossAxisSpacing: context.rp(12),
      // FIX: was Responsive.responsiveValue(mobile:1.0)
      // compact phones need slightly taller cards
      childAspectRatio: context.forTier(
          base: 1.0, compact: 0.90, small: 0.95, large: 1.05),
      children: [
        _StatCard(
          icon:    Icons.access_time_outlined,
          label:   'Total Drive Time',
          value:   '${totalDriveHrs.toStringAsFixed(1)} hrs',
          subtext: 'Last 30 days',
          accent:  false,
        ),
        _StatCard(
          icon:    Icons.shield_outlined,
          label:   'Alert Triggered',
          value:   '$alertsLast24h',
          subtext: 'Last 24 hours',
          accent:  alertsLast24h > 0,
        ),
        _StatCard(
          icon:    Icons.local_fire_department_outlined,
          label:   'Safety Streak',
          value:   '$safetyStreak days',
          subtext: safetyStreak > 0 ? 'No incidents!' : 'Stay alert!',
          accent:  false,
        ),
        _StatCard(
          icon:    Icons.trending_up,
          label:   'Avg Alertness',
          value:   '${avgAlertness.toStringAsFixed(0)}%',
          subtext: 'Last 7 days',
          accent:  false,
        ),
      ],
    );
  }

  Widget _buildEmptyStatsGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap:     true,
      physics:        const NeverScrollableScrollPhysics(),
      mainAxisSpacing:  context.rs(12),
      crossAxisSpacing: context.rp(12),
      childAspectRatio: context.forTier(
          base: 1.0, compact: 0.90, small: 0.95, large: 1.05),
      children: const [
        _EmptyStatCard(icon: Icons.access_time_outlined,
            label: 'Total Drive Time'),
        _EmptyStatCard(icon: Icons.shield_outlined,
            label: 'Alert Triggered'),
        _EmptyStatCard(icon: Icons.local_fire_department_outlined,
            label: 'Safety Streak'),
        _EmptyStatCard(icon: Icons.trending_up,
            label: 'Avg Alertness'),
      ],
    );
  }

  // ── SAFETY SCORE HISTORY ───────────────────────────────────────────────────

  Widget _buildSafetyScoreHistory(
    BuildContext context,
    List<Map<String, dynamic>> dailyScores,
    bool hasAnySessions,
  ) {
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
        // FIX: was Responsive.responsiveBorderRadius(mobile:20)
        borderRadius: BorderRadius.circular(context.rp(20)),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(6, 6), blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-6, -6), blurRadius: 16),
        ],
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
              : 'Start your first session to begin tracking',
          style: TextStyle(
              color: const Color(0xFF475569), fontSize: context.sp(12)),
        ),

        SizedBox(height: context.rs(16)),

        if (!hasAnySessions)
          _buildEmptyChartState(context)
        else
          SizedBox(
            // FIX: was hardcoded 245 — now scales with screen height
            height: context.rs(context.isSmallPhone ? 210 : 240),
            child: _SafetyScoreChartInner(
                spots: spots, xLabels: xLabels),
          ),
      ]),
    );
  }

  Widget _buildEmptyChartState(BuildContext context) {
    return Container(
      // FIX: was hardcoded 200
      height: context.rs(context.isSmallPhone ? 160 : 190),
      decoration: BoxDecoration(
        color:        const Color(0xFF0D1627),
        // FIX: was hardcoded 12
        borderRadius: BorderRadius.circular(context.rp(12)),
        border: Border.all(color: const Color(0xFF1e293b), width: 1),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.show_chart_rounded,
              // FIX: was hardcoded 48
              color: const Color(0xFF1e293b), size: context.ri(44)),
          SizedBox(height: context.rs(12)),
          Text('No drive history yet',
              style: TextStyle(
                  color:      const Color(0xFF475569),
                  fontSize:   context.sp(14),
                  fontWeight: FontWeight.w600)),
          SizedBox(height: context.rs(4)),
          Text('Complete a session in Monitor to see your score',
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

  // FIX: point spacing and y-axis width now use responsive helpers
  // so charts on compact phones don't cram labels together
  static const double _chartMin = 0.0;
  // FIX: was 105.0 — when score is near 100% the dot+stroke was clipped.
  // 112.0 gives ~12 units breathing room above 100 so high scores show fully.
  static const double _chartMax = 112.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients && _sc.position.maxScrollExtent > 0) {
        // Jump to absolute end so the last date label is fully visible.
        // Using maxScrollExtent directly ensures all right padding is shown.
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
      labels = widget.xLabels;  // ← back to original, NO phantom
      maxX   = (widget.spots.length - 1).toDouble() + 0.4; 
    }

    // FIX: point spacing and y-axis width responsive
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
              // FIX: add top reserved space so the 100% dot is never clipped
              // at the top edge of the chart area
              topTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   false,
                  reservedSize: context.rs(12),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  // FIX: was hardcoded 36
                  reservedSize: context.rs(34),
                  interval:     1,
                  getTitlesWidget: (value, meta) {
                    // fl_chart calls getTitlesWidget at maxX even when it is
                    // not integer-aligned (e.g. 6.3).  value.toInt() would map
                    // that to the same index as the real last point at 6.0,
                    // drawing the label twice.  Skip any non-integer value.
                    if ((value - value.roundToDouble()).abs() > 0.01) {
                      return const SizedBox.shrink();
                    }
                    final idx = value.toInt();
                    // skip if out of real data range
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
                    // FIX: only show 0,20,40,60,80,100 
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
                // FIX: Always keep tooltip inside the chart drawing area.
                // Without these, tooltip is clipped on Samsung/Xiaomi when
                // score is near 100% (tooltip goes above the top boundary)
                // or when the last point is near the right edge.
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
        // FIX: was Responsive.responsiveBorderRadius(mobile:16)
        borderRadius: BorderRadius.circular(context.rp(16)),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(3, 3), blurRadius: 8),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-3, -3), blurRadius: 8),
        ],
      ),
      // FIX: was Responsive.responsivePadding(mobile:16)
      padding: EdgeInsets.all(context.rp(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              // FIX: was Responsive.responsivePadding(mobile:8)
              padding: EdgeInsets.all(context.rp(7)),
              decoration: BoxDecoration(
                color: const Color(0xFF22d3ee).withValues(alpha: 0.1),
                // FIX: was Responsive.responsiveBorderRadius(mobile:10)
                borderRadius: BorderRadius.circular(context.rp(9)),
              ),
              child: Icon(icon,
                  // FIX: was Responsive.responsiveIconSize(mobile:20)
                  size:  context.ri(19),
                  color: const Color(0xFF22d3ee)),
            ),
            if (accent)
              Padding(
                padding: EdgeInsets.only(left: context.rp(10)),
                child: Container(
                  // FIX: was Responsive.responsiveValue(mobile:7.0)
                  width:  context.ri(7), height: context.ri(7),
                  decoration: BoxDecoration(
                    color:  const Color(0xFF22d3ee),
                    shape:  BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color:        const Color(0xFF22d3ee)
                              .withValues(alpha: 0.4),
                          blurRadius:   8, spreadRadius: 2),
                    ],
                  ),
                ),
              ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              color:      const Color(0xFF64748b),
              // FIX: was Responsive.responsiveFont(mobile:12)
              fontSize:   context.sp(11),
              fontWeight: FontWeight.w500,
            )),
            SizedBox(height: context.rs(3)),
            Text(value, style: TextStyle(
              // FIX: was Responsive.responsiveFont(mobile:22)
              // compact phones get smaller value text to avoid overflow
              fontSize:   context.forTier(
                  base: 20.0, compact: 16.0, small: 18.0, large: 22.0),
              fontWeight: FontWeight.bold,
              color:      const Color(0xFFe2e8f0),
            ), overflow: TextOverflow.ellipsis),
            SizedBox(height: context.rs(2)),
            Text(subtext, style: TextStyle(
              // FIX: was Responsive.responsiveFont(mobile:10)
              fontSize: context.sp(10),
              color:    const Color(0xFF475569),
            )),
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
        borderRadius: BorderRadius.circular(context.rp(16)),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(3, 3), blurRadius: 8),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-3, -3), blurRadius: 8),
        ],
      ),
      padding: EdgeInsets.all(context.rp(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: EdgeInsets.all(context.rp(7)),
            decoration: BoxDecoration(
                color:        const Color(0xFF1e293b),
                // FIX: was hardcoded 10
                borderRadius: BorderRadius.circular(context.rp(9))),
            child: Icon(icon,
                size:  context.ri(19),
                color: const Color(0xFF334155)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
                color:      const Color(0xFF334155),
                fontSize:   context.sp(11),
                fontWeight: FontWeight.w500)),
            SizedBox(height: context.rs(3)),
            Text('—', style: TextStyle(
                // FIX: was Responsive.responsiveFont(mobile:22)
                fontSize:   context.forTier(
                    base: 20.0, compact: 16.0, small: 18.0, large: 22.0),
                fontWeight: FontWeight.bold,
                color:      const Color(0xFF1e293b))),
            SizedBox(height: context.rs(2)),
            Text('No data yet', style: TextStyle(
                fontSize: context.sp(10),
                color:    const Color(0xFF1e293b))),
          ]),
        ],
      ),
    );
  }
}