import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../utils/responsive.dart';

// RIVERPOD PROVIDERS
final analyticsFilterProvider = StateProvider<int?>((ref) => 7);

final analyticsDataProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.watch(dbChangeCounterProvider);
  final days = ref.watch(analyticsFilterProvider);
  return await DatabaseHelper.instance.getAnalyticsSummary(days: days);
});

// ANALYTICS SCREEN
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(analyticsDataProvider);
    final selectedDays   = ref.watch(analyticsFilterProvider);
    final isMobile       = Responsive.isMobile(context);
    final isTablet       = Responsive.isTablet(context);

    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(selectedDays),
          Expanded(
            child: analyticsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF22d3ee)),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: Colors.white54)),
              ),
              data: (data) => _buildContent(context, data, isMobile, isTablet),
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────

  Widget _buildHeader(int? selectedDays) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: const Color(0xFF0b1120).withValues(alpha: 0.8), offset: const Offset(4, 4),   blurRadius: 8),
            BoxShadow(color: const Color(0xFF1e293b).withValues(alpha: 0.8), offset: const Offset(-4, -4), blurRadius: 8),
          ],
        ),
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTimeRangeButton('7 Days',   selectedDays == 7,    () => ref.read(analyticsFilterProvider.notifier).state = 7),
              const SizedBox(width: 4),
              _buildTimeRangeButton('30 Days',  selectedDays == 30,   () => ref.read(analyticsFilterProvider.notifier).state = 30),
              const SizedBox(width: 4),
              _buildTimeRangeButton('All Time', selectedDays == null, () => ref.read(analyticsFilterProvider.notifier).state = null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRangeButton(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.responsivePadding(context, mobile: 12, tablet: 14, desktop: 16),
          vertical:   Responsive.responsivePadding(context, mobile: 8,  tablet: 9,  desktop: 10),
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1e293b) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF0b1120).withValues(alpha: 0.6), offset: const Offset(2, 2), blurRadius: 4)]
              : [],
        ),
        child: Text(label,
          style: TextStyle(
            fontSize:   Responsive.responsiveFont(context, mobile: 12, tablet: 13, desktop: 14),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color:      isSelected ? const Color(0xFF22d3ee) : const Color(0xFF64748b),
          ),
        ),
      ),
    );
  }

  // ── CONTENT ───────────────────────────────────────────────────────────────

  Widget _buildContent(BuildContext context, Map<String, dynamic> data, bool isMobile, bool isTablet) {
    final totalSessions     = data['total_sessions']     as int? ?? 0;
    final totalAlerts       = data['total_alerts']       as int? ?? 0;
    final drowsinessEvents  = data['drowsiness_events']  as int? ?? 0;
    final distractionEvents = data['distraction_events'] as int? ?? 0;
    final dailyTrends       = (data['daily_trends']        as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final hourlyDist        = (data['hourly_distribution'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      color: const Color(0xFF22d3ee),
      backgroundColor: const Color(0xFF0f172a),
      onRefresh: () async {
        ref.invalidate(analyticsDataProvider);
        await ref.read(analyticsDataProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(
              context,
              isMobile: isMobile,
              isTablet: isTablet,
              totalSessions: totalSessions,
              totalAlerts: totalAlerts,
              drowsinessEvents: drowsinessEvents,
              distractionEvents: distractionEvents,
            ),
            SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: isMobile || isTablet
                  ? _buildMobileChartsLayout(context, dailyTrends, hourlyDist)
                  : _buildDesktopChartsLayout(context, dailyTrends, hourlyDist),
            ),
            SizedBox(height: isMobile ? 96 : 32),
          ],
        ),
      ),
    );
  }

  // ── SUMMARY CARDS ─────────────────────────────────────────────────────────

  Widget _buildSummaryCards(
    BuildContext context, {
    required bool isMobile,
    required bool isTablet,
    required int totalSessions,
    required int totalAlerts,
    required int drowsinessEvents,
    required int distractionEvents,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount:  isMobile ? 2 : 4,
        mainAxisSpacing: Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
        crossAxisSpacing:Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
        childAspectRatio:Responsive.responsiveValue(context,   mobile: 0.95, tablet: 1.2, desktop: 1.5),
        children: [
          _HoverableSummaryCard(icon: Icons.timer_outlined,          label: 'Total Sessions',     value: '$totalSessions',     change: '',     isPositive: true),
          _HoverableSummaryCard(icon: Icons.warning_amber_outlined,  label: 'Total Alerts',       value: '$totalAlerts',       change: '',     isPositive: totalAlerts == 0),
          _HoverableSummaryCard(icon: Icons.bedtime_outlined,        label: 'Drowsiness Events',  value: '$drowsinessEvents',  change: '',     isPositive: drowsinessEvents == 0),
          _HoverableSummaryCard(icon: Icons.visibility_off_outlined, label: 'Distraction Events', value: '$distractionEvents', change: '',     isPositive: distractionEvents == 0),
        ],
      ),
    );
  }

  // ── CHART LAYOUTS ─────────────────────────────────────────────────────────

  Widget _buildMobileChartsLayout(BuildContext context, List<Map<String, dynamic>> dailyTrends, List<Map<String, dynamic>> hourlyDist) {
    return Column(
      children: [
        _buildDrowsinessVsDistractionChart(context, dailyTrends),
        SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),
        _buildAlertTimelineChart(context, hourlyDist),
      ],
    );
  }

  Widget _buildDesktopChartsLayout(BuildContext context, List<Map<String, dynamic>> dailyTrends, List<Map<String, dynamic>> hourlyDist) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: _buildDrowsinessVsDistractionChart(context, dailyTrends)),
        SizedBox(width: Responsive.responsiveSpacing(context, mobile: 16, tablet: 24, desktop: 32)),
        Expanded(flex: 4, child: _buildAlertTimelineChart(context, hourlyDist)),
      ],
    );
  }

  // ── LINE CHART: DROWSINESS VS DISTRACTION ─────────────────────────────────

  Widget _buildDrowsinessVsDistractionChart(BuildContext context, List<Map<String, dynamic>> dailyTrends) {

    // ── Build spots from real data ─────────────────────────────────────────
    List<FlSpot> drowsySpots;
    List<FlSpot> distractedSpots;
    List<String> xLabels;

    if (dailyTrends.isEmpty) {
      // Placeholder data — consistent 7 points
      drowsySpots     = const [FlSpot(0,0), FlSpot(1,0), FlSpot(2,0), FlSpot(3,0), FlSpot(4,0), FlSpot(5,0), FlSpot(6,0)];
      distractedSpots = const [FlSpot(0,0), FlSpot(1,0), FlSpot(2,0), FlSpot(3,0), FlSpot(4,0), FlSpot(5,0), FlSpot(6,0)];
      xLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    } else {
      drowsySpots     = [];
      distractedSpots = [];
      xLabels         = [];
      for (int i = 0; i < dailyTrends.length; i++) {
        final drowsy     = (dailyTrends[i]['drowsy_count']     as int? ?? 0).toDouble();
        final distracted = (dailyTrends[i]['distracted_count'] as int? ?? 0).toDouble();
        drowsySpots.add(FlSpot(i.toDouble(), drowsy));
        distractedSpots.add(FlSpot(i.toDouble(), distracted));

        // Build short date label e.g. "Mar 17"
        final dateStr = dailyTrends[i]['date'] as String? ?? '';
        xLabels.add(_shortDate(dateStr));
      }
    }

    // ── Compute dynamic axis bounds ────────────────────────────────────────
    // FIX: hardcoded maxX=6 and maxY=20 caused overlap when real data had
    // fewer points or higher values. Now computed from actual data.
    final double maxX = (drowsySpots.length - 1).toDouble().clamp(1, double.infinity);

    double dataMaxY = 5; // minimum ceiling so chart never looks flat
    for (final s in [...drowsySpots, ...distractedSpots]) {
      if (s.y > dataMaxY) dataMaxY = s.y;
    }
    // Round up to nearest 5 for clean grid lines
    final double maxY = ((dataMaxY / 5).ceil() * 5).toDouble();
    final double yInterval = maxY <= 10 ? 2 : maxY <= 20 ? 5 : 10;

    return Container(
      // FIX: give the chart a fixed height with no Expanded inside a Column
      // that is itself inside a SingleChildScrollView — this was the primary
      // cause of the overlap / unbounded height error.
      height: Responsive.responsiveHeight(context, mobile: 300, tablet: 320, desktop: 340),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24)),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(8, 8),   blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b), offset: Offset(-8, -8), blurRadius: 16),
        ],
      ),
      padding: EdgeInsets.all(Responsive.responsivePadding(context, mobile: 20, tablet: 22, desktop: 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          if (Responsive.isMobile(context))
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Drowsiness vs Distraction Trends',
                  style: TextStyle(fontSize: Responsive.responsiveFont(context, mobile: 15, tablet: 16, desktop: 17),
                      fontWeight: FontWeight.w600, color: const Color(0xFFcbd5e1))),
              const SizedBox(height: 8),
              Row(children: [
                _buildLegendItem(context, 'Drowsiness', const Color(0xFFef4444)),
                const SizedBox(width: 12),
                _buildLegendItem(context, 'Distraction', const Color(0xFFfbbf24)),
              ]),
            ])
          else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Drowsiness vs Distraction Trends',
                  style: TextStyle(fontSize: Responsive.responsiveFont(context, mobile: 15, tablet: 16, desktop: 17),
                      fontWeight: FontWeight.w600, color: const Color(0xFFcbd5e1))),
              Row(children: [
                _buildLegendItem(context, 'Drowsiness', const Color(0xFFef4444)),
                SizedBox(width: Responsive.responsiveSpacing(context, mobile: 12)),
                _buildLegendItem(context, 'Distraction', const Color(0xFFfbbf24)),
              ]),
            ]),

          SizedBox(height: Responsive.responsiveSpacing(context, mobile: 16, tablet: 20, desktop: 24)),

          // FIX: wrap chart in Expanded so it fills remaining space inside
          // the fixed-height Container — prevents unbounded height
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: const Color(0xFF1e293b), strokeWidth: 1, dashArray: [3, 3],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      // FIX: interval must match actual data point spacing
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx >= 0 && idx < xLabels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(xLabels[idx],
                              style: TextStyle(color: const Color(0xFF64748b),
                                  fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12)),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: yInterval,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        // FIX: skip labels at 0 and maxY to prevent overlap
                        // with axis border
                        if (value == 0 || value == maxY) return const SizedBox.shrink();
                        return Text(value.toInt().toString(),
                          style: TextStyle(color: const Color(0xFF64748b),
                              fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                // FIX: dynamic bounds from actual data
                minX: 0,
                maxX: maxX,
                minY: 0,
                maxY: maxY,
                clipData: const FlClipData.all(), // FIX: clips lines to chart area — prevents overflow
                lineBarsData: [
                  LineChartBarData(
                    spots: drowsySpots,
                    isCurved: drowsySpots.length > 2,
                    curveSmoothness: 0.3,
                    color: const Color(0xFFef4444),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 3.5, color: const Color(0xFFef4444),
                        strokeWidth: 2, strokeColor: const Color(0xFF0f172a),
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFef4444).withValues(alpha: 0.06),
                    ),
                  ),
                  LineChartBarData(
                    spots: distractedSpots,
                    isCurved: distractedSpots.length > 2,
                    curveSmoothness: 0.3,
                    color: const Color(0xFFfbbf24),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 3.5, color: const Color(0xFFfbbf24),
                        strokeWidth: 2, strokeColor: const Color(0xFF0f172a),
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFfbbf24).withValues(alpha: 0.06),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1e293b),
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                      s.y.toInt().toString(),
                      TextStyle(
                        color: s.barIndex == 0 ? const Color(0xFFef4444) : const Color(0xFFfbbf24),
                        fontWeight: FontWeight.bold, fontSize: 12,
                      ),
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

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(
          fontSize: Responsive.responsiveFont(context, mobile: 11, tablet: 12, desktop: 13),
          color: const Color(0xFF94a3b8))),
    ]);
  }

  // ── BAR CHART: HOURLY ALERT DISTRIBUTION ──────────────────────────────────

  Widget _buildAlertTimelineChart(BuildContext context, List<Map<String, dynamic>> hourlyDist) {
    const hourLabels = ['6AM', '9AM', '12PM', '3PM', '6PM', '9PM'];
    const hourValues = [6, 9, 12, 15, 18, 21];

    // Build hour → count map from real data
    final hourMap = <int, int>{};
    for (final row in hourlyDist) {
      hourMap[row['hour'] as int] = row['count'] as int;
    }

    final barGroups = List.generate(hourValues.length,
        (i) => _buildBarGroup(context, i, (hourMap[hourValues[i]] ?? 0).toDouble()));

    // FIX: dynamic maxY so bars never overflow the chart
    double dataMaxY = 5;
    for (final g in barGroups) {
      final y = g.barRods.first.toY;
      if (y > dataMaxY) dataMaxY = y;
    }
    final double maxY = ((dataMaxY / 5).ceil() * 5).toDouble();

    return Container(
      height: Responsive.responsiveHeight(context, mobile: 300, tablet: 320, desktop: 340),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24)),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(8, 8),   blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b), offset: Offset(-8, -8), blurRadius: 16),
        ],
      ),
      padding: EdgeInsets.all(Responsive.responsivePadding(context, mobile: 20, tablet: 22, desktop: 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hourly Alert Distribution',
            style: TextStyle(
              fontSize: Responsive.responsiveFont(context, mobile: 15, tablet: 16, desktop: 17),
              fontWeight: FontWeight.w600, color: const Color(0xFFcbd5e1),
            ),
          ),
          SizedBox(height: Responsive.responsiveSpacing(context, mobile: 16, tablet: 20, desktop: 24)),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                // FIX: dynamic maxY prevents bars from being cut off or overflowing
                maxY: maxY,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1e293b),
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                      rod.toY.toInt().toString(),
                      const TextStyle(color: Color(0xFF22d3ee), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < hourLabels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(hourLabels[idx],
                              style: TextStyle(color: const Color(0xFF64748b),
                                  fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12))),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: maxY <= 10 ? 2 : maxY <= 20 ? 5 : 10,
                      getTitlesWidget: (value, meta) {
                        if (value == 0 || value == maxY) return const SizedBox.shrink();
                        return Text(value.toInt().toString(),
                          style: TextStyle(color: const Color(0xFF64748b),
                              fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12)));
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY <= 10 ? 2 : maxY <= 20 ? 5 : 10,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: const Color(0xFF1e293b), strokeWidth: 1, dashArray: [3, 3],
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildBarGroup(BuildContext context, int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          width: Responsive.responsiveValue(context, mobile: 16.0, tablet: 18.0, desktop: 20.0),
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(
            colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
      ],
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  /// Converts "2026-03-17" → "Mar 17"
  String _shortDate(String iso) {
    if (iso.length < 10) return iso;
    try {
      final d = DateTime.parse(iso);
      const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${mo[d.month - 1]} ${d.day}';
    } catch (_) {
      return iso.substring(5); // fallback: "03-17"
    }
  }
}

// ── HOVERABLE SUMMARY CARD ────────────────────────────────────────────────────

class _HoverableSummaryCard extends StatefulWidget {
  final IconData icon;
  final String label, value, change;
  final bool isPositive;

  const _HoverableSummaryCard({
    required this.icon, required this.label,
    required this.value, required this.change, required this.isPositive,
  });

  @override
  State<_HoverableSummaryCard> createState() => _HoverableSummaryCardState();
}

class _HoverableSummaryCardState extends State<_HoverableSummaryCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit:  (_) => setState(() => isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(
              Responsive.responsiveBorderRadius(context, mobile: 16, tablet: 18, desktop: 20)),
          boxShadow: isHovered
              ? [
                  BoxShadow(color: const Color(0xFF0b1120).withValues(alpha: 0.8), offset: const Offset(-3, -3), blurRadius: 6),
                  BoxShadow(color: const Color(0xFF1e293b).withValues(alpha: 0.8), offset: const Offset(3, 3),   blurRadius: 6),
                ]
              : const [
                  BoxShadow(color: Color(0xFF0b1120), offset: Offset(6, 6),   blurRadius: 12),
                  BoxShadow(color: Color(0xFF1e293b), offset: Offset(-6, -6), blurRadius: 12),
                ],
        ),
        padding: EdgeInsets.all(Responsive.responsivePadding(context, mobile: 12, tablet: 16, desktop: 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(Responsive.responsivePadding(context, mobile: 8, tablet: 9, desktop: 10)),
                  decoration: BoxDecoration(color: const Color(0xFF1e293b), borderRadius: BorderRadius.circular(10)),
                  child: Icon(widget.icon,
                    size:  Responsive.responsiveIconSize(context, mobile: 18, tablet: 20, desktop: 24),
                    color: const Color(0xFF22d3ee)),
                ),
                // Only show change badge if there's a value to show
                if (widget.change.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.responsivePadding(context, mobile: 6, tablet: 7, desktop: 8),
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isPositive
                          ? const Color(0xFF10b981).withValues(alpha: 0.1)
                          : const Color(0xFFef4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(children: [
                      Icon(
                        widget.isPositive ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                        size: Responsive.responsiveIconSize(context, mobile: 11, tablet: 12, desktop: 14),
                        color: widget.isPositive ? const Color(0xFF10b981) : const Color(0xFFef4444),
                      ),
                    ]),
                  )
                else
                  // Status dot — green if isPositive (zero events), amber if not
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: widget.isPositive ? const Color(0xFF10b981) : const Color(0xFFfbbf24),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.value,
                  style: TextStyle(
                    fontSize:   Responsive.responsiveFont(context, mobile: 24, tablet: 28, desktop: 32),
                    fontWeight: FontWeight.bold,
                    color:      const Color(0xFFe2e8f0),
                  ),
                ),
                SizedBox(height: Responsive.responsiveSpacing(context, mobile: 4, tablet: 5, desktop: 6)),
                Text(widget.label,
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 13),
                    color:    const Color(0xFF64748b),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}