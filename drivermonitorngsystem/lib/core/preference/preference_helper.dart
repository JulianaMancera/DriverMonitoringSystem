import 'package:shared_preferences/shared_preferences.dart';
class PreferencesHelper {
  static final PreferencesHelper instance = PreferencesHelper._init();
  PreferencesHelper._init();

  // KEYS 
  static const String _keyAlertSound       = 'alert_sound';
  static const String _keyAlertVolume      = 'alert_volume';
  static const String _keyAlertSensitivity = 'alert_sensitivity';
  static const String _keyAutoStart        = 'auto_start';
  static const String _keyRetention        = 'session_retention';

  // ALERT SETTINGS 

  /// Alert sound ON/OFF — plays audio tone on drowsy/distracted detection
  Future<bool> getAlertSound() async =>
      (await _prefs()).getBool(_keyAlertSound) ?? true;
  Future<void> setAlertSound(bool value) async =>
      (await _prefs()).setBool(_keyAlertSound, value);

  /// Alert volume — 0.0 to 1.0
  Future<double> getAlertVolume() async =>
      (await _prefs()).getDouble(_keyAlertVolume) ?? 0.8;
  Future<void> setAlertVolume(double value) async =>
      (await _prefs()).setDouble(_keyAlertVolume, value);

  /// Alert sensitivity — 0 = Low, 1 = Medium, 2 = High
  /// Controls consecutive detection threshold before Level 3 alarm
  Future<int> getAlertSensitivity() async =>
      (await _prefs()).getInt(_keyAlertSensitivity) ?? 1;
  Future<void> setAlertSensitivity(int value) async =>
      (await _prefs()).setInt(_keyAlertSensitivity, value);

  // MONITORING SETTINGS

  /// Auto-start recording — if true, recording starts when app opens
  Future<bool> getAutoStart() async =>
      (await _prefs()).getBool(_keyAutoStart) ?? false;
  Future<void> setAutoStart(bool value) async =>
      (await _prefs()).setBool(_keyAutoStart, value);

  //  DATA & PRIVACY 
  /// Session retention period — '7 days', '30 days', '90 days', 'Forever'
  Future<String> getRetention() async =>
      (await _prefs()).getString(_keyRetention) ?? '30 days';
  Future<void> setRetention(String value) async =>
      (await _prefs()).setString(_keyRetention, value);

  // PRIVATE

  Future<SharedPreferences> _prefs() async =>
      await SharedPreferences.getInstance();
}