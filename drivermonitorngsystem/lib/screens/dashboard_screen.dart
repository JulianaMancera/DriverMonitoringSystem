import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../utils/responsive.dart';

// RIVERPOD PROVIDER
// Watches dbChangeCounterProvider — auto re-fetches whenever
// monitor_screen increments the counter (on session start/stop/alert)
final dashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.watch(dbChangeCounterProvider); // ← this is all that's needed
  return await DatabaseHelper.instance.getDashboardSummary();
});

// DASHBOARD SCREEN
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
    // Periodic refresh every 30 seconds as a fallback
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
      child: Column(
        children: [
          Expanded(
            child: dashAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF22d3ee)),
              ),
              error: (e, _) => const Center(
                child: Text('Error loading data',
                    style: TextStyle(color: Colors.white54)),
              ),
              data: (data) => _buildContent(context, data),
            ),
          ),
        ],
      ),
    );
  }

  // MAIN SCROLLABLE CONTENT
  Widget _buildContent(BuildContext context, Map<String, dynamic> data) {
    final safetyScore   = data['safety_score']        as double? ?? 0.0;
    final totalDriveHrs = data['total_drive_hrs']      as double? ?? 0.0;
    final alertsLast24h = data['alerts_last_24h']      as int?    ?? 0;
    final safetyStreak  = data['safety_streak_days']   as int?    ?? 0;
    final avgAlertness  = data['avg_alertness_pct']    as double? ?? 0.0;
    final snapshots     = (data['alertness_snapshots'] as List<Map<String, dynamic>>?) ?? [];

    String scoreLabel = 'EXCELLENT';
    if (safetyScore < 60) {
      scoreLabel = 'POOR';
    } else if (safetyScore < 75)  scoreLabel = 'FAIR';
    else if (safetyScore < 90)  scoreLabel = 'GOOD';

    final isMobile = Responsive.isMobile(context);

    return RefreshIndicator(
      color: const Color(0xFF22d3ee),
      backgroundColor: const Color(0xFF0f172a),
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          Responsive.responsivePadding(context, mobile: 16, tablet: 24, desktop: 32),
        ),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (isMobile || Responsive.isTablet(context)) {
                  return Column(
                    children: [
                      _buildSafetyScoreCard(context, safetyScore, scoreLabel),
                      SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),
                      _buildQuickStatsGrid(context,
                        totalDriveHrs: totalDriveHrs,
                        alertsLast24h: alertsLast24h,
                        safetyStreak: safetyStreak,
                        avgAlertness: avgAlertness,
                      ),
                    ],
                  );
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: _buildSafetyScoreCard(context, safetyScore, scoreLabel)),
                      SizedBox(width: Responsive.responsiveSpacing(context, mobile: 16, tablet: 24, desktop: 32)),
                      Expanded(flex: 8, child: _buildQuickStatsGrid(context,
                        totalDriveHrs: totalDriveHrs,
                        alertsLast24h: alertsLast24h,
                        safetyStreak: safetyStreak,
                        avgAlertness: avgAlertness,
                      )),
                    ],
                  );
                }
              },
            ),

            SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),

            _buildAlertnessChart(context, snapshots),

            SizedBox(height: isMobile ? 16 : 32),
          ],
        ),
      ),
    );
  }

  // SAFETY SCORE CARD
  Widget _buildSafetyScoreCard(BuildContext context, double score, String label) {
    final isMobile = Responsive.isMobile(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(6, 6), blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b), offset: Offset(-6, -6), blurRadius: 16),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: Responsive.responsiveValue(context, mobile: 6.0, tablet: 7.0, desktop: 8.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)]),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24)),
                  topRight: Radius.circular(Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24)),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.all(
                Responsive.responsivePadding(context, mobile: isMobile ? 48 : 60, tablet: 55, desktop: 87),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'SAFETY SCORE',
                    style: TextStyle(
                      color: const Color(0xFF94a3b8),
                      fontSize: Responsive.responsiveFont(context, mobile: 18, tablet: 20, desktop: 24),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),
                  _buildCircularScoreIndicator(context, score, label),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // CIRCULAR SCORE INDICATOR
  Widget _buildCircularScoreIndicator(BuildContext context, double score, String label) {
    final outerSize    = Responsive.responsiveValue(context, mobile: 150.0, tablet: 170.0, desktop: 195.0);
    final progressSize = Responsive.responsiveValue(context, mobile: 138.0, tablet: 156.0, desktop: 179.0);
    final innerSize    = Responsive.responsiveValue(context, mobile: 115.0, tablet: 130.0, desktop: 147.0);

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: outerSize, height: outerSize,
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: const Color(0xFF0b1120).withValues(alpha: 0.8), offset: const Offset(6, 6),   blurRadius: 12),
                BoxShadow(color: const Color(0xFF1e293b).withValues(alpha: 0.8), offset: const Offset(-6, -6), blurRadius: 12),
              ],
            ),
          ),
          SizedBox(
            width: progressSize, height: progressSize,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: Responsive.responsiveValue(context, mobile: 6.0, tablet: 7.0, desktop: 8.0),
              backgroundColor: const Color(0xFF1e293b),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22d3ee)),
              strokeCap: StrokeCap.round,
            ),
          ),
          Container(
            width: innerSize, height: innerSize,
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Color(0xFF0b1120), offset: Offset(6, 6),   blurRadius: 12),
                BoxShadow(color: Color(0xFF1e293b), offset: Offset(-6, -6), blurRadius: 12),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  score.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(context, mobile: 38, tablet: 42, desktop: 48),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF22d3ee),
                  ),
                ),
                SizedBox(height: Responsive.responsiveSpacing(context, mobile: 2, desktop: 4)),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(context, mobile: 9, tablet: 9.5, desktop: 10),
                    color: const Color(0xFF64748b),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // QUICK STATS GRID
  Widget _buildQuickStatsGrid(
    BuildContext context, {
    required double totalDriveHrs,
    required int    alertsLast24h,
    required int    safetyStreak,
    required double avgAlertness,
  }) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing:  Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
      crossAxisSpacing: Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
      childAspectRatio: Responsive.responsiveValue(context, mobile: 1.0, tablet: 1.4, desktop: 2.1),
      children: [
        _StatCard(icon: Icons.access_time_outlined,          label: 'Total Drive Time', value: '${totalDriveHrs.toStringAsFixed(1)} hrs', subtext: 'Last 30 days',                                    accent: false),
        _StatCard(icon: Icons.shield_outlined,                label: 'Alert Triggered',  value: '$alertsLast24h',                           subtext: 'Last 24 hours',                                   accent: true),
        _StatCard(icon: Icons.local_fire_department_outlined, label: 'Safety Streak',    value: '$safetyStreak days',                        subtext: safetyStreak > 0 ? 'No incidents' : 'Stay alert!', accent: false),
        _StatCard(icon: Icons.trending_up,                    label: 'Avg Alertness',    value: '${avgAlertness.toStringAsFixed(0)}%',        subtext: 'Last 7 days',                                     accent: false),
      ],
    );
  }

  // ALERTNESS CHART
  Widget _buildAlertnessChart(BuildContext context, List<Map<String, dynamic>> snapshots) {
    late final List<FlSpot>  spots;
    late final List<String>  timeLabels;

    if (snapshots.isEmpty) {
      spots      = const [FlSpot(0,95), FlSpot(1,92), FlSpot(2,88), FlSpot(3,94), FlSpot(4,85), FlSpot(5,78), FlSpot(6,82)];
      timeLabels = const ['10:00', '10:10', '10:20', '10:30', '10:40', '10:50', '11:00'];
    } else {
      spots = []; timeLabels = [];
      for (int i = 0; i < snapshots.length; i++) {
        spots.add(FlSpot(i.toDouble(), snapshots[i]['alertness_pct'] as double? ?? 0.0));
        timeLabels.add(snapshots[i]['time_label'] as String? ?? '$i');
      }
    }

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(6, 6),   blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b), offset: Offset(-6, -6), blurRadius: 16),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context, mobile: 16, tablet: 20, desktop: 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alertness History',
            style: TextStyle(
              color: const Color(0xFFcbd5e1),
              fontSize: Responsive.responsiveFont(context, mobile: 15, tablet: 15.5, desktop: 16),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: Responsive.responsiveSpacing(context, mobile: 16, tablet: 20, desktop: 24)),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: const Color(0xFF1e293b),
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < timeLabels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(timeLabels[idx],
                              style: TextStyle(
                                color: const Color(0xFF64748b),
                                fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12),
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 10,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          color: const Color(0xFF64748b),
                          fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (spots.length - 1).toDouble(),
                minY: 50,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF22d3ee),
                    barWidth: Responsive.responsiveValue(context, mobile: 2.5, tablet: 2.75, desktop: 3.0),
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF22d3ee).withValues(alpha: 0.3),
                          const Color(0xFF22d3ee).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF0f172a),
                    tooltipBorderRadius: BorderRadius.circular(12),
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                      s.y.toInt().toString(),
                      const TextStyle(color: Color(0xFF22d3ee), fontWeight: FontWeight.bold),
                    )).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// REUSABLE STAT CARD
class _StatCard extends StatefulWidget {
  final IconData icon;
  final String label, value, subtext;
  final bool accent;

  const _StatCard({
    required this.icon, required this.label,
    required this.value, required this.subtext, required this.accent,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit:  (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: const Color(0xFF0f172a),
            borderRadius: BorderRadius.circular(
              Responsive.responsiveBorderRadius(context, mobile: 16, tablet: 18, desktop: 20),
            ),
            boxShadow: isHovered
                ? const [
                    BoxShadow(color: Color(0xFF0b1120), offset: Offset(-3, -3), blurRadius: 6, spreadRadius: 0),
                    BoxShadow(color: Color(0xFF1e293b), offset: Offset(3, 3),   blurRadius: 6, spreadRadius: 0),
                  ]
                : const [
                    BoxShadow(color: Color(0xFF0b1120), offset: Offset(3, 3),   blurRadius: 8, spreadRadius: 0),
                    BoxShadow(color: Color(0xFF1e293b), offset: Offset(-3, -3), blurRadius: 8, spreadRadius: 0),
                  ],
          ),
          padding: EdgeInsets.all(
            Responsive.responsivePadding(context, mobile: 16, tablet: 18, desktop: 20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(
                      Responsive.responsivePadding(context, mobile: 8, tablet: 9, desktop: 10),
                    ),
                    decoration: BoxDecoration(
                      color: widget.accent
                          ? const Color(0xFF22d3ee).withValues(alpha: 0.1)
                          : const Color(0xFF1e293b),
                      borderRadius: BorderRadius.circular(
                        Responsive.responsiveBorderRadius(context, mobile: 10, tablet: 11, desktop: 12),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size:  Responsive.responsiveIconSize(context, mobile: 20, tablet: 21, desktop: 22),
                      color: widget.accent ? const Color(0xFF22d3ee) : const Color(0xFF64748b),
                    ),
                  ),
                  if (widget.accent)
                    Padding(
                      padding: EdgeInsets.only(
                        left: Responsive.responsiveSpacing(context, mobile: 10, tablet: 11, desktop: 12),
                      ),
                      child: Container(
                        width:  Responsive.responsiveValue(context, mobile: 7.0, tablet: 7.5, desktop: 8.0),
                        height: Responsive.responsiveValue(context, mobile: 7.0, tablet: 7.5, desktop: 8.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22d3ee),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF22d3ee).withValues(alpha: 0.4),
                              blurRadius: 8, spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                    style: TextStyle(
                      color: const Color(0xFF64748b),
                      fontSize: Responsive.responsiveFont(context, mobile: 12, tablet: 12.5, desktop: 13),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: Responsive.responsiveSpacing(context, mobile: 4, tablet: 5, desktop: 6)),
                  Text(widget.value,
                    style: TextStyle(
                      fontSize:   Responsive.responsiveFont(context, mobile: 22, tablet: 24, desktop: 26),
                      fontWeight: FontWeight.bold,
                      color:      const Color(0xFFe2e8f0),
                    ),
                  ),
                  SizedBox(height: Responsive.responsiveSpacing(context, mobile: 2, tablet: 3, desktop: 4)),
                  Text(widget.subtext,
                    style: TextStyle(
                      fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 10.5, desktop: 11),
                      color:    const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}