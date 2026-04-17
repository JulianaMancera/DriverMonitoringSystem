import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/database/database_helper.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import 'package:bantaydrive/core/database/db_change_notifier.dart';
import '../utils/responsive.dart';
import 'dart:async';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const Color _bg            = Color(0xFF080E1A);
  static const Color _surface       = Color(0xFF0D1627);
  static const Color _surfaceAlt    = Color(0xFF1A2235);
  static const Color _cyan          = Color(0xFF00D4FF);
  static const Color _textPrimary   = Color(0xFFEEF2FF);
  static const Color _textSecondary = Color(0xFF6B7A99);
  static const Color _red           = Color(0xFFFF4757);
  static const Color _divider       = Color(0xFF1E2D45);

  bool   _isLoading        = true;
  double _alertVolume      = 0.8;
  int    _alertSensitivity = 1;
  bool   _autoStartEnabled = false;
  String _retentionPeriod  = '30 days';
  String _appVersion       = '';

  StreamSubscription<double>? _volumeSubscription;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey        _authorsKey       = GlobalKey();

  int? _retentionDays(String period) {
    switch (period) {
      case '7 days':  return 7;
      case '30 days': return 30;
      default:        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _volumeSubscription = VolumeController.instance.addListener(
      (v) { if (mounted) setState(() => _alertVolume = v); },
      fetchInitialVolume: true,
    );
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
    String version     = 'v1.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'v${info.version} (${info.buildNumber})';
    } catch (_) {}
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
      final ctx = _authorsKey.currentContext;
      if (ctx == null) return;

      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      Future.delayed(const Duration(milliseconds: 320), () {
        if (!mounted) return;
        final renderObj = _authorsKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderObj == null) return;
        final offset = renderObj.localToGlobal(Offset.zero);
        _scrollController.animateTo(
          _scrollController.offset + offset.dy - 100,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }

    // Responsive horizontal padding — tighter on compact phones
    final hPad = context.rp(16).clamp(12.0, 20.0);
    final vPad = context.rs(12).clamp(8.0, 16.0);

    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        children: [
          _sectionLabel('ALERT SETTINGS'),
          _buildCard([
            _sliderTile(
              icon: Icons.speaker_rounded, iconColor: _cyan,
              title: 'Alert Volume',
              value: _alertVolume, min: 0.0, max: 1.0,
              displayValue: '${(_alertVolume * 100).round()}%',
              onChanged: (v) {
                setState(() => _alertVolume = v);
                VolumeController.instance.setVolume(v);
                PreferencesHelper.instance.setAlertVolume(v);
              },
            ),
            _dividerLine(),
            _segmentedTile(
              icon: Icons.tune_rounded, iconColor: _cyan,
              title: 'Alert Sensitivity',
              subtitle: 'Consecutive detections before triggering an alarm',
              options: const ['Low', 'Medium', 'High'],
              selectedIndex: _alertSensitivity,
              onChanged: (i) {
                setState(() => _alertSensitivity = i);
                PreferencesHelper.instance.setAlertSensitivity(i);
              },
            ),
          ]),
          SizedBox(height: context.rs(24)),
          _sectionLabel('MONITORING SETTINGS'),
          _buildCard([
            _toggleTile(
              icon: Icons.play_circle_rounded, iconColor: _cyan,
              title: 'Auto-Start Recording',
              subtitle: 'Begin monitoring automatically when app opens',
              value: _autoStartEnabled,
              onChanged: (v) {
                setState(() => _autoStartEnabled = v);
                PreferencesHelper.instance.setAutoStart(v);
              },
            ),
          ]),
          SizedBox(height: context.rs(24)),
          _sectionLabel('DATA & PRIVACY'),
          _buildCard([
            _dropdownTile(
              icon: Icons.history_rounded, iconColor: _cyan,
              title: 'Session Retention',
              subtitle: 'Auto-delete sessions older than selected period',
              value: _retentionPeriod,
              options: const ['7 days', '30 days', 'Forever'],
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _retentionPeriod = v);
                await PreferencesHelper.instance.setRetention(v);
                final days = _retentionDays(v);
                if (days != null) {
                  await DatabaseHelper.instance.deleteSessionsOlderThan(days);
                  ref.read(dbChangeCounterProvider.notifier).increment();
                }
              },
            ),
            _dividerLine(),
            _actionTile(
              icon: Icons.delete_outline_rounded, iconColor: _red,
              title: 'Clear All History',
              subtitle: 'Permanently delete all session data',
              titleColor: _red,
              onTap: () => _onClearHistory(context),
            ),
          ]),
          SizedBox(height: context.rs(24)),
          _sectionLabel('ABOUT'),
          _buildCard([
            _infoTile(icon: Icons.school_rounded,
                title: 'Institution', value: 'New Era University'),
            _dividerLine(),
            _infoTile(icon: Icons.info_outline_rounded,
                title: 'Version', value: _appVersion),
            _dividerLine(),
            _authorsTile(),
          ]),
          SizedBox(height: context.rs(32)),
        ],
      ),
    );
  }

  // ── TILE WIDGETS ───────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Padding(
        padding: EdgeInsets.only(
            left: context.rp(4),
            bottom: context.rs(8),
            top: context.rs(4)),
        child: Text(label,
            style: TextStyle(
                color: _textSecondary,
                fontSize: context.sp(11),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
      );

  Widget _buildCard(List<Widget> children) => Container(
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(context.rp(16)),
            border: Border.all(color: _divider, width: 1)),
        child: Column(children: children),
      );

  Widget _dividerLine() => Divider(
      color: _divider, height: 1, thickness: 1,
      indent: context.rp(56));

  Widget _iconBox(IconData icon, Color color) => Container(
        width: context.ri(36), height: context.ri(36),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(context.rp(10))),
        child: Icon(icon, color: color, size: context.ri(18)),
      );

  Widget _toggleTile({
    required IconData icon, required Color iconColor,
    required String title, String? subtitle,
    required bool value, required ValueChanged<bool> onChanged,
  }) =>
      Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.rp(16), vertical: context.rs(14)),
        child: Row(children: [
          _iconBox(icon, iconColor),
          SizedBox(width: context.rp(14)),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
                color: _textPrimary, fontSize: context.sp(14),
                fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              SizedBox(height: context.rs(2)),
              Text(subtitle, style: TextStyle(
                  color: _textSecondary, fontSize: context.sp(12))),
            ],
          ])),
          Switch(
            value: value, onChanged: onChanged,
            activeThumbColor: _cyan,
            activeTrackColor: _cyan.withValues(alpha: 0.3),
            inactiveThumbColor: _textSecondary,
            inactiveTrackColor: _surfaceAlt,
          ),
        ]),
      );

  Widget _sliderTile({
    required IconData icon, required Color iconColor,
    required String title, String? subtitle,
    required double value, required double min, required double max,
    required String displayValue, required ValueChanged<double> onChanged,
    int? divisions,
  }) =>
      Padding(
        padding: EdgeInsets.fromLTRB(
            context.rp(16), context.rs(14), context.rp(16), context.rs(10)),
        child: Column(children: [
          Row(children: [
            _iconBox(icon, iconColor),
            SizedBox(width: context.rp(14)),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(
                  color: _textPrimary, fontSize: context.sp(14),
                  fontWeight: FontWeight.w500)),
              if (subtitle != null) ...[
                SizedBox(height: context.rs(2)),
                Text(subtitle, style: TextStyle(
                    color: _textSecondary, fontSize: context.sp(12))),
              ],
            ])),
            Text(displayValue, style: TextStyle(
                color: _cyan, fontSize: context.sp(14),
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
                value: value, min: min, max: max,
                divisions: divisions, onChanged: onChanged),
          ),
        ]),
      );

  Widget _segmentedTile({
    required IconData icon, required Color iconColor,
    required String title, String? subtitle,
    required List<String> options,
    required int selectedIndex, required ValueChanged<int> onChanged,
  }) =>
      Padding(
        padding: EdgeInsets.fromLTRB(
            context.rp(16), context.rs(14),
            context.rp(16), context.rs(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _iconBox(icon, iconColor),
            SizedBox(width: context.rp(14)),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(
                  color: _textPrimary, fontSize: context.sp(14),
                  fontWeight: FontWeight.w500)),
              if (subtitle != null) ...[
                SizedBox(height: context.rs(2)),
                Text(subtitle, style: TextStyle(
                    color: _textSecondary, fontSize: context.sp(12)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ])),
          ]),
          SizedBox(height: context.rs(12)),
          Row(
            children: List.generate(options.length, (i) {
              final sel = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); onChanged(i); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(
                        left:  i == 0 ? 0 : context.rp(4),
                        right: i == options.length - 1 ? 0 : context.rp(4)),
                    padding: EdgeInsets.symmetric(vertical: context.rs(8)),
                    decoration: BoxDecoration(
                      color: sel ? _cyan.withValues(alpha: 0.15) : _surfaceAlt,
                      borderRadius: BorderRadius.circular(context.rp(8)),
                      border: Border.all(color: sel ? _cyan : _divider),
                    ),
                    child: Text(options[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: sel ? _cyan : _textSecondary,
                          fontSize: context.sp(13),
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        )),
                  ),
                ),
              );
            }),
          ),
        ]),
      );

  Widget _dropdownTile({
    required IconData icon, required Color iconColor,
    required String title, String? subtitle,
    required String value, required List<String> options,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.rp(16), vertical: context.rs(14)),
        child: Row(children: [
          _iconBox(icon, iconColor),
          SizedBox(width: context.rp(14)),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
                color: _textPrimary, fontSize: context.sp(14),
                fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              SizedBox(height: context.rs(2)),
              Text(subtitle, style: TextStyle(
                  color: _textSecondary, fontSize: context.sp(12)),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ])),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: _surfaceAlt,
              icon: Icon(Icons.chevron_right_rounded,
                  color: _textSecondary, size: context.ri(20)),
              style: TextStyle(color: _cyan, fontSize: context.sp(13)),
              items: options.map((o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, style: TextStyle(
                      color: _textPrimary, fontSize: context.sp(13))))).toList(),
              onChanged: onChanged,
            ),
          ),
        ]),
      );

  Widget _actionTile({
    required IconData icon, required Color iconColor,
    required String title, String? subtitle, Color? titleColor,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.rp(16)),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: context.rp(16), vertical: context.rs(14)),
          child: Row(children: [
            _iconBox(icon, iconColor),
            SizedBox(width: context.rp(14)),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(
                  color: titleColor ?? _textPrimary,
                  fontSize: context.sp(14), fontWeight: FontWeight.w500)),
              if (subtitle != null) ...[
                SizedBox(height: context.rs(2)),
                Text(subtitle, style: TextStyle(
                    color: _textSecondary, fontSize: context.sp(12))),
              ],
            ])),
            Icon(Icons.chevron_right_rounded,
                color: _textSecondary, size: context.ri(20)),
          ]),
        ),
      );

  Widget _infoTile({
    required IconData icon, required String title, required String value,
  }) =>
      Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.rp(16), vertical: context.rs(14)),
        child: Row(children: [
          _iconBox(icon, _textSecondary),
          SizedBox(width: context.rp(14)),
          Expanded(child: Text(title, style: TextStyle(
              color: _textSecondary, fontSize: context.sp(14),
              fontWeight: FontWeight.w400))),
          Flexible(child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(color: _textPrimary,
                  fontSize: context.sp(13), fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _authorsTile() => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: _authorsKey,
          tilePadding: EdgeInsets.symmetric(
              horizontal: context.rp(16), vertical: context.rs(2)),
          childrenPadding: EdgeInsets.fromLTRB(
              context.rp(16), 0, context.rp(16), context.rs(14)),
          leading: _iconBox(Icons.people_rounded, _textSecondary),
          title: Text('Authors', style: TextStyle(
              color: _textSecondary, fontSize: context.sp(14),
              fontWeight: FontWeight.w400)),
          trailing: Icon(Icons.expand_more_rounded,
              color: _textSecondary, size: context.ri(20)),
          collapsedIconColor: _textSecondary,
          iconColor: _cyan,
          onExpansionChanged: _onAuthorsExpanded,
          children: [
            _githubLink(name: 'Juliana Mancera',
                username: 'JulianaMancera',
                url: 'https://github.com/JulianaMancera'),
            SizedBox(height: context.rs(8)),
            _githubLink(name: 'Pia Katleya Macalanda',
                username: 'PiaMacalanda',
                url: 'https://github.com/PiaMacalanda'),
          ],
        ),
      );

  Widget _githubLink({
    required String name, required String username, required String url,
  }) =>
      InkWell(
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        borderRadius: BorderRadius.circular(context.rp(10)),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.rp(12), vertical: context.rs(10)),
          decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(context.rp(10)),
              border: Border.all(color: _divider, width: 1)),
          child: Row(children: [
            Container(
              width: context.ri(32), height: context.ri(32),
              decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(context.rp(8))),
              child: Icon(Icons.code_rounded,
                  color: _cyan, size: context.ri(16)),
            ),
            SizedBox(width: context.rp(12)),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(
                  color: _textPrimary, fontSize: context.sp(13),
                  fontWeight: FontWeight.w500)),
              SizedBox(height: context.rs(1)),
              Text('github.com/$username', style: TextStyle(
                  color: _cyan, fontSize: context.sp(11),
                  fontWeight: FontWeight.w400)),
            ])),
            Icon(Icons.open_in_new_rounded,
                color: _textSecondary, size: context.ri(14)),
          ]),
        ),
      );

  void _showSnackbar(BuildContext context, String message,
      {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(
          color: isError ? Colors.white : _bg,
          fontSize: context.sp(13))),
      backgroundColor: isError ? _red : _cyan,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.rp(8))),
      duration: const Duration(seconds: 3),
    ));
  }

  void _onClearHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.rp(16))),
        title: Text('Clear All History', style: TextStyle(
            color: _red, fontWeight: FontWeight.bold,
            fontSize: context.sp(16))),
        content: Text(
          'This will permanently delete ALL session data including '
          'alerts, logs, and analytics. This action cannot be undone.',
          style: TextStyle(color: _textSecondary, fontSize: context.sp(14)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: TextStyle(
                color: _textSecondary, fontSize: context.sp(14))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.rp(8))),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await DatabaseHelper.instance.clearAllData();
              ref.read(dbChangeCounterProvider.notifier).increment();
              await PreferencesHelper.instance.setClearGlasses(false);
              if (context.mounted) {
                _showSnackbar(context, 'All history cleared.', isError: false);
              }
            },
            child: Text('Delete All', style: TextStyle(
                fontSize: context.sp(14))),
          ),
        ],
      ),
    );
  }
}