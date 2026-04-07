import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/database/database_helper.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import 'dart:async';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool   _isLoading        = true;
  double _alertVolume      = 0.8;
  int    _alertSensitivity = 1;
  bool   _autoStartEnabled = false;
  String _retentionPeriod  = '30 days';

  static const Color _bg            = Color(0xFF080E1A);
  static const Color _surface       = Color(0xFF0D1627);
  static const Color _surfaceAlt    = Color(0xFF1A2235);
  static const Color _cyan          = Color(0xFF00D4FF);
  static const Color _textPrimary   = Color(0xFFEEF2FF);
  static const Color _textSecondary = Color(0xFF6B7A99);
  static const Color _red           = Color(0xFFFF4757);
  static const Color _divider       = Color(0xFF1E2D45);

  StreamSubscription<double>? _volumeSubscription;

  // ScrollController to programmatically scroll the list
  final ScrollController _scrollController = ScrollController();

  // GlobalKey to find the authors tile position
  final GlobalKey _authorsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _volumeSubscription = VolumeController.instance.addListener((volume) {
      if (mounted) setState(() => _alertVolume = volume);
    }, fetchInitialVolume: true);
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs        = PreferencesHelper.instance;
    final sensitivity  = await prefs.getAlertSensitivity();
    final autoStart    = await prefs.getAutoStart();
    final retention    = await prefs.getRetention();
    final systemVolume = await VolumeController.instance.getVolume();
    if (mounted) {
      setState(() {
        _alertVolume      = systemVolume;
        _alertSensitivity = sensitivity;
        _autoStartEnabled = autoStart;
        _retentionPeriod  = retention;
        _isLoading        = false;
      });
    }
  }

  /// Called when the authors ExpansionTile is expanded.
  /// Waits for the animation to finish, then scrolls so the
  /// expanded content is fully visible.
  void _onAuthorsExpanded(bool expanded) {
    if (!expanded) return;
    // Wait for the expansion animation (~300 ms) to complete
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final ctx = _authorsKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        body: const Center(
            child: CircularProgressIndicator(color: Color(0xFF00D4FF))),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _sectionLabel('ALERT SETTINGS'),
          _buildCard([
            _sliderTile(
              icon: Icons.speaker_rounded,
              iconColor: _cyan,
              title: 'Alert Volume',
              value: _alertVolume,
              min: 0.0, max: 1.0,
              displayValue: '${(_alertVolume * 100).round()}%',
              onChanged: (v) {
                setState(() => _alertVolume = v);
                VolumeController.instance.setVolume(v);
                PreferencesHelper.instance.setAlertVolume(v);
              },
            ),
            _dividerLine(),
            _segmentedTile(
              icon: Icons.tune_rounded,
              iconColor: _cyan,
              title: 'Alert Sensitivity',
              subtitle: 'Consecutive detections before Level 3 alarm',
              options: const ['Low', 'Medium', 'High'],
              selectedIndex: _alertSensitivity,
              onChanged: (i) {
                setState(() => _alertSensitivity = i);
                PreferencesHelper.instance.setAlertSensitivity(i);
              },
            ),
          ]),
          const SizedBox(height: 24),
          _sectionLabel('MONITORING SETTINGS'),
          _buildCard([
            _toggleTile(
              icon: Icons.play_circle_rounded,
              iconColor: _cyan,
              title: 'Auto-Start Recording',
              subtitle: 'Begin monitoring automatically when app opens',
              value: _autoStartEnabled,
              onChanged: (v) {
                setState(() => _autoStartEnabled = v);
                PreferencesHelper.instance.setAutoStart(v);
              },
            ),
          ]),
          const SizedBox(height: 24),
          _sectionLabel('DATA & PRIVACY'),
          _buildCard([
            _dropdownTile(
              icon: Icons.history_rounded,
              iconColor: _cyan,
              title: 'Session Retention',
              subtitle: 'Auto-delete sessions older than',
              value: _retentionPeriod,
              options: const ['7 days', '30 days', 'Forever'],
              onChanged: (v) {
                setState(() => _retentionPeriod = v!);
                PreferencesHelper.instance.setRetention(v!);
              },
            ),
            _dividerLine(),
            _actionTile(
              icon: Icons.download_rounded,
              iconColor: _cyan,
              title: 'Export Session Data',
              subtitle: 'Export as CSV or PDF report with analytics',
              onTap: () => _onExportData(context),
            ),
            _dividerLine(),
            _actionTile(
              icon: Icons.delete_outline_rounded,
              iconColor: _red,
              title: 'Clear All History',
              subtitle: 'Permanently delete all session data',
              titleColor: _red,
              onTap: () => _onClearHistory(context),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionLabel('ABOUT'),
          _buildCard([
            _infoTile(
              icon: Icons.school_rounded,
              title: 'Institution',
              value: 'New Era University',
            ),
            _dividerLine(),
            _authorsTile(),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── TILE WIDGETS ───────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
    child: Text(label,
        style: TextStyle(
            color: _textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2)),
  );

  Widget _buildCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 1)),
    child: Column(children: children),
  );

  Widget _dividerLine() =>
      Divider(color: _divider, height: 1, thickness: 1, indent: 56);

  Widget _toggleTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        _iconBox(icon, iconColor),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(color: _textSecondary, fontSize: 12))
          ],
        ])),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: _cyan,
          activeTrackColor: _cyan.withValues(alpha: 0.3),
          inactiveThumbColor: _textSecondary,
          inactiveTrackColor: _surfaceAlt,
        ),
      ]),
    );
  }

  Widget _sliderTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(children: [
        Row(children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(color: _textSecondary, fontSize: 12))
            ],
          ])),
          Text(displayValue,
              style: TextStyle(
                  color: _cyan,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ]),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: _cyan,
            inactiveTrackColor: _divider,
            thumbColor: _cyan,
            overlayColor: _cyan.withValues(alpha: 0.15),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }

  Widget _segmentedTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required List<String> options,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(color: _textSecondary, fontSize: 12))
            ],
          ])),
        ]),
        const SizedBox(height: 12),
        Row(
          children: List.generate(options.length, (i) {
            final selected = i == selectedIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.only(
                    left: i == 0 ? 0 : 4,
                    right: i == options.length - 1 ? 0 : 4,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? _cyan.withValues(alpha: 0.15)
                        : _surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: selected ? _cyan : _divider, width: 1),
                  ),
                  child: Text(options[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? _cyan : _textSecondary,
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }

  Widget _dropdownTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        _iconBox(icon, iconColor),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(color: _textSecondary, fontSize: 12))
          ],
        ])),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            dropdownColor: _surfaceAlt,
            icon: Icon(Icons.chevron_right_rounded,
                color: _textSecondary, size: 20),
            style: TextStyle(color: _cyan, fontSize: 13),
            items: options
                .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(o,
                        style:
                            TextStyle(color: _textPrimary, fontSize: 13))))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: titleColor ?? _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(color: _textSecondary, fontSize: 12))
            ],
          ])),
          Icon(Icons.chevron_right_rounded, color: _textSecondary, size: 20),
        ]),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        _iconBox(icon, _textSecondary),
        const SizedBox(width: 14),
        Expanded(child: Text(title,
            style: TextStyle(
                color: _textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400))),
        Text(value,
            style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ── AUTHORS TILE WITH EXPANDABLE GITHUB LINKS + AUTO-SCROLL ───────────────

  Widget _authorsTile() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: _authorsKey,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        leading: _iconBox(Icons.people_rounded, _textSecondary),
        title: Text('Authors',
            style: TextStyle(
                color: _textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400)),
        trailing: Icon(Icons.expand_more_rounded,
            color: _textSecondary, size: 20),
        collapsedIconColor: _textSecondary,
        iconColor: _cyan,
        onExpansionChanged: _onAuthorsExpanded,
        children: [
           _githubLink(
            name: 'Juliana Mancera',
            username: 'JulianaMancera',
            url: 'https://github.com/JulianaMancera',
          ),
          const SizedBox(height: 8),
          _githubLink(
            name: 'Pia Katleya Macalanda',
            username: 'PiaMacalanda',
            url: 'https://github.com/PiaMacalanda',
          ),
        ],
      ),
    );
  }

  Widget _githubLink({
    required String name,
    required String username,
    required String url,
  }) {
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _divider, width: 1),
        ),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.code_rounded, color: _cyan, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 1),
              Text('github.com/$username',
                  style: TextStyle(
                      color: _cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w400)),
            ]),
          ),
          Icon(Icons.open_in_new_rounded, color: _textSecondary, size: 14),
        ]),
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: color, size: 18),
  );

  // SNACKBAR 
  void _showSnackbar(BuildContext context, String message,
      {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: TextStyle(
              color: isError ? Colors.white : _bg, fontSize: 13)),
      backgroundColor: isError ? _red : _cyan,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 5),
    ));
  }

  // CSV EXPORT
  String _pad(int n) => n.toString().padLeft(2, '0');

  Future<void> _exportCSV(BuildContext ctx) async {
    try {
      final sessions = await DatabaseHelper.instance.getAllSessions();
      if (sessions.isEmpty) {
        if (ctx.mounted) {
          _showSnackbar(ctx, 'No sessions to export.', isError: false);
        }
        return;
      }

      final buf = StringBuffer();
      buf.writeln(
          'Session ID,Date,Start Time,End Time,Duration (sec),'
          'Alertness Avg (%),Safety Score (%),Alert Count');

      for (final s in sessions) {
        final id       = s['id'] as int;
        final alerts   = await DatabaseHelper.instance.getAlertsBySession(id);
        final started  = s['started_at'] as String? ?? '';
        final ended    = s['ended_at']   as String? ?? '';
        final duration = s['duration_sec'] as int? ?? 0;
        final alertAvg = (s['alertness_avg'] as double? ?? 0.0).toStringAsFixed(1);
        final safety   = (s['safety_score']  as double? ?? 0.0).toStringAsFixed(1);

        final sd = DateTime.tryParse(started);
        final ed = DateTime.tryParse(ended);
        final date  = sd != null
            ? '${sd.year}-${_pad(sd.month)}-${_pad(sd.day)}'
            : '';
        final sTime = sd != null
            ? '${_pad(sd.hour)}:${_pad(sd.minute)}:${_pad(sd.second)}'
            : '';
        final eTime = ed != null
            ? '${_pad(ed.hour)}:${_pad(ed.minute)}:${_pad(ed.second)}'
            : '';

        buf.writeln(
            '$id,$date,$sTime,$eTime,$duration,$alertAvg,$safety,${alerts.length}');
      }

      final docsDir  = await getApplicationDocumentsDirectory();
      final now      = DateTime.now();
      final stamp    =
          '${now.year}${_pad(now.month)}${_pad(now.day)}'
          '_${_pad(now.hour)}${_pad(now.minute)}';
      final fileName = 'bantaydrive_sessions_$stamp.csv';
      final file     = File('${docsDir.path}/$fileName');
      await file.writeAsString(buf.toString());

      if (!ctx.mounted) return;

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: fileName)],
        subject: 'Bantay Drive Session Export',
        text: 'Bantay Drive — ${sessions.length} sessions exported',
      );

    } catch (e) {
      if (ctx.mounted) {
        _showSnackbar(ctx, 'Export failed: $e', isError: true);
      }
    }
  }

  //  ACTION HANDLERS
  void _onExportData(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Export Session Data',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Choose your export format.\n\n'
          '• CSV — raw session table for spreadsheets\n'
          '• PDF — formatted report with safety scores & analytics\n\n'
          'A share sheet will open so you can save to Downloads, '
          'Google Drive, email, or any app.',
          style: TextStyle(color: _textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _cyan,
              side: BorderSide(color: _cyan.withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _exportCSV(context);
            },
            child: const Text('CSV'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _cyan,
              foregroundColor: _bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _exportPDF(context);
            },
            child: const Text('PDF Report'),
          ),
        ],
      ),
    );
  }


  // ── PDF EXPORT ─────────────────────────────────────────────────────────────
  /// Generates a formatted PDF report containing:
  ///   1. Summary analytics (total sessions, alerts, avg safety score)
  ///   2. Per-session table with date, duration, alertness, safety score, alerts
  /// Uses the `pdf` package (pdf: ^3.x). Add to pubspec.yaml if not present.
  Future<void> _exportPDF(BuildContext ctx) async {
    try {
      final sessions = await DatabaseHelper.instance.getAllSessions();
      if (sessions.isEmpty) {
        if (ctx.mounted) _showSnackbar(ctx, 'No sessions to export.', isError: false);
        return;
      }

      // ── Gather per-session alert counts ──────────────────────────────────
      final alertCounts = <int, int>{};
      for (final s in sessions) {
        final id = s['id'] as int;
        final alerts = await DatabaseHelper.instance.getAlertsBySession(id);
        alertCounts[id] = alerts.length;
      }

      // ── Compute summary analytics ────────────────────────────────────────
      final totalSessions = sessions.length;
      final completedSessions = sessions.where((s) => s['ended_at'] != null).toList();
      final totalAlerts   = alertCounts.values.fold(0, (a, b) => a + b);
      final avgSafety     = completedSessions.isEmpty ? 0.0
          : completedSessions.map((s) => s['safety_score'] as double? ?? 0.0)
              .reduce((a, b) => a + b) / completedSessions.length;
      final avgAlertness  = completedSessions.isEmpty ? 0.0
          : completedSessions.map((s) => s['alertness_avg'] as double? ?? 0.0)
              .reduce((a, b) => a + b) / completedSessions.length;
      final safeSessions  = alertCounts.values.where((c) => c == 0).length;

      // ── Build PDF ────────────────────────────────────────────────────────
      final pdf  = pw.Document();
      final now  = DateTime.now();
      final dateStr = '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
      final timeStr = '${_pad(now.hour)}:${_pad(now.minute)}';

      // Color palette matching app theme
      const cyanColor   = PdfColor.fromInt(0xFF00D4FF);
      const darkBg      = PdfColor.fromInt(0xFF0D1627);
      const surfaceBg   = PdfColor.fromInt(0xFF1A2235);
      const textPrimary = PdfColor.fromInt(0xFFEEF2FF);
      const textMuted   = PdfColor.fromInt(0xFF6B7A99);
      const greenColor  = PdfColor.fromInt(0xFF00FF88);
      const redColor    = PdfColor.fromInt(0xFFFF4757);
      const orangeColor = PdfColor.fromInt(0xFFFFA500);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
          build: (pw.Context pdfCtx) => [

            // ── HEADER ──────────────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: darkBg,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BANTAY DRIVE',
                        style: pw.TextStyle(
                          font: pw.Font.helveticaBold(),
                          fontSize: 22,
                          color: cyanColor,
                          letterSpacing: 2,
                        )),
                      pw.SizedBox(height: 4),
                      pw.Text('Driver Monitoring System — Session Report',
                        style: pw.TextStyle(fontSize: 10, color: textMuted)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Generated', style: pw.TextStyle(fontSize: 8, color: textMuted)),
                      pw.Text('$dateStr  $timeStr',
                        style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 10, color: textPrimary)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // ── ANALYTICS SUMMARY ────────────────────────────────────────
            pw.Text('ANALYTICS SUMMARY',
              style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 10,
                color: textMuted, letterSpacing: 1.5)),
            pw.SizedBox(height: 10),
            pw.Row(children: [
              _pdfStatBox('Total Sessions',  '$totalSessions',             cyanColor),
              pw.SizedBox(width: 8),
              _pdfStatBox('Total Alerts',    '$totalAlerts',               totalAlerts == 0 ? greenColor : redColor),
              pw.SizedBox(width: 8),
              _pdfStatBox('Avg Safety Score','${avgSafety.toStringAsFixed(1)}%', _pdfScoreColor(avgSafety)),
              pw.SizedBox(width: 8),
              _pdfStatBox('Avg Alertness',   '${avgAlertness.toStringAsFixed(1)}%', cyanColor),
              pw.SizedBox(width: 8),
              _pdfStatBox('Safe Drives',     '$safeSessions',              safeSessions == totalSessions ? greenColor : orangeColor),
            ]),
            pw.SizedBox(height: 24),

            // ── SESSION TABLE ─────────────────────────────────────────────
            pw.Text('SESSION HISTORY',
              style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 10,
                color: textMuted, letterSpacing: 1.5)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: surfaceBg, width: 1),
                bottom: pw.BorderSide(color: surfaceBg, width: 1),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2), // Date
                1: const pw.FlexColumnWidth(1.4), // Start
                2: const pw.FlexColumnWidth(1.2), // Duration
                3: const pw.FlexColumnWidth(1.3), // Alertness
                4: const pw.FlexColumnWidth(1.4), // Safety Score
                5: const pw.FlexColumnWidth(1.0), // Alerts
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: darkBg),
                  children: [
                    _pdfTh('DATE'),
                    _pdfTh('START'),
                    _pdfTh('DURATION'),
                    _pdfTh('ALERTNESS'),
                    _pdfTh('SAFETY SCORE'),
                    _pdfTh('ALERTS'),
                  ],
                ),
                // Data rows
                ...sessions.map((s) {
                  final id         = s['id'] as int;
                  final alertCount = alertCounts[id] ?? 0;
                  final started    = s['started_at'] as String? ?? '';
                  final duration   = s['duration_sec'] as int? ?? 0;
                  final alertness  = (s['alertness_avg'] as double? ?? 0.0);
                  final safety     = (s['safety_score']  as double? ?? 0.0);
                  final sd         = DateTime.tryParse(started)?.toLocal();
                  final dateLabel  = sd != null
                      ? '${_pdfMonth(sd.month)} ${sd.day}, ${sd.year}' : '—';
                  final timeLabel  = sd != null
                      ? '${_padAmPm(sd.hour, sd.minute)}' : '—';
                  final durLabel   = _formatDurationPdf(duration);
                  final safetyColor = _pdfScoreColor(safety);

                  return pw.TableRow(children: [
                    _pdfTd(dateLabel),
                    _pdfTd(timeLabel),
                    _pdfTd(durLabel),
                    _pdfTd('${alertness.toStringAsFixed(1)}%'),
                    _pdfTdColored('${safety.toStringAsFixed(1)}%', safetyColor),
                    _pdfTdColored('$alertCount', alertCount == 0 ? greenColor : (alertCount <= 2 ? orangeColor : redColor)),
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 24),

            // ── FOOTER ──────────────────────────────────────────────────────
            pw.Divider(color: surfaceBg),
            pw.SizedBox(height: 6),
            pw.Text(
              'Safety Score = Average Alertness − Alert Penalty  '
              '(L1 −2 pts, L2 −4 pts, L3 −8 pts), clamped to [0, 100].',
              style: pw.TextStyle(fontSize: 7, color: textMuted),
            ),
            pw.Text(
              'Bantay Drive · Driver Monitoring System · New Era University',
              style: pw.TextStyle(fontSize: 7, color: textMuted),
            ),
          ],
        ),
      );

      // ── Save & share ──────────────────────────────────────────────────────
      final bytes    = await pdf.save();
      final docsDir  = await getApplicationDocumentsDirectory();
      final stamp    = '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}';
      final fileName = 'bantaydrive_report_$stamp.pdf';
      final file     = File('${docsDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (!ctx.mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
        subject: 'Bantay Drive Session Report',
        text: 'Bantay Drive — $totalSessions sessions, avg safety ${avgSafety.toStringAsFixed(1)}%',
      );
    } catch (e) {
      if (ctx.mounted) _showSnackbar(ctx, 'PDF export failed: $e', isError: true);
    }
  }

  // ── PDF HELPERS ───────────────────────────────────────────────────────────

  PdfColor _pdfScoreColor(double score) {
    if (score >= 80) return const PdfColor.fromInt(0xFF00FF88);
    if (score >= 60) return const PdfColor.fromInt(0xFFFFA500);
    return const PdfColor.fromInt(0xFFFF4757);
  }

  pw.Widget _pdfStatBox(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFF0D1627),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value,
              style: pw.TextStyle(
                font: pw.Font.helveticaBold(),
                fontSize: 16,
                color: color,
              )),
            pw.SizedBox(height: 3),
            pw.Text(label,
              style: pw.TextStyle(fontSize: 7, color: const PdfColor.fromInt(0xFF6B7A99))),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfTh(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(text,
      style: pw.TextStyle(
        font: pw.Font.helveticaBold(),
        fontSize: 8,
        color: const PdfColor.fromInt(0xFF6B7A99),
        letterSpacing: 0.8,
      )),
  );

  pw.Widget _pdfTd(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Text(text,
      style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFFCBD5E1))),
  );

  pw.Widget _pdfTdColored(String text, PdfColor color) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: pw.Text(text,
      style: pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 9, color: color)),
  );

  String _formatDurationPdf(int sec) {
    final h = sec ~/ 3600; final m = (sec % 3600) ~/ 60; final s = sec % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _pdfMonth(int m) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[m - 1];
  }

  String _padAmPm(int hour, int minute) {
    final h    = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '$h:${minute.toString().padLeft(2, '0')} $ampm';
  }

  void _onClearHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear All History',
            style: TextStyle(
                color: _red, fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete ALL session data including '
          'alerts, logs, and analytics. This action cannot be undone.',
          style: TextStyle(color: _textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await DatabaseHelper.instance.clearAllData();
              if (context.mounted) {
                _showSnackbar(context, 'All history cleared.',
                    isError: false);
              }
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}