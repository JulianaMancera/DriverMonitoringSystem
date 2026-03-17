import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';

// ─────────────────────────────────────────────────────────────────────────────
// history_screen.dart
// Bantay Drive — History Screen
// Auto-refreshes via DbChangeNotifier. Pull-to-refresh as backup.
// ─────────────────────────────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // ── COLORS ─────────────────────────────────────────────────────────────────
  static const Color _bg          = Color(0xFF080E1A);
  static const Color _surface     = Color(0xFF0D1627);
  static const Color _surfaceAlt  = Color(0xFF1A2235);
  static const Color _cyan        = Color(0xFF00D4FF);
  static const Color _green       = Color(0xFF00FF88);
  static const Color _red         = Color(0xFFFF4757);
  static const Color _orange      = Color(0xFFFFA500);
  static const Color _textPrimary = Color(0xFFEEF2FF);
  static const Color _textDim     = Color(0xFF6B7A99);
  static const Color _divider     = Color(0xFF1E2D45);

  // ── STATE ──────────────────────────────────────────────────────────────────
  bool   _isLoading      = true;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _filtered = [];
  int    _selectedFilter = 0;
  final  TextEditingController _searchCtrl = TextEditingController();

  final List<String> _filters = [
    'All', 'This Week', 'This Month', 'With Alerts', 'Safe Drives',
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _searchCtrl.addListener(_applyFilter);

    // Auto-refresh whenever DatabaseHelper writes new data
    DbChangeNotifier.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    DbChangeNotifier.instance.removeListener(_onDataChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDataChanged() => _loadSessions();

  // ─────────────────────────────────────────────────────────────────────────
  // DATA
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);

    final sessions = await DatabaseHelper.instance.getAllSessions();

    final enriched = <Map<String, dynamic>>[];
    for (final s in sessions) {
      final alerts = await DatabaseHelper.instance
          .getAlertsBySession(s['id'] as int);
      enriched.add({...s, 'alert_count': alerts.length});
    }

    if (mounted) {
      setState(() {
        _sessions  = enriched;
        _isLoading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase();
    final now   = DateTime.now();
    List<Map<String, dynamic>> result = List.from(_sessions);

    if (query.isNotEmpty) {
      result = result.where((s) =>
          (s['started_at'] ?? '').toString().toLowerCase().contains(query)
      ).toList();
    }

    switch (_selectedFilter) {
      case 1:
        final since = now.subtract(const Duration(days: 7));
        result = result.where((s) {
          final d = DateTime.tryParse(s['started_at'] ?? '');
          return d != null && d.isAfter(since);
        }).toList();
        break;
      case 2:
        result = result.where((s) {
          final d = DateTime.tryParse(s['started_at'] ?? '');
          return d != null && d.month == now.month && d.year == now.year;
        }).toList();
        break;
      case 3:
        result = result.where((s) =>
            (s['alert_count'] as int? ?? 0) > 0).toList();
        break;
      case 4:
        result = result.where((s) =>
            (s['alert_count'] as int? ?? 0) == 0).toList();
        break;
    }

    setState(() => _filtered = result);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

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
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    final h    = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final m    = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _dateGroupLabel(String? iso) {
    if (iso == null) return 'UNKNOWN';
    final d   = DateTime.tryParse(iso);
    if (d == null) return 'UNKNOWN';
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day   = DateTime(d.year, d.month, d.day);
    if (day == today) return 'TODAY';
    if (day == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return _formatDate(iso).toUpperCase();
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> sessions) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in sessions) {
      final lbl = _dateGroupLabel(s['started_at']);
      groups.putIfAbsent(lbl, () => []).add(s);
    }
    return groups;
  }

  Color _scoreColor(double score) {
    if (score >= 80) return _green;
    if (score >= 60) return _orange;
    return _red;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
                : _filtered.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEARCH BAR — refresh button removed
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchCtrl,
          style: TextStyle(color: _textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search sessions...',
            hintStyle: TextStyle(color: _textDim, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded, color: _textDim, size: 18),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER CHIPS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_filters.length, (i) {
            final on = i == _selectedFilter;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedFilter = i);
                _applyFilter();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? _cyan.withOpacity(0.15) : _surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: on ? _cyan.withOpacity(0.4) : _divider,
                  ),
                ),
                child: Text(
                  _filters[i],
                  style: TextStyle(
                    color: on ? _cyan : _textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION LIST — wrapped in RefreshIndicator for pull-to-refresh
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildList() {
    final groups = _groupByDate(_filtered);

    return RefreshIndicator(
      color: _cyan,
      backgroundColor: _surface,
      onRefresh: _loadSessions,  // pull-to-refresh as manual backup
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: groups.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    color: _textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ...entry.value.map((s) => _buildCard(s)),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCard(Map<String, dynamic> s) {
    final score      = (s['safety_score'] as double? ?? 0.0);
    final duration   = s['duration_sec'] as int? ?? 0;
    final alertCount = s['alert_count'] as int? ?? 0;
    final color      = _scoreColor(score);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _divider, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            // TODO: navigate to session detail
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Score circle
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withOpacity(0.3), width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '${score.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: score >= 100 ? 10 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Date + time + duration
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(s['started_at']),
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(_formatTime(s['started_at']),
                              style: TextStyle(color: _textDim, fontSize: 11)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Container(
                              width: 3, height: 3,
                              decoration: BoxDecoration(
                                  color: _textDim, shape: BoxShape.circle),
                            ),
                          ),
                          Text(_formatDuration(duration),
                              style: TextStyle(color: _textDim, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Alert badge + chevron
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildAlertBadge(alertCount),
                    const SizedBox(height: 6),
                    Icon(Icons.chevron_right_rounded, color: _divider, size: 18),
                  ],
                ),
              ],
            ),
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
      color = _green;
      bg    = _green.withOpacity(0.1);
      label = 'Safe';
      icon  = Icons.check_circle_outline_rounded;
    } else if (count <= 2) {
      color = _orange;
      bg    = _orange.withOpacity(0.1);
      label = '$count alert${count > 1 ? 's' : ''}';
      icon  = Icons.warning_amber_rounded;
    } else {
      color = _red;
      bg    = _red.withOpacity(0.1);
      label = '$count alerts';
      icon  = Icons.warning_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return RefreshIndicator(
      color: _cyan,
      backgroundColor: _surface,
      onRefresh: _loadSessions,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, color: _textDim, size: 56),
              const SizedBox(height: 16),
              Text(
                'No sessions found',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedFilter == 0
                    ? 'Start recording to see your drive history.'
                    : 'Try a different filter.',
                style: TextStyle(color: _textDim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }
}