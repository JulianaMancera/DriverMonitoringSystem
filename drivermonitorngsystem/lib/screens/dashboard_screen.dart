import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/responsive.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

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
          children: [
            // Top section with Safety Score + Stats
            LayoutBuilder(
              builder: (context, constraints) {
                if (isMobile || Responsive.isTablet(context)) {
                  // Mobile & Tablet: Stack vertically
                  return Column(
                    children: [
                      _buildSafetyScoreCard(context),
                      SizedBox(
                        height: Responsive.responsiveSpacing(
                          context,
                          mobile: 24,
                          tablet: 28,
                          desktop: 32,
                        ),
                      ),
                      _buildQuickStatsGrid(context),
                    ],
                  );
                } else {
                  // Desktop only: Side by side
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _buildSafetyScoreCard(context),
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
                        flex: 8,
                        child: _buildQuickStatsGrid(context),
                      ),
                    ],
                  );
                }
              },
            ),
            
            SizedBox(
              height: Responsive.responsiveSpacing(
                context,
                mobile: 24,
                tablet: 28,
                desktop: 32,
              ),
            ),

            // Chart section
            _buildAlertnesChart(context),

            SizedBox(
              height: isMobile
                  ? 96
                  : Responsive.responsiveSpacing(
                      context,
                      mobile: 32,
                      desktop: 32,
                    ),
            ), // Extra padding for mobile bottom nav
          ],
        ),
      ),
    );
  }

  // Safety Score Card (the circular score display)
  Widget _buildSafetyScoreCard(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

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
            offset: Offset(10, 10),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-10, -10),
            blurRadius: 16,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top gradient bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: Responsive.responsiveValue(
                context,
                mobile: 6.0,
                tablet: 7.0,
                desktop: 8.0,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(
                    Responsive.responsiveBorderRadius(
                      context,
                      mobile: 20,
                      tablet: 22,
                      desktop: 24,
                    ),
                  ),
                  topRight: Radius.circular(
                    Responsive.responsiveBorderRadius(
                      context,
                      mobile: 20,
                      tablet: 22,
                      desktop: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Main content
          Center(
            child: Padding(
              padding: EdgeInsets.all(
                Responsive.responsivePadding(
                  context,
                  mobile: isMobile ? 48 : 60,
                  tablet: 55,
                  desktop: 87,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'SAFETY SCORE',
                    style: TextStyle(
                      color: const Color(0xFF94a3b8),
                      fontSize: Responsive.responsiveFont(
                        context,
                        mobile: 18,
                        tablet: 20,
                        desktop: 24,
                      ),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(
                    height: Responsive.responsiveSpacing(
                      context,
                      mobile: 24,
                      tablet: 28,
                      desktop: 32,
                    ),
                  ),

                  // Circular score indicator
                  _buildCircularScoreIndicator(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularScoreIndicator(BuildContext context) {
    final outerSize = Responsive.responsiveValue(
      context,
      mobile: 150.0,
      tablet: 170.0,
      desktop: 195.0,
    );
    final progressSize = Responsive.responsiveValue(
      context,
      mobile: 138.0,
      tablet: 156.0,
      desktop: 179.0,
    );
    final innerSize = Responsive.responsiveValue(
      context,
      mobile: 115.0,
      tablet: 130.0,
      desktop: 147.0,
    );

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring shadow
          Container(
            width: outerSize,
            height: outerSize,
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0b1120).withOpacity(0.8),
                  offset: const Offset(6, 6),
                  blurRadius: 12,
                ),
                BoxShadow(
                  color: const Color(0xFF1e293b).withOpacity(0.8),
                  offset: const Offset(-6, -6),
                  blurRadius: 12,
                ),
              ],
            ),
          ),

          // Progress ring
          SizedBox(
            width: progressSize,
            height: progressSize,
            child: CircularProgressIndicator(
              value: 0.92, // 92%
              strokeWidth: Responsive.responsiveValue(
                context,
                mobile: 6.0,
                tablet: 7.0,
                desktop: 8.0,
              ),
              backgroundColor: const Color(0xFF1e293b),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF22d3ee),
              ),
              strokeCap: StrokeCap.round,
            ),
          ),

          // Inner circle with score
          Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              shape: BoxShape.circle,
              boxShadow: [
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '92',
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                      context,
                      mobile: 38,
                      tablet: 42,
                      desktop: 48,
                    ),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF22d3ee),
                  ),
                ),
                SizedBox(
                  height: Responsive.responsiveSpacing(
                    context,
                    mobile: 2,
                    desktop: 4,
                  ),
                ),
                Text(
                  'EXCELLENT',
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                      context,
                      mobile: 9,
                      tablet: 9.5,
                      desktop: 10,
                    ),
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

  // Quick Stats Grid (4 cards)
  Widget _buildQuickStatsGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
        mobile: 1.0,
        tablet: 1.4,
        desktop: 2.1,
      ),
      children: [
        _buildStatCard(
          context,
          icon: Icons.access_time_outlined,
          label: 'Total Drive Time',
          value: '127.5 hrs',
          subtext: 'Last 30 days',
          accent: false,
        ),
        _buildStatCard(
          context,
          icon: Icons.shield_outlined,
          label: 'Alert Triggered',
          value: '3',
          subtext: 'Last 24 hours',
          accent: true,
        ),
        _buildStatCard(
          context,
          icon: Icons.local_fire_department_outlined,
          label: 'Safety Streak',
          value: '12 days',
          subtext: 'No incidents',
          accent: false,
        ),
        _buildStatCard(
          context,
          icon: Icons.trending_up,
          label: 'Avg Alertness',
          value: '88%',
          subtext: '+2% vs last week',
          accent: false,
        ),
      ],
    );
  }

  // Individual Stat Card
  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
    required bool accent,
  }) {
    return _StatCard(
      icon: icon,
      label: label,
      value: value,
      subtext: subtext,
      accent: accent,
    );
  }

  // Alertness History Chart
  Widget _buildAlertnesChart(BuildContext context) {
    return Container(
      height: Responsive.responsiveHeight(
        context,
        mobile: 280,
        tablet: 300,
        desktop: 320,
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
            offset: Offset(10, 10),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-10, -10),
            blurRadius: 16,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 16,
          tablet: 20,
          desktop: 24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alertness History',
            style: TextStyle(
              color: const Color(0xFFcbd5e1),
              fontSize: Responsive.responsiveFont(
                context,
                mobile: 15,
                tablet: 15.5,
                desktop: 16,
              ),
              fontWeight: FontWeight.w500,
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
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
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
                        const times = [
                          '10:00',
                          '10:10',
                          '10:20',
                          '10:30',
                          '10:40',
                          '10:50',
                          '11:00',
                        ];
                        if (value.toInt() >= 0 &&
                            value.toInt() < times.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              times[value.toInt()],
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
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 10,
                      reservedSize: 40,
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
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 6,
                minY: 50,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 95),
                      FlSpot(1, 92),
                      FlSpot(2, 88),
                      FlSpot(3, 94),
                      FlSpot(4, 85),
                      FlSpot(5, 78),
                      FlSpot(6, 82),
                    ],
                    isCurved: true,
                    color: const Color(0xFF22d3ee),
                    barWidth: Responsive.responsiveValue(
                      context,
                      mobile: 2.5,
                      tablet: 2.75,
                      desktop: 3.0,
                    ),
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF22d3ee).withOpacity(0.3),
                          const Color(0xFF22d3ee).withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => const Color(0xFF0f172a),
                    tooltipRoundedRadius: 12,
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                      return touchedBarSpots.map((barSpot) {
                        return LineTooltipItem(
                          barSpot.y.toInt().toString(),
                          const TextStyle(
                            color: Color(0xFF22d3ee),
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
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

// Stateful widget for individual stat cards with hover effect
class _StatCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtext;
  final bool accent;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtext,
    required this.accent,
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
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: () {
          // Add your onTap action here if needed
          print('Card tapped: ${widget.label}');
        },
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
                    // Hovered/Pressed state - inset shadows (inverted offsets)
                    const BoxShadow(
                      color: Color(0xFF0b1120),
                      offset: Offset(-3, -3),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                    const BoxShadow(
                      color: Color(0xFF1e293b),
                      offset: Offset(3, 3),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ]
                : [
                    // Normal state - subtle raised shadows
                    const BoxShadow(
                      color: Color(0xFF0b1120),
                      offset: Offset(4, 4),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                    const BoxShadow(
                      color: Color(0xFF1e293b),
                      offset: Offset(-4, -4),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ],
          ),
          padding: EdgeInsets.all(
            Responsive.responsivePadding(
              context,
              mobile: 16,
              tablet: 18,
              desktop: 20,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon and pulse indicator row
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
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
                      color: widget.accent
                          ? const Color(0xFF22d3ee).withOpacity(0.1)
                          : const Color(0xFF1e293b),
                      borderRadius: BorderRadius.circular(
                        Responsive.responsiveBorderRadius(
                          context,
                          mobile: 10,
                          tablet: 11,
                          desktop: 12,
                        ),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: Responsive.responsiveIconSize(
                        context,
                        mobile: 20,
                        tablet: 21,
                        desktop: 22,
                      ),
                      color: widget.accent
                          ? const Color(0xFF22d3ee)
                          : const Color(0xFF64748b),
                    ),
                  ),
                  if (widget.accent)
                    Padding(
                      padding: EdgeInsets.only(
                        left: Responsive.responsiveSpacing(
                          context,
                          mobile: 10,
                          tablet: 11,
                          desktop: 12,
                        ),
                      ),
                      child: Container(
                        width: Responsive.responsiveValue(
                          context,
                          mobile: 7.0,
                          tablet: 7.5,
                          desktop: 8.0,
                        ),
                        height: Responsive.responsiveValue(
                          context,
                          mobile: 7.0,
                          tablet: 7.5,
                          desktop: 8.0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22d3ee),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF22d3ee).withOpacity(0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              // Stats content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: const Color(0xFF64748b),
                      fontSize: Responsive.responsiveFont(
                        context,
                        mobile: 12,
                        tablet: 12.5,
                        desktop: 13,
                      ),
                      fontWeight: FontWeight.w500,
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
                    widget.value,
                    style: TextStyle(
                      fontSize: Responsive.responsiveFont(
                        context,
                        mobile: 22,
                        tablet: 24,
                        desktop: 26,
                      ),
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFe2e8f0),
                    ),
                  ),
                  SizedBox(
                    height: Responsive.responsiveSpacing(
                      context,
                      mobile: 2,
                      tablet: 3,
                      desktop: 4,
                    ),
                  ),
                  Text(
                    widget.subtext,
                    style: TextStyle(
                      fontSize: Responsive.responsiveFont(
                        context,
                        mobile: 10,
                        tablet: 10.5,
                        desktop: 11,
                      ),
                      color: const Color(0xFF475569),
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