// session_state.dart
// Global session state — survives PiP transitions, widget rebuilds,
// and is accessible from notification stop handler regardless of
// which MonitorScreen instance is active.

class ActiveSession {
  static int? sessionId;
  static DateTime? startTime;

  static bool get isActive => sessionId != null;

  static void start(int id) {
    sessionId = id;
    startTime = DateTime.now();
  }

  static void clear() {
    sessionId = null;
    startTime = null;
  }
}