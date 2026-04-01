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
              _filterBtn('7 Days',   selectedDays == 7,    () => ref.read(analyticsFilterProvider.notifier).state = 7),
              const SizedBox(width: 4),
              _filterBtn('30 Days',  selectedDays == 30,   () => ref.read(analyticsFilterProvider.notifier).state = 30),
              const SizedBox(width: 4),
              _filterBtn('All Time', selectedDays == null, () => ref.read(analyticsFilterProvider.notifier).state = null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterBtn(String label, bool isSelected, VoidCallback onTap) {
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

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> data,
    bool isMobile,
    bool isTablet,
  ) {
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
            _buildSummaryCards(context,
              isMobile: isMobile, isTablet: isTablet,
              totalSessions: totalSessions, totalAlerts: totalAlerts,
              drowsinessEvents: drowsinessEvents, distractionEvents: distractionEvents,
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

  Widget _buildSummaryCards(BuildContext context, {
    required bool isMobile, required bool isTablet,
    required int totalSessions, required int totalAlerts,
    required int drowsinessEvents, required int distractionEvents,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount:   isMobile ? 2 : 4,
        mainAxisSpacing:  Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
        crossAxisSpacing: Responsive.responsiveSpacing(context, mobile: 12, tablet: 14, desktop: 16),
        childAspectRatio: Responsive.responsiveValue(context,   mobile: 0.95, tablet: 1.2, desktop: 1.5),
        children: [
          _HoverableSummaryCard(icon: Icons.timer_outlined,          label: 'Total Sessions',     value: '$totalSessions',     isPositive: true),
          _HoverableSummaryCard(icon: Icons.warning_amber_outlined,  label: 'Total Alerts',       value: '$totalAlerts',       isPositive: totalAlerts == 0),
          _HoverableSummaryCard(icon: Icons.bedtime_outlined,        label: 'Drowsiness Events',  value: '$drowsinessEvents',  isPositive: drowsinessEvents == 0),
          _HoverableSummaryCard(icon: Icons.visibility_off_outlined, label: 'Distraction Events', value: '$distractionEvents', isPositive: distractionEvents == 0),
        ],
      ),
    );
  }

  // ── CHART LAYOUTS ─────────────────────────────────────────────────────────

  Widget _buildMobileChartsLayout(
    BuildContext context,
    List<Map<String, dynamic>> dailyTrends,
    List<Map<String, dynamic>> hourlyDist,
  ) {
    return Column(children: [
      _buildLineChartCard(context, dailyTrends),
      SizedBox(height: Responsive.responsiveSpacing(context, mobile: 24, tablet: 28, desktop: 32)),
      _buildBarChartCard(context, hourlyDist),
    ]);
  }

  Widget _buildDesktopChartsLayout(
    BuildContext context,
    List<Map<String, dynamic>> dailyTrends,
    List<Map<String, dynamic>> hourlyDist,
  ) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 6, child: _buildLineChartCard(context, dailyTrends)),
      SizedBox(width: Responsive.responsiveSpacing(context, mobile: 16, tablet: 24, desktop: 32)),
      Expanded(flex: 4, child: _buildBarChartCard(context, hourlyDist)),
    ]);
  }

  // ── LINE CHART CARD ───────────────────────────────────────────────────────

  Widget _buildLineChartCard(BuildContext context, List<Map<String, dynamic>> dailyTrends) {
    final parsed = _parseLineChartData(dailyTrends);

    return GestureDetector(
      onTap: () => _openLineChartModal(context, dailyTrends, parsed),
      child: Container(
        // FIX: explicit fixed height on the card — no Expanded here
        height: 300,
        clipBehavior: Clip.antiAlias,
        decoration: _cardDecoration(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chartCardHeader('Drowsiness vs Distraction Trends'),
            const SizedBox(height: 8),
            Row(children: [
              _legendDot('Drowsiness', const Color(0xFFef4444)),
              const SizedBox(width: 12),
              _legendDot('Distraction', const Color(0xFFfbbf24)),
            ]),
            const SizedBox(height: 12),
            // FIX: Expanded is valid here because its parent Column is
            // inside a Container with a fixed height (300) — bounded.
            Expanded(
              child: _LineChartWidget(
                drowsySpots:     parsed.drowsySpots,
                distractedSpots: parsed.distractedSpots,
                xLabels:         parsed.xLabels,
                maxX:            parsed.maxX,
                maxY:            parsed.maxY,
                yInterval:       parsed.yInterval,
                labelFontSize:   9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BAR CHART CARD ────────────────────────────────────────────────────────

  Widget _buildBarChartCard(BuildContext context, List<Map<String, dynamic>> hourlyDist) {
    return GestureDetector(
      onTap: () => _openBarChartModal(context, hourlyDist),
      child: Container(
        // FIX: same pattern — explicit fixed height, Expanded valid inside it
        height: 300,
        clipBehavior: Clip.antiAlias,
        decoration: _cardDecoration(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chartCardHeader('Hourly Alert Distribution'),
            const SizedBox(height: 16),
            Expanded(
              child: _BarChartWidget(hourlyDist: hourlyDist, labelFontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartCardHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFcbd5e1)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF22d3ee).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF22d3ee).withValues(alpha: 0.25)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.open_in_full_rounded, color: Color(0xFF22d3ee), size: 11),
            SizedBox(width: 4),
            Text('Expand', style: TextStyle(color: Color(0xFF22d3ee), fontSize: 9, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    );
  }

  // ── MODAL — LINE CHART ────────────────────────────────────────────────────

  void _openLineChartModal(
    BuildContext context,
    List<Map<String, dynamic>> dailyTrends,
    _LineChartData parsed,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _ChartModal(
        title:    'Drowsiness vs Distraction',
        subtitle: 'Tap a point to see value',
        // FIX: _ChartModal takes a builder so Expanded is always inside
        // a Column that is inside a Container with bounded height.
        chartBuilder: (height) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _legendDot('Drowsiness', const Color(0xFFef4444)),
              const SizedBox(width: 16),
              _legendDot('Distraction', const Color(0xFFfbbf24)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: height - 80, // bounded height for the chart
              child: _LineChartWidget(
                drowsySpots:     parsed.drowsySpots,
                distractedSpots: parsed.distractedSpots,
                xLabels:         parsed.xLabels,
                maxX:            parsed.maxX,
                maxY:            parsed.maxY,
                yInterval:       parsed.yInterval,
                labelFontSize:   12,
              ),
            ),
            const SizedBox(height: 16),
            if (dailyTrends.isNotEmpty) _buildLineSummaryRow(parsed),
          ],
        ),
      ),
    );
  }

  // ── MODAL — BAR CHART ─────────────────────────────────────────────────────

  void _openBarChartModal(BuildContext context, List<Map<String, dynamic>> hourlyDist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _ChartModal(
        title:    'Hourly Alert Distribution',
        subtitle: 'Alerts grouped by hour of day',
        chartBuilder: (height) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: height - 80,
              child: _BarChartWidget(hourlyDist: hourlyDist, labelFontSize: 12),
            ),
            const SizedBox(height: 16),
            if (hourlyDist.isNotEmpty) _buildBarSummaryRow(hourlyDist),
          ],
        ),
      ),
    );
  }

  // ── SUMMARY ROWS ──────────────────────────────────────────────────────────

  Widget _buildLineSummaryRow(_LineChartData parsed) {
    final totalDrowsy     = parsed.drowsySpots.fold(0.0,     (s, x) => s + x.y).toInt();
    final totalDistracted = parsed.distractedSpots.fold(0.0, (s, x) => s + x.y).toInt();
    final peak = parsed.drowsySpots.isEmpty ? 0
        : parsed.drowsySpots.reduce((a, b) => a.y > b.y ? a : b).y.toInt();

    return Row(children: [
      _summaryPill('Total Drowsy',     '$totalDrowsy',   const Color(0xFFef4444)),
      const SizedBox(width: 8),
      _summaryPill('Total Distracted', '$totalDistracted', const Color(0xFFfbbf24)),
      const SizedBox(width: 8),
      _summaryPill('Peak Day',         '$peak alerts',   const Color(0xFF22d3ee)),
    ]);
  }

  Widget _buildBarSummaryRow(List<Map<String, dynamic>> hourlyDist) {
    int total = 0; int peakHour = 0; int peakCount = 0;
    for (final row in hourlyDist) {
      final h = row['hour']  as int;
      final c = row['count'] as int;
      total += c;
      if (c > peakCount) { peakCount = c; peakHour = h; }
    }
    final ampm = peakHour >= 12 ? 'PM' : 'AM';
    final h12  = peakHour > 12 ? peakHour - 12 : (peakHour == 0 ? 12 : peakHour);

    return Row(children: [
      _summaryPill('Total Alerts', '$total',          const Color(0xFF22d3ee)),
      const SizedBox(width: 8),
      _summaryPill('Peak Hour',    '$h12:00 $ampm',   const Color(0xFFfbbf24)),
      const SizedBox(width: 8),
      _summaryPill('Peak Count',   '$peakCount',      const Color(0xFFef4444)),
    ]);
  }

  Widget _summaryPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,  style: const TextStyle(color: Color(0xFF64748b), fontSize: 10)),
        ]),
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  _LineChartData _parseLineChartData(List<Map<String, dynamic>> dailyTrends) {
    List<FlSpot> drowsySpots;
    List<FlSpot> distractedSpots;
    List<String> xLabels;

    if (dailyTrends.isEmpty) {
      drowsySpots = distractedSpots = List.generate(7, (i) => FlSpot(i.toDouble(), 0));
      xLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    } else {
      drowsySpots = []; distractedSpots = []; xLabels = [];
      for (int i = 0; i < dailyTrends.length; i++) {
        drowsySpots.add(FlSpot(i.toDouble(), (dailyTrends[i]['drowsy_count']     as int? ?? 0).toDouble()));
        distractedSpots.add(FlSpot(i.toDouble(), (dailyTrends[i]['distracted_count'] as int? ?? 0).toDouble()));
        xLabels.add(_shortDate(dailyTrends[i]['date'] as String? ?? ''));
      }
    }

    final double maxX      = (drowsySpots.length - 1).toDouble().clamp(1, double.infinity);
    double dataMaxY = 5;
    for (final s in [...drowsySpots, ...distractedSpots]) {
      if (s.y > dataMaxY) dataMaxY = s.y;
    }
    final double maxY      = ((dataMaxY / 5).ceil() * 5).toDouble();
    final double yInterval = maxY <= 10 ? 2 : maxY <= 20 ? 5 : 10;

    return _LineChartData(
      drowsySpots: drowsySpots, distractedSpots: distractedSpots,
      xLabels: xLabels, maxX: maxX, maxY: maxY, yInterval: yInterval,
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 11)),
    ]);
  }

  String _shortDate(String iso) {
    if (iso.length < 10) return iso;
    try {
      final d = DateTime.parse(iso);
      const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${mo[d.month - 1]} ${d.day}';
    } catch (_) {
      return iso.length >= 7 ? iso.substring(5) : iso;
    }
  }

  BoxDecoration _cardDecoration() {
    return const BoxDecoration(
      color: Color(0xFF0f172a),
      borderRadius: BorderRadius.all(Radius.circular(20)),
      boxShadow: [
        BoxShadow(color: Color(0xFF0b1120), offset: Offset(8, 8),   blurRadius: 16),
        BoxShadow(color: Color(0xFF1e293b), offset: Offset(-8, -8), blurRadius: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASS
// ─────────────────────────────────────────────────────────────────────────────

class _LineChartData {
  final List<FlSpot> drowsySpots;
  final List<FlSpot> distractedSpots;
  final List<String> xLabels;
  final double maxX, maxY, yInterval;

  const _LineChartData({
    required this.drowsySpots, required this.distractedSpots,
    required this.xLabels, required this.maxX,
    required this.maxY,    required this.yInterval,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// LINE CHART WIDGET
// Stateless — receives all data, renders LineChart directly.
// Must always be placed inside a SizedBox or Container with bounded height,
// OR inside an Expanded that itself is inside a bounded Column.
// ─────────────────────────────────────────────────────────────────────────────

class _LineChartWidget extends StatelessWidget {
  final List<FlSpot> drowsySpots;
  final List<FlSpot> distractedSpots;
  final List<String> xLabels;
  final double maxX, maxY, yInterval, labelFontSize;

  const _LineChartWidget({
    required this.drowsySpots,
    required this.distractedSpots,
    required this.xLabels,
    required this.maxX,
    required this.maxY,
    required this.yInterval,
    required this.labelFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        clipData: const FlClipData.all(),
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
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.round();
                if (idx < 0 || idx >= xLabels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(xLabels[idx],
                    style: TextStyle(color: const Color(0xFF64748b), fontSize: labelFontSize - 1)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yInterval,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == maxY) return const SizedBox.shrink();
                return Text(value.toInt().toString(),
                  style: TextStyle(color: const Color(0xFF64748b), fontSize: labelFontSize - 1));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0, maxX: maxX,
        minY: 0, maxY: maxY,
        lineBarsData: [
          _bar(drowsySpots,     const Color(0xFFef4444)),
          _bar(distractedSpots, const Color(0xFFfbbf24)),
        ],
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1e293b),
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              '${s.y.toInt()} ${s.barIndex == 0 ? "drowsy" : "distracted"}',
              TextStyle(
                color: s.barIndex == 0 ? const Color(0xFFef4444) : const Color(0xFFfbbf24),
                fontWeight: FontWeight.bold,
                fontSize: labelFontSize,
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  LineChartBarData _bar(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: spots.length > 2,
      curveSmoothness: 0.3,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
          radius: 4, color: color, strokeWidth: 2, strokeColor: const Color(0xFF0f172a),
        ),
      ),
      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.07)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BAR CHART WIDGET
// Same rule: must be inside a bounded SizedBox / Container / Expanded.
// ─────────────────────────────────────────────────────────────────────────────

class _BarChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> hourlyDist;
  final double labelFontSize;

  const _BarChartWidget({required this.hourlyDist, required this.labelFontSize});

  static const _labels = ['6AM', '9AM', '12PM', '3PM', '6PM', '9PM'];
  static const _hours  = [6, 9, 12, 15, 18, 21];

  @override
  Widget build(BuildContext context) {
    final hourMap = <int, int>{};
    for (final row in hourlyDist) {
      hourMap[row['hour'] as int] = row['count'] as int;
    }

    final barGroups = List.generate(_hours.length, (i) {
      final y = (_hourMap(hourMap, i)).toDouble();
      return BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: y,
          width: 18,
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(
            colors: [Color(0xFF22d3ee), Color(0xFF3b82f6)],
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
          ),
        ),
      ]);
    });

    double dataMaxY = 5;
    for (final g in barGroups) { if (g.barRods.first.toY > dataMaxY) dataMaxY = g.barRods.first.toY; }
    final double maxY      = ((dataMaxY / 5).ceil() * 5).toDouble();
    final double yInterval = maxY <= 10 ? 2 : maxY <= 20 ? 5 : 10;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1e293b),
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${rod.toY.toInt()} alert${rod.toY.toInt() == 1 ? '' : 's'}\n${_labels[group.x]}',
              TextStyle(color: const Color(0xFF22d3ee), fontWeight: FontWeight.bold, fontSize: labelFontSize),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= _labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_labels[idx],
                    style: TextStyle(color: const Color(0xFF64748b), fontSize: labelFontSize - 1)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 28, interval: yInterval,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == maxY) return const SizedBox.shrink();
                return Text(value.toInt().toString(),
                  style: TextStyle(color: const Color(0xFF64748b), fontSize: labelFontSize - 1));
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true, drawVerticalLine: false, horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: const Color(0xFF1e293b), strokeWidth: 1, dashArray: [3, 3],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
      ),
    );
  }

  int _hourMap(Map<int, int> map, int i) => map[_hours[i]] ?? 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART MODAL BOTTOM SHEET
// FIX: uses a builder pattern (chartBuilder) so the chart always receives
// an explicit bounded height — eliminating the unbounded height error.
// ─────────────────────────────────────────────────────────────────────────────

class _ChartModal extends StatelessWidget {
  final String title;
  final String subtitle;
  // Builder receives the available chart area height (double) and returns
  // a Column containing a SizedBox(height: ...) wrapping the chart.
  // This guarantees the chart always has a bounded, explicit height.
  final Widget Function(double availableHeight) chartBuilder;

  const _ChartModal({
    required this.title,
    required this.subtitle,
    required this.chartBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Sheet takes 85% of screen height
    final sheetHeight = MediaQuery.of(context).size.height * 0.85;
    // Header area: drag handle (28) + top padding (12) + header row (~56) + divider (20) + bottom pad (20)
    const headerHeight = 136.0;
    final chartAreaHeight = sheetHeight - headerHeight;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1627),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2D45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                    style: const TextStyle(color: Color(0xFF6B7A99), fontSize: 12)),
                ],
              )),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2235), shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1E2D45)),
                  ),
                  child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                ),
              ),
            ]),
          ),

          Divider(color: const Color(0xFF1E2D45).withValues(alpha: 0.6), height: 20),

          // Chart body — receives explicit bounded height via chartBuilder
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: chartBuilder(chartAreaHeight),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOVERABLE SUMMARY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _HoverableSummaryCard extends StatefulWidget {
  final IconData icon;
  final String label, value;
  final bool isPositive;

  const _HoverableSummaryCard({
    required this.icon, required this.label,
    required this.value, required this.isPositive,
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
        padding: EdgeInsets.all(
            Responsive.responsivePadding(context, mobile: 12, tablet: 16, desktop: 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(
                      Responsive.responsivePadding(context, mobile: 8, tablet: 9, desktop: 10)),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1e293b), borderRadius: BorderRadius.circular(10)),
                  child: Icon(widget.icon,
                    size: Responsive.responsiveIconSize(context, mobile: 18, tablet: 20, desktop: 24),
                    color: const Color(0xFF22d3ee)),
                ),
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
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}