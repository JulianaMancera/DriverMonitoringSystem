import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../utils/responsive.dart';

// RIVERPOD PROVIDER
final dashboardProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(dbChangeCounterProvider);
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

  Widget _buildContent(BuildContext context, Map<String, dynamic> data) {
    final safetyScore   = data['safety_score']        as double? ?? 0.0;
    final totalDriveHrs = data['total_drive_hrs']      as double? ?? 0.0;
    final alertsLast24h = data['alerts_last_24h']      as int?    ?? 0;
    final safetyStreak  = data['safety_streak_days']   as int?    ?? 0;
    final avgAlertness  = data['avg_alertness_pct']    as double? ?? 0.0;
    final dailyScores   = (data['daily_safety_scores'] as List<Map<String, dynamic>>?) ?? [];

    String scoreLabel = 'EXCELLENT';
    if (safetyScore < 60)      scoreLabel = 'POOR';
    else if (safetyScore < 75) scoreLabel = 'FAIR';
    else if (safetyScore < 90) scoreLabel = 'GOOD';

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
                        safetyStreak:  safetyStreak,
                        avgAlertness:  avgAlertness,
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
                        safetyStreak:  safetyStreak,
                        avgAlertness:  avgAlertness,
                      )),
                    ],
                  );
                }
              },
            ),
            SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),
            _buildAlertnessHistory(context, dailyScores),
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
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(6, 6),   blurRadius: 16),
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
                  topLeft:  Radius.circular(Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24)),
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

  Widget _buildCircularScoreIndicator(BuildContext context, double score, String label) {
    final outerSize    = Responsive.responsiveValue(context, mobile: 150.0, tablet: 170.0, desktop: 195.0);
    final progressSize = Responsive.responsiveValue(context, mobile: 138.0, tablet: 156.0, desktop: 179.0);
    final innerSize    = Responsive.responsiveValue(context, mobile: 115.0, tablet: 130.0, desktop: 147.0);

    return SizedBox(
      width: outerSize, height: outerSize,
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
            decoration: const BoxDecoration(
              color: Color(0xFF0f172a),
              shape: BoxShape.circle,
              boxShadow: [
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

  // ── ALERTNESS HISTORY ──────────────────────────────────────────────────────
  Widget _buildAlertnessHistory(
    BuildContext context,
    List<Map<String, dynamic>> dailyScores,
  ) {
    final bool hasData = dailyScores.length >= 2;

    final List<FlSpot> spots;
    final List<String> xLabels;
    final bool         isPlaceholder;

    if (hasData) {
      spots   = [];
      xLabels = [];
      for (int i = 0; i < dailyScores.length; i++) {
        final score = (dailyScores[i]['avg_score'] as double? ?? 0.0).clamp(0.0, 100.0);
        final day   = dailyScores[i]['day'] as String? ?? '';
        final parts = day.split('-');
        const mo = ['','Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
        final label = parts.length == 3
            ? '${mo[int.tryParse(parts[1]) ?? 0]} ${int.tryParse(parts[2]) ?? 0}'
            : day;
        spots.add(FlSpot(i.toDouble(), score));
        xLabels.add(label);
      }
      isPlaceholder = false;
    } else {
      // Placeholder — mirrors screenshot shape
      spots = const [
        FlSpot(0,  95), FlSpot(1,  96), FlSpot(2,  95), FlSpot(3,  96),
        FlSpot(4,  95), FlSpot(5,  96), FlSpot(6,  95), FlSpot(7,  96),
        FlSpot(8,  95), FlSpot(9,  97), FlSpot(10, 67), FlSpot(11, 48),
        FlSpot(12, 57), FlSpot(13, 42), FlSpot(14, 53), FlSpot(15, 49),
        FlSpot(16, 55),
      ];
      xLabels = const [
        'Mar 14','','','','','','Mar 20','','','Mar 27','','Apr 2','','','','','Apr 6',
      ];
      isPlaceholder = true;
    }

    final Color lineColor = isPlaceholder
        ? const Color(0xFF22d3ee).withOpacity(0.5)
        : const Color(0xFF22d3ee);

    return Container(
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ──────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Safety Score History',
                  style: TextStyle(
                    color:      Color(0xFFe2e8f0),
                    fontSize:   19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              // Session pill — teal border + teal text, NOT tappable (placeholder)
              IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22d3ee).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF22d3ee).withOpacity(0.65),
                      width: 1.4,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.show_chart_rounded, size: 14, color: Color(0xFF22d3ee)),
                      SizedBox(width: 6),
                      Text(
                        'Session',
                        style: TextStyle(
                          fontSize:   12,
                          fontWeight: FontWeight.w600,
                          color:      Color(0xFF22d3ee),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          // ── Subtitle ────────────────────────────────────────────────────
          Text(
            isPlaceholder
                ? 'Start a session to see your history'
                : 'Avg safety score per drive day · swipe to explore',
            style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
          ),

          const SizedBox(height: 18),

          // ── Horizontally scrollable chart ────────────────────────────────
          SizedBox(
            height: 245,
            child: _AlertnessChartInner(
              spots:         spots,
              xLabels:       xLabels,
              isPlaceholder: isPlaceholder,
              lineColor:     lineColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Horizontally-scrollable chart ─────────────────────────────────────────────
// Each day gets a fixed pixel slot so labels never crowd, and the user can
// swipe left/right to explore all 30 days. Auto-scrolls to the latest date.
// Y-axis is fixed: minY = 15, maxY = 105  →  labels 20, 30 … 90, 100 visible.
class _AlertnessChartInner extends StatefulWidget {
  final List<FlSpot>  spots;
  final List<String>  xLabels;
  final bool          isPlaceholder;
  final Color         lineColor;

  const _AlertnessChartInner({
    required this.spots,
    required this.xLabels,
    required this.isPlaceholder,
    required this.lineColor,
  });

  @override
  State<_AlertnessChartInner> createState() => _AlertnessChartInnerState();
}

class _AlertnessChartInnerState extends State<_AlertnessChartInner> {
  final ScrollController _sc = ScrollController();

  // Pixels per day point — wide enough so "Mar 14" labels never touch
  static const double _pointSpacing = 42.0;
  static const double _yAxisWidth   = 38.0;
  static const double _rightPad     = 16.0;

  // Fixed Y bounds so 20 and 100 always appear as axis labels
  static const double _chartMin = 15.0;   // just below 20 so the label fits
  static const double _chartMax = 105.0;  // just above 100 so the label fits

  @override
  void initState() {
    super.initState();
    // Auto-scroll to the most-recent (rightmost) day after first layout
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
    final double chartW =
        _yAxisWidth + (widget.spots.length * _pointSpacing) + _rightPad;
    final double maxX =
        (widget.spots.length - 1).toDouble().clamp(1.0, double.infinity);

    return SingleChildScrollView(
      controller:      _sc,
      scrollDirection: Axis.horizontal,
      physics:         const BouncingScrollPhysics(),
      child: SizedBox(
        width: chartW,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 10,
              getDrawingHorizontalLine: (_) => FlLine(
                color:       const Color(0xFF1e293b),
                strokeWidth: 1,
                dashArray:   [4, 4],
              ),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),

              // X-axis — every label stored in xLabels; blanks are skipped
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  reservedSize: 30,
                  interval:     1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= widget.xLabels.length) {
                      return const SizedBox.shrink();
                    }
                    final text = widget.xLabels[idx];
                    if (text.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        text,
                        style: const TextStyle(
                          color:    Color(0xFF64748b),
                          fontSize: 10.5,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Y-axis — 10-unit ticks; 20 and 100 are intentionally included
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles:   true,
                  interval:     10,
                  reservedSize: _yAxisWidth,
                  getTitlesWidget: (value, meta) {
                    // Only render the values we actually want: 20 → 100
                    final v = value.toInt();
                    if (v < 20 || v > 100) return const SizedBox.shrink();
                    return Text(
                      '$v',
                      style: const TextStyle(
                        color:    Color(0xFF64748b),
                        fontSize: 11,
                      ),
                    );
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
                spots:            widget.spots,
                isCurved:         true,
                curveSmoothness:  0.3,
                color:            widget.lineColor,
                barWidth:         2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius:      3.2,
                        color:       widget.lineColor,
                        strokeWidth: 1.5,
                        strokeColor: const Color(0xFF0f172a),
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      widget.lineColor.withOpacity(widget.isPlaceholder ? 0.20 : 0.30),
                      widget.lineColor.withOpacity(0.0),
                    ],
                    begin: Alignment.topCenter,
                    end:   Alignment.bottomCenter,
                  ),
                ),
              ),
            ],

            lineTouchData: widget.isPlaceholder
                ? const LineTouchData(enabled: false)
                : LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF0f172a),
                      tooltipBorderRadius: BorderRadius.circular(12),
                      tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      getTooltipItems: (touchedSpots) =>
                          touchedSpots.map((s) {
                        final label = s.x.toInt() < widget.xLabels.length
                            ? widget.xLabels[s.x.toInt()]
                            : '';
                        return LineTooltipItem(
                          '${s.y.toInt()}%\n',
                          const TextStyle(
                            color:      Color(0xFF22d3ee),
                            fontWeight: FontWeight.bold,
                            fontSize:   13,
                          ),
                          children: [
                            TextSpan(
                              text: label,
                              style: const TextStyle(
                                color:      Color(0xFF64748b),
                                fontSize:   10,
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

// REUSABLE STAT CARD
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String   label, value, subtext;
  final bool     accent;

  const _StatCard({
    required this.icon,   required this.label,
    required this.value,  required this.subtext,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context, mobile: 16, tablet: 18, desktop: 20),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(3, 3),   blurRadius: 8),
          BoxShadow(color: Color(0xFF1e293b), offset: Offset(-3, -3), blurRadius: 8),
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
            children: [
              Container(
                padding: EdgeInsets.all(
                  Responsive.responsivePadding(context, mobile: 8, tablet: 9, desktop: 10),
                ),
                decoration: BoxDecoration(
                  color: accent
                      ? const Color(0xFF22d3ee).withValues(alpha: 0.1)
                      : const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(
                    Responsive.responsiveBorderRadius(context, mobile: 10, tablet: 11, desktop: 12),
                  ),
                ),
                child: Icon(
                  icon,
                  size:  Responsive.responsiveIconSize(context, mobile: 20, tablet: 21, desktop: 22),
                  color: accent ? const Color(0xFF22d3ee) : const Color(0xFF64748b),
                ),
              ),
              if (accent)
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
                          color:       const Color(0xFF22d3ee).withValues(alpha: 0.4),
                          blurRadius:  8,
                          spreadRadius: 2,
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
              Text(label,
                style: TextStyle(
                  color:      const Color(0xFF64748b),
                  fontSize:   Responsive.responsiveFont(context, mobile: 12, tablet: 12.5, desktop: 13),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: Responsive.responsiveSpacing(context, mobile: 4, tablet: 5, desktop: 6)),
              Text(value,
                style: TextStyle(
                  fontSize:   Responsive.responsiveFont(context, mobile: 22, tablet: 24, desktop: 26),
                  fontWeight: FontWeight.bold,
                  color:      const Color(0xFFe2e8f0),
                ),
              ),
              SizedBox(height: Responsive.responsiveSpacing(context, mobile: 2, tablet: 3, desktop: 4)),
              Text(subtext,
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 10.5, desktop: 11),
                  color:    const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}