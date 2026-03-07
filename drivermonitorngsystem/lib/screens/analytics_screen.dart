import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/database/database_helper.dart';
import '../utils/responsive.dart';

// RIVERPOD PROVIDERS
final analyticsFilterProvider = StateProvider<int?>((ref) => 7);

final analyticsDataProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
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

    // No Scaffold/SafeArea — nav shell handles that
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
            error: (e, _) => const Center(
              child: Text('Error loading analytics',
                  style: TextStyle(color: Colors.white54)),
            ),
            data: (data) => _buildContent(context, data, isMobile, isTablet),
          ),
        ),
      ],
      ),
    );
  }

  // HEADER + FILTER TABS
    Widget _buildHeader(int? selectedDays) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: const Color(0xFF0b1120).withOpacity(0.8), offset: const Offset(4, 4),   blurRadius: 8),
            BoxShadow(color: const Color(0xFF1e293b).withOpacity(0.8), offset: const Offset(-4, -4), blurRadius: 8),
          ],
        ),
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
              ? [BoxShadow(color: const Color(0xFF0b1120).withOpacity(0.6), offset: const Offset(2, 2), blurRadius: 4)]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize:   Responsive.responsiveFont(context, mobile: 12, tablet: 13, desktop: 14),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color:      isSelected ? const Color(0xFF22d3ee) : const Color(0xFF64748b),
          ),
        ),
      ),
    );
  }

  // SCROLLABLE CONTENT
  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> data,
    bool isMobile,
    bool isTablet,
  ) {
    // Extract DB values
    final totalSessions     = data['total_sessions']     as int? ?? 0;
    final totalAlerts       = data['total_alerts']       as int? ?? 0;
    final drowsinessEvents  = data['drowsiness_events']  as int? ?? 0;
    final distractionEvents = data['distraction_events'] as int? ?? 0;
    final dailyTrends       = (data['daily_trends']         as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final hourlyDist        = (data['hourly_distribution']  as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

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
            // Summary Cards
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

            // Charts
            if (isMobile || isTablet)
              _buildMobileChartsLayout(context, dailyTrends, hourlyDist)
            else
              _buildDesktopChartsLayout(context, dailyTrends, hourlyDist),

            SizedBox(height: isMobile ? 96 : 32),
          ],
        ),
      ),
    );
  }

  // SUMMARY CARDS
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
      padding: const EdgeInsets.all(4),
      child: GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : 4,
      mainAxisSpacing:  Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
      crossAxisSpacing: Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
      childAspectRatio: Responsive.responsiveValue(context, mobile: 0.95, tablet: 1.2, desktop: 1.5),
      children: [
        _HoverableSummaryCard(icon: Icons.timer_outlined,          label: 'Total Sessions',     value: '$totalSessions',     change: '+12%', isPositive: true),
        _HoverableSummaryCard(icon: Icons.warning_amber_outlined,  label: 'Total Alerts',       value: '$totalAlerts',       change: '-8%',  isPositive: true),
        _HoverableSummaryCard(icon: Icons.bedtime_outlined,        label: 'Drowsiness Events',  value: '$drowsinessEvents',  change: '-15%', isPositive: true),
        _HoverableSummaryCard(icon: Icons.visibility_off_outlined, label: 'Distraction Events', value: '$distractionEvents', change: '+5%',  isPositive: false),
      ],
      ),
    );
  }

  // CHART LAYOUTS
  Widget _buildMobileChartsLayout(
    BuildContext context,
    List<Map<String, dynamic>> dailyTrends,
    List<Map<String, dynamic>> hourlyDist,
  ) {
    return Column(
      children: [
        _buildDrowsinessVsDistractionChart(context, dailyTrends),
        SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),
        _buildAlertTimelineChart(context, hourlyDist),
      ],
    );
  }

  Widget _buildDesktopChartsLayout(
    BuildContext context,
    List<Map<String, dynamic>> dailyTrends,
    List<Map<String, dynamic>> hourlyDist,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: _buildDrowsinessVsDistractionChart(context, dailyTrends)),
        SizedBox(width: Responsive.responsiveSpacing(context, mobile: 16, tablet: 24, desktop: 32)),
        Expanded(flex: 4, child: _buildAlertTimelineChart(context, hourlyDist)),
      ],
    );
  }

  // DROWSINESS VS DISTRACTION LINE CHART
  Widget _buildDrowsinessVsDistractionChart(
    BuildContext context,
    List<Map<String, dynamic>> dailyTrends,
  ) {
    // Build spots — DB data or fallback
    List<FlSpot> drowsySpots;
    List<FlSpot> distractedSpots;

    if (dailyTrends.isEmpty) {
      drowsySpots     = const [FlSpot(0,8), FlSpot(1,6), FlSpot(2,10), FlSpot(3,5), FlSpot(4,7), FlSpot(5,4), FlSpot(6,3)];
      distractedSpots = const [FlSpot(0,4), FlSpot(1,5), FlSpot(2,3),  FlSpot(3,6), FlSpot(4,4), FlSpot(5,2), FlSpot(6,2)];
    } else {
      drowsySpots     = [];
      distractedSpots = [];
      for (int i = 0; i < dailyTrends.length; i++) {
        drowsySpots.add(FlSpot(i.toDouble(),     (dailyTrends[i]['drowsy_count']     as int? ?? 0).toDouble()));
        distractedSpots.add(FlSpot(i.toDouble(), (dailyTrends[i]['distracted_count'] as int? ?? 0).toDouble()));
      }
    }

    return Container(
      height: Responsive.responsiveHeight(context, mobile: 300, tablet: 320, desktop: 340),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(8, 8),   blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b), offset: Offset(-8, -8), blurRadius: 16),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context, mobile: 20, tablet: 22, desktop: 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Responsive.isMobile(context))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drowsiness vs Distraction Trends',
                  style: TextStyle(
                    fontSize:   Responsive.responsiveFont(context, mobile: 15, tablet: 16, desktop: 17),
                    fontWeight: FontWeight.w600,
                    color:      const Color(0xFFcbd5e1),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildLegendItem(context, 'Drowsiness', const Color(0xFFef4444)),
                    const SizedBox(width: 12),
                    _buildLegendItem(context, 'Distraction', const Color(0xFFfbbf24)),
                  ],
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Drowsiness vs Distraction Trends',
                  style: TextStyle(
                    fontSize:   Responsive.responsiveFont(context, mobile: 15, tablet: 16, desktop: 17),
                    fontWeight: FontWeight.w600,
                    color:      const Color(0xFFcbd5e1),
                  ),
                ),
                Row(
                  children: [
                    _buildLegendItem(context, 'Drowsiness', const Color(0xFFef4444)),
                    SizedBox(width: Responsive.responsiveSpacing(context, mobile: 12)),
                    _buildLegendItem(context, 'Distraction', const Color(0xFFfbbf24)),
                  ],
                ),
              ],
            ),

          SizedBox(height: Responsive.responsiveSpacing(context, mobile: 16, tablet: 20, desktop: 24)),

          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
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
                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        final idx = value.toInt();
                        if (idx >= 0 && idx < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(days[idx],
                                style: TextStyle(
                                    color: const Color(0xFF64748b),
                                    fontSize: Responsive.responsiveFont(context, mobile: 11, tablet: 12, desktop: 13))),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 5,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                            color: const Color(0xFF64748b),
                            fontSize: Responsive.responsiveFont(context, mobile: 11, tablet: 12, desktop: 13)),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: 20,
                lineBarsData: [
                  LineChartBarData(
                    spots: drowsySpots,
                    isCurved: true,
                    color: const Color(0xFFef4444),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4,
                        color: const Color(0xFFef4444),
                        strokeWidth: 2,
                        strokeColor: const Color(0xFF0f172a),
                      ),
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots: distractedSpots,
                    isCurved: true,
                    color: const Color(0xFFfbbf24),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4,
                        color: const Color(0xFFfbbf24),
                        strokeWidth: 2,
                        strokeColor: const Color(0xFF0f172a),
                      ),
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: Responsive.responsiveFont(context, mobile: 11, tablet: 12, desktop: 13),
            color: const Color(0xFF94a3b8),
          ),
        ),
      ],
    );
  }

  // HOURLY BAR CHART
  Widget _buildAlertTimelineChart(
    BuildContext context,
    List<Map<String, dynamic>> hourlyDist,
  ) {
    const hourLabels = ['6AM', '9AM', '12PM', '3PM', '6PM', '9PM'];
    const hourValues = [6, 9, 12, 15, 18, 21];

    List<BarChartGroupData> barGroups;

    if (hourlyDist.isEmpty) {
      const placeholders = [3, 7, 5, 9, 12, 6];
      barGroups = List.generate(hourLabels.length,
          (i) => _buildBarGroup(context, i, placeholders[i].toDouble()));
    } else {
      final hourMap = <int, int>{};
      for (final row in hourlyDist) {
        hourMap[row['hour'] as int] = row['count'] as int;
      }
      barGroups = List.generate(hourValues.length,
          (i) => _buildBarGroup(context, i, (hourMap[hourValues[i]] ?? 0).toDouble()));
    }

    return Container(
      height: Responsive.responsiveHeight(context, mobile: 300, tablet: 320, desktop: 340),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context, mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120), offset: Offset(8, 8),   blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b), offset: Offset(-8, -8), blurRadius: 16),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context, mobile: 20, tablet: 22, desktop: 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hourly Alert Distribution',
            style: TextStyle(
              fontSize:   Responsive.responsiveFont(context, mobile: 15, tablet: 16, desktop: 17),
              fontWeight: FontWeight.w600,
              color:      const Color(0xFFcbd5e1),
            ),
          ),
          SizedBox(height: Responsive.responsiveSpacing(context, mobile: 16, tablet: 20, desktop: 24)),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 15,
                barTouchData: BarTouchData(enabled: false),
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
                                style: TextStyle(
                                    color: const Color(0xFF64748b),
                                    fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12))),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 5,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(
                            color: const Color(0xFF64748b),
                            fontSize: Responsive.responsiveFont(context, mobile: 10, tablet: 11, desktop: 12)),
                      ),
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: const Color(0xFF1e293b),
                    strokeWidth: 1,
                    dashArray: [3, 3],
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
          color: const Color(0xFF22d3ee),
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
}

// HOVERABLE SUMMARY CARD 
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
            Responsive.responsiveBorderRadius(context, mobile: 16, tablet: 18, desktop: 20),
          ),
          boxShadow: isHovered
              ? [
                  BoxShadow(color: const Color(0xFF0b1120).withOpacity(0.8), offset: const Offset(-3, -3), blurRadius: 6),
                  BoxShadow(color: const Color(0xFF1e293b).withOpacity(0.8), offset: const Offset(3, 3),   blurRadius: 6),
                ]
              : const [
                  BoxShadow(color: Color(0xFF0b1120), offset: Offset(6, 6),   blurRadius: 12),
                  BoxShadow(color: Color(0xFF1e293b), offset: Offset(-6, -6), blurRadius: 12),
                ],
        ),
        padding: EdgeInsets.all(
          Responsive.responsivePadding(context, mobile: 12, tablet: 16, desktop: 20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Icon + change badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(
                    Responsive.responsivePadding(context, mobile: 8, tablet: 9, desktop: 10),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e293b),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    size:  Responsive.responsiveIconSize(context, mobile: 18, tablet: 20, desktop: 24),
                    color: const Color(0xFF22d3ee),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.responsivePadding(context, mobile: 6, tablet: 7, desktop: 8),
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isPositive
                        ? const Color(0xFF10b981).withOpacity(0.1)
                        : const Color(0xFFef4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isPositive ? Icons.trending_down : Icons.trending_up,
                        size:  Responsive.responsiveIconSize(context, mobile: 11, tablet: 12, desktop: 14),
                        color: widget.isPositive
                            ? const Color(0xFF10b981)
                            : const Color(0xFFef4444),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        widget.change,
                        style: TextStyle(
                          fontSize:   Responsive.responsiveFont(context, mobile: 9, tablet: 10, desktop: 12),
                          fontWeight: FontWeight.w600,
                          color:      widget.isPositive
                              ? const Color(0xFF10b981)
                              : const Color(0xFFef4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Value + label
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.value,
                  style: TextStyle(
                    fontSize:   Responsive.responsiveFont(context, mobile: 24, tablet: 28, desktop: 32),
                    fontWeight: FontWeight.bold,
                    color:      const Color(0xFFe2e8f0),
                  ),
                ),
                SizedBox(height: Responsive.responsiveSpacing(context, mobile: 4, tablet: 5, desktop: 6)),
                Text(
                  widget.label,
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