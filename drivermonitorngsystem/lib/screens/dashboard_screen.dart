import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RIVERPOD PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

final dashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return await DatabaseHelper.instance.getDashboardSummary();
});

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN
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
    // Auto-refresh every 30 seconds
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

    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: dashAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF00D4FF),
                  ),
                ),
                error: (e, _) => Center(
                  child: Text('Error loading data',
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

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Dashboard',
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
          const SizedBox(height: 12),
          // Cyan progress bar
          Container(
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF0066FF)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── SCROLLABLE CONTENT ────────────────────────────────────────────────────
  Widget _buildContent(Map<String, dynamic> data) {
    final safetyScore = (data['safety_score'] as double? ?? 0.0);
    final totalDriveHrs = (data['total_drive_hrs'] as double? ?? 0.0);
    final alertsLast24h = (data['alerts_last_24h'] as int? ?? 0);
    final safetyStreak = (data['safety_streak_days'] as int? ?? 0);
    final avgAlertness = (data['avg_alertness_pct'] as double? ?? 0.0);
    final snapshots =
        (data['alertness_snapshots'] as List<Map<String, dynamic>>?) ?? [];

    // Determine score label
    String scoreLabel = 'EXCELLENT';
    if (safetyScore < 60) scoreLabel = 'POOR';
    else if (safetyScore < 75) scoreLabel = 'FAIR';
    else if (safetyScore < 90) scoreLabel = 'GOOD';

    return RefreshIndicator(
      color: const Color(0xFF00D4FF),
      backgroundColor: const Color(0xFF0D1627),
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // Safety Score Gauge
            _buildSafetyGauge(safetyScore, scoreLabel),

            const SizedBox(height: 20),

            // 4 Stat Cards
            _buildStatCards(
              totalDriveHrs: totalDriveHrs,
              alertsLast24h: alertsLast24h,
              safetyStreak: safetyStreak,
              avgAlertness: avgAlertness,
            ),

            const SizedBox(height: 20),

            // Alertness History Chart
            _buildAlertnessChart(snapshots),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── SAFETY GAUGE ──────────────────────────────────────────────────────────
  Widget _buildSafetyGauge(double score, String label) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          const Text(
            'SAFETY SCORE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              letterSpacing: 2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 12,
                    backgroundColor: Colors.white.withOpacity(0.06),
                    valueColor: const AlwaysStoppedAnimation(Colors.transparent),
                  ),
                ),
                // Score arc
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF00D4FF)),
                  ),
                ),
                // Score text
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      score.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Color(0xFF00D4FF),
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STAT CARDS ─────────────────────────────────────────────────────────────
  Widget _buildStatCards({
    required double totalDriveHrs,
    required int alertsLast24h,
    required int safetyStreak,
    required double avgAlertness,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.schedule_rounded,
                title: 'Total Drive Time',
                value: '${totalDriveHrs.toStringAsFixed(1)} hrs',
                subtitle: 'Last 30 days',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.shield_outlined,
                title: 'Alert Triggered',
                value: '$alertsLast24h',
                subtitle: 'Last 24 hours',
                hasIndicator: alertsLast24h > 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.local_fire_department_rounded,
                title: 'Safety Streak',
                value: '$safetyStreak days',
                subtitle: safetyStreak > 0 ? 'No incidents' : 'Stay alert!',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.trending_up_rounded,
                title: 'Avg Alertness',
                value: '${avgAlertness.toStringAsFixed(0)}%',
                subtitle: 'Last 7 days',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── ALERTNESS HISTORY CHART ───────────────────────────────────────────────
  Widget _buildAlertnessChart(List<Map<String, dynamic>> snapshots) {
    // Build chart spots from snapshots
    List<FlSpot> spots = [];
    if (snapshots.isEmpty) {
      // Placeholder data when no sessions yet
      spots = [
        const FlSpot(0, 85),
        const FlSpot(1, 90),
        const FlSpot(2, 88),
        const FlSpot(3, 92),
        const FlSpot(4, 85),
        const FlSpot(5, 80),
        const FlSpot(6, 83),
      ];
    } else {
      for (int i = 0; i < snapshots.length; i++) {
        spots.add(FlSpot(
          i.toDouble(),
          (snapshots[i]['alertness_pct'] as double? ?? 0.0),
        ));
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
            'Alertness History',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 10,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: false,
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: 50,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF00D4FF),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF00D4FF).withOpacity(0.25),
                          const Color(0xFF00D4FF).withOpacity(0.0),
                        ],
                      ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE STAT CARD WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool hasIndicator;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.hasIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
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
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white54, size: 18),
              ),
              if (hasIndicator) ...[
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00D4FF),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}