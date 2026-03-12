import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import '../core/database/database_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // STATE
  bool _isLoading = true; // shows loading indicator while prefs load

  // Alert Settings
  bool   _alertSoundEnabled  = true;
  double _alertVolume        = 0.8;
  int    _alertSensitivity   = 1; // 0=Low, 1=Medium, 2=High

  // Monitoring Settings
  bool   _autoStartEnabled   = false;

  // Data & Privacy
  String _retentionPeriod    = '30 days';

  // COLORS
  static const Color _bg            = Color(0xFF080E1A);
  static const Color _surface       = Color(0xFF0D1627);
  static const Color _surfaceAlt    = Color(0xFF1A2235);
  static const Color _cyan          = Color(0xFF00D4FF);
  static const Color _textPrimary   = Color(0xFFEEF2FF);
  static const Color _textSecondary = Color(0xFF6B7A99);
  static const Color _red           = Color(0xFFFF4757);
  static const Color _divider       = Color(0xFF1E2D45);

  // LIFECYCLE
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Load all saved preferences when screen opens
  Future<void> _loadSettings() async {
    final prefs = PreferencesHelper.instance;

    final alertSound      = await prefs.getAlertSound();
    final alertVolume     = await prefs.getAlertVolume();
    final alertSensitivity= await prefs.getAlertSensitivity();
    final autoStart       = await prefs.getAutoStart();
    final retention       = await prefs.getRetention();

    if (mounted) {
      setState(() {
        _alertSoundEnabled  = alertSound;
        _alertVolume        = alertVolume;
        _alertSensitivity   = alertSensitivity;
        _autoStartEnabled   = autoStart;
        _retentionPeriod    = retention;
        _isLoading          = false;
      });
    }
  }

  // BUILD
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [

          // ALERT SETTINGS
          _sectionLabel('ALERT SETTINGS'),
          _buildCard([
            _toggleTile(
              icon: Icons.volume_up_rounded,
              iconColor: _cyan,
              title: 'Alert Sound',
              subtitle: 'Play audio tone when drowsy or distracted',
              value: _alertSoundEnabled,
              onChanged: (v) {
                setState(() => _alertSoundEnabled = v);
                PreferencesHelper.instance.setAlertSound(v);
              },
            ),
            _dividerLine(),
            _sliderTile(
              icon: Icons.speaker_rounded,
              iconColor: _cyan,
              title: 'Alert Volume',
              value: _alertVolume,
              min: 0.0,
              max: 1.0,
              displayValue: '${(_alertVolume * 100).round()}%',
              onChanged: (v) {
                setState(() => _alertVolume = v);
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

          // MONITORING SETTINGS
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

          // DATA & PRIVACY
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
              subtitle: 'Download all sessions as CSV',
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

          // ABOUT
          _sectionLabel('ABOUT'),
          _buildCard([
            _infoTile(
              icon: Icons.info_outline_rounded,
              title: 'App Version',
              value: '1.0.0 (Build 1)',
            ),
            _dividerLine(),
            _infoTile(
              icon: Icons.school_rounded,
              title: 'Institution',
              value: 'New Era University',
            ),
            _dividerLine(),
            _infoTile(
              icon: Icons.people_rounded,
              title: 'Authors',
              value: 'Macalanda & Mancera',
            ),
            _dividerLine(),
            _infoTile(
              icon: Icons.person_rounded,
              title: 'Adviser',
              value: 'Dr. Marc P. Laureta',
            ),
            _dividerLine(),
            _actionTile(
              icon: Icons.article_outlined,
              iconColor: _cyan,
              title: 'Thesis Title',
              subtitle:
                  'DMS-HybridNet: A Hybrid CNN-BiLSTM-Attention Architecture for Real-Time Driver Monitoring',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // SECTION LABEL
  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        label,
        style: TextStyle(
          color: _textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // CARD WRAPPER
  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 1),
      ),
      child: Column(children: children),
    );
  }

  Widget _dividerLine() {
    return Divider(color: _divider, height: 1, thickness: 1, indent: 56);
  }

  // TILE TYPES
  /// Toggle tile — ON/OFF switch
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
      child: Row(
        children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: _textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _cyan,
            activeTrackColor: _cyan.withOpacity(0.3),
            inactiveThumbColor: _textSecondary,
            inactiveTrackColor: _surfaceAlt,
          ),
        ],
      ),
    );
  }

  /// Slider tile — volume, battery %, etc.
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
      child: Column(
        children: [
          Row(
            children: [
              _iconBox(icon, iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style:
                              TextStyle(color: _textSecondary, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              Text(
                displayValue,
                style: TextStyle(
                    color: _cyan, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _cyan,
              inactiveTrackColor: _divider,
              thumbColor: _cyan,
              overlayColor: _cyan.withOpacity(0.15),
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
        ],
      ),
    );
  }

  /// Segmented tile — Low / Medium / High
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(icon, iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: _textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style:
                              TextStyle(color: _textSecondary, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
                      color: selected ? _cyan.withOpacity(0.15) : _surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? _cyan : _divider,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      options[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? _cyan : _textSecondary,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// Dropdown tile — Camera position, retention period
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
      child: Row(
        children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: _textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
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
                            style: TextStyle(
                                color: _textPrimary, fontSize: 13)),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// Action tile — Export, Clear History, Thesis Title
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
        child: Row(
          children: [
            _iconBox(icon, iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: titleColor ?? _textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            TextStyle(color: _textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: _textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  /// Info tile — read-only (About section)
  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _iconBox(icon, _textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: _textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w400)),
          ),
          Text(value,
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
  // ICON BOX
  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  // ACTION HANDLERS
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
          'All your session data will be exported as a CSV file and saved to your Downloads folder.',
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
              // TODO: implement CSV export using DatabaseHelper
              // Example:
              // final sessions = await DatabaseHelper.instance.getAllSessions();
              // convert to CSV → save to Downloads via path_provider + permission
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('Export coming soon!', style: TextStyle(color: _bg)),
                backgroundColor: _cyan,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ));
            },
            child: const Text('Export'),
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
            style:
                TextStyle(color: _red, fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete ALL session data including alerts, logs, and analytics. This action cannot be undone.',
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
              // Calls DatabaseHelper to wipe all tables
              await DatabaseHelper.instance.clearAllData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('All history cleared.',
                      style: TextStyle(color: Colors.white)),
                  backgroundColor: _red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ));
              }
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}