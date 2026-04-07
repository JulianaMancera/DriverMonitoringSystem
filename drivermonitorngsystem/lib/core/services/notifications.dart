import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BantayDriveService
//
// Manages the foreground service notification (low-priority persistent bar)
// and in-app alert state updates.
// System pop-up notifications are NOT used — alerts are handled entirely
// in-app via MonitorScreen's banner (L1/L2) and overlay (L3).
//   1. initialize() is idempotent — safe to call multiple times.
//   2. startService() / stopService() control the foreground service.
//   3. updateState() keeps the persistent notification text in sync.
// ─────────────────────────────────────────────────────────────────────────────

class BantayDriveService {
  static const _monitorChannelId = 'bantay_drive_monitoring';

  static bool _serviceReady = false;
  static bool get isReady => _serviceReady;

  // ─── INIT ──────────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    try {
      // Foreground service setup only — system pop-up notifications removed.
      // All driver alerts are handled in-app (MonitorScreen banners/overlay).
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId:          _monitorChannelId,
          channelName:        'Bantay Drive Monitoring',
          channelDescription: 'Shown while Bantay Drive is actively monitoring.',
          channelImportance:  NotificationChannelImportance.LOW,
          priority:           NotificationPriority.LOW,
        ),
        // Required by flutter_foreground_task API signature — has no effect
        // on Android. Cannot be removed without a compile error.
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction:   ForegroundTaskEventAction.repeat(5000),
          autoRunOnBoot: false,
          allowWifiLock: true,
        ),
      );

      // ── 3. Battery optimization exemption ─────────────────────────────────
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();

      _serviceReady = true;
      debugPrint('>>> [BantayDrive] FULLY READY');
    } catch (e, stack) {
      debugPrint('>>> [BantayDrive] initialize() FAILED: $e\n$stack');
      _serviceReady = false;
    }
  }

  // ─── START FOREGROUND SERVICE ──────────────────────────────────────────────
  static Future<void> startService({String state = 'neutral'}) async {
    if (!_serviceReady) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Bantay Drive',
          notificationText:  _monitoringText(state),
        );
      } else {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Bantay Drive',
          notificationText:  _monitoringText(state),
          callback:          startCallback,
        );
      }
    } catch (e) {
      debugPrint('>>> [BantayDrive] startService() FAILED: $e');
    }
  }

  // ─── STOP FOREGROUND SERVICE ───────────────────────────────────────────────
  static Future<void> stopService() async {
    if (!_serviceReady) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('>>> [BantayDrive] stopService() FAILED: $e');
    }
  }

  // ─── UPDATE FOREGROUND TEXT ────────────────────────────────────────────────
  static Future<void> updateState(String state) async {
    if (!_serviceReady) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Bantay Drive',
        notificationText:  _monitoringText(state),
      );
    } catch (e) {
      debugPrint('>>> [BantayDrive] updateState() FAILED: $e');
    }
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────
  static String _monitoringText(String state) {
    switch (state) {
      case 'drowsy':     return '😴 Drowsiness detected — stay alert!';
      case 'distracted': return '👀 Distraction detected — focus ahead!';
      default:           return '✅ Monitoring actively...';
    }
  }
}

// ─── FOREGROUND TASK CALLBACK ──────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BantayDriveTaskHandler());
}

class BantayDriveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('>>> [TaskHandler] onStart');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain('heartbeat');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('>>> [TaskHandler] onDestroy isTimeout=$isTimeout');
  }
}