// ─────────────────────────────────────────────────────────────────────────────
// settings_screen.dart
//
// PURPOSE:
//   App configuration panel for Bantay Drive. Lets the driver control
//   alert behavior, monitoring preferences, and manage their session data.
//
// WHAT IT CONTROLS:
//   • Alert Volume     — system volume slider (via volume_controller)
//   • Alert Sensitivity— Low/Medium/High (consecutive frames before alarm)
//   • Auto-Start       — begin recording automatically when app opens
//   • Session Retention— auto-delete sessions older than 7/30 days/Forever
//   • Clear All History— wipes all sessions, alerts, logs, analytics
//
// CONNECTIONS:
//   • PreferencesHelper  — reads/writes all user preferences to SharedPrefs
//   • DatabaseHelper     — runs clearAllData() and deleteSessionsOlderThan()
//   • dbChangeCounterProvider — notifies History/Dashboard/Analytics to refresh
//   • VolumeController   — reads/sets system media volume

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/database/database_helper.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import 'package:bantaydrive/core/database/db_change_notifier.dart';
import 'dart:async';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {

  // ── COLORS ────────────────────────────────────────────────────────────────
  static const Color _bg            = Color(0xFF080E1A);
  static const Color _surface       = Color(0xFF0D1627);
  static const Color _surfaceAlt    = Color(0xFF1A2235);
  static const Color _cyan          = Color(0xFF00D4FF);
  static const Color _textPrimary   = Color(0xFFEEF2FF);
  static const Color _textSecondary = Color(0xFF6B7A99);
  static const Color _red           = Color(0xFFFF4757);
  static const Color _divider       = Color(0xFF1E2D45);

  // ── STATE ─────────────────────────────────────────────────────────────────
  bool   _isLoading        = true;
  double _alertVolume      = 0.8;
  int    _alertSensitivity = 1;
  bool   _autoStartEnabled = false;
  String _retentionPeriod  = '30 days';
  String _appVersion       = '';

  StreamSubscription<double>? _volumeSubscription;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey        _authorsKey       = GlobalKey();

  // ── RETENTION HELPERS ─────────────────────────────────────────────────────

  /// Convert retention string → days int (null = Forever, keep all)
  int? _retentionDays(String period) {
    switch (period) {
      case '7 days':  return 7;
      case '30 days': return 30;
      default:        return null; // Forever
    }
  }

  // ── LIFECYCLE ─────────────────────────────────────────────────────────────

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

    // FIX: Load app version for About section
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'v${info.version} (${info.buildNumber})';
    } catch (_) {
      version = 'v1.0.0';
    }

    if (mounted) {
      setState(() {
        _alertVolume      = systemVolume;
        _alertSensitivity = sensitivity;
        _autoStartEnabled = autoStart;
        _retentionPeriod  = retention;
        _appVersion       = version;
        _isLoading        = false;
      });
    }
  }

  void _onAuthorsExpanded(bool expanded) {
    if (!expanded) return;
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final ctx = _authorsKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration:        const Duration(milliseconds: 400),
          curve:           Curves.easeInOut,
          alignment:       0.0,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFF00D4FF))),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [

          // ── ALERT SETTINGS ─────────────────────────────────────────────────
          _sectionLabel('ALERT SETTINGS'),
          _buildCard([
            _sliderTile(
              icon:         Icons.speaker_rounded,
              iconColor:    _cyan,
              title:        'Alert Volume',
              value:        _alertVolume,
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
              icon:          Icons.tune_rounded,
              iconColor:     _cyan,
              title:         'Alert Sensitivity',
              subtitle:      'Consecutive detections before triggering an alarm',
              options:       const ['Low', 'Medium', 'High'],
              selectedIndex: _alertSensitivity,
              onChanged: (i) {
                setState(() => _alertSensitivity = i);
                PreferencesHelper.instance.setAlertSensitivity(i);
              },
            ),
          ]),

          const SizedBox(height: 24),

          // ── MONITORING SETTINGS ────────────────────────────────────────────
          _sectionLabel('MONITORING SETTINGS'),
          _buildCard([
            _toggleTile(
              icon:      Icons.play_circle_rounded,
              iconColor: _cyan,
              title:     'Auto-Start Recording',
              subtitle:  'Begin monitoring automatically when app opens',
              value:     _autoStartEnabled,
              onChanged: (v) {
                setState(() => _autoStartEnabled = v);
                PreferencesHelper.instance.setAutoStart(v);
              },
            ),
          ]),

          const SizedBox(height: 24),

          // ── DATA & PRIVACY ─────────────────────────────────────────────────
          _sectionLabel('DATA & PRIVACY'),
          _buildCard([
            _dropdownTile(
              icon:      Icons.history_rounded,
              iconColor: _cyan,
              title:     'Session Retention',
              subtitle:  'Auto-delete sessions older than selected period',
              value:     _retentionPeriod,
              options:   const ['7 days', '30 days', 'Forever'],
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _retentionPeriod = v);
                await PreferencesHelper.instance.setRetention(v);
                // FIX: Actually apply deletion when retention changes.
                // Original code saved the preference but never ran the cleanup.
                final days = _retentionDays(v);
                if (days != null) {
                  await DatabaseHelper.instance.deleteSessionsOlderThan(days);
                  ref.read(dbChangeCounterProvider.notifier).increment();
                }
              },
            ),
            _dividerLine(),
            _actionTile(
              icon:       Icons.delete_outline_rounded,
              iconColor:  _red,
              title:      'Clear All History',
              subtitle:   'Permanently delete all session data',
              titleColor: _red,
              onTap:      () => _onClearHistory(context),
            ),
          ]),

          const SizedBox(height: 24),

          // ── ABOUT ──────────────────────────────────────────────────────────
          _sectionLabel('ABOUT'),
          _buildCard([
            _infoTile(
              icon:  Icons.school_rounded,
              title: 'Institution',
              value: 'New Era University',
            ),
            _dividerLine(),
            _infoTile(
              icon:  Icons.psychology_rounded,
              title: 'Model',
              value: 'DMS-HybridNet v2.1',
            ),
            _dividerLine(),
            // FIX: App version now shown — useful for thesis defense
            _infoTile(
              icon:  Icons.info_outline_rounded,
              title: 'Version',
              value: _appVersion,
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
            style: const TextStyle(
                color:         Color(0xFF6B7A99),
                fontSize:      11,
                fontWeight:    FontWeight.w600,
                letterSpacing: 1.2)),
      );

  Widget _buildCard(List<Widget> children) => Container(
        decoration: BoxDecoration(
            color:        _surface,
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(color: _divider, width: 1)),
        child: Column(children: children),
      );

  Widget _dividerLine() =>
      Divider(color: _divider, height: 1, thickness: 1, indent: 56);

  Widget _toggleTile({
    required IconData        icon,
    required Color           iconColor,
    required String          title,
    String?                  subtitle,
    required bool            value,
    required ValueChanged<bool> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color:      Color(0xFFEEF2FF),
                        fontSize:   14,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF6B7A99), fontSize: 12)),
                ],
              ])),
          Switch(
            value:              value,
            onChanged:          onChanged,
            activeThumbColor:   _cyan,
            activeTrackColor:   _cyan.withValues(alpha: 0.3),
            inactiveThumbColor: _textSecondary,
            inactiveTrackColor: _surfaceAlt,
          ),
        ]),
      );

  Widget _sliderTile({
    required IconData          icon,
    required Color             iconColor,
    required String            title,
    String?                    subtitle,
    required double            value,
    required double            min,
    required double            max,
    required String            displayValue,
    required ValueChanged<double> onChanged,
    int?                       divisions,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(children: [
          Row(children: [
            _iconBox(icon, iconColor),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color:      Color(0xFFEEF2FF),
                          fontSize:   14,
                          fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF6B7A99), fontSize: 12)),
                  ],
                ])),
            Text(displayValue,
                style: const TextStyle(
                    color:      Color(0xFF00D4FF),
                    fontSize:   14,
                    fontWeight: FontWeight.bold)),
          ]),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor:   _cyan,
              inactiveTrackColor: _divider,
              thumbColor:         _cyan,
              overlayColor:       _cyan.withValues(alpha: 0.15),
              trackHeight:        3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value:     value,
              min:       min,
              max:       max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ]),
      );

  Widget _segmentedTile({
    required IconData          icon,
    required Color             iconColor,
    required String            title,
    String?                    subtitle,
    required List<String>      options,
    required int               selectedIndex,
    required ValueChanged<int> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconBox(icon, iconColor),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color:      Color(0xFFEEF2FF),
                          fontSize:   14,
                          fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF6B7A99), fontSize: 12)),
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
                        left:  i == 0 ? 0 : 4,
                        right: i == options.length - 1 ? 0 : 4),
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
                          color:      selected ? _cyan : _textSecondary,
                          fontSize:   13,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        )),
                  ),
                ),
              );
            }),
          ),
        ]),
      );

  Widget _dropdownTile({
    required IconData              icon,
    required Color                 iconColor,
    required String                title,
    String?                        subtitle,
    required String                value,
    required List<String>          options,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color:      Color(0xFFEEF2FF),
                        fontSize:   14,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF6B7A99), fontSize: 12)),
                ],
              ])),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value:         value,
              dropdownColor: _surfaceAlt,
              icon: const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF6B7A99), size: 20),
              style: const TextStyle(
                  color: Color(0xFF00D4FF), fontSize: 13),
              items: options
                  .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(o,
                          style: const TextStyle(
                              color: Color(0xFFEEF2FF), fontSize: 13))))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ]),
      );

  Widget _actionTile({
    required IconData    icon,
    required Color       iconColor,
    required String      title,
    String?              subtitle,
    Color?               titleColor,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            _iconBox(icon, iconColor),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color:      titleColor ?? _textPrimary,
                          fontSize:   14,
                          fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF6B7A99), fontSize: 12)),
                  ],
                ])),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF6B7A99), size: 20),
          ]),
        ),
      );

  Widget _infoTile({
    required IconData icon,
    required String   title,
    required String   value,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          _iconBox(icon, _textSecondary),
          const SizedBox(width: 14),
          Expanded(child: Text(title,
              style: const TextStyle(
                  color:      Color(0xFF6B7A99),
                  fontSize:   14,
                  fontWeight: FontWeight.w400))),
          Text(value,
              style: const TextStyle(
                  color:      Color(0xFFEEF2FF),
                  fontSize:   13,
                  fontWeight: FontWeight.w500)),
        ]),
      );

  // ── AUTHORS TILE ───────────────────────────────────────────────────────────

  Widget _authorsTile() => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key:             _authorsKey,
          tilePadding:     const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: _iconBox(Icons.people_rounded, _textSecondary),
          title: const Text('Authors',
              style: TextStyle(
                  color:      Color(0xFF6B7A99),
                  fontSize:   14,
                  fontWeight: FontWeight.w400)),
          trailing:           const Icon(Icons.expand_more_rounded,
              color: Color(0xFF6B7A99), size: 20),
          collapsedIconColor: _textSecondary,
          iconColor:          _cyan,
          onExpansionChanged: _onAuthorsExpanded,
          children: [
            _githubLink(
              name:     'Juliana Mancera',
              username: 'JulianaMancera',
              url:      'https://github.com/JulianaMancera',
            ),
            const SizedBox(height: 8),
            _githubLink(
              name:     'Pia Katleya Macalanda',
              username: 'PiaMacalanda',
              url:      'https://github.com/PiaMacalanda',
            ),
          ],
        ),
      );

  Widget _githubLink({
    required String name,
    required String username,
    required String url,
  }) =>
      InkWell(
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
            color:        _surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: _divider, width: 1),
          ),
          child: Row(children: [
            Container(
              width:  32, height: 32,
              decoration: BoxDecoration(
                  color:        _cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.code_rounded,
                  color: Color(0xFF00D4FF), size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color:      Color(0xFFEEF2FF),
                          fontSize:   13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 1),
                  Text('github.com/$username',
                      style: const TextStyle(
                          color:      Color(0xFF00D4FF),
                          fontSize:   11,
                          fontWeight: FontWeight.w400)),
                ])),
            const Icon(Icons.open_in_new_rounded,
                color: Color(0xFF6B7A99), size: 14),
          ]),
        ),
      );

  Widget _iconBox(IconData icon, Color color) => Container(
        width:  36, height: 36,
        decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.12),
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
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── CLEAR HISTORY ──────────────────────────────────────────────────────────

  void _onClearHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All History',
            style: TextStyle(
                color: Color(0xFFFF4757), fontWeight: FontWeight.bold)),
        content: const Text(
          'This will permanently delete ALL session data including '
          'alerts, logs, and analytics. This action cannot be undone.',
          style: TextStyle(color: Color(0xFF6B7A99), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7A99))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await DatabaseHelper.instance.clearAllData();
              // FIX: Riverpod 3.x — use .increment() not .state++
              ref.read(dbChangeCounterProvider.notifier).increment();
              // FIX: Also reset clearGlasses pref since session context is gone
              await PreferencesHelper.instance.setClearGlasses(false);
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