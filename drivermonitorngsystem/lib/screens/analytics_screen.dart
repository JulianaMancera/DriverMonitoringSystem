import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../utils/responsive.dart';
// FIX #11: import the sidebar width constant so both files use the same value
import '../constants/layout_constants.dart';

// ─── PROVIDERS ────────────────────────────────────────────────────────────────
final analyticsFilterProvider = StateProvider<int?>((ref) => 7);

final analyticsDataProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  ref.watch(dbChangeCounterProvider);
  final days = ref.watch(analyticsFilterProvider);
  return DatabaseHelper.instance.getAnalyticsSummary(days: days);
});

// ─────────────────────────────────────────────────────────────────────────────
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(analyticsDataProvider);
    final selDays = ref.watch(analyticsFilterProvider);
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);

    // FIX #9: Sticky filter tabs — the tab row lives OUTSIDE the scrollable
    // content (above the Expanded) so it never scrolls away.
    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Pinned filter tabs ──────────────────────────────────────────────
          _FilterTabs(selectedDays: selDays, ref: ref),

          // ── Scrollable content ──────────────────────────────────────────────
          Expanded(
            child: asyncData.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF22d3ee)),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              data: (data) =>
                  _Content(data: data, isMobile: isMobile, isTablet: isTablet),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PINNED FILTER TABS ────────────────────────────────────────────────────────
class _FilterTabs extends StatelessWidget {
  final int? selectedDays;
  final WidgetRef ref;
  const _FilterTabs({required this.selectedDays, required this.ref});

  @override
  Widget build(BuildContext context) {
    final hPad = MediaQuery.of(context).size.width * 0.05;
    final vPad = MediaQuery.of(context).size.height * 0.02;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad * 0.75),
      child: Container(
        padding: const EdgeInsets.all(4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(
            MediaQuery.of(context).size.width * 0.04,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFF0b1120),
              offset: Offset(4, 4),
              blurRadius: 8,
            ),
            BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-4, -4),
              blurRadius: 8,
            ),
          ],
        ),
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tab(
                context,
                '7 Days',
                selectedDays == 7,
                () => ref.read(analyticsFilterProvider.notifier).state = 7,
              ),
              SizedBox(width: MediaQuery.of(context).size.width * 0.01),
              _tab(
                context,
                '30 Days',
                selectedDays == 30,
                () => ref.read(analyticsFilterProvider.notifier).state = 30,
              ),
              SizedBox(width: MediaQuery.of(context).size.width * 0.01),
              _tab(
                context,
                'All Time',
                selectedDays == null,
                () => ref.read(analyticsFilterProvider.notifier).state = null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext ctx, String label, bool sel, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ctx.rp(12)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.responsivePadding(
              ctx,
              mobile: 14,
              tablet: 16,
              desktop: 18,
            ),
            vertical: Responsive.responsivePadding(
              ctx,
              mobile: 8,
              tablet: 9,
              desktop: 10,
            ),
          ),
          decoration: BoxDecoration(
            color: sel ? const Color(0xFF1e293b) : Colors.transparent,
            borderRadius: BorderRadius.circular(ctx.rp(12)),
            boxShadow: sel
                ? [
                    const BoxShadow(
                      color: Color(0xFF0b1120),
                      offset: Offset(2, 2),
                      blurRadius: 4,
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: Responsive.responsiveFont(
                ctx,
                mobile: 12,
                tablet: 13,
                desktop: 14,
              ),
              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              color: sel ? const Color(0xFF22d3ee) : const Color(0xFF64748b),
            ),
          ),
        ),
      );
}

// ── SCROLLABLE CONTENT ────────────────────────────────────────────────────────
class _Content extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMobile, isTablet;
  const _Content({
    required this.data,
    required this.isMobile,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = data['total_sessions'] as int? ?? 0;
    final alerts = data['total_alerts'] as int? ?? 0;
    final drowsy = data['drowsiness_events'] as int? ?? 0;
    final distracted = data['distraction_events'] as int? ?? 0;
    final dailyTrends =
        (data['daily_trends'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final hourlyDist =
        (data['hourly_distribution'] as List?)?.cast<Map<String, dynamic>>() ??
        [];

    return RefreshIndicator(
      color: const Color(0xFF22d3ee),
      backgroundColor: const Color(0xFF0f172a),
      onRefresh: () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            _SummaryCards(
              isMobile: isMobile,
              isTablet: isTablet,
              sessions: sessions,
              alerts: alerts,
              drowsy: drowsy,
              distracted: distracted,
            ),
            SizedBox(
              height: Responsive.responsiveSpacing(
                context,
                mobile: 24,
                tablet: 28,
                desktop: 32,
              ),
            ),
            // Charts
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.05,
              ),
              child: isMobile || isTablet
                  ? _mobileCharts(context, dailyTrends, hourlyDist)
                  : _desktopCharts(context, dailyTrends, hourlyDist),
            ),
            SizedBox(height: context.rs(16)),
          ],
        ),
      ),
    );
  }

  Widget _mobileCharts(
    BuildContext ctx,
    List<Map<String, dynamic>> trends,
    List<Map<String, dynamic>> hourly,
  ) => Column(
    children: [
      _LineCard(dailyTrends: trends),
      SizedBox(
        height: Responsive.responsiveSpacing(
          ctx,
          mobile: 24,
          tablet: 28,
          desktop: 32,
        ),
      ),
      _BarCard(hourlyDist: hourly),
    ],
  );

  Widget _desktopCharts(
    BuildContext ctx,
    List<Map<String, dynamic>> trends,
    List<Map<String, dynamic>> hourly,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 6, child: _LineCard(dailyTrends: trends)),
      SizedBox(
        width: Responsive.responsiveSpacing(
          ctx,
          mobile: 16,
          tablet: 24,
          desktop: 32,
        ),
      ),
      Expanded(flex: 4, child: _BarCard(hourlyDist: hourly)),
    ],
  );
}

// ── SUMMARY CARDS ─────────────────────────────────────────────────────────────
class _SummaryCards extends StatelessWidget {
  final bool isMobile, isTablet;
  final int sessions, alerts, drowsy, distracted;
  const _SummaryCards({
    required this.isMobile,
    required this.isTablet,
    required this.sessions,
    required this.alerts,
    required this.drowsy,
    required this.distracted,
  });

  double _aspect(BuildContext ctx) {
    final landscape = MediaQuery.of(ctx).orientation == Orientation.landscape;
    if (!landscape) {
      return Responsive.responsiveValue(
        ctx,
        mobile: 0.95,
        tablet: 1.2,
        desktop: 1.5,
      );
    }
    // FIX #11: use the same sidebar width constant as main.dart
    const sbW = kSidebarWidth;
    final w = MediaQuery.of(ctx).size.width - sbW - 40 - 36;
    return (w / 4 / 115).clamp(1.2, 3.0);
  }

  @override
  Widget build(BuildContext ctx) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.of(ctx).size.width * 0.05,
    ),
    child: GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : 4,
      mainAxisSpacing: Responsive.responsiveSpacing(
        ctx,
        mobile: 12,
        tablet: 14,
        desktop: 16,
      ),
      crossAxisSpacing: Responsive.responsiveSpacing(
        ctx,
        mobile: 12,
        tablet: 14,
        desktop: 16,
      ),
      childAspectRatio: _aspect(ctx),
      children: [
        _StatCard(
          icon: Icons.timer_outlined,
          label: 'Total Sessions',
          value: '$sessions',
          positive: true,
        ),
        _StatCard(
          icon: Icons.warning_amber_outlined,
          label: 'Total Alerts',
          value: '$alerts',
          positive: alerts == 0,
        ),
        _StatCard(
          icon: Icons.bedtime_outlined,
          label: 'Drowsiness',
          value: '$drowsy',
          positive: drowsy == 0,
        ),
        _StatCard(
          icon: Icons.visibility_off_outlined,
          label: 'Distraction',
          value: '$distracted',
          positive: distracted == 0,
        ),
      ],
    ),
  );
}

// ── LINE CHART CARD ───────────────────────────────────────────────────────────
/// FIX #8: Chart is wrapped in a horizontal SingleChildScrollView with
/// minPointSpacing = 40 px per data point.  30-day data (30 points) now
/// spreads across 1200 px instead of squashing into the card width.
class _LineCard extends StatelessWidget {
  final List<Map<String, dynamic>> dailyTrends;
  const _LineCard({required this.dailyTrends});

  @override
  Widget build(BuildContext context) {
    final parsed = _parse();
    return GestureDetector(
      onTap: () => _modal(context, parsed),
      child: Container(
        height: Responsive.responsiveHeight(
          context,
          mobile: 300,
          tablet: 320,
          desktop: 340,
        ),
        decoration: _cardDecor(),
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
              'Drowsiness vs Distraction Trends',
              style: TextStyle(
                fontSize: context.sp(14),
                fontWeight: FontWeight.w600,
                color: const Color(0xFFcbd5e1),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: context.rs(6)),
            Row(
              children: [
                _legend(context, 'Drowsiness', const Color(0xFFef4444)),
                SizedBox(width: context.rp(10)),
                _legend(context, 'Distraction', const Color(0xFFfbbf24)),
                const Spacer(),
                _expandBadge(context),
              ],
            ),
            SizedBox(height: context.rs(12)),
            Expanded(child: _scrollableChart(context, parsed, 10)),
          ],
        ),
      ),
    );
  }

  void _modal(BuildContext context, _LineData d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _ChartModal(
        title: 'Drowsiness vs Distraction',
        subtitle: 'Swipe chart sideways  •  Tap point to see value',
        child: LayoutBuilder(
          builder: (ctx, con) {
            final chartH = (con.maxHeight - 90).clamp(80.0, 600.0);
            return Column(
              children: [
                Row(
                  children: [
                    _legend(ctx, 'Drowsiness', const Color(0xFFef4444)),
                    SizedBox(width: ctx.rp(16)),
                    _legend(ctx, 'Distraction', const Color(0xFFfbbf24)),
                  ],
                ),
                SizedBox(height: ctx.rs(12)),
                SizedBox(height: chartH, child: _scrollableChart(ctx, d, 12)),
                SizedBox(height: ctx.rs(6)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.swipe_rounded,
                      color: Color(0xFF475569),
                      size: 13,
                    ),
                    SizedBox(width: ctx.rp(4)),
                    Text(
                      'Swipe to see all dates',
                      style: TextStyle(
                        color: const Color(0xFF475569),
                        fontSize: ctx.sp(10),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Wraps the chart in a horizontal scroll view.
  /// Each data point gets at least 40 px — so 30 points = min 1200 px width.
  Widget _scrollableChart(BuildContext ctx, _LineData d, double fontSize) =>
      LayoutBuilder(
        builder: (ctx, con) {
          const minSpacing = 40.0;
          final minW = d.labels.length * minSpacing;
          final w = minW.clamp(con.maxWidth, double.infinity);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: w,
              height: con.maxHeight,
              child: _lineWidget(ctx, d, fontSize),
            ),
          );
        },
      );

  Widget _lineWidget(BuildContext ctx, _LineData d, double fs) => LineChart(
    LineChartData(
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: d.yInterval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: const Color(0xFF1e293b),
          strokeWidth: 1,
          dashArray: [3, 3],
        ),
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: (v, _) {
              final i = v.round();
              if (i < 0 || i >= d.labels.length) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(top: ctx.rs(8)),
                child: Text(
                  d.labels[i],
                  style: TextStyle(
                    color: const Color(0xFF64748b),
                    fontSize: fs - 1,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: d.yInterval,
            reservedSize: 38,
            getTitlesWidget: (v, _) {
              if (v == 0 || v == d.maxY) return const SizedBox.shrink();
              return Text(
                '${v.toInt()}',
                style: TextStyle(
                  color: const Color(0xFF64748b),
                  fontSize: fs - 1,
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: d.maxX,
      minY: 0,
      maxY: d.maxY,
      lineBarsData: [
        _bar(d.drowsy, const Color(0xFFef4444)),
        _bar(d.distracted, const Color(0xFFfbbf24)),
      ],
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xFF0f172a),
          tooltipBorderRadius: BorderRadius.circular(12),
          tooltipPadding: EdgeInsets.all(ctx.rp(8)),
          getTooltipItems: (spots) => spots
              .map(
                (s) => LineTooltipItem(
                  '${s.y.toInt()} ${s.barIndex == 0 ? "drowsy" : "distracted"}',
                  TextStyle(
                    color: s.barIndex == 0
                        ? const Color(0xFFef4444)
                        : const Color(0xFFfbbf24),
                    fontWeight: FontWeight.bold,
                    fontSize: fs,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ),
  );

  LineChartBarData _bar(List<FlSpot> spots, Color c) => LineChartBarData(
    spots: spots,
    isCurved: spots.length > 2,
    curveSmoothness: 0.3,
    color: c,
    barWidth: 3,
    isStrokeCapRound: true,
    dotData: FlDotData(
      show: true,
      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
        radius: 4,
        color: c,
        strokeWidth: 2,
        strokeColor: const Color(0xFF0f172a),
      ),
    ),
    belowBarData: BarAreaData(show: false),
  );

  _LineData _parse() {
    if (dailyTrends.isEmpty) {
      final empty = List.generate(7, (i) => FlSpot(i.toDouble(), 0));
      return _LineData(
        drowsy: empty,
        distracted: List.from(empty),
        labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
        maxX: 6,
        maxY: 5,
        yInterval: 2,
      );
    }
    final drowsy = <FlSpot>[], dist = <FlSpot>[], labels = <String>[];
    for (int i = 0; i < dailyTrends.length; i++) {
      final r = dailyTrends[i];
      drowsy.add(
        FlSpot(i.toDouble(), (r['drowsy_count'] as int? ?? 0).toDouble()),
      );
      dist.add(
        FlSpot(i.toDouble(), (r['distracted_count'] as int? ?? 0).toDouble()),
      );
      labels.add(_shortDate(r['date'] as String? ?? ''));
    }
    final maxY0 = [
      ...drowsy,
      ...dist,
    ].map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);
    final maxY = ((maxY0 / 5).ceil() * 5.0).clamp(5.0, double.infinity);
    return _LineData(
      drowsy: drowsy,
      distracted: dist,
      labels: labels,
      maxX: (drowsy.length - 1).toDouble().clamp(1, double.infinity),
      maxY: maxY,
      yInterval: maxY <= 10
          ? 2.0
          : maxY <= 20
          ? 5.0
          : 10.0,
    );
  }

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${m[d.month - 1]} ${d.day}';
    } catch (_) {
      return iso.length >= 7 ? iso.substring(5) : iso;
    }
  }
}

class _LineData {
  final List<FlSpot> drowsy, distracted;
  final List<String> labels;
  final double maxX, maxY, yInterval;
  const _LineData({
    required this.drowsy,
    required this.distracted,
    required this.labels,
    required this.maxX,
    required this.maxY,
    required this.yInterval,
  });
}

// ── BAR CHART CARD ────────────────────────────────────────────────────────────
/// FIX #14: Height uses Responsive instead of hardcoded 220.
/// FIX #3:  Hour labels come from substr(triggered_at,12,2) in the DB query,
///          so they always reflect LOCAL time (not UTC).
class _BarCard extends StatelessWidget {
  final List<Map<String, dynamic>> hourlyDist;
  const _BarCard({required this.hourlyDist});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _modal(context),
    child: Container(
      // FIX #14: was height: 220 (hardcoded)
      height: Responsive.responsiveHeight(
        context,
        mobile: 240,
        tablet: 260,
        desktop: 280,
      ),
      decoration: _cardDecor(),
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
              Expanded(
                child: Text(
                  'Hourly Alert Distribution',
                  style: TextStyle(
                    fontSize: context.sp(14),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFcbd5e1),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: context.rp(8)),
              _expandBadge(context),
            ],
          ),
          SizedBox(height: context.rs(16)),
          Expanded(child: _barWidget(context, _preview(), 10, false)),
        ],
      ),
    ),
  );

  void _modal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _ChartModal(
        title: 'Hourly Alert Distribution',
        subtitle: 'All hours  •  Swipe to scroll',
        child: LayoutBuilder(
          builder: (ctx, con) {
            final chartH = (con.maxHeight - 80).clamp(80.0, 600.0);
            final full = _full();
            final minW = (full.length * 44.0).clamp(
              MediaQuery.of(ctx).size.width - 32,
              double.infinity,
            );
            return Column(
              children: [
                SizedBox(
                  height: chartH,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: minW,
                      height: chartH,
                      child: _barWidget(ctx, full, 11, true),
                    ),
                  ),
                ),
                SizedBox(height: ctx.rs(6)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.swipe_rounded,
                      color: Color(0xFF475569),
                      size: 13,
                    ),
                    SizedBox(width: ctx.rp(4)),
                    Text(
                      'Swipe to see all hours',
                      style: TextStyle(
                        color: const Color(0xFF475569),
                        fontSize: ctx.sp(10),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _barWidget(
    BuildContext ctx,
    List<Map<String, dynamic>> dist,
    double fs,
    bool full,
  ) {
    final groups = <BarChartGroupData>[];
    final labels = <String>[];
    for (int i = 0; i < dist.length; i++) {
      final h = dist[i]['hour'] as int;
      final c = (dist[i]['count'] as int).toDouble();
      labels.add(_hLabel(h));
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: c,
              width: Responsive.responsiveValue(
                ctx,
                mobile: 16.0,
                tablet: 18.0,
                desktop: 20.0,
              ),
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: c > 0
                    ? [const Color(0xFF22d3ee), const Color(0xFF3b82f6)]
                    : [const Color(0xFF1e293b), const Color(0xFF1e293b)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ],
        ),
      );
    }
    final maxC = groups
        .map((g) => g.barRods.first.toY)
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY = ((maxC / 5).ceil() * 5.0).clamp(5.0, double.infinity);
    final yi = maxY <= 10
        ? 2.0
        : maxY <= 20
        ? 5.0
        : maxY <= 50
        ? 10.0
        : 20.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1e293b),
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: EdgeInsets.symmetric(
              horizontal: ctx.rp(10),
              vertical: ctx.rs(8),
            ),
            getTooltipItem: (g, _, rod, _) => BarTooltipItem(
              '${rod.toY.toInt()} alert${rod.toY == 1 ? '' : 's'}\n${labels[g.x]}',
              TextStyle(
                color: const Color(0xFF22d3ee),
                fontWeight: FontWeight.bold,
                fontSize: fs,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
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
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: ctx.rs(8)),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: const Color(0xFF64748b),
                      fontSize: fs - 1,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: yi,
              reservedSize: 30,
              getTitlesWidget: (v, _) {
                if (v == 0 || v == maxY) return const SizedBox.shrink();
                return Text(
                  '${v.toInt()}',
                  style: TextStyle(
                    color: const Color(0xFF64748b),
                    fontSize: fs - 1,
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yi,
          getDrawingHorizontalLine: (_) => FlLine(
            color: const Color(0xFF1e293b),
            strokeWidth: 1,
            dashArray: [3, 3],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: groups,
      ),
    );
  }

  // Preview shows 6 representative hours (avoids clutter in card)
  List<Map<String, dynamic>> _preview() {
    const ph = [6, 9, 12, 15, 18, 21];
    final m = <int, int>{};
    for (final r in hourlyDist) m[r['hour'] as int] = r['count'] as int;
    return ph.map((h) => {'hour': h, 'count': m[h] ?? 0}).toList();
  }

  // Full 24-hour view (only hours ≥6 or that have data)
  List<Map<String, dynamic>> _full() {
    final m = <int, int>{};
    for (final r in hourlyDist) m[r['hour'] as int] = r['count'] as int;
    return List.generate(
      24,
      (h) => {'hour': h, 'count': m[h] ?? 0},
    ).where((r) => (r['count'] as int) > 0 || (r['hour'] as int) >= 6).toList();
  }

  static String _hLabel(int h) {
    if (h == 0) return '12AM';
    if (h == 12) return '12PM';
    return h < 12 ? '${h}AM' : '${h - 12}PM';
  }
}

// ── STAT CARD ─────────────────────────────────────────────────────────────────
class _StatCard extends StatefulWidget {
  final IconData icon;
  final String label, value;
  final bool positive;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.positive,
  });
  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final dot = widget.positive
        ? const Color(0xFF10b981)
        : const Color(0xFFfbbf24);
    final ls = MediaQuery.of(context).orientation == Orientation.landscape;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        clipBehavior: Clip.antiAlias,
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
          boxShadow: _hov
              ? [
                  const BoxShadow(
                    color: Color(0xFF0b1120),
                    offset: Offset(-3, -3),
                    blurRadius: 6,
                  ),
                  const BoxShadow(
                    color: Color(0xFF1e293b),
                    offset: Offset(3, 3),
                    blurRadius: 6,
                  ),
                ]
              : [
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
          ls
              ? context.rp(10)
              : Responsive.responsivePadding(
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
                    ls
                        ? context.rp(6)
                        : Responsive.responsivePadding(
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
                    size: ls
                        ? 14
                        : Responsive.responsiveIconSize(
                            context,
                            mobile: 18,
                            tablet: 20,
                            desktop: 24,
                          ),
                    color: const Color(0xFF22d3ee),
                  ),
                ),
                Container(
                  width: ls ? 8 : 10,
                  height: ls ? 8 : 10,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dot.withValues(alpha: 0.6),
                        blurRadius: ls ? 6 : 8,
                        spreadRadius: ls ? 1 : 2,
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
                    fontSize: ls
                        ? context.sp(20)
                        : Responsive.responsiveFont(
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
                  height: ls
                      ? 2
                      : Responsive.responsiveSpacing(
                          context,
                          mobile: 4,
                          tablet: 5,
                          desktop: 6,
                        ),
                ),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: ls
                        ? context.sp(9)
                        : Responsive.responsiveFont(
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

// ── CHART MODAL ───────────────────────────────────────────────────────────────
class _ChartModal extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  const _ChartModal({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final h = MediaQuery.of(context).size.height * (landscape ? 0.95 : 0.85);

    return Container(
      height: h,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1627),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Padding(
              padding: EdgeInsets.only(
                top: context.rs(12),
                bottom: context.rs(8),
              ),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2D45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.rp(20),
              context.rs(4),
              context.rp(16),
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: context.sp(18),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: const Color(0xFF6B7A99),
                          fontSize: context.sp(11),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2235),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1E2D45)),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF94A3B8),
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            color: const Color(0xFF1E2D45).withValues(alpha: 0.6),
            height: 20,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.rp(16),
                0,
                context.rp(16),
                context.rs(16),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ── SHARED HELPERS ────────────────────────────────────────────────────────────
BoxDecoration _cardDecor() => const BoxDecoration(
  color: Color(0xFF0f172a),
  borderRadius: BorderRadius.all(Radius.circular(20)),
  boxShadow: [
    BoxShadow(color: Color(0xFF0b1120), offset: Offset(8, 8), blurRadius: 16),
    BoxShadow(color: Color(0xFF1e293b), offset: Offset(-8, -8), blurRadius: 16),
  ],
);

Widget _legend(BuildContext ctx, String label, Color c) => Row(
  children: [
    Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    ),
    SizedBox(width: ctx.rp(5)),
    Text(
      label,
      style: TextStyle(
        fontSize: Responsive.responsiveFont(
          ctx,
          mobile: 11,
          tablet: 12,
          desktop: 13,
        ),
        color: const Color(0xFF94a3b8),
      ),
    ),
  ],
);

Widget _expandBadge(BuildContext ctx) => Container(
  padding: EdgeInsets.symmetric(horizontal: ctx.rp(6), vertical: ctx.rs(3)),
  decoration: BoxDecoration(
    color: const Color(0xFF22d3ee).withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xFF22d3ee).withValues(alpha: 0.25)),
  ),
  child: const Icon(
    Icons.open_in_full_rounded,
    color: Color(0xFF22d3ee),
    size: 13,
  ),
);
