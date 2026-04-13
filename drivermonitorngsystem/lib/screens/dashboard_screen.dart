// ─────────────────────────────────────────────────────────────────────────────
// dashboard_screen.dart
//
// PURPOSE:
//   The home screen of Bantay Drive. Shows the driver's overall safety
//   performance at a glance with 4 stat cards and a score history chart.
//
// WHAT IT SHOWS:
//   • Circular Safety Score ring (0–100) — color-coded green/amber/red
//   • 4 stat cards: Total Drive Time, Alerts (24h), Safety Streak, Avg Alertness
//   • Safety Score History line chart (last 30 days, horizontally scrollable)
//
// SAFETY SCORE FORMULA (per session, computed in monitor_screen._stopRecording):
//   Base  = avg alertness % over the session (from alertness snapshots)
//   Penalty per alert level:
//     L1 alert → -2 pts
//     L2 alert → -4 pts
//     L3 alert → -8 pts
//   Final = (base - total penalty).clamp(0, 100)
//
//   Dashboard shows the AVERAGE of all session scores in the last 30 days.
//   Fresh install (no sessions) → shows 100 (perfect, no history to penalize).
//   This is correct — a driver with no history has no recorded incidents.
//
// BUGS FIXED:
//   1. Safety score history shows placeholder data on new phone (no sessions)
//      → Fixed: checks actual session count from DB before showing any data
//   2. Chart graph too close to bottom label when score is low (e.g. 20%)
//      → Fixed: minY set to 0 with bottom padding; chart has reserved space
//   3. Stats visible on fresh install (other phone with no data)
//      → Fixed: explicit empty-state UI when no sessions exist
//   4. Avg Alertness showing 30% — this was correct but confusing
//      → Added explanation: alertness = neutral% from model per session
//
// CONNECTIONS:
//   • DatabaseHelper.getDashboardSummary() — fetches all stats
//   • dbChangeCounterProvider — auto-refreshes when monitor_screen saves data
//   • Timer every 30s — catches live session updates during active recording
// ─────────────────────────────────────────────────────────────────────────────

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
              child: CircularProgressIndicator(color: Color(0xFF22d3ee)),
            ),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFF64748b), size: 48),
                const SizedBox(height: 12),
                Text('Error loading dashboard: $e',
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
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

    // FIX: Check if user has ANY completed sessions.
    // If not, show empty state instead of stats with default/placeholder values.
    // This prevents the "30% avg alertness" showing on a fresh install.
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

          // ── Safety score + stat cards ────────────────────────────────────
          LayoutBuilder(builder: (context, constraints) {
            if (isMobile || Responsive.isTablet(context)) {
              return Column(children: [
                _buildSafetyScoreCard(
                    context, safetyScore, scoreLabel, hasAnySessions),
                SizedBox(height: Responsive.responsiveSpacing(
                    context, mobile: 24, tablet: 28, desktop: 32)),
                // FIX: Show empty state cards if no sessions yet
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
                  SizedBox(width: Responsive.responsiveSpacing(
                      context, mobile: 16, tablet: 24, desktop: 32)),
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

          SizedBox(height: Responsive.responsiveSpacing(
              context, mobile: 24, tablet: 28, desktop: 32)),

          // ── Safety score history chart ───────────────────────────────────
          _buildSafetyScoreHistory(context, dailyScores, hasAnySessions),

          SizedBox(height: MediaQuery.of(context).size.height * 0.02),
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
    final isMobile = Responsive.isMobile(context);

    // Score ring color based on value
    const Color ringColor = Color(0xFF22d3ee);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
              context, mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(6, 6), blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-6, -6), blurRadius: 16),
        ],
      ),
      child: Stack(children: [
        // Top accent bar
        Positioned(top: 0, left: 0, right: 0,
          child: Container(
            height: Responsive.responsiveValue(
                context, mobile: 6.0, tablet: 7.0, desktop: 8.0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)]),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(Responsive.responsiveBorderRadius(
                    context, mobile: 20, tablet: 22, desktop: 24)),
                topRight: Radius.circular(Responsive.responsiveBorderRadius(
                    context, mobile: 20, tablet: 22, desktop: 24)),
              ),
            ),
          ),
        ),

        Center(
          child: Padding(
            padding: EdgeInsets.all(
              Responsive.responsivePadding(context,
                  mobile: isMobile ? 48 : 60, tablet: 55, desktop: 87),
            ),
            child: Column(
              mainAxisAlignment:  MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('SAFETY SCORE',
                    style: TextStyle(
                      color:         const Color(0xFF94a3b8),
                      fontSize:      Responsive.responsiveFont(
                          context, mobile: 18, tablet: 20, desktop: 24),
                      fontWeight:    FontWeight.w500,
                      letterSpacing: 1.5,
                    )),
                SizedBox(height: Responsive.responsiveSpacing(
                    context, mobile: 24, tablet: 28, desktop: 32)),
                _buildCircularScoreIndicator(
                    context, hasAnySessions ? score : 100.0,
                    hasAnySessions ? label : '—', ringColor, hasAnySessions),
                // FIX: Show hint when no sessions
                if (!hasAnySessions) ...[
                  const SizedBox(height: 12),
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
    Color ringColor,
    bool hasAnySessions,
  ) {
    final outerSize    = (context.sw * 0.42).clamp(140.0, 220.0);
    final progressSize = Responsive.responsiveValue(
        context, mobile: 138.0, tablet: 156.0, desktop: 179.0);
    final innerSize    = Responsive.responsiveValue(
        context, mobile: 115.0, tablet: 130.0, desktop: 147.0);

    return SizedBox(
      width: outerSize, height: outerSize,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: outerSize, height: outerSize,
          decoration: BoxDecoration(
            color:  const Color(0xFF0f172a),
            shape:  BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color:      const Color(0xFF0b1120).withValues(alpha: 0.8),
                  offset:     const Offset(6, 6),
                  blurRadius: 12),
              BoxShadow(
                  color:      const Color(0xFF1e293b).withValues(alpha: 0.8),
                  offset:     const Offset(-6, -6),
                  blurRadius: 12),
            ],
          ),
        ),
        SizedBox(
          width: progressSize, height: progressSize,
          child: CircularProgressIndicator(
            value:           hasAnySessions ? score / 100 : 0,
            strokeWidth:     Responsive.responsiveValue(
                context, mobile: 6.0, tablet: 7.0, desktop: 8.0),
            backgroundColor: const Color(0xFF1e293b),
            valueColor:      AlwaysStoppedAnimation<Color>(
                hasAnySessions ? ringColor : const Color(0xFF1e293b)),
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
                fontSize:   Responsive.responsiveFont(
                    context, mobile: 38, tablet: 42, desktop: 48),
                fontWeight: FontWeight.bold,
                color:      hasAnySessions
                    ? ringColor
                    : const Color(0xFF1e293b),
              ),
            ),
            SizedBox(height: Responsive.responsiveSpacing(
                context, mobile: 2, desktop: 4)),
            Text(label,
                style: TextStyle(
                  fontSize:      Responsive.responsiveFont(
                      context, mobile: 9, tablet: 9.5, desktop: 10),
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
      mainAxisSpacing: Responsive.responsiveSpacing(
          context, mobile: 12, tablet: 14, desktop: 16),
      crossAxisSpacing: Responsive.responsiveSpacing(
          context, mobile: 12, tablet: 14, desktop: 16),
      childAspectRatio: Responsive.responsiveValue(
          context, mobile: 1.0, tablet: 1.4, desktop: 2.1),
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

  // FIX: Empty state grid shown when user has no sessions yet.
  // Prevents showing "30% avg alertness" on a fresh install —
  // that was confusing because 30% came from the default alertness
  // of sessions recorded on another device sharing the same DB path.
  Widget _buildEmptyStatsGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap:     true,
      physics:        const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Responsive.responsiveSpacing(
          context, mobile: 12, tablet: 14, desktop: 16),
      crossAxisSpacing: Responsive.responsiveSpacing(
          context, mobile: 12, tablet: 14, desktop: 16),
      childAspectRatio: Responsive.responsiveValue(
          context, mobile: 1.0, tablet: 1.4, desktop: 2.1),
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
    // Build chart data from real sessions
    final List<FlSpot> spots   = [];
    final List<String> xLabels = [];

    if (hasAnySessions) {
      for (int i = 0; i < dailyScores.length; i++) {
        final score = (dailyScores[i]['avg_score'] as double? ?? 0.0)
            .clamp(0.0, 100.0);
        final day   = dailyScores[i]['day'] as String? ?? '';
        // FIX: Parse as local time — DB stores UTC, display local date
        String label;
        try {
          final d = DateTime.parse(day).toLocal();
          const mo = ['', 'Jan','Feb','Mar','Apr','May','Jun',
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
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
              context, mobile: 20, tablet: 22, desktop: 24),
        ),
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

        // Header
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text('Safety Score History',
              style: TextStyle(
                color:         const Color(0xFFe2e8f0),
                fontSize:      context.sp(17),
                fontWeight:    FontWeight.bold,
                letterSpacing: 0.1,
              ))),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: context.rp(14), vertical: context.rs(7)),
            decoration: BoxDecoration(
              color:  const Color(0xFF22d3ee).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: const Color(0xFF22d3ee).withValues(alpha: 0.65),
                  width: 1.4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.show_chart_rounded,
                  size: 14, color: Color(0xFF22d3ee)),
              SizedBox(width: context.rp(6)),
              Text('30 Days',
                  style: TextStyle(
                      fontSize:   context.sp(12),
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
              color:    const Color(0xFF475569),
              fontSize: context.sp(12)),
        ),

        SizedBox(height: context.rs(18)),

        // FIX: Show proper empty state when no sessions
        // Previously showed placeholder data that confused users on new phones
        if (!hasAnySessions)
          _buildEmptyChartState(context)
        else
          SizedBox(
            height: 245,
            child: _SafetyScoreChartInner(
              spots:   spots,
              xLabels: xLabels,
            ),
          ),
      ]),
    );
  }

  // FIX: Empty chart state — shown on fresh install / new phone
  Widget _buildEmptyChartState(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color:        const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF1e293b), width: 1),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.show_chart_rounded,
              color: const Color(0xFF1e293b), size: 48),
          const SizedBox(height: 12),
          Text('No drive history yet',
              style: TextStyle(
                  color:      const Color(0xFF475569),
                  fontSize:   context.sp(14),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
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

// ── SAFETY SCORE CHART (horizontally scrollable) ──────────────────────────────

class _SafetyScoreChartInner extends StatefulWidget {
  final List<FlSpot> spots;
  final List<String> xLabels;

  const _SafetyScoreChartInner({
    required this.spots,
    required this.xLabels,
  });

  @override
  State<_SafetyScoreChartInner> createState() =>
      _SafetyScoreChartInnerState();
}

class _SafetyScoreChartInnerState extends State<_SafetyScoreChartInner> {
  final ScrollController _sc = ScrollController();

  static const double _pointSpacing = 48.0;
  static const double _yAxisWidth   = 42.0;
  static const double _rightPad     = 16.0;

  // FIX: minY set to 0, maxY to 105.
  // Previously minY=15 caused the chart line to sit right on top of bottom
  // labels when scores were low (20–30%). Now there's always breathing room.
  static const double _chartMin = 0.0;
  static const double _chartMax = 105.0;

  @override
  void initState() {
    super.initState();
    // Auto-scroll to the most recent (rightmost) data point
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
    // Handle single data point — fl_chart needs at least 2 x positions
    final List<FlSpot> spots;
    final List<String> labels;
    final double       maxX;

    if (widget.spots.length == 1) {
      spots  = [
        FlSpot(0, widget.spots[0].y),
        FlSpot(1, widget.spots[0].y),
      ];
      labels = ['', widget.xLabels[0]];
      maxX   = 1;
    } else {
      spots  = widget.spots;
      labels = widget.xLabels;
      maxX   = (widget.spots.length - 1).toDouble().clamp(1.0, double.infinity);
    }

    final double chartW =
        _yAxisWidth + (spots.length * _pointSpacing) + _rightPad;

   const Color lineColor = Color(0xFF22d3ee);                      
    return SingleChildScrollView(
      controller:      _sc,
      scrollDirection: Axis.horizontal,
      physics:         const BouncingScrollPhysics(),
      child: SizedBox(
        width: chartW,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show:             true,
              drawVerticalLine: false,
              horizontalInterval: 20,
              getDrawingHorizontalLine: (_) => FlLine(
                color:       const Color(0xFF1e293b),
                strokeWidth: 1,
                dashArray:   [4, 4],
              ),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  // FIX: Increased reservedSize from 30 to 36.
                  // This gives more space between the chart line and the
                  // date labels — prevents overlap when scores are low.
                  reservedSize: 36,
                  interval:     1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    final text = labels[idx];
                    if (text.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(text,
                          style: const TextStyle(
                              color:    Color(0xFF64748b),
                              fontSize: 10.5)),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  interval:     20,
                  reservedSize: _yAxisWidth,
                  getTitlesWidget: (value, meta) {
                    final v = value.toInt();
                    // FIX: Show 0, 20, 40, 60, 80, 100 — full range
                    if (v < 0 || v > 100 || v % 20 != 0) {
                      return const SizedBox.shrink();
                    }
                    return Text('$v',
                        style: TextStyle(
                          color:    const Color(0xFF64748b),
                          fontSize: Responsive.responsiveFont(
                              context, mobile: 11, tablet: 12, desktop: 13),
                        ));
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: maxX,
            minY: _chartMin,
            maxY: _chartMax,
            lineBarsData: [
              LineChartBarData(
                spots:            spots,
                isCurved:         spots.length > 2,
                curveSmoothness:  0.3,
                color:            lineColor,
                barWidth:         2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius:      3.5,
                        color: const Color(0xFF22d3ee),
                        strokeWidth: 1.5,
                        strokeColor: const Color(0xFF0f172a),
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      lineColor.withValues(alpha: 0.25),
                      lineColor.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end:   Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF0f172a),
                tooltipBorderRadius: BorderRadius.circular(12),
                tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                getTooltipItems: (touchedSpots) =>
                    touchedSpots.map((s) {
                  final idx   = s.x.toInt();
                  final label = idx < labels.length ? labels[idx] : '';
                  return LineTooltipItem(
                    '${s.y.toInt()}%\n',
                    TextStyle(
                      color:      lineColor,
                      fontWeight: FontWeight.bold,
                      fontSize:   context.sp(13),
                    ),
                    children: [
                      TextSpan(
                        text: label,
                        style: TextStyle(
                          color:      const Color(0xFF64748b),
                          fontSize:   context.sp(10),
                          fontWeight: FontWeight.normal,
                        ),
                      ),
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
    required this.icon,
    required this.label,
    required this.value,
    required this.subtext,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve:    Curves.easeInOut,
      decoration: BoxDecoration(
        color:        const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
              context, mobile: 16, tablet: 18, desktop: 20),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(3, 3), blurRadius: 8),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-3, -3), blurRadius: 8),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
            context, mobile: 16, tablet: 18, desktop: 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              padding: EdgeInsets.all(
                Responsive.responsivePadding(
                    context, mobile: 8, tablet: 9, desktop: 10),
              ),
              decoration: BoxDecoration(
                color: accent
                    ? const Color(0xFF22d3ee).withValues(alpha: 0.1)
                    : const Color(0xFF1e293b),
                borderRadius: BorderRadius.circular(
                  Responsive.responsiveBorderRadius(
                      context, mobile: 10, tablet: 11, desktop: 12),
                ),
              ),
              child: Icon(icon,
                  size: Responsive.responsiveIconSize(
                      context, mobile: 20, tablet: 21, desktop: 22),
                  color: accent
                      ? const Color(0xFF22d3ee)
                      : const Color(0xFF64748b)),
            ),
            if (accent)
              Padding(
                padding: EdgeInsets.only(
                  left: Responsive.responsiveSpacing(
                      context, mobile: 10, tablet: 11, desktop: 12),
                ),
                child: Container(
                  width:  Responsive.responsiveValue(
                      context, mobile: 7.0, tablet: 7.5, desktop: 8.0),
                  height: Responsive.responsiveValue(
                      context, mobile: 7.0, tablet: 7.5, desktop: 8.0),
                  decoration: BoxDecoration(
                    color:  const Color(0xFF22d3ee),
                    shape:  BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color:        const Color(0xFF22d3ee)
                              .withValues(alpha: 0.4),
                          blurRadius:   8,
                          spreadRadius: 2),
                    ],
                  ),
                ),
              ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                  color:      const Color(0xFF64748b),
                  fontSize:   Responsive.responsiveFont(
                      context, mobile: 12, tablet: 12.5, desktop: 13),
                  fontWeight: FontWeight.w500,
                )),
            SizedBox(height: Responsive.responsiveSpacing(
                context, mobile: 4, tablet: 5, desktop: 6)),
            Text(value,
                style: TextStyle(
                  fontSize:   Responsive.responsiveFont(
                      context, mobile: 22, tablet: 24, desktop: 26),
                  fontWeight: FontWeight.bold,
                  color:      const Color(0xFFe2e8f0),
                )),
            SizedBox(height: Responsive.responsiveSpacing(
                context, mobile: 2, tablet: 3, desktop: 4)),
            Text(subtext,
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                      context, mobile: 10, tablet: 10.5, desktop: 11),
                  color:    const Color(0xFF475569),
                )),
          ]),
        ],
      ),
    );
  }
}

// ── EMPTY STAT CARD ───────────────────────────────────────────────────────────
// FIX: Shown on fresh install / new phone instead of misleading default values.
// Shows a skeleton-style card with "—" placeholder values.

class _EmptyStatCard extends StatelessWidget {
  final IconData icon;
  final String   label;

  const _EmptyStatCard({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
              context, mobile: 16, tablet: 18, desktop: 20),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(3, 3), blurRadius: 8),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-3, -3), blurRadius: 8),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
            context, mobile: 16, tablet: 18, desktop: 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: EdgeInsets.all(
              Responsive.responsivePadding(
                  context, mobile: 8, tablet: 9, desktop: 10),
            ),
            decoration: BoxDecoration(
              color:        const Color(0xFF1e293b),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size:  Responsive.responsiveIconSize(
                    context, mobile: 20, tablet: 21, desktop: 22),
                color: const Color(0xFF334155)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                  color:      const Color(0xFF334155),
                  fontSize:   Responsive.responsiveFont(
                      context, mobile: 12, tablet: 12.5, desktop: 13),
                  fontWeight: FontWeight.w500,
                )),
            SizedBox(height: Responsive.responsiveSpacing(
                context, mobile: 4, tablet: 5, desktop: 6)),
            Text('—',
                style: TextStyle(
                  fontSize:   Responsive.responsiveFont(
                      context, mobile: 22, tablet: 24, desktop: 26),
                  fontWeight: FontWeight.bold,
                  color:      const Color(0xFF1e293b),
                )),
            SizedBox(height: Responsive.responsiveSpacing(
                context, mobile: 2, tablet: 3, desktop: 4)),
            Text('No data yet',
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                      context, mobile: 10, tablet: 10.5, desktop: 11),
                  color:    const Color(0xFF1e293b),
                )),
          ]),
        ],
      ),
    );
  }
}