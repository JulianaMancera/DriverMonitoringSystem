import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/responsive.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String selectedTimeRange = '7 Days';
  
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);

    return Container(
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 16,
          tablet: 24,
          desktop: 32,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time Range Selector
            _buildTimeRangeSelector(),
            
            SizedBox(
              height: Responsive.responsiveSpacing(
                context,
                mobile: 16,
                tablet: 20,
                desktop: 24,
              ),
            ),

            // Summary Cards
            _buildSummaryCards(isMobile, isTablet),
            
            SizedBox(
              height: Responsive.responsiveSpacing(
                context,
                mobile: 24,
                tablet: 28,
                desktop: 32,
              ),
            ),

            // Charts Section
            if (isMobile || isTablet)
              _buildMobileChartsLayout()
            else
              _buildDesktopChartsLayout(),

            SizedBox(
              height: Responsive.responsiveSpacing(
                context,
                mobile: 24,
                tablet: 28,
                desktop: 32,
              ),
            ),

            // Lighting Condition Analysis (Thesis Focus)
            _buildLightingAnalysis(),

            SizedBox(
              height: isMobile ? 96 : 32,
            ), // Extra padding for mobile bottom nav
          ],
        ),
      ),
    );
  }

  // Time Range Selector
  Widget _buildTimeRangeSelector() {
    return Container(
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 4,
          tablet: 5,
          desktop: 6,
        ),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
            context,
            mobile: 16,
            tablet: 18,
            desktop: 20,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0b1120).withOpacity(0.8),
            offset: const Offset(4, 4),
            blurRadius: 8,
          ),
          BoxShadow(
            color: const Color(0xFF1e293b).withOpacity(0.8),
            offset: const Offset(-4, -4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimeRangeButton('7 Days'),
          SizedBox(width: Responsive.responsiveSpacing(context, mobile: 4)),
          _buildTimeRangeButton('30 Days'),
          SizedBox(width: Responsive.responsiveSpacing(context, mobile: 4)),
          _buildTimeRangeButton('All Time'),
        ],
      ),
    );
  }

  Widget _buildTimeRangeButton(String label) {
    final isSelected = selectedTimeRange == label;
    
    return InkWell(
      onTap: () {
        setState(() {
          selectedTimeRange = label;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.responsivePadding(
            context,
            mobile: 12,
            tablet: 14,
            desktop: 16,
          ),
          vertical: Responsive.responsivePadding(
            context,
            mobile: 8,
            tablet: 9,
            desktop: 10,
          ),
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1e293b) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0b1120).withOpacity(0.6),
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: Responsive.responsiveFont(
              context,
              mobile: 12,
              tablet: 13,
              desktop: 14,
            ),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? const Color(0xFF22d3ee)
                : const Color(0xFF64748b),
          ),
        ),
      ),
    );
  }

  // Summary Cards
  Widget _buildSummaryCards(bool isMobile, bool isTablet) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : 4,
      mainAxisSpacing: Responsive.responsiveSpacing(
        context,
        mobile: 12,
        tablet: 14,
        desktop: 16,
      ),
      crossAxisSpacing: Responsive.responsiveSpacing(
        context,
        mobile: 12,
        tablet: 14,
        desktop: 16,
      ),
      childAspectRatio: Responsive.responsiveValue(
        context,
        mobile: 0.95,
        tablet: 1.2,
        desktop: 1.5,
      ),
      children: [
        _buildSummaryCard(
          icon: Icons.timer_outlined,
          label: 'Total Sessions',
          value: '127',
          change: '+12%',
          isPositive: true,
        ),
        _buildSummaryCard(
          icon: Icons.warning_amber_outlined,
          label: 'Total Alerts',
          value: '43',
          change: '-8%',
          isPositive: true,
        ),
        _buildSummaryCard(
          icon: Icons.bedtime_outlined,
          label: 'Drowsiness Events',
          value: '28',
          change: '-15%',
          isPositive: true,
        ),
        _buildSummaryCard(
          icon: Icons.visibility_off_outlined,
          label: 'Distraction Events',
          value: '15',
          change: '+5%',
          isPositive: false,
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String change,
    required bool isPositive,
  }) {
    return _HoverableSummaryCard(
      icon: icon,
      label: label,
      value: value,
      change: change,
      isPositive: isPositive,
    );
  }

  // Mobile Charts Layout
  Widget _buildMobileChartsLayout() {
    return Column(
      children: [
        _buildDrowsinessVsDistractionChart(),
        SizedBox(
          height: Responsive.responsiveSpacing(
            context,
            mobile: 24,
            tablet: 28,
            desktop: 32,
          ),
        ),
        _buildAlertTimelineChart(),
      ],
    );
  }

  // Desktop Charts Layout
  Widget _buildDesktopChartsLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: _buildDrowsinessVsDistractionChart(),
        ),
        SizedBox(
          width: Responsive.responsiveSpacing(
            context,
            mobile: 16,
            tablet: 24,
            desktop: 32,
          ),
        ),
        Expanded(
          flex: 4,
          child: _buildAlertTimelineChart(),
        ),
      ],
    );
  }

  // Drowsiness vs Distraction Chart
  Widget _buildDrowsinessVsDistractionChart() {
    return Container(
      height: Responsive.responsiveHeight(
        context,
        mobile: 300,
        tablet: 320,
        desktop: 340,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
            context,
            mobile: 20,
            tablet: 22,
            desktop: 24,
          ),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(8, 8),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-8, -8),
            blurRadius: 16,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 20,
          tablet: 22,
          desktop: 24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section with title and legend
          if (Responsive.isMobile(context))
            // Mobile: Stack vertically
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drowsiness vs Distraction Trends',
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                      context,
                      mobile: 15,
                      tablet: 16,
                      desktop: 17,
                    ),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFcbd5e1),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildLegendItem('Drowsiness', const Color(0xFFef4444)),
                    const SizedBox(width: 12),
                    _buildLegendItem('Distraction', const Color(0xFFfbbf24)),
                  ],
                ),
              ],
            )
          else
            // Desktop/Tablet: Side by side
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Drowsiness vs Distraction Trends',
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                      context,
                      mobile: 15,
                      tablet: 16,
                      desktop: 17,
                    ),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFcbd5e1),
                  ),
                ),
                Row(
                  children: [
                    _buildLegendItem('Drowsiness', const Color(0xFFef4444)),
                    SizedBox(width: Responsive.responsiveSpacing(context, mobile: 12)),
                    _buildLegendItem('Distraction', const Color(0xFFfbbf24)),
                  ],
                ),
              ],
            ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFF1e293b),
                      strokeWidth: 1,
                      dashArray: [3, 3],
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        if (value.toInt() >= 0 && value.toInt() < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              days[value.toInt()],
                              style: TextStyle(
                                color: const Color(0xFF64748b),
                                fontSize: Responsive.responsiveFont(
                                  context,
                                  mobile: 11,
                                  tablet: 12,
                                  desktop: 13,
                                ),
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
                      interval: 5,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: const Color(0xFF64748b),
                            fontSize: Responsive.responsiveFont(
                              context,
                              mobile: 11,
                              tablet: 12,
                              desktop: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: 20,
                lineBarsData: [
                  // Drowsiness line
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 8),
                      FlSpot(1, 6),
                      FlSpot(2, 10),
                      FlSpot(3, 5),
                      FlSpot(4, 7),
                      FlSpot(5, 4),
                      FlSpot(6, 3),
                    ],
                    isCurved: true,
                    color: const Color(0xFFef4444),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: const Color(0xFFef4444),
                          strokeWidth: 2,
                          strokeColor: const Color(0xFF0f172a),
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                  // Distraction line
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 4),
                      FlSpot(1, 5),
                      FlSpot(2, 3),
                      FlSpot(3, 6),
                      FlSpot(4, 4),
                      FlSpot(5, 2),
                      FlSpot(6, 2),
                    ],
                    isCurved: true,
                    color: const Color(0xFFfbbf24),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: const Color(0xFFfbbf24),
                          strokeWidth: 2,
                          strokeColor: const Color(0xFF0f172a),
                        );
                      },
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

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: Responsive.responsiveFont(
              context,
              mobile: 11,
              tablet: 12,
              desktop: 13,
            ),
            color: const Color(0xFF94a3b8),
          ),
        ),
      ],
    );
  }

  // Alert Timeline Chart
  Widget _buildAlertTimelineChart() {
    return Container(
      height: Responsive.responsiveHeight(
        context,
        mobile: 300,
        tablet: 320,
        desktop: 340,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
            context,
            mobile: 20,
            tablet: 22,
            desktop: 24,
          ),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(8, 8),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-8, -8),
            blurRadius: 16,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 20,
          tablet: 22,
          desktop: 24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hourly Alert Distribution',
            style: TextStyle(
              fontSize: Responsive.responsiveFont(
                context,
                mobile: 15,
                tablet: 16,
                desktop: 17,
              ),
              fontWeight: FontWeight.w600,
              color: const Color(0xFFcbd5e1),
            ),
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 15,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const hours = ['6AM', '9AM', '12PM', '3PM', '6PM', '9PM'];
                        if (value.toInt() >= 0 && value.toInt() < hours.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              hours[value.toInt()],
                              style: TextStyle(
                                color: const Color(0xFF64748b),
                                fontSize: Responsive.responsiveFont(
                                  context,
                                  mobile: 10,
                                  tablet: 11,
                                  desktop: 12,
                                ),
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: const Color(0xFF64748b),
                            fontSize: Responsive.responsiveFont(
                              context,
                              mobile: 10,
                              tablet: 11,
                              desktop: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFF1e293b),
                      strokeWidth: 1,
                      dashArray: [3, 3],
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  _buildBarGroup(0, 3),
                  _buildBarGroup(1, 7),
                  _buildBarGroup(2, 5),
                  _buildBarGroup(3, 9),
                  _buildBarGroup(4, 12),
                  _buildBarGroup(5, 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: const Color(0xFF22d3ee),
          width: Responsive.responsiveValue(
            context,
            mobile: 16.0,
            tablet: 18.0,
            desktop: 20.0,
          ),
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

  // Lighting Condition Analysis
  Widget _buildLightingAnalysis() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
            context,
            mobile: 20,
            tablet: 22,
            desktop: 24,
          ),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(8, 8),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-8, -8),
            blurRadius: 16,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 20,
          tablet: 22,
          desktop: 24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                size: Responsive.responsiveIconSize(
                  context,
                  mobile: 20,
                  tablet: 22,
                  desktop: 24,
                ),
                color: const Color(0xFF22d3ee),
              ),
              SizedBox(width: Responsive.responsiveSpacing(context, mobile: 8)),
              Text(
                'Performance by Lighting Condition',
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                    context,
                    mobile: 16,
                    tablet: 17,
                    desktop: 18,
                  ),
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFcbd5e1),
                ),
              ),
            ],
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 20,
              tablet: 22,
              desktop: 24,
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: Responsive.responsiveSpacing(context, mobile: 12),
            crossAxisSpacing: Responsive.responsiveSpacing(context, mobile: 12),
            childAspectRatio: Responsive.responsiveValue(
              context,
              mobile: 1.3,
              tablet: 1.6,
              desktop: 2.2,
            ),
            children: [
              _buildLightingCard(
                'Day',
                '96.5%',
                Icons.wb_sunny,
                const Color(0xFFfbbf24),
              ),
              _buildLightingCard(
                'Night',
                '94.2%',
                Icons.nightlight_round,
                const Color(0xFF6366f1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLightingCard(
    String label,
    String accuracy,
    IconData icon,
    Color color,
  ) {
    return _HoverableLightingCard(
      label: label,
      accuracy: accuracy,
      icon: icon,
      color: color,
    );
  }
}

// Hoverable Summary Card with neumorphic hover effect
class _HoverableSummaryCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final String change;
  final bool isPositive;

  const _HoverableSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.change,
    required this.isPositive,
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
      onExit: (_) => setState(() => isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(
              context,
              mobile: 16,
              tablet: 18,
              desktop: 20,
            ),
          ),
          boxShadow: isHovered
              ? [
                  // Hovered - inset neumorphic
                  BoxShadow(
                    color: const Color(0xFF0b1120).withOpacity(0.8),
                    offset: const Offset(-3, -3),
                    blurRadius: 6,
                  ),
                  BoxShadow(
                    color: const Color(0xFF1e293b).withOpacity(0.8),
                    offset: const Offset(3, 3),
                    blurRadius: 6,
                  ),
                ]
              : [
                  // Normal - raised neumorphic
                  const BoxShadow(
                    color: Color(0xFF0b1120),
                    offset: Offset(6, 6),
                    blurRadius: 12,
                  ),
                  const BoxShadow(
                    color: Color(0xFF1e293b),
                    offset: Offset(-6, -6),
                    blurRadius: 12,
                  ),
                ],
        ),
        padding: EdgeInsets.all(
          Responsive.responsivePadding(
            context,
            mobile: 12,
            tablet: 16,
            desktop: 20,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(
                    Responsive.responsivePadding(
                      context,
                      mobile: 8,
                      tablet: 9,
                      desktop: 10,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e293b),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    size: Responsive.responsiveIconSize(
                      context,
                      mobile: 18,
                      tablet: 20,
                      desktop: 24,
                    ),
                    color: const Color(0xFF22d3ee),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.responsivePadding(
                      context,
                      mobile: 6,
                      tablet: 7,
                      desktop: 8,
                    ),
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
                        widget.isPositive
                            ? Icons.trending_down
                            : Icons.trending_up,
                        size: Responsive.responsiveIconSize(
                          context,
                          mobile: 11,
                          tablet: 12,
                          desktop: 14,
                        ),
                        color: widget.isPositive
                            ? const Color(0xFF10b981)
                            : const Color(0xFFef4444),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        widget.change,
                        style: TextStyle(
                          fontSize: Responsive.responsiveFont(
                            context,
                            mobile: 9,
                            tablet: 10,
                            desktop: 12,
                          ),
                          fontWeight: FontWeight.w600,
                          color: widget.isPositive
                              ? const Color(0xFF10b981)
                              : const Color(0xFFef4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.value,
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                      context,
                      mobile: 24,
                      tablet: 28,
                      desktop: 32,
                    ),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFe2e8f0),
                  ),
                ),
                SizedBox(
                  height: Responsive.responsiveSpacing(
                    context,
                    mobile: 4,
                    tablet: 5,
                    desktop: 6,
                  ),
                ),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                      context,
                      mobile: 10,
                      tablet: 11,
                      desktop: 13,
                    ),
                    color: const Color(0xFF64748b),
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

// Hoverable Lighting Card with neumorphic hover effect
class _HoverableLightingCard extends StatefulWidget {
  final String label;
  final String accuracy;
  final IconData icon;
  final Color color;

  const _HoverableLightingCard({
    required this.label,
    required this.accuracy,
    required this.icon,
    required this.color,
  });

  @override
  State<_HoverableLightingCard> createState() => _HoverableLightingCardState();
}

class _HoverableLightingCardState extends State<_HoverableLightingCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: const Color(0xFF1e293b),
          borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(
              context,
              mobile: 14,
              tablet: 16,
              desktop: 18,
            ),
          ),
          boxShadow: isHovered
              ? [
                  // Hovered - inset neumorphic
                  BoxShadow(
                    color: const Color(0xFF0b1120).withOpacity(0.8),
                    offset: const Offset(-2, -2),
                    blurRadius: 4,
                  ),
                  BoxShadow(
                    color: const Color(0xFF334155).withOpacity(0.5),
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                ]
              : [
                  // Normal - subtle raised
                  const BoxShadow(
                    color: Color(0xFF0b1120),
                    offset: Offset(3, 3),
                    blurRadius: 6,
                  ),
                  const BoxShadow(
                    color: Color(0xFF334155),
                    offset: Offset(-3, -3),
                    blurRadius: 6,
                  ),
                ],
        ),
        padding: EdgeInsets.all(
          Responsive.responsivePadding(
            context,
            mobile: 12,
            tablet: 14,
            desktop: 16,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: Responsive.responsiveIconSize(
                context,
                mobile: 28,
                tablet: 32,
                desktop: 36,
              ),
              color: widget.color,
            ),
            SizedBox(
              height: Responsive.responsiveSpacing(
                context,
                mobile: 8,
                tablet: 10,
                desktop: 12,
              ),
            ),
            Text(
              widget.accuracy,
              style: TextStyle(
                fontSize: Responsive.responsiveFont(
                  context,
                  mobile: 18,
                  tablet: 20,
                  desktop: 22,
                ),
                fontWeight: FontWeight.bold,
                color: widget.color,
              ),
            ),
            SizedBox(
              height: Responsive.responsiveSpacing(
                context,
                mobile: 4,
                tablet: 5,
                desktop: 6,
              ),
            ),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: Responsive.responsiveFont(
                  context,
                  mobile: 11,
                  tablet: 12,
                  desktop: 13,
                ),
                color: const Color(0xFF94a3b8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}