import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../utils/responsive.dart';

const Color _kDrowsyColor     = Colors.red;
const Color _kDistractedColor = Color(0xFFfbbf24);

class _FilterNotifier extends Notifier<int?> {
  @override
  int? build() => 7;
  void set(int? value) => state = value;
}

final analyticsFilterProvider = NotifierProvider<_FilterNotifier, int?>(
  _FilterNotifier.new,
);

final analyticsDataProvider =
    FutureProvider.family.autoDispose<Map<String, dynamic>, int?>((ref, days) async {
  ref.watch(dbChangeCounterProvider);
  return DatabaseHelper.instance.getAnalyticsSummary(days: days);
});

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  static const _pages = <int?>[7, 30, null];
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _selectDays(int? days) {
    final idx = _pages.indexOf(days);
    if (idx < 0) return;
    ref.read(analyticsFilterProvider.notifier).set(days);
    _pageCtrl.animateToPage(
      idx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selDays = ref.watch(analyticsFilterProvider);
    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Column(
        children: [
          _FilterTabs(selectedDays: selDays, onSelect: _selectDays),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              onPageChanged: (idx) =>
                  ref.read(analyticsFilterProvider.notifier).set(_pages[idx]),
              children: _pages
                  .map((days) => _PageContent(days: days))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PER-PAGE LOADER ───────────────────────────────────────────────────────────
class _PageContent extends ConsumerWidget {
  final int? days;
  const _PageContent({required this.days});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(analyticsDataProvider(days));
    return asyncData.when(
      loading: () => const _AnalyticsSkeleton(),
      error: (e, _) => Center(
          child: Text('Error loading analytics: $e',
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center)),
      data: (data) => _Content(data: data, selDays: days),
    );
  }
}

// ── FILTER TABS ───────────────────────────────────────────────────────────────
class _FilterTabs extends StatelessWidget {
  final int?              selectedDays;
  final void Function(int?) onSelect;
  const _FilterTabs({required this.selectedDays, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.rp(20), context.rs(16),
          context.rp(20), context.rs(12)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
        padding: EdgeInsets.all(context.rp(4)),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(context.rp(16)),
          border: Border.all(color: const Color(0xFF1E2D45), width: 1),
        ),
        child: IntrinsicWidth(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _tab(context, '7 Days',   selectedDays == 7,   () => onSelect(7)),
            SizedBox(width: context.rp(4)),
            _tab(context, '30 Days',  selectedDays == 30,  () => onSelect(30)),
            SizedBox(width: context.rp(4)),
            _tab(context, 'All Time', selectedDays == null, () => onSelect(null)),
          ]),
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
              horizontal: ctx.rp(14), vertical: ctx.rs(8)),
          decoration: BoxDecoration(
            color: sel ? const Color(0xFF1e293b) : Colors.transparent,
            borderRadius: BorderRadius.circular(ctx.rp(12)),
          ),
          child: Text(label, style: TextStyle(
            fontSize:   ctx.sp(12),
            fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
            color: sel ? const Color(0xFF22d3ee) : const Color(0xFF64748b),
          )),
        ),
      );
}

// ── CONTENT ───────────────────────────────────────────────────────────────────
class _Content extends StatelessWidget {
  final Map<String, dynamic> data;
  final int? selDays;
  const _Content({required this.data, required this.selDays});

  @override
  Widget build(BuildContext context) {
    final sessions   = data['total_sessions']    as int? ?? 0;
    final alerts     = data['total_alerts']       as int? ?? 0;
    final drowsy     = data['drowsiness_events']  as int? ?? 0;
    final distracted = data['distraction_events'] as int? ?? 0;
    final dailyTrends =
        (data['daily_trends'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final hourlyDist =
        (data['hourly_distribution'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      color: const Color(0xFF22d3ee),
      backgroundColor: const Color(0xFF0f172a),
      onRefresh: () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: context.rs(16)),
            _SummaryCards(
              sessions: sessions, alerts: alerts,
              drowsy: drowsy, distracted: distracted,
            ),
            SizedBox(height: context.rs(24)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.rp(20)),
              child: _mobileCharts(context, dailyTrends, hourlyDist),
            ),
            SizedBox(height: context.rs(32)),
          ],
        ),
      ),
    );
  }

  Widget _mobileCharts(BuildContext ctx,
      List<Map<String, dynamic>> trends,
      List<Map<String, dynamic>> hourly) =>
      Column(children: [
        _LineCard(dailyTrends: trends, selDays: selDays),
        SizedBox(height: ctx.rs(24)),
        _BarCard(hourlyDist: hourly),
      ]);

}

// ── SUMMARY CARDS ─────────────────────────────────────────────────────────────
class _SummaryCards extends StatelessWidget {
  final int sessions, alerts, drowsy, distracted;
  const _SummaryCards({
    required this.sessions, required this.alerts,
    required this.drowsy, required this.distracted,
  });

  double _aspect(BuildContext ctx) =>
      ctx.forTier(base: 0.95, compact: 0.85, small: 0.90, large: 1.0);

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ctx.rp(20)),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing:  ctx.rs(10),
        crossAxisSpacing: ctx.rp(10),
        childAspectRatio: _aspect(ctx),
        children: [
          _StatCard(icon: Icons.timer_outlined,
              label: 'Total Sessions', value: '$sessions', positive: true),
          _StatCard(icon: Icons.warning_amber_outlined,
              label: 'Total Alerts', value: '$alerts', positive: alerts == 0),
          _StatCard(icon: Icons.bedtime_outlined,
              label: 'Drowsiness', value: '$drowsy',
              positive: drowsy == 0, accentColor: _kDrowsyColor),
          _StatCard(icon: Icons.visibility_off_outlined,
              label: 'Distraction', value: '$distracted',
              positive: distracted == 0, accentColor: _kDistractedColor),
        ],
      ),
    );
  }
}

// ── LINE CHART CARD ───────────────────────────────────────────────────────────
class _LineCard extends StatefulWidget {
  final List<Map<String, dynamic>> dailyTrends;
  final int? selDays;
  const _LineCard({required this.dailyTrends, required this.selDays});

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  bool get _is7Day => widget.selDays == 7;

  @override
  Widget build(BuildContext context) {
    final parsed = _parse();
    return GestureDetector(
      onTap: () => _modal(context, parsed),
      child: Container(
        height: context.rs(context.isSmallPhone ? 260 : 295),
        decoration: _cardDecor(context),
        padding: EdgeInsets.all(context.rp(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drowsiness vs Distraction Trends',
                style: TextStyle(fontSize: context.sp(13),
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFcbd5e1)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: context.rs(6)),
            Row(children: [
              _legend(context, 'Drowsiness', _kDrowsyColor),
              SizedBox(width: context.rp(10)),
              _legend(context, 'Distraction', _kDistractedColor),
              const Spacer(),
              _expandBadge(context),
            ]),
            SizedBox(height: context.rs(10)),
            Expanded(
              child: _is7Day
                  ? _sevenDayChart(context, parsed, context.sp(9),
                      (idx) => _showDayBreakdown(context, idx))
                  : _scrollableChart(context, parsed, context.sp(9),
                      (idx) => _showDayBreakdown(context, idx)),
            ),
          ],
        ),
      ),
    );
  }

  void _modal(BuildContext context, _LineData d) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      useSafeArea: true,
      builder: (ctx) => _ChartModal(
          title: 'Drowsiness vs Distraction',
          subtitle: _is7Day
              ? 'Tap a point to see that day\'s breakdown'
              : 'Swipe chart  •  Tap a point for day breakdown',
          child: Column(children: [
            Row(children: [
              _legend(ctx, 'Drowsiness', _kDrowsyColor),
              SizedBox(width: ctx.rp(16)),
              _legend(ctx, 'Distraction', _kDistractedColor),
            ]),
            SizedBox(height: ctx.rs(12)),
            Expanded(
              child: _is7Day
                  ? _sevenDayChart(ctx, d, ctx.sp(11),
                      (idx) => _showDayBreakdown(ctx, idx))
                  : _scrollableChart(ctx, d, ctx.sp(11),
                      (idx) => _showDayBreakdown(ctx, idx)),
            ),
            ...(!_is7Day ? [
              SizedBox(height: ctx.rs(6)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.swipe_rounded,
                    color: const Color(0xFF475569), size: ctx.ri(13)),
                SizedBox(width: ctx.rp(4)),
                Text('Swipe to see all dates',
                    style: TextStyle(color: const Color(0xFF475569),
                        fontSize: ctx.sp(10))),
              ]),
              SizedBox(height: ctx.rs(8)),
            ] : [
              SizedBox(height: ctx.rs(8)),
            ]),
          ]),
        ),
    );
  }

  void _showDayBreakdown(BuildContext context, int index) {
    if (index < 0 || index >= widget.dailyTrends.length) return;
    final row        = widget.dailyTrends[index];
    final rawDate    = row['date'] as String? ?? '';
    final drowsy     = row['drowsy_count']     as int? ?? 0;
    final distracted = row['distracted_count'] as int? ?? 0;
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      useSafeArea: true,
      builder: (_) => _DayBreakdownModal(
        date:        _fullDate(rawDate),
        rawDate:     rawDate,
        drowsy:      drowsy,
        distracted:  distracted,
      ),
    );
  }

  Widget _sevenDayChart(BuildContext ctx, _LineData d, double fs,
          void Function(int) onDayTap) =>
      LayoutBuilder(builder: (ctx, con) => SizedBox(
            width: con.maxWidth, height: con.maxHeight,
            child: _lineWidget(ctx, d, fs, onDayTap)));

  Widget _scrollableChart(BuildContext ctx, _LineData d, double fs,
          void Function(int) onDayTap) =>
      LayoutBuilder(builder: (ctx, con) {
        final pointCount = d.labels.length;
        final spacing    = pointCount <= 30 ? 48.0 : 40.0;
        final minW = (pointCount * spacing).clamp(con.maxWidth, double.infinity);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(width: minW, height: con.maxHeight,
              child: _lineWidget(ctx, d, fs, onDayTap)),
        );
      });

  Widget _lineWidget(BuildContext ctx, _LineData d, double fs,
      void Function(int) onDayTap) =>
      LineChart(
        LineChartData(
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            horizontalInterval: d.yInterval,
            getDrawingHorizontalLine: (_) => FlLine(
                color: const Color(0xFF1e293b), strokeWidth: 1,
                dashArray: [3, 3]),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: ctx.rs(28),
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= d.labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: EdgeInsets.only(top: ctx.rs(6)),
                    child: Text(d.labels[i], style: TextStyle(
                        color: const Color(0xFF64748b), fontSize: fs)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, interval: d.yInterval,
                reservedSize: ctx.rp(34),
                getTitlesWidget: (v, _) {
                  if (v == 0 || v == d.maxY) return const SizedBox.shrink();
                  return Text('${v.toInt()}', style: TextStyle(
                      color: const Color(0xFF64748b), fontSize: fs));
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0, maxX: d.maxX, minY: 0, maxY: d.maxY,
          lineBarsData: [
            _bar(d.drowsy,     _kDrowsyColor),
            _bar(d.distracted, _kDistractedColor),
          ],
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchCallback: (event, response) {
              if (event is FlTapUpEvent &&
                  response?.lineBarSpots?.isNotEmpty == true) {
                final x = response!.lineBarSpots!.first.x.round();
                onDayTap(x);
              }
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF0f172a),
              tooltipBorderRadius: BorderRadius.circular(ctx.rp(12)),
              tooltipPadding: EdgeInsets.all(ctx.rp(8)),
              getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                    '${s.y.toInt()} '
                    '${s.barIndex == 0 ? "drowsy" : "distracted"}',
                    TextStyle(
                      color: s.barIndex == 0 ? _kDrowsyColor : _kDistractedColor,
                      fontWeight: FontWeight.bold, fontSize: fs,
                    ),
                  )).toList(),
            ),
          ),
        ),
      );

  LineChartBarData _bar(List<FlSpot> spots, Color c) => LineChartBarData(
        spots: spots, isCurved: spots.length > 2,
        curveSmoothness: 0.3, color: c, barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (p0, p1, p2, p3) => FlDotCirclePainter(
              radius: 3.5, color: c, strokeWidth: 2,
              strokeColor: const Color(0xFF0f172a)),
        ),
        belowBarData: BarAreaData(show: false),
      );

  _LineData _parse() {
    if (widget.dailyTrends.isEmpty) {
      final empty = List.generate(7, (i) => FlSpot(i.toDouble(), 0));
      return _LineData(
        drowsy: empty, distracted: List.from(empty),
        labels: const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],
        maxX: 6, maxY: 5, yInterval: 2,
      );
    }
    final drowsy = <FlSpot>[], dist = <FlSpot>[], labels = <String>[];
    for (int i = 0; i < widget.dailyTrends.length; i++) {
      final r = widget.dailyTrends[i];
      drowsy.add(FlSpot(i.toDouble(),
          (r['drowsy_count'] as int? ?? 0).toDouble()));
      dist.add(FlSpot(i.toDouble(),
          (r['distracted_count'] as int? ?? 0).toDouble()));
      labels.add(_shortDate(r['date'] as String? ?? ''));
    }
    final maxY0 = [...drowsy, ...dist].map((s) => s.y)
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY  = ((maxY0 / 5).ceil() * 5.0).clamp(5.0, double.infinity);
    return _LineData(
      drowsy: drowsy, distracted: dist, labels: labels,
      maxX: (drowsy.length - 1).toDouble().clamp(1, double.infinity),
      maxY: maxY,
      yInterval: maxY <= 10 ? 2.0 : maxY <= 20 ? 5.0 : 10.0,
    );
  }

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[d.month - 1]} ${d.day}';
    } catch (_) {
      return iso.length >= 7 ? iso.substring(5) : iso;
    }
  }

  String _fullDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December'
      ];
      const weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _LineData {
  final List<FlSpot> drowsy, distracted;
  final List<String> labels;
  final double       maxX, maxY, yInterval;
  const _LineData({
    required this.drowsy, required this.distracted, required this.labels,
    required this.maxX,   required this.maxY,       required this.yInterval,
  });
}

// ── DAY BREAKDOWN MODAL ───────────────────────────────────────────────────────
class _DayBreakdownModal extends StatefulWidget {
  final String date;
  final String rawDate;
  final int    drowsy;
  final int    distracted;
  const _DayBreakdownModal({
    required this.date, required this.rawDate,
    required this.drowsy, required this.distracted,
  });

  @override
  State<_DayBreakdownModal> createState() => _DayBreakdownModalState();
}

class _DayBreakdownModalState extends State<_DayBreakdownModal> {
  Map<String, dynamic>? _breakdown;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result =
          await DatabaseHelper.instance.getDayAlertBreakdown(widget.rawDate);
      if (mounted) setState(() { _breakdown = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.drowsy + widget.distracted;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.rp(24))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Padding(
          padding: EdgeInsets.only(
              top: context.rs(12), bottom: context.rs(8)),
          child: Container(
            width: context.rp(40), height: context.rs(4),
            decoration: BoxDecoration(
                color: const Color(0xFF1E2D45),
                borderRadius: BorderRadius.circular(context.rp(2))),
          ),
        )),
        Padding(
          padding: EdgeInsets.fromLTRB(
              context.rp(20), context.rs(4), context.rp(16), 0),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.date, style: TextStyle(
                    color: Colors.white, fontSize: context.sp(15),
                    fontWeight: FontWeight.w700)),
                SizedBox(height: context.rs(3)),
                Text('$total alert${total == 1 ? '' : 's'} detected',
                    style: TextStyle(color: const Color(0xFF6B7A99),
                        fontSize: context.sp(11))),
              ],
            )),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                  width: context.ri(34), height: context.ri(34),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1A2235),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1E2D45))),
                  child: Icon(Icons.close_rounded,
                      color: const Color(0xFF94A3B8),
                      size: context.ri(18))),
            ),
          ]),
        ),
        Divider(color: const Color(0xFF1E2D45).withValues(alpha: 0.6),
            height: context.rs(20)),
        if (_loading)
          Padding(
            padding: EdgeInsets.all(context.rp(32)),
            child: const CircularProgressIndicator(
                color: Color(0xFF22d3ee)),
          )
        else
          Padding(
            padding: EdgeInsets.fromLTRB(
                context.rp(16), 0, context.rp(16), context.rs(28)),
            child: Column(children: [
              if (widget.drowsy > 0) ...[
                _TypeRow(
                  label: 'Drowsiness', total: widget.drowsy,
                  color: _kDrowsyColor, icon: Icons.bedtime_outlined,
                  l1: _breakdown?['l1_drowsy']     as int? ?? 0,
                  l2: _breakdown?['l2_drowsy']     as int? ?? 0,
                  l3: _breakdown?['l3_drowsy']     as int? ?? 0,
                ),
                SizedBox(height: context.rs(10)),
              ],
              if (widget.distracted > 0) ...[
                _TypeRow(
                  label: 'Distraction', total: widget.distracted,
                  color: _kDistractedColor, icon: Icons.visibility_off_outlined,
                  l1: _breakdown?['l1_distracted'] as int? ?? 0,
                  l2: _breakdown?['l2_distracted'] as int? ?? 0,
                  l3: _breakdown?['l3_distracted'] as int? ?? 0,
                ),
                SizedBox(height: context.rs(10)),
              ],
              if (widget.drowsy == 0 && widget.distracted == 0)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: context.rs(16)),
                  child: Text('No alerts on this day',
                      style: TextStyle(color: const Color(0xFF64748b),
                          fontSize: context.sp(13))),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _TypeRow extends StatelessWidget {
  final String   label;
  final int      total, l1, l2, l3;
  final Color    color;
  final IconData icon;
  const _TypeRow({
    required this.label, required this.total, required this.color,
    required this.icon,  required this.l1,    required this.l2,
    required this.l3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.rp(14)),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
        border: Border.all(color: const Color(0xFF1E2D45)),
      ),
      child: Row(children: [
        Container(
          padding: EdgeInsets.all(context.rp(8)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(context.rp(10)),
          ),
          child: Icon(icon, color: color, size: context.ri(18)),
        ),
        SizedBox(width: context.rp(12)),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label, style: TextStyle(
                  color: const Color(0xFFcbd5e1), fontSize: context.sp(13),
                  fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$total total', style: TextStyle(
                  color: color, fontSize: context.sp(13),
                  fontWeight: FontWeight.w700)),
            ]),
            SizedBox(height: context.rs(8)),
            Row(children: [
              if (l1 > 0) _pill(context, 'L1', l1, const Color(0xFFf59e0b)),
              if (l1 > 0 && (l2 > 0 || l3 > 0))
                SizedBox(width: context.rp(6)),
              if (l2 > 0) _pill(context, 'L2', l2, const Color(0xFFef8c34)),
              if (l2 > 0 && l3 > 0) SizedBox(width: context.rp(6)),
              if (l3 > 0) _pill(context, 'L3', l3, const Color(0xFFef4444)),
              if (l1 == 0 && l2 == 0 && l3 == 0)
                Text('—', style: TextStyle(
                    color: const Color(0xFF475569), fontSize: context.sp(11))),
            ]),
          ],
        )),
      ]),
    );
  }

  Widget _pill(BuildContext ctx, String lvl, int count, Color c) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: ctx.rp(8), vertical: ctx.rs(3)),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(ctx.rp(20)),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Text('$lvl  $count', style: TextStyle(
            color: c, fontSize: ctx.sp(10), fontWeight: FontWeight.w600)),
      );
}

// ── BAR CHART CARD ────────────────────────────────────────────────────────────
class _BarCard extends StatelessWidget {
  final List<Map<String, dynamic>> hourlyDist;
  const _BarCard({required this.hourlyDist});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => _modal(context),
        child: Container(
          height: context.rs(context.isSmallPhone ? 210 : 235),
          decoration: _cardDecor(context),
          padding: EdgeInsets.all(context.rp(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('Hourly Alert Distribution',
                    style: TextStyle(fontSize: context.sp(13),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFcbd5e1)),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                SizedBox(width: context.rp(8)),
                _expandBadge(context),
              ]),
              SizedBox(height: context.rs(14)),
              Expanded(child: _barWidget(context, _preview(), context.sp(9))),
            ],
          ),
        ),
      );

  void _modal(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      useSafeArea: true,
      builder: (ctx) => _ChartModal(
        title:    'Hourly Alert Distribution',
        subtitle: 'All hours  •  Swipe to scroll  •  Local time',
        child: Column(children: [
          Expanded(
            child: LayoutBuilder(builder: (ctx, con) {
              final full = _full();
              final minW = (full.length * ctx.rp(44)).clamp(
                  MediaQuery.of(ctx).size.width - ctx.rp(32),
                  double.infinity);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(width: minW, height: con.maxHeight,
                    child: _barWidget(ctx, full, ctx.sp(10))),
              );
            }),
          ),
          SizedBox(height: ctx.rs(6)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.swipe_rounded,
                color: const Color(0xFF475569), size: ctx.ri(13)),
            SizedBox(width: ctx.rp(4)),
            Text('Swipe to see all hours',
                style: TextStyle(color: const Color(0xFF475569),
                    fontSize: ctx.sp(10))),
          ]),
          SizedBox(height: ctx.rs(8)),
        ]),
      ),
    );
  }

  Widget _barWidget(BuildContext ctx, List<Map<String, dynamic>> dist,
      double fs) {
    final groups = <BarChartGroupData>[];
    final labels = <String>[];
    for (int i = 0; i < dist.length; i++) {
      final h = dist[i]['hour']  as int;
      final c = (dist[i]['count'] as int).toDouble();
      labels.add(_hLabel(h));
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: c,
          width: ctx.rp(14),
          borderRadius: BorderRadius.circular(ctx.rp(4)),
          gradient: LinearGradient(
            colors: c > 0
                ? [const Color(0xFF22d3ee), const Color(0xFF3b82f6)]
                : [const Color(0xFF1e293b), const Color(0xFF1e293b)],
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
          ),
        ),
      ]));
    }
    final maxC = groups.map((g) => g.barRods.first.toY)
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY = ((maxC / 5).ceil() * 5.0).clamp(5.0, double.infinity);
    final yi   = maxY <= 10 ? 2.0 : maxY <= 20 ? 5.0 :
                 maxY <= 50 ? 10.0 : 20.0;

    return BarChart(BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => const Color(0xFF1e293b),
          tooltipBorderRadius: BorderRadius.circular(ctx.rp(10)),
          tooltipPadding: EdgeInsets.symmetric(
              horizontal: ctx.rp(10), vertical: ctx.rs(8)),
          getTooltipItem: (group, groupIndex, rod, rodIndex) =>
              BarTooltipItem(
            '${rod.toY.toInt()} alert${rod.toY == 1 ? '' : 's'}\n'
            '${labels[group.x]}',
            TextStyle(color: const Color(0xFF22d3ee),
                fontWeight: FontWeight.bold, fontSize: fs),
          ),
        ),
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: ctx.rs(28),
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= labels.length) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(top: ctx.rs(6)),
                child: Text(labels[i], style: TextStyle(
                    color: const Color(0xFF64748b), fontSize: fs)));
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true, interval: yi,
            reservedSize: ctx.rp(28),
            getTitlesWidget: (v, _) {
              if (v == 0 || v == maxY) return const SizedBox.shrink();
              return Text('${v.toInt()}', style: TextStyle(
                  color: const Color(0xFF64748b), fontSize: fs));
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true, drawVerticalLine: false, horizontalInterval: yi,
        getDrawingHorizontalLine: (_) => FlLine(
            color: const Color(0xFF1e293b), strokeWidth: 1,
            dashArray: [3, 3]),
      ),
      borderData: FlBorderData(show: false),
      barGroups: groups,
    ));
  }

  List<Map<String, dynamic>> _preview() {
    const ph = [6, 9, 12, 15, 18, 21];
    final m   = <int, int>{};
    for (final r in hourlyDist) {
      m[r['hour'] as int] = r['count'] as int;
    }
    return ph.map((h) => {'hour': h, 'count': m[h] ?? 0}).toList();
  }

  List<Map<String, dynamic>> _full() {
    final m = <int, int>{};
    for (final r in hourlyDist) {
      m[r['hour'] as int] = r['count'] as int;
    }
    return List.generate(24, (h) => {'hour': h, 'count': m[h] ?? 0});
  }

  static String _hLabel(int h) {
    if (h == 0)  return '12AM';
    if (h == 12) return '12PM';
    return h < 12 ? '${h}AM' : '${h - 12}PM';
  }
}

// ── STAT CARD ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final bool     positive;
  final Color?   accentColor;
  const _StatCard({
    required this.icon, required this.label,
    required this.value, required this.positive,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final dot = accentColor ??
        (positive ? const Color(0xFF10b981) : const Color(0xFFfbbf24));

    return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(context.rp(14)),
          border: Border.all(color: const Color(0xFF1E2D45), width: 1),
        ),
        padding: EdgeInsets.all(context.rp(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:  MainAxisAlignment.spaceBetween,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding: EdgeInsets.all(context.rp(7)),
                decoration: BoxDecoration(
                    color: const Color(0xFF1e293b),
                    borderRadius: BorderRadius.circular(context.rp(8))),
                child: Icon(icon,
                    size: context.ri(17),
                    color: const Color(0xFF22d3ee)),
              ),
              Container(
                width:  context.ri(9),
                height: context.ri(9),
                decoration: BoxDecoration(
                  color: dot, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: dot.withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 2)],
                ),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(
                fontSize: context.sp(22),
                fontWeight: FontWeight.bold,
                color: const Color(0xFFe2e8f0),
              )),
              SizedBox(height: context.rs(3)),
              Text(label, style: TextStyle(
                fontSize: context.sp(10),
                color: const Color(0xFF64748b),
              ), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ],
        ),
    );
  }
}

// ── CHART MODAL ───────────────────────────────────────────────────────────────
class _ChartModal extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  const _ChartModal({
    required this.title, required this.subtitle, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.92;

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.rp(24))),
      ),
      child: Column(children: [
        Center(child: Padding(
          padding: EdgeInsets.only(
              top: context.rs(12), bottom: context.rs(8)),
          child: Container(
              width: context.rp(40), height: context.rs(4),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E2D45),
                  borderRadius: BorderRadius.circular(context.rp(2)))),
        )),
        Padding(
          padding: EdgeInsets.fromLTRB(
              context.rp(20), context.rs(4), context.rp(16), 0),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.white,
                    fontSize: context.sp(17), fontWeight: FontWeight.w700)),
                SizedBox(height: context.rs(3)),
                Text(subtitle, style: TextStyle(
                    color: const Color(0xFF6B7A99),
                    fontSize: context.sp(11))),
              ],
            )),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                  width: context.ri(34), height: context.ri(34),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1A2235),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1E2D45))),
                  child: Icon(Icons.close_rounded,
                      color: const Color(0xFF94A3B8),
                      size: context.ri(18))),
            ),
          ]),
        ),
        Divider(color: const Color(0xFF1E2D45).withValues(alpha: 0.6),
            height: context.rs(20)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                context.rp(16), 0, context.rp(16),
                // useSafeArea:true positions the sheet above the nav bar and
                // sets padding.bottom = 0 inside the modal; use a larger fixed
                // clearance so the bottom hint/label is never flush with the
                // sheet edge on small or button-nav devices.
                context.rs(24)),
            child: child,
          ),
        ),
      ]),
    );
  }
}

// ── SHARED HELPERS ────────────────────────────────────────────────────────────
BoxDecoration _cardDecor(BuildContext ctx) => BoxDecoration(
      color:        const Color(0xFF0f172a),
      borderRadius: BorderRadius.all(Radius.circular(ctx.rp(18))),
      border: Border.all(color: const Color(0xFF1E2D45), width: 1),
    );

Widget _legend(BuildContext ctx, String label, Color c) => Row(children: [
      Container(
          width: ctx.ri(10), height: ctx.ri(10),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      SizedBox(width: ctx.rp(5)),
      Text(label, style: TextStyle(
          fontSize: ctx.sp(11), color: const Color(0xFF94a3b8))),
    ]);

Widget _expandBadge(BuildContext ctx) => Container(
      padding: EdgeInsets.symmetric(
          horizontal: ctx.rp(6), vertical: ctx.rs(3)),
      decoration: BoxDecoration(
        color:        const Color(0xFF22d3ee).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ctx.rp(8)),
        border: Border.all(
            color: const Color(0xFF22d3ee).withValues(alpha: 0.25)),
      ),
      child: Icon(Icons.open_in_full_rounded,
          color: const Color(0xFF22d3ee), size: ctx.ri(13)),
    );

// ── ANALYTICS SKELETON ────────────────────────────────────────────────────────
class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      const Color(0xFF1A2235),
      highlightColor: const Color(0xFF263350),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: context.rs(32)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: context.rs(16)),
            // Summary cards — 2 × 2 grid
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.rp(20)),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount:   2,
                mainAxisSpacing:  context.rs(10),
                crossAxisSpacing: context.rp(10),
                childAspectRatio: context.forTier(
                    base: 0.95, compact: 0.85, small: 0.90, large: 1.0),
                children: List.generate(
                    4, (_) => _box(context, double.infinity, double.infinity)),
              ),
            ),
            SizedBox(height: context.rs(24)),
            // Line chart card
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.rp(20)),
              child: _box(context, double.infinity,
                  context.rs(context.isSmallPhone ? 260 : 295)),
            ),
            SizedBox(height: context.rs(24)),
            // Bar chart card
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.rp(20)),
              child: _box(context, double.infinity,
                  context.rs(context.isSmallPhone ? 210 : 235)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(BuildContext ctx, double w, double h, {double r = 18}) =>
      Container(
        width: w, height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ctx.rp(r)),
        ),
      );
}