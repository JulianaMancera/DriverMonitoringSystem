import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RIVERPOD PROVIDERS

// Selected filter tab: 7, 30, or null (all time)
final analyticsFilterProvider = StateProvider<int?>((ref) => 7);

final analyticsDataProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final days = ref.watch(analyticsFilterProvider);
  return await DatabaseHelper.instance.getAnalyticsSummary(days: days);
});

// ─────────────────────────────────────────────────────────────────────────────
// ANALYTICS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(analyticsDataProvider);
    final selectedDays = ref.watch(analyticsFilterProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(selectedDays),
            Expanded(
              child: analyticsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
                ),
                error: (e, _) => const Center(
                  child: Text('Error loading analytics',
                      style: TextStyle(color: Colors.white54)),
                ),
                data: (data) => _buildContent(data),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER + FILTER TABS ──────────────────────────────────────────────────
  Widget _buildHeader(int? selectedDays) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Analytics',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF88),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF88).withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RichText(
            text: const TextSpan(
              text: 'Connected: ',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              children: [
                TextSpan(
                  text: 'USER',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Filter Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1627),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                _FilterTab(
                  label: '7 Days',
                  isSelected: selectedDays == 7,
                  onTap: () =>
                      ref.read(analyticsFilterProvider.notifier).state = 7,
                ),
                _FilterTab(
                  label: '30 Days',
                  isSelected: selectedDays == 30,
                  onTap: () =>
                      ref.read(analyticsFilterProvider.notifier).state = 30,
                ),
                _FilterTab(
                  label: 'All Time',
                  isSelected: selectedDays == null,
                  onTap: () =>
                      ref.read(analyticsFilterProvider.notifier).state = null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── SCROLLABLE CONTENT ────────────────────────────────────────────────────
  Widget _buildContent(Map<String, dynamic> data) {
    final totalSessions = data['total_sessions'] as int? ?? 0;
    final totalAlerts = data['total_alerts'] as int? ?? 0;
    final drowsinessEvents = data['drowsiness_events'] as int? ?? 0;
    final distractionEvents = data['distraction_events'] as int? ?? 0;
    final dailyTrends =
        (data['daily_trends'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
            [];
    final hourlyDist =
        (data['hourly_distribution'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
            [];

    return RefreshIndicator(
      color: const Color(0xFF00D4FF),
      backgroundColor: const Color(0xFF0D1627),
      onRefresh: () async {
        ref.invalidate(analyticsDataProvider); // ✅ now works — ref is in scope
        // Wait for the new data to load
        await ref.read(analyticsDataProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            // 4 Stat Cards
            _buildStatCards(
              totalSessions: totalSessions,
              totalAlerts: totalAlerts,
              drowsinessEvents: drowsinessEvents,
              distractionEvents: distractionEvents,
            ),

            const SizedBox(height: 20),

            // Drowsiness vs Distraction Trends
            _buildTrendsChart(dailyTrends),

            const SizedBox(height: 20),

            // Hourly Alert Distribution
            _buildHourlyChart(hourlyDist),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── STAT CARDS ────────────────────────────────────────────────────────────
  Widget _buildStatCards({
    required int totalSessions,
    required int totalAlerts,
    required int drowsinessEvents,
    required int distractionEvents,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _AnalyticsCard(
                icon: Icons.timer_outlined,
                value: '$totalSessions',
                label: 'Total Sessions',
                changePct: '+12%',
                changePositive: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AnalyticsCard(
                icon: Icons.warning_amber_outlined,
                value: '$totalAlerts',
                label: 'Total Alerts',
                changePct: '-8%',
                changePositive: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AnalyticsCard(
                icon: Icons.bedtime_outlined,
                value: '$drowsinessEvents',
                label: 'Drowsiness Events',
                changePct: '-15%',
                changePositive: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AnalyticsCard(
                icon: Icons.visibility_off_outlined,
                value: '$distractionEvents',
                label: 'Distraction Events',
                changePct: '+5%',
                changePositive: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── TRENDS LINE CHART ─────────────────────────────────────────────────────
  Widget _buildTrendsChart(List<Map<String, dynamic>> dailyTrends) {
    List<FlSpot> drowsySpots = [];
    List<FlSpot> distractedSpots = [];

    if (dailyTrends.isEmpty) {
      drowsySpots = [
        const FlSpot(0, 8), const FlSpot(1, 5), const FlSpot(2, 10),
        const FlSpot(3, 7), const FlSpot(4, 6), const FlSpot(5, 4),
        const FlSpot(6, 3),
      ];
      distractedSpots = [
        const FlSpot(0, 4), const FlSpot(1, 5), const FlSpot(2, 6),
        const FlSpot(3, 5), const FlSpot(4, 4), const FlSpot(5, 3),
        const FlSpot(6, 2),
      ];
    } else {
      for (int i = 0; i < dailyTrends.length; i++) {
        drowsySpots.add(FlSpot(
          i.toDouble(),
          (dailyTrends[i]['drowsy_count'] as int? ?? 0).toDouble(),
        ));
        distractedSpots.add(FlSpot(
          i.toDouble(),
          (dailyTrends[i]['distracted_count'] as int? ?? 0).toDouble(),
        ));
      }
    }

    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Drowsiness vs Distraction Trends',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Legend
          Row(
            children: [
              _LegendDot(color: const Color(0xFFFF4444), label: 'Drowsiness'),
              const SizedBox(width: 16),
              _LegendDot(color: const Color(0xFFFFB800), label: 'Distraction'),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 5,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= dayLabels.length) {
                          return const SizedBox();
                        }
                        return Text(
                          dayLabels[idx],
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: 20,
                lineBarsData: [
                  LineChartBarData(
                    spots: drowsySpots,
                    isCurved: true,
                    color: const Color(0xFFFF4444),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: const Color(0xFFFF4444),
                        strokeWidth: 0,
                      ),
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                  LineChartBarData(
                    spots: distractedSpots,
                    isCurved: true,
                    color: const Color(0xFFFFB800),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: const Color(0xFFFFB800),
                        strokeWidth: 0,
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

  // ── HOURLY BAR CHART ──────────────────────────────────────────────────────
  Widget _buildHourlyChart(List<Map<String, dynamic>> hourlyDist) {
    final hourLabels = ['6AM', '9AM', '12PM', '3PM', '6PM', '9PM'];
    final hourValues = [6, 9, 12, 15, 18, 21];

    List<BarChartGroupData> barGroups = [];

    if (hourlyDist.isEmpty) {
      final placeholders = [2, 7, 5, 9, 12, 6];
      for (int i = 0; i < hourLabels.length; i++) {
        barGroups.add(_buildBarGroup(i, placeholders[i].toDouble()));
      }
    } else {
      final hourMap = <int, int>{};
      for (final row in hourlyDist) {
        hourMap[row['hour'] as int] = row['count'] as int;
      }
      for (int i = 0; i < hourValues.length; i++) {
        final count = hourMap[hourValues[i]] ?? 0;
        barGroups.add(_buildBarGroup(i, count.toDouble()));
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hourly Alert Distribution',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 15,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 5,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= hourLabels.length) {
                          return const SizedBox();
                        }
                        return Text(
                          hourLabels[idx],
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
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

  BarChartGroupData _buildBarGroup(int x, double value) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: value,
          width: 28,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(6),
          ),
          gradient: const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xFF0066FF), Color(0xFF00D4FF)],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00D4FF).withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF00D4FF).withOpacity(0.4),
                    width: 1,
                  )
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? const Color(0xFF00D4FF) : Colors.white38,
              fontSize: 13,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String changePct;
  final bool changePositive;

  const _AnalyticsCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.changePct,
    required this.changePositive,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor = changePositive
        ? const Color(0xFF00FF88)
        : const Color(0xFFFF4444);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white54, size: 18),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: changeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      changePositive
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      color: changeColor,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      changePct,
                      style: TextStyle(
                        color: changeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}