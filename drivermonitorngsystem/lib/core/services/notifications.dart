// ─────────────────────────────────────────────────────────────────────────────
// notifications.dart
//
// PURPOSE:
//   Manages the foreground service persistent notification bar shown while
//   Bantay Drive is actively monitoring in the background.
//
// WHAT IT DOES:
//   • Shows a LOW-priority persistent notification in the status bar:
//     "✅ Monitoring actively..." / "😴 Drowsiness detected!" etc.
//   • Has a "⏹ Stop" button in the notification that stops recording
//   • Keeps running when user presses Home or switches apps (background mode)
//   • Sends heartbeat every 5 seconds to keep the service alive
//
// WHAT IT DOES NOT DO:
//   • Does NOT request notification permission from the user
//     → Foreground service notifications are system-level and don't need
//       explicit user permission on Android (they appear automatically)
//   • Does NOT show popup alert notifications
//     → All L1/L2/L3 driver alerts are handled IN-APP by monitor_screen.dart
//       (banners and full-screen overlay) — not via system notifications
//
// CALLED BY:
//   • main.dart          — initialize() on app start
//   • monitor_screen.dart— startService(), stopService(), updateState()
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BantayDriveService {
  static const _monitorChannelId = 'bantay_drive_monitoring';

  static bool _serviceReady = false;
  static bool get isReady => _serviceReady;

  // ── INIT ───────────────────────────────────────────────────────────────────
  //
  // FIX: Removed FlutterLocalNotificationsPlugin.requestNotificationsPermission()
  // call that was in main.dart. That call triggered the "Allow notifications?"
  // system popup which confused users — our app doesn't use popup notifications.
  //
  // Foreground service notifications (the persistent status bar entry) are
  // exempt from this permission on Android — they show automatically when
  // startService() is called, no user approval needed.
  static Future<void> initialize() async {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId:          _monitorChannelId,
          channelName:        'Bantay Drive Monitoring',
          channelDescription: 'Shown while Bantay Drive is actively monitoring.',
          // LOW importance = no sound, no heads-up popup, just status bar entry
          // This is intentional — we don't want the notification itself to
          // distract the driver. Only the in-app alerts (monitor_screen) do that.
          channelImportance:  NotificationChannelImportance.LOW,
          priority:           NotificationPriority.LOW,
        ),
        // Required by flutter_foreground_task API — no effect on Android.
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          // Heartbeat every 5 seconds — keeps service alive in background
          eventAction:   ForegroundTaskEventAction.repeat(5000),
          // Don't auto-restart on device boot — user must open app manually
          autoRunOnBoot: false,
          // Keep WiFi active during monitoring (useful for future GPS features)
          allowWifiLock: true,
        ),
      );

      _serviceReady = true;
      debugPrint('[BantayDrive] ✅ Service initialized');
    } catch (e, stack) {
      debugPrint('[BantayDrive] ❌ initialize() failed: $e\n$stack');
      _serviceReady = false;
    }
  }

  // ── START FOREGROUND SERVICE ───────────────────────────────────────────────
  //
  // Called by monitor_screen when user taps START recording.
  // If service is already running (e.g. app was backgrounded), updates it.
  static Future<void> startService({String state = 'neutral'}) async {
    if (!_serviceReady) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        // Already running — just update the notification text
        await FlutterForegroundTask.updateService(
          notificationTitle:   'Bantay Drive',
          notificationText:    _monitoringText(state),
          notificationButtons: [
            const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
          ],
        );
      } else {
        // Start fresh foreground service
        await FlutterForegroundTask.startService(
          notificationTitle:   'Bantay Drive',
          notificationText:    _monitoringText(state),
          callback:            startCallback,
          notificationButtons: [
            const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
          ],
        );
      }
      debugPrint('[BantayDrive] ✅ Service started — state: $state');
    } catch (e) {
      debugPrint('[BantayDrive] ❌ startService() failed: $e');
    }
  }

  // ── STOP FOREGROUND SERVICE ────────────────────────────────────────────────
  //
  // Called by monitor_screen when user taps STOP recording,
  // or when the "⏹ Stop" notification button is pressed.
  static Future<void> stopService() async {
    if (!_serviceReady) return;
    try {
      await FlutterForegroundTask.stopService();
      debugPrint('[BantayDrive] ✅ Service stopped');
    } catch (e) {
      debugPrint('[BantayDrive] ❌ stopService() failed: $e');
    }
  }

  // ── UPDATE NOTIFICATION TEXT ───────────────────────────────────────────────
  //
  // Called by monitor_screen every time the driver state changes.
  // Keeps the persistent notification in sync with the current detection.
  // FIX: Added isRunningService check — avoids calling updateService()
  // when the service isn't running, which caused silent failures before.
  static Future<void> updateState(String state) async {
    if (!_serviceReady) return;
    try {
      // FIX: Only update if service is actually running
      if (!await FlutterForegroundTask.isRunningService) return;

      await FlutterForegroundTask.updateService(
        notificationTitle:   'Bantay Drive',
        notificationText:    _monitoringText(state),
        notificationButtons: [
          const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
        ],
      );
    } catch (e) {
      debugPrint('[BantayDrive] ❌ updateState() failed: $e');
    }
  }

  // ── CHECK SERVICE STATUS ───────────────────────────────────────────────────

  /// Returns true if the foreground service is currently running.
  /// Used by monitor_screen to sync UI state on app resume.
  static Future<bool> get isRunning async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  // ── NOTIFICATION TEXT ──────────────────────────────────────────────────────

  static String _monitoringText(String state) {
    switch (state.toLowerCase()) {
      case 'drowsy':
        return '😴 Drowsiness detected — stay alert!';
      case 'distracted':
        return '👀 Distraction detected — focus ahead!';
      default:
        return '✅ Monitoring actively...';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOREGROUND TASK CALLBACK
// Must be a top-level function with @pragma('vm:entry-point') so the Android
// foreground service can find it across isolate boundaries.
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BantayDriveTaskHandler());
}

class BantayDriveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] onStart — foreground service active');
  }

  // Called every 5 seconds (per eventAction repeat interval).
  // Sends heartbeat to main isolate so monitor_screen knows
  // the service is still alive.
  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain('heartbeat');
  }

  // Called when user taps the "⏹ Stop" button in the notification.
  // Forwards the event to monitor_screen via sendDataToMain().
  // monitor_screen listens for this and calls _stopRecording().
  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_recording') {
      FlutterForegroundTask.sendDataToMain('stop_recording');
      debugPrint('[TaskHandler] Stop button pressed');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[TaskHandler] onDestroy — isTimeout: $isTimeout');
  }
}