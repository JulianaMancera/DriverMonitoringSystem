import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Top section with Safety Score + Stats
            LayoutBuilder(
              builder: (context, constraints) {
                if (isMobile) {
                  // Mobile: Stack vertically
                  return Column(
                    children: [
                      _buildSafetyScoreCard(),
                      const SizedBox(height: 32),
                      _buildQuickStatsGrid(),
                    ],
                  );
                } else {
                  // Desktop: Side by side
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: _buildSafetyScoreCard()),
                      const SizedBox(width: 32),
                      Expanded(flex: 8, child: _buildQuickStatsGrid()),
                    ],
                  );
                }
              },
            ),

            const SizedBox(height: 32),

            // Chart section
            _buildAlertnesChart(),

            SizedBox(
              height: isMobile ? 96 : 32,
            ), // Extra padding for mobile bottom nav
          ],
        ),
      ),
    );
  }

  // Safety Score Card (the circular score display)
  Widget _buildSafetyScoreCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(24),
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
              height: 8,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
            ),
          ),

         // Main content
          Center ( 
            child: Padding(
            padding: const EdgeInsets.all(87),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'SAFETY SCORE',
                  style: TextStyle(
                    color: Color(0xFF94a3b8),
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // Circular score indicator
                SizedBox(
                  width: 195,
                  height: 195,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring shadow
                      Container(
                        width: 195,
                        height: 195,
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
                        width: 179,
                        height: 179,
                        child: CircularProgressIndicator(
                          value: 0.92, // 92%
                          strokeWidth: 8,
                          backgroundColor: const Color(0xFF1e293b),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF22d3ee),
                          ),
                          strokeCap: StrokeCap.round,
                        ),
                      ),

                      // Inner circle with score
                      Container(
                        width: 147,
                        height: 147,
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
                          children: const [
                            Text(
                              '92',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF22d3ee),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'EXCELLENT',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748b),
                                letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Quick Stats Grid (4 cards)
  Widget _buildQuickStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 24,
      crossAxisSpacing: 24,
      childAspectRatio: 2.1,
      children: [
        _buildStatCard(
          icon: Icons.access_time_outlined,
          label: 'Total Drive Time',
          value: '127.5 hrs',
          subtext: 'Last 30 days',
          accent: false,
        ),
        _buildStatCard(
          icon: Icons.shield_outlined,
          label: 'Alert Triggered',
          value: '3',
          subtext: 'Last 24 hours',
          accent: true,
        ),
        _buildStatCard(
          icon: Icons.local_fire_department_outlined,
          label: 'Safety Streak',
          value: '12 days',
          subtext: 'No incidents',
          accent: false,
        ),
        _buildStatCard(
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
  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
    required bool accent,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(20),
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
      
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon and pulse indicator row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent
                      ? const Color(0xFF22d3ee).withOpacity(0.1)
                      : const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: accent
                      ? const Color(0xFF22d3ee)
                      : const Color(0xFF64748b),
                ),
              ),
              if (accent)
                Container(
                  width: 8,
                  height: 8,
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
            ],
          ),

          // Stats content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF64748b),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFe2e8f0),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtext,
                style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Alertness History Chart
  Widget _buildAlertnesChart() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(24),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alertness History',
            style: TextStyle(
              color: Color(0xFFcbd5e1),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
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
                              style: const TextStyle(
                                color: Color(0xFF64748b),
                                fontSize: 12,
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
                          style: const TextStyle(
                            color: Color(0xFF64748b),
                            fontSize: 12,
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
                    barWidth: 3,
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
