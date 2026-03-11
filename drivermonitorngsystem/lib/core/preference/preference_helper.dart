import 'package:shared_preferences/shared_preferences.dart';

class PreferencesHelper {
  static final PreferencesHelper instance = PreferencesHelper._init();
  PreferencesHelper._init();

  // KEYS
  static const String _keyAlertSound      = 'alert_sound';
  static const String _keyHaptic          = 'haptic_enabled';
  static const String _keyAlertVolume     = 'alert_volume';
  static const String _keyAlertSensitivity= 'alert_sensitivity';
  static const String _keyCameraPosition  = 'camera_position';
  static const String _keyAutoStart       = 'auto_start';
  static const String _keyRetention       = 'session_retention';

  // ALERT SETTINGS
  Future<bool>   getAlertSound()       async => (await _prefs()).getBool(_keyAlertSound)       ?? true;
  Future<void>   setAlertSound(bool v) async => (await _prefs()).setBool(_keyAlertSound, v);

  Future<bool>   getHaptic()           async => (await _prefs()).getBool(_keyHaptic)            ?? true;
  Future<void>   setHaptic(bool v)     async => (await _prefs()).setBool(_keyHaptic, v);

  Future<double> getAlertVolume()      async => (await _prefs()).getDouble(_keyAlertVolume)     ?? 0.8;
  Future<void>   setAlertVolume(double v) async => (await _prefs()).setDouble(_keyAlertVolume, v);

  Future<int>    getAlertSensitivity() async => (await _prefs()).getInt(_keyAlertSensitivity)   ?? 1;
  Future<void>   setAlertSensitivity(int v) async => (await _prefs()).setInt(_keyAlertSensitivity, v);

  // MONITORING SETTINGS
  Future<String> getCameraPosition()   async => (await _prefs()).getString(_keyCameraPosition)  ?? 'Front';
  Future<void>   setCameraPosition(String v) async => (await _prefs()).setString(_keyCameraPosition, v);

  Future<bool>   getAutoStart()        async => (await _prefs()).getBool(_keyAutoStart)          ?? false;
  Future<void>   setAutoStart(bool v)  async => (await _prefs()).setBool(_keyAutoStart, v);

  // DATA & PRIVACY
  Future<String> getRetention()        async => (await _prefs()).getString(_keyRetention)        ?? '30 days';
  Future<void>   setRetention(String v) async => (await _prefs()).setString(_keyRetention, v);

  // PRIVATE
  Future<SharedPreferences> _prefs() async => await SharedPreferences.getInstance();
}