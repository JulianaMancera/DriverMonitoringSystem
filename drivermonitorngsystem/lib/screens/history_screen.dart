// history_screen.dart — fully responsive
// All sizes use context.sp() / context.rp() / context.rs() / context.ri()
// Search bar: fixed logical 44px → now context.rs(44).clamp(38,52)
// Icon sizes: context.ri() so they scale on compact phones
// Card heights: intrinsic (no fixed px) so content never clips

import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const Color _bg          = Color(0xFF080E1A);
  static const Color _surface     = Color(0xFF0D1627);
  static const Color _surfaceAlt  = Color(0xFF1A2235);
  static const Color _cyan        = Color(0xFF00D4FF);
  static const Color _green       = Color(0xFF00FF88);
  static const Color _drowsy      = Color(0xFFF59E0B);
  static const Color _distracted  = Color(0xFFA855F7);
  static const Color _textPrimary = Color(0xFFEEF2FF);
  static const Color _textDim     = Color(0xFF6B7A99);
  static const Color _divider     = Color(0xFF1E2D45);

  bool   _isLoading      = true;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _filtered = [];
  int    _selectedFilter = 0;
  final  TextEditingController _searchCtrl       = TextEditingController();
  final  ScrollController      _filterScrollCtrl = ScrollController();
  bool   _filterCanScrollRight = true;
  bool   _filterCanScrollLeft  = false;

  final List<String> _filters = [
    'All', 'This Week', 'This Month', 'With Alerts', 'Safe Drives',
  ];

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _searchCtrl.addListener(_applyFilter);
    _filterScrollCtrl.addListener(_onFilterScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFilterScroll());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _filterScrollCtrl.dispose();
    super.dispose();
  }

  void _onFilterScroll() {
    final pos       = _filterScrollCtrl.position;
    final showRight = pos.extentAfter > 4;
    final showLeft  = pos.extentBefore > 4;
    if (showRight != _filterCanScrollRight || showLeft != _filterCanScrollLeft) {
      setState(() {
        _filterCanScrollRight = showRight;
        _filterCanScrollLeft  = showLeft;
      });
    }
  }

  void _checkFilterScroll() {
    if (_filterScrollCtrl.hasClients) {
      setState(() {
        _filterCanScrollRight = _filterScrollCtrl.position.maxScrollExtent > 0;
        _filterCanScrollLeft  = false;
      });
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final sessions    = await DatabaseHelper.instance.getAllSessions();
    final alertCounts = await DatabaseHelper.instance.getAllSessionAlertCounts();
    final enriched    = sessions.map((s) => {
          ...s,
          'alert_count': alertCounts[s['id'] as int] ?? 0,
        }).toList();
    if (mounted) {
      setState(() { _sessions = enriched; _isLoading = false; });
      _applyFilter();
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    final now   = DateTime.now();
    List<Map<String, dynamic>> result = List.from(_sessions);

    if (query.isNotEmpty) {
      result = result.where((s) {
        final iso        = s['started_at'] as String? ?? '';
        final d          = DateTime.tryParse(iso)?.toLocal();
        final alertCount = s['alert_count'] as int? ?? 0;
        final searchables = <String>[];
        if (d != null) {
          const months = ['january','february','march','april','may','june',
                          'july','august','september','october','november','december'];
          const short  = ['jan','feb','mar','apr','may','jun',
                          'jul','aug','sep','oct','nov','dec'];
          searchables.addAll([months[d.month-1], short[d.month-1],
            '${short[d.month-1]} ${d.day}', '${d.day}', '${d.year}',
            '${d.month}/${d.day}/${d.year}']);
          final h    = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
          final m    = d.minute.toString().padLeft(2, '0');
          final ampm = d.hour >= 12 ? 'pm' : 'am';
          searchables.addAll(['$h:$m $ampm', ampm]);
        }
        if (alertCount == 0) searchables.add('safe');
        if (alertCount > 0)  searchables.addAll(['alert', 'alerts']);
        return searchables.any((t) => t.contains(query));
      }).toList();
    }

    switch (_selectedFilter) {
      case 1:
        final since = now.subtract(const Duration(days: 7));
        result = result.where((s) {
          final d = DateTime.tryParse(s['started_at'] ?? '');
          return d != null && d.toLocal().isAfter(since);
        }).toList();
        break;
      case 2:
        result = result.where((s) {
          final d = DateTime.tryParse(s['started_at'] ?? '');
          if (d == null) return false;
          final local = d.toLocal();
          return local.month == now.month && local.year == now.year;
        }).toList();
        break;
      case 3:
        result = result.where((s) => (s['alert_count'] as int? ?? 0) > 0).toList();
        break;
      case 4:
        result = result.where((s) => (s['alert_count'] as int? ?? 0) == 0).toList();
        break;
    }
    setState(() => _filtered = result);
  }

  void _openSessionDetail(Map<String, dynamic> session) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      enableDrag: true,
      builder: (_) => _SessionDetailSheet(session: session),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    final l = d.toLocal();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[l.month-1]} ${l.day}, ${l.year}';
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    final l    = d.toLocal();
    final h    = l.hour == 0 ? 12 : (l.hour > 12 ? l.hour - 12 : l.hour);
    final m    = l.minute.toString().padLeft(2, '0');
    final ampm = l.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _dateGroupLabel(String? iso) {
    if (iso == null) return 'UNKNOWN';
    final d = DateTime.tryParse(iso);
    if (d == null) return 'UNKNOWN';
    final local = d.toLocal();
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day   = DateTime(local.year, local.month, local.day);
    if (day == today) return 'TODAY';
    if (day == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return _formatDate(iso).toUpperCase();
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> sessions) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in sessions) {
      groups.putIfAbsent(_dateGroupLabel(s['started_at']), () => []).add(s);
    }
    return groups;
  }

  Color _accentColor(int alertCount) {
    if (alertCount == 0) return _green;
    if (alertCount <= 2) return _drowsy;
    return _distracted;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dbChangeCounterProvider, (previous, next) {
      if (next > (previous ?? 0)) _loadSessions();
    });

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildSearchBar(),
        _buildFilterChips(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _cyan))
              : _filtered.isEmpty ? _buildEmpty() : _buildList(),
        ),
      ]),
    );
  }

  // FIX: Search bar height uses context.rs() so it scales correctly
  // on compact phones (was fixed 44px — too tall on 360dp phones)
  Widget _buildSearchBar() {
    final barH = context.rs(44).clamp(38.0, 52.0);
    return Container(
      color: _surface,
      padding: EdgeInsets.symmetric(
          horizontal: context.rp(16), vertical: context.rs(10)),
      child: SizedBox(
        height: barH,
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(context.rp(12))),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(color: _textPrimary, fontSize: context.sp(13)),
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.center,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: 'Search by date, month, or "safe"...',
              hintStyle: TextStyle(
                  color: _textDim, fontSize: context.sp(13)),
              prefixIcon: Icon(Icons.search_rounded,
                  color: _textDim, size: context.ri(18)),
              prefixIconConstraints: BoxConstraints(
                  minWidth: barH, minHeight: barH),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        FocusScope.of(context).unfocus();
                      },
                      child: Icon(Icons.close_rounded,
                          color: _textDim, size: context.ri(16)))
                  : null,
              suffixIconConstraints: BoxConstraints(
                  minWidth: context.ri(36), minHeight: barH),
              border: InputBorder.none, isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollArrow({required bool visible, required bool isLeft}) =>
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: SizedBox(
          width: visible ? context.rp(24) : 0,
          child: visible
              ? Container(
                  alignment: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isLeft
                          ? [_surface, _surface.withValues(alpha: 0.0)]
                          : [_surface.withValues(alpha: 0.0), _surface],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                  ),
                  child: Icon(
                    isLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    color: _textDim, size: context.ri(16)),
                )
              : const SizedBox.shrink(),
        ),
      );

  Widget _buildFilterChips() => Container(
        color: _surface,
        padding: EdgeInsets.only(bottom: context.rs(10)),
        child: Row(children: [
          _scrollArrow(visible: _filterCanScrollLeft, isLeft: true),
          Expanded(
            child: SingleChildScrollView(
              controller: _filterScrollCtrl, scrollDirection: Axis.horizontal,
              child: Row(children: [
                SizedBox(width: context.rp(16)),
                ...List.generate(_filters.length, (i) {
                  final on = i == _selectedFilter;
                  return GestureDetector(
                    onTap: () { setState(() => _selectedFilter = i); _applyFilter(); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(right: context.rp(8)),
                      padding: EdgeInsets.symmetric(
                          horizontal: context.rp(13), vertical: context.rs(6)),
                      decoration: BoxDecoration(
                        color: on ? _cyan.withValues(alpha: 0.15) : _surfaceAlt,
                        borderRadius: BorderRadius.circular(context.rp(20)),
                        border: Border.all(
                            color: on ? _cyan.withValues(alpha: 0.4) : _divider),
                      ),
                      child: Text(_filters[i], style: TextStyle(
                        color: on ? _cyan : _textDim,
                        fontSize: context.sp(11),
                        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    ),
                  );
                }),
              ]),
            ),
          ),
          _scrollArrow(visible: _filterCanScrollRight, isLeft: false),
        ]),
      );

  Widget _buildList() {
    final groups = _groupByDate(_filtered);
    return RefreshIndicator(
      color: _cyan, backgroundColor: _surface, onRefresh: _loadSessions,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            context.rp(16), context.rs(6),
            context.rp(16), context.rs(32)),
        children: groups.entries.map((entry) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                  top: context.rs(12), bottom: context.rs(6)),
              child: Text(entry.key, style: TextStyle(
                  color: _textDim, fontSize: context.sp(10),
                  fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            ),
            ...entry.value.map((s) => _buildCard(s)),
          ],
        )).toList(),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> s) {
    final duration   = s['duration_sec'] as int? ?? 0;
    final alertCount = s['alert_count']  as int? ?? 0;
    final isSafe     = alertCount == 0;
    final accent     = _accentColor(alertCount);
    // FIX: icon container size uses context.ri() — scales on small phones
    final iconBoxSize = context.ri(40).clamp(34.0, 48.0);

    return Container(
      margin: EdgeInsets.only(bottom: context.rs(10)),
      decoration: BoxDecoration(
          color: _surface, borderRadius: BorderRadius.circular(context.rp(14)),
          border: Border.all(color: _divider, width: 1)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(context.rp(14)),
          splashColor: _cyan.withValues(alpha: 0.08),
          highlightColor: _cyan.withValues(alpha: 0.04),
          onTap: () => _openSessionDetail(s),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: context.rp(16), vertical: context.rs(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Accent strip
              Container(
                width: context.rp(4), height: context.rs(44),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(context.rp(2)))),
              SizedBox(width: context.rp(12)),
              // Status icon
              Container(
                width: iconBoxSize, height: iconBoxSize,
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(context.rp(10)),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.2), width: 1)),
                child: Icon(
                  isSafe ? Icons.check_circle_outline_rounded
                         : Icons.warning_amber_rounded,
                  color: accent, size: context.ri(20))),
              SizedBox(width: context.rp(12)),
              // Date / time / duration
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_formatDate(s['started_at']), style: TextStyle(
                      color: _textPrimary, fontSize: context.sp(13),
                      fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: context.rs(3)),
                  Row(children: [
                    Icon(Icons.access_time_rounded,
                        color: _textDim, size: context.ri(11)),
                    SizedBox(width: context.rp(4)),
                    Text(_formatTime(s['started_at']), style: TextStyle(
                        color: _textDim, fontSize: context.sp(11))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.rp(6)),
                      child: Container(
                          width: context.rp(3), height: context.rp(3),
                          decoration: BoxDecoration(
                              color: _textDim, shape: BoxShape.circle))),
                    Icon(Icons.timer_outlined,
                        color: _textDim, size: context.ri(11)),
                    SizedBox(width: context.rp(4)),
                    Text(_formatDuration(duration), style: TextStyle(
                        color: _textDim, fontSize: context.sp(11))),
                  ]),
                ],
              )),
              // Badge + chevron
              Row(mainAxisSize: MainAxisSize.min, children: [
                _buildAlertBadge(alertCount),
                SizedBox(width: context.rp(4)),
                Icon(Icons.chevron_right_rounded,
                    color: _textDim, size: context.ri(18)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertBadge(int count) {
    final Color color;
    final Color bg;
    final String label;
    final IconData icon;
    if (count == 0) {
      color = _green; bg = _green.withValues(alpha: 0.1);
      label = 'Safe'; icon = Icons.check_circle_outline_rounded;
    } else if (count <= 2) {
      color = _drowsy; bg = _drowsy.withValues(alpha: 0.1);
      label = '$count alert${count > 1 ? 's' : ''}';
      icon = Icons.warning_amber_rounded;
    } else {
      color = _distracted; bg = _distracted.withValues(alpha: 0.1);
      label = '$count alerts'; icon = Icons.warning_rounded;
    }
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.rp(8), vertical: context.rs(4)),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(context.rp(6))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: context.ri(11)),
        SizedBox(width: context.rp(4)),
        Text(label, style: TextStyle(
            color: color, fontSize: context.sp(10),
            fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildEmpty() => RefreshIndicator(
        color: _cyan, backgroundColor: _surface, onRefresh: _loadSessions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history_rounded, color: _textDim, size: context.ri(56)),
              SizedBox(height: context.rs(16)),
              Text('No sessions found', style: TextStyle(
                  color: _textPrimary, fontSize: context.sp(16),
                  fontWeight: FontWeight.w600)),
              SizedBox(height: context.rs(6)),
              Text(
                _selectedFilter == 0
                    ? 'Start recording to see your drive history.'
                    : 'Try a different filter.',
                style: TextStyle(color: _textDim, fontSize: context.sp(13)),
                textAlign: TextAlign.center),
            ]),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SESSION DETAIL BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════
class _SessionDetailSheet extends StatefulWidget {
  final Map<String, dynamic> session;
  const _SessionDetailSheet({required this.session});
  @override
  State<_SessionDetailSheet> createState() => _SessionDetailSheetState();
}

class _SessionDetailSheetState extends State<_SessionDetailSheet>
    with SingleTickerProviderStateMixin {
  static const Color _sheetBg    = Color(0xFF0D1627);
  static const Color _surfaceAlt = Color(0xFF1A2235);
  static const Color _cyan       = Color(0xFF00D4FF);
  static const Color _green      = Color(0xFF00FF88);
  static const Color _drowsy     = Color(0xFFF59E0B);
  static const Color _distracted = Color(0xFFA855F7);
  static const Color _textPrimary= Color(0xFFEEF2FF);
  static const Color _textMuted  = Color(0xFF94A3B8);
  static const Color _textDim    = Color(0xFF6B7A99);
  static const Color _divider    = Color(0xFF1E2D45);

  bool _loading = true;
  Map<String, dynamic>?      _counts;
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _logs   = [];

  late AnimationController _animCtrl;
  late Animation<double>    _scaleAnim;
  late Animation<double>    _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl  = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 320));
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _loadDetail();
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _loadDetail() async {
    final id     = widget.session['id'] as int;
    final counts = await DatabaseHelper.instance.getStateCounts(id);
    final alerts = await DatabaseHelper.instance.getAlertsBySession(id);
    final logs   = await DatabaseHelper.instance.getSystemLogs(id);
    if (mounted) {
      setState(() {
      _counts = counts; _alerts = alerts; _logs = logs; _loading = false;
    });
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    final l = d.toLocal();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[l.month-1]} ${l.day}, ${l.year}';
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    final l    = d.toLocal();
    final h    = l.hour == 0 ? 12 : (l.hour > 12 ? l.hour - 12 : l.hour);
    final m    = l.minute.toString().padLeft(2, '0');
    final ampm = l.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Color _alertTypeColor(String type) =>
      type == 'DROWSY' ? _drowsy : _distracted;

  String _alertLevelLabel(int level) =>
      level == 1 ? 'L1' : level == 2 ? 'L2' : level == 3 ? 'L3' : 'L?';

  Color _logTypeColor(String type) {
    switch (type) {
      case 'SUCCESS': return _green;
      case 'WARNING': return _drowsy;
      default:        return _textMuted;
    }
  }

  String _formatLogTime(String? isoOrTime) {
    if (isoOrTime == null || isoOrTime.isEmpty) return '--:--:--';
    try {
      final d = DateTime.parse(isoOrTime).toLocal();
      return '${d.hour.toString().padLeft(2,'0')}:'
             '${d.minute.toString().padLeft(2,'0')}:'
             '${d.second.toString().padLeft(2,'0')}';
    } catch (_) {
      return isoOrTime.length >= 19 ? isoOrTime.substring(11, 19) : isoOrTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration   = widget.session['duration_sec'] as int? ?? 0;
    final alertCount = widget.session['alert_count']  as int? ?? 0;
    final isSafe     = alertCount == 0;
    final headerColor = isSafe ? _green :
        (alertCount <= 2 ? _drowsy : _distracted);
    // FIX: header icon size responsive
    final iconSize = context.ri(48).clamp(40.0, 56.0);

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.93, end: 1.0).animate(_scaleAnim),
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88),
          decoration: BoxDecoration(
            color: _sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40, offset: const Offset(0, -8)),
              BoxShadow(color: _cyan.withValues(alpha: 0.04),
                  blurRadius: 60, spreadRadius: 2),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: EdgeInsets.only(
                  top: context.rs(12), bottom: context.rs(4)),
              child: Container(
                  width: context.rp(40), height: context.rs(4),
                  decoration: BoxDecoration(
                      color: _divider,
                      borderRadius: BorderRadius.circular(2))),
            ),
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(
                  context.rp(20), context.rs(8),
                  context.rp(16), context.rs(12)),
              child: Row(children: [
                Container(
                  width: iconSize, height: iconSize,
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: headerColor.withValues(alpha: 0.35), width: 2)),
                  child: Icon(
                    isSafe ? Icons.check_circle_outline_rounded
                           : Icons.warning_amber_rounded,
                    color: headerColor, size: context.ri(24))),
                SizedBox(width: context.rp(14)),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_formatDate(widget.session['started_at']),
                      style: TextStyle(color: _textPrimary,
                          fontSize: context.sp(16), fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: context.rs(3)),
                  Text('${_formatTime(widget.session['started_at'])}  →  '
                       '${_formatTime(widget.session['ended_at'])}',
                      style: TextStyle(color: _textDim, fontSize: context.sp(12))),
                  Text(_formatDuration(duration),
                      style: TextStyle(color: _textMuted,
                          fontSize: context.sp(11), fontWeight: FontWeight.w500)),
                ])),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: context.ri(34), height: context.ri(34),
                    decoration: BoxDecoration(
                        color: _surfaceAlt, shape: BoxShape.circle,
                        border: Border.all(color: _divider, width: 1)),
                    child: Icon(Icons.close_rounded,
                        color: _textMuted, size: context.ri(18)))),
              ]),
            ),
            Divider(color: _divider, height: 1, thickness: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: _cyan))
                  : SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          context.rp(20), context.rs(16),
                          context.rp(20), context.rs(32)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('STATE BREAKDOWN'),
                          _buildStateBreakdown(),
                          SizedBox(height: context.rs(20)),
                          _sectionLabel('ALERT EVENTS'),
                          _buildAlertEvents(),
                          SizedBox(height: context.rs(20)),
                          _sectionLabel('SYSTEM LOG'),
                          _buildSystemLog(),
                        ],
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: EdgeInsets.only(bottom: context.rs(10)),
        child: Text(label, style: TextStyle(
            color: _textDim, fontSize: context.sp(10),
            fontWeight: FontWeight.w600, letterSpacing: 1.2)),
      );

  Widget _buildStateBreakdown() {
    final neutral    = _counts?['neutral_count']    as int? ?? 0;
    final drowsy     = _counts?['drowsy_count']     as int? ?? 0;
    final distracted = _counts?['distracted_count'] as int? ?? 0;
    final total      = (neutral + drowsy + distracted).toDouble();

    if (total == 0) {
      return Container(
        padding: EdgeInsets.all(context.rp(16)),
        decoration: BoxDecoration(color: _surfaceAlt,
            borderRadius: BorderRadius.circular(context.rp(12))),
        child: Center(child: Text('No state data recorded',
            style: TextStyle(color: _textDim, fontSize: context.sp(13)))));
    }

    final nPct = (neutral    / total * 100).round();
    final dPct = (drowsy     / total * 100).round();
    final xPct = (distracted / total * 100).round();

    return Container(
      padding: EdgeInsets.all(context.rp(16)),
      decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(context.rp(12)),
          border: Border.all(color: _divider, width: 1)),
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(context.rp(6)),
          child: Row(children: [
            if (neutral > 0)
              Flexible(flex: neutral, child: Container(height: context.rs(10), color: _cyan)),
            if (drowsy > 0)
              Flexible(flex: drowsy, child: Container(
                  height: context.rs(10), color: _drowsy,
                  margin: EdgeInsets.only(left: context.rp(2)))),
            if (distracted > 0)
              Flexible(flex: distracted, child: Container(
                  height: context.rs(10), color: _distracted,
                  margin: EdgeInsets.only(left: context.rp(2)))),
          ]),
        ),
        SizedBox(height: context.rs(14)),
        Row(children: [
          Expanded(child: _statePill(_cyan,       'Neutral',    '$nPct%')),
          SizedBox(width: context.rp(8)),
          Expanded(child: _statePill(_drowsy,     'Drowsy',     '$dPct%')),
          SizedBox(width: context.rp(8)),
          Expanded(child: _statePill(_distracted, 'Distracted', '$xPct%')),
        ]),
      ]),
    );
  }

  Widget _statePill(Color color, String label, String pct) => Container(
        padding: EdgeInsets.symmetric(
            vertical: context.rs(8), horizontal: context.rp(10)),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(context.rp(8)),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1)),
        child: Column(children: [
          Text(pct, style: TextStyle(color: color,
              fontSize: context.sp(15), fontWeight: FontWeight.w700)),
          SizedBox(height: context.rs(2)),
          Text(label, style: TextStyle(color: _textDim,
              fontSize: context.sp(10), fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _buildAlertEvents() {
    if (_alerts.isEmpty) {
      return Container(
        padding: EdgeInsets.all(context.rp(16)),
        decoration: BoxDecoration(color: _surfaceAlt,
            borderRadius: BorderRadius.circular(context.rp(12))),
        child: Row(children: [
          Icon(Icons.check_circle_outline_rounded,
              color: _green, size: context.ri(18)),
          SizedBox(width: context.rp(10)),
          Text('No alerts triggered — safe drive!',
              style: TextStyle(color: _green, fontSize: context.sp(13))),
        ]),
      );
    }
    return Container(
      decoration: BoxDecoration(color: _surfaceAlt,
          borderRadius: BorderRadius.circular(context.rp(12)),
          border: Border.all(color: _divider, width: 1)),
      child: Column(
        children: _alerts.asMap().entries.map((entry) {
          final i      = entry.key;
          final alert  = entry.value;
          final type   = alert['alert_type']  as String? ?? 'DROWSY';
          final level  = alert['alert_level'] as int?    ?? 1;
          final time   = _formatTime(alert['triggered_at']);
          final color  = _alertTypeColor(type);
          final isLast = i == _alerts.length - 1;
          return Column(children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: context.rp(14), vertical: context.rs(10)),
              child: Row(children: [
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.rp(7), vertical: context.rs(3)),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(context.rp(6)),
                      border: Border.all(
                          color: color.withValues(alpha: 0.3), width: 1)),
                  child: Text(_alertLevelLabel(level), style: TextStyle(
                      color: color, fontSize: context.sp(10),
                      fontWeight: FontWeight.w700))),
                SizedBox(width: context.rp(10)),
                Expanded(child: Text(
                  type == 'DROWSY' ? 'Drowsiness Detected' : 'Distraction Detected',
                  style: TextStyle(color: _textPrimary,
                      fontSize: context.sp(13), fontWeight: FontWeight.w500))),
                Text(time, style: TextStyle(
                    color: _textDim, fontSize: context.sp(11))),
              ]),
            ),
            if (!isLast) Divider(color: _divider, height: 1,
                thickness: 1, indent: context.rp(14)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildSystemLog() {
    if (_logs.isEmpty) {
      return Container(
        padding: EdgeInsets.all(context.rp(16)),
        decoration: BoxDecoration(color: _surfaceAlt,
            borderRadius: BorderRadius.circular(context.rp(12))),
        child: Text('No log entries.',
            style: TextStyle(color: _textDim, fontSize: context.sp(13))));
    }
    return Container(
      decoration: BoxDecoration(color: _surfaceAlt,
          borderRadius: BorderRadius.circular(context.rp(12)),
          border: Border.all(color: _divider, width: 1)),
      padding: EdgeInsets.all(context.rp(12)),
      child: Column(
        children: _logs.map((log) {
          final type    = log['log_type'] as String? ?? 'INFO';
          final message = log['message']  as String? ?? '';
          final rawTime = log['log_time'] as String? ?? '';
          final color   = _logTypeColor(type);
          final timeStr = _formatLogTime(rawTime);
          return Padding(
            padding: EdgeInsets.only(bottom: context.rs(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('[$timeStr]', style: TextStyle(
                  color: _textDim, fontSize: context.sp(10),
                  fontFamily: 'monospace')),
              SizedBox(width: context.rp(8)),
              Expanded(child: Text(message, style: TextStyle(
                  color: color, fontSize: context.sp(10),
                  fontFamily: 'monospace'))),
            ]),
          );
        }).toList(),
      ),
    );
  }
}