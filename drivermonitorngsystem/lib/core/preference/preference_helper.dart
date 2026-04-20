// PURPOSE:
//   Persists small user settings across app restarts using SharedPreferences.
//   This is NOT for drive session data — that goes in database_helper.dart.
//   This is ONLY for user-configurable app settings.
//
// WHAT IT STORES:
//   • alert_volume        — how loud the L1/L2/L3 alert sounds play (0.0–1.0)
//   • alert_sensitivity   — how quickly alerts trigger (Low/Medium/High)
//   • auto_start          — whether recording starts automatically on app open
//   • session_retention   — how long to keep session history (7/30/forever)
//   • clear_glasses       — whether periocular occlusion mode is enabled
//   • onboarding_seen     — whether the user has completed onboarding
//   • show_session_summary— whether the session summary modal is shown after a session
//
// CALLED BY:
//   • settings_screen.dart  — reads and writes all preferences
//   • monitor_screen.dart   — reads volume, sensitivity, autoStart, clearGlasses, showSessionSummary
//   • onboarding_screen.dart— reads/writes onboarding_seen
//   • database_helper.dart  — retention value used by deleteSessionsOlderThan()
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesHelper {
  static final PreferencesHelper instance = PreferencesHelper._init();
  PreferencesHelper._init();

  // Cached instance — avoids repeated async getInstance() calls.
  // Initialised lazily on first access via _prefs().
  SharedPreferences? _cache;

  // KEYS
  static const String _keyAlertVolume        = 'alert_volume';
  static const String _keyAlertSensitivity   = 'alert_sensitivity';
  static const String _keyAutoStart          = 'auto_start';
  static const String _keyRetention          = 'session_retention';
  static const String _keyClearGlasses       = 'clear_glasses';
  static const String _keyOnboardingSeen     = 'onboarding_seen';
  static const String _keyShowSessionSummary = 'show_session_summary';
  static const String _keyCameraGuideSeen    = 'camera_guide_seen';

  // ALERT SETTINGS

  /// Alert volume — 0.0 (silent) to 1.0 (full volume).
  /// Default: 0.8 — loud enough to wake a drowsy driver.
  /// Used by monitor_screen to set audioplayers volume on each alert.
  Future<double> getAlertVolume() async =>
      (await _prefs()).getDouble(_keyAlertVolume) ?? 0.8;

  Future<void> setAlertVolume(double value) async =>
      (await _prefs()).setDouble(_keyAlertVolume, value.clamp(0.0, 1.0));

  /// Alert sensitivity — 0 = Low, 1 = Medium, 2 = High.
  /// Controls consecutive-frame thresholds before escalating alert level.
  ///
  /// Threshold table (consecutive drowsy/distracted frames):
  ///   Low    → L1: 5 frames, L2: 10 frames, L3: 15 frames
  ///   Medium → L1: 3 frames, L2:  6 frames, L3:  9 frames
  ///   High   → L1: 2 frames, L2:  4 frames, L3:  6 frames
  ///
  /// Default: 1 (Medium) — balanced for most drivers.
  Future<int> getAlertSensitivity() async =>
      (await _prefs()).getInt(_keyAlertSensitivity) ?? 1;

  Future<void> setAlertSensitivity(int value) async =>
      (await _prefs()).setInt(_keyAlertSensitivity, value.clamp(0, 2));

  /// Convenience: returns the L1/L2/L3 frame thresholds for the
  /// current sensitivity setting. Used directly by monitor_screen.
  /// Returns [l1Threshold, l2Threshold, l3Threshold]
  Future<List<int>> getAlertThresholds() async {
    final sensitivity = await getAlertSensitivity();
    switch (sensitivity) {
      case 0:  return [5, 10, 15]; // Low
      case 2:  return [2,  4,  6]; // High
      default: return [3,  6,  9]; // Medium (default)
    }
  }

  // MONITORING SETTINGS

  /// Auto-start recording — if true, monitor_screen starts recording
  /// automatically when the app opens (or when Monitor tab is tapped).
  /// Default: false — user must manually start recording.
  Future<bool> getAutoStart() async =>
      (await _prefs()).getBool(_keyAutoStart) ?? false;

  Future<void> setAutoStart(bool value) async =>
      (await _prefs()).setBool(_keyAutoStart, value);

  /// Clear Glasses mode — adjusts periocular occlusion tolerance.
  /// When true, the EAR threshold is relaxed slightly to account for
  /// glasses frames partially occluding the eye region.
  /// Default: false.
  Future<bool> getClearGlasses() async =>
      (await _prefs()).getBool(_keyClearGlasses) ?? false;

  Future<void> setClearGlasses(bool value) async =>
      (await _prefs()).setBool(_keyClearGlasses, value);

  /// Show Session Summary — if true, a summary modal is displayed after
  /// each drive session ends showing safety score, duration, and alert counts.
  /// Default: true — summary is shown by default.
  Future<bool> getShowSessionSummary() async =>
      (await _prefs()).getBool(_keyShowSessionSummary) ?? true;

  Future<void> setShowSessionSummary(bool value) async =>
      (await _prefs()).setBool(_keyShowSessionSummary, value);

  // DATA & PRIVACY

  /// Valid values: '7 days', '30 days', 'forever'
  /// Default: '30 days'
  ///
  /// settings_screen enforces this immediately on change by calling
  /// DatabaseHelper.instance.deleteSessionsOlderThan(days).
  Future<String> getRetention() async =>
      (await _prefs()).getString(_keyRetention) ?? '30 days';

  Future<void> setRetention(String value) async {
    const valid = {'7 days', '30 days', 'forever'};
    if (!valid.contains(value)) return;
    await (await _prefs()).setString(_keyRetention, value);
  }

  /// Converts retention string to days integer for database queries.
  /// Returns null for 'forever' (no deletion).
  Future<int?> getRetentionDays() async {
    final retention = await getRetention();
    switch (retention) {
      case '7 days':  return 7;
      case '30 days': return 30;
      default:        return null; // 'forever' → no deletion
    }
  }

  // ONBOARDING

  /// Whether the user has completed the onboarding walkthrough.
  /// Set to true by onboarding_screen.dart when user taps "Get Started".
  /// Read by main.dart EntryPoint to decide whether to show onboarding.
  Future<bool> getOnboardingSeen() async =>
      (await _prefs()).getBool(_keyOnboardingSeen) ?? false;

  Future<void> setOnboardingSeen(bool value) async =>
      (await _prefs()).setBool(_keyOnboardingSeen, value);

  Future<bool> getCameraGuideSeen() async =>
      (await _prefs()).getBool(_keyCameraGuideSeen) ?? false;

  Future<void> setCameraGuideSeen(bool value) async =>
      (await _prefs()).setBool(_keyCameraGuideSeen, value);

  // UTILITY

  /// Resets ALL preferences to their default values.
  /// Called by settings_screen "Reset to Defaults" if you add that feature.
  Future<void> resetToDefaults() async {
    final prefs = await _prefs();
    await prefs.setDouble(_keyAlertVolume,        0.8);
    await prefs.setInt   (_keyAlertSensitivity,   1);
    await prefs.setBool  (_keyAutoStart,          false);
    await prefs.setString(_keyRetention,          '30 days');
    await prefs.setBool  (_keyClearGlasses,       false);
    await prefs.setBool  (_keyShowSessionSummary, true);
    // Note: onboarding_seen is intentionally NOT reset here
    // — user should not have to redo onboarding after a settings reset.
  }

  // PRIVATE

  /// Returns the cached SharedPreferences instance.
  /// Initialises once on first call — all subsequent calls return cache.
  Future<SharedPreferences> _prefs() async {
    _cache ??= await SharedPreferences.getInstance();
    return _cache!;
  }
}