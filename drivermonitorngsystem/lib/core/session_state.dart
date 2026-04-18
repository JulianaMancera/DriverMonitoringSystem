// session_state.dart
//
// Global session state — survives PiP transitions, widget rebuilds,
// and is accessible from notification stop handler regardless of
// which MonitorScreen instance is active.
//
// FIX: Added SharedPreferences persistence.
//
// Why this matters:
//   FlutterForegroundTask.addTaskDataCallback() delivers 'stop_recording'
//   to the MAIN isolate (not the service isolate), so plain static fields
//   work for the callback itself. However, on some OEMs (Xiaomi, Samsung),
//   the main Flutter isolate is briefly torn down and recreated when the
//   app is backgrounded into PiP. When this happens, all static fields reset
//   to null — so _currentSessionId in monitor_screen AND ActiveSession.sessionId
//   are both null when the notification stop arrives.
//
//   SharedPreferences persists across isolate restarts because it reads from
//   disk. The monitor_screen restore logic ("restored sessionId from ActiveSession")
//   now reliably finds the session ID even after an OEM-triggered isolate restart.

import 'package:shared_preferences/shared_preferences.dart';

class ActiveSession {
  static const _keySessionId  = 'active_session_id';
  static const _keyStartTime  = 'active_session_start';

  // In-memory cache — fast path for normal operation (no isolate restart).
  static int?      _sessionId;
  static DateTime? _startTime;

  static int?      get sessionId => _sessionId;
  static DateTime? get startTime => _startTime;
  static bool      get isActive  => _sessionId != null;

  /// Called when recording starts. Writes to memory AND SharedPreferences.
  static Future<void> start(int id) async {
    _sessionId = id;
    _startTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySessionId, id);
      await prefs.setString(_keyStartTime, _startTime!.toIso8601String());
    } catch (_) {
      // SharedPreferences failure is non-fatal — in-memory path still works
      // for the normal case (no OEM isolate restart).
    }
  }

  /// Called when recording stops. Clears both memory and SharedPreferences.
  static Future<void> clear() async {
    _sessionId = null;
    _startTime = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySessionId);
      await prefs.remove(_keyStartTime);
    } catch (_) {}
  }

  /// Restores session state from SharedPreferences if memory was wiped.
  /// Call this at the top of _onReceiveTaskData before reading sessionId.
  /// Returns true if a session was restored from disk.
  static Future<bool> restoreIfNeeded() async {
    if (_sessionId != null) return false; // memory is fine, nothing to do
    try {
      final prefs = await SharedPreferences.getInstance();
      final id    = prefs.getInt(_keySessionId);
      final tsStr = prefs.getString(_keyStartTime);
      if (id != null) {
        _sessionId = id;
        _startTime = tsStr != null ? DateTime.tryParse(tsStr) : DateTime.now();
        return true;
      }
    } catch (_) {}
    return false;
  }
}