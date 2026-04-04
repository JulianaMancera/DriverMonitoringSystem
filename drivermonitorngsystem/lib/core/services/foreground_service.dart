import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FOREGROUND SERVICE HELPER
// Place at: lib/core/services/foreground_service.dart
//
// Compatible with flutter_foreground_task ^9.x
//
// TWO ICON VERSIONS — toggle comment on notificationIcon in startService():
//   Version A: null → uses default app launcher icon
//   Version B: NotificationIconData with warning icon
// ─────────────────────────────────────────────────────────────────────────────

class BantayDriveService {

  // ── INIT — call once in main() before runApp() ───────────────────────────

  static void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:          'bantay_drive_monitoring',
        channelName:        'Bantay Drive Monitoring',
        channelDescription: 'Shows when Bantay Drive is actively monitoring.',
        channelImportance:  NotificationChannelImportance.HIGH,
        priority:           NotificationPriority.HIGH,
        
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound:        false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction:               ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot:             false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock:             true,
        allowWifiLock:             false,
      ),
    );
  }

  // ── REQUEST PERMISSIONS — call on first launch ────────────────────────────

  static Future<void> requestPermissions() async {
    // Android 13+: request notification permission
    final status = await FlutterForegroundTask.checkNotificationPermission();
    if (status != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  // ── START — call when recording begins ───────────────────────────────────

  static Future<void> startService({String state = 'neutral'}) async {
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      serviceId:         1001,
      notificationTitle: 'Bantay Drive',
      notificationText:  _notifText(state),

      notificationIcon: null,

      notificationButtons: const [
        NotificationButton(id: 'stop_recording', text: 'Stop Recording'),
      ],

      callback: _serviceCallback,
    );
  }

  // ── STOP — call when recording ends ──────────────────────────────────────

  static Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
  }

  // ── UPDATE STATE — call when driver state changes ─────────────────────────

  static Future<void> updateState(String state) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Bantay Drive',
      notificationText:  _notifText(state),
    );
  }

  // ── ALERT NOTIFICATION — L1/L2 while app is in background ────────────────

  static Future<void> showAlertNotification(String type) async {
    if (!await FlutterForegroundTask.isRunningService) return;

    final isDrowsy = type == 'DROWSY';
    await FlutterForegroundTask.updateService(
      notificationTitle: isDrowsy
          ? '⚠️ Drowsiness Detected!'
          : '⚠️ Distraction Detected!',
      notificationText: isDrowsy
          ? 'Stay alert — eyes on the road!'
          : 'Focus on the road ahead!',
    );

    // Restore normal notification after 8 seconds
    await Future.delayed(const Duration(seconds: 8));
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Bantay Drive',
        notificationText:  '🟢 Monitoring Active — driving safely',
      );
    }
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  static String _notifText(String state) {
    switch (state) {
      case 'drowsy':     return '😴 Drowsiness detected — stay alert!';
      case 'distracted': return '👀 Distraction detected — focus ahead!';
      default:           return '🟢 Monitoring Active — driving safely';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE CALLBACK — top-level, runs in background isolate
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void _serviceCallback() {
  FlutterForegroundTask.setTaskHandler(_MonitoringTaskHandler());
}

class _MonitoringTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Service started — monitoring continues in main isolate
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called every 5 seconds — send heartbeat to main isolate
    FlutterForegroundTask.sendDataToMain({'event': 'heartbeat'});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Service stopping
  }

  @override
  void onReceiveData(Object data) {
    // Data from main isolate — not used currently
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_recording') {
      // Tell main isolate to stop recording
      FlutterForegroundTask.sendDataToMain({'event': 'stop_recording'});
    }
  }

  @override
  void onNotificationPressed() {
    // Tapping notification brings app to foreground
    FlutterForegroundTask.launchApp('/');
  }
}