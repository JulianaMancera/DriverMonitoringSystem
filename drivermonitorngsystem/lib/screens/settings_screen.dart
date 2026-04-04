import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';         
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
              options: const ['7 days', '30 days', '90 days', 'Forever'],
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
              subtitle: 'Share all sessions as CSV',
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
            _infoTile(icon: Icons.school_rounded,  title: 'Institution', value: 'New Era University'),
            _dividerLine(),
            _infoTile(icon: Icons.people_rounded,  title: 'Authors',     value: 'Macalanda & Mancera'),
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

  Widget _iconBox(IconData icon, Color color) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: color, size: 18),
  );

  // ── SNACKBAR ───────────────────────────────────────────────────────────────

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

  // ── CSV EXPORT — FIXED for Android 13+ ────────────────────────────────────
  // Old approach: Permission.storage → always denied on Android 13+
  // New approach: write to app documents dir (no permission needed),
  //               then use share_plus to let user save/share anywhere.

  String _pad(int n) => n.toString().padLeft(2, '0');

  Future<void> _exportCSV(BuildContext ctx) async {
    try {
      // 1. Fetch all sessions
      final sessions = await DatabaseHelper.instance.getAllSessions();
      if (sessions.isEmpty) {
        if (ctx.mounted) {
          _showSnackbar(ctx, 'No sessions to export.', isError: false);
        }
        return;
      }

      // 2. Build CSV
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

      // 3. Save to app's internal documents directory
      //    → no permission needed on ANY Android version
      final docsDir  = await getApplicationDocumentsDirectory();
      final now      = DateTime.now();
      final stamp    =
          '${now.year}${_pad(now.month)}${_pad(now.day)}'
          '_${_pad(now.hour)}${_pad(now.minute)}';
      final fileName = 'bantaydrive_sessions_$stamp.csv';
      final file     = File('${docsDir.path}/$fileName');
      await file.writeAsString(buf.toString());

      if (!ctx.mounted) return;

      // 4. Open native share sheet — user picks where to save
      //    (Downloads, Google Drive, Gmail, etc.)
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

  // ── ACTION HANDLERS ────────────────────────────────────────────────────────

  void _onExportData(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Export Session Data',
            style: TextStyle(
                color: _textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'All sessions will be exported as a CSV file.\n\n'
          'A share sheet will open so you can save it to '
          'Downloads, Google Drive, email, or any app.',
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
              backgroundColor: _cyan,
              foregroundColor: _bg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _exportCSV(context);
            },
            child: const Text('Export & Share'),
          ),
        ],
      ),
    );
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