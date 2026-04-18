// notifications.dart
//
// FIX: updateState() was called on every inference frame (~3-5 FPS).
// FlutterForegroundTask.updateService() re-registers notification buttons
// on every call. On Android, re-registering a notification action while
// the user is interacting with it (tapping Stop) drops the tap event silently.
// This is why the stop button appeared "clickable or not" — the button press
// was being lost because the notification was being rebuilt under the user's finger.
//
// Fix: throttle updateState() to fire at most once every 2 seconds,
// and only when the state actually changes.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BantayDriveService {
  static const _channelId = 'bantay_drive_monitoring';
  static const _serviceId = 256;
  static bool _serviceReady = false;
  static bool get isReady => _serviceReady;

  // Throttle state: track last update time and last state so we only call
  // updateService() when something actually changed AND enough time has passed.
  static String   _lastState      = '';
  static DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const    _kUpdateThrottle = Duration(seconds: 2);

  static Future<void> initialize() async {
    try {
      if (Platform.isAndroid) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: _channelId,
          channelName: 'Bantay Drive',
          channelDescription: 'Active while Bantay Drive is monitoring.',
          channelImportance: NotificationChannelImportance.DEFAULT,
          priority: NotificationPriority.DEFAULT,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000),
          autoRunOnBoot: false,
          allowWifiLock: true,
        ),
      );
      _serviceReady = true;
      debugPrint('[BantayDrive] ✅ initialized');
    } catch (e) {
      debugPrint('[BantayDrive] ❌ initialize() failed: $e');
      _serviceReady = false;
    }
  }

  static Future<void> startService({String state = 'neutral'}) async {
    if (!_serviceReady) return;
    // Reset throttle on fresh session start so the first update always fires.
    _lastState      = '';
    _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Bantay Drive',
          notificationText: _statusText(state),
          notificationButtons: [
            const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
          ],
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: _serviceId,
          notificationTitle: 'Bantay Drive',
          notificationText: _statusText(state),
          callback: startCallback,
          notificationButtons: [
            const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
          ],
        );
      }
      _lastState      = state;
      _lastUpdateTime = DateTime.now();
      debugPrint('[BantayDrive] ✅ startService — state: $state');
    } catch (e) {
      debugPrint('[BantayDrive] ❌ startService() failed: $e');
    }
  }

  static Future<void> stopService() async {
    if (!_serviceReady) return;
    try {
      await FlutterForegroundTask.stopService();
      _lastState = '';
      debugPrint('[BantayDrive] ✅ stopService');
    } catch (e) {
      debugPrint('[BantayDrive] ❌ stopService() failed: $e');
    }
  }

  // FIX: Throttled updateState().
  //
  // Root cause of "stop button not working":
  //   onModelOutput() calls updateState() on every inference frame (~3-5 FPS).
  //   updateService() re-registers the notification button list each time.
  //   On Android, if a notification is rebuilt while the user is tapping it,
  //   the tap event is dropped — the system discards input to the old view.
  //   This made the Stop button unreliable, especially during active detection.
  //
  // Two-part throttle:
  //   1. State must have actually changed (no-op if 'drowsy' → 'drowsy').
  //   2. At least 2 seconds must have passed since the last update.
  //      2s is long enough to avoid the tap-drop race while still keeping
  //      the notification text reasonably current.
  static Future<void> updateState(String state) async {
    if (!_serviceReady) return;

    // Skip if state hasn't changed
    if (state == _lastState) return;

    // Throttle: skip if updated too recently
    final now = DateTime.now();
    if (now.difference(_lastUpdateTime) < _kUpdateThrottle) return;

    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Bantay Drive',
        notificationText: _statusText(state),
        notificationButtons: [
          const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
        ],
      );
      _lastState      = state;
      _lastUpdateTime = now;
    } catch (e) {
      debugPrint('[BantayDrive] ❌ updateState() failed: $e');
    }
  }

  static Future<bool> get isRunning async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  static String _statusText(String state) {
    switch (state.toLowerCase()) {
      case 'drowsy':     return '😴 Drowsiness detected — stay alert!';
      case 'distracted': return '👀 Distraction detected — focus ahead!';
      default:           return '✅ Monitoring actively...';
    }
  }
}

// ── Foreground task entry point ───────────────────────────────────────────────

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BantayDriveTaskHandler());
}

class BantayDriveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat every 5s keeps the service alive.
    // monitor_screen._onReceiveTaskData filters this with:
    //   if (data != 'stop_recording') return;
    FlutterForegroundTask.sendDataToMain('heartbeat');
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Send to main isolate only — do NOT call stopService() here.
    // stopService() here kills the service before Flutter receives the message,
    // so _onReceiveTaskData never fires and the session is never saved to DB.
    if (id == 'stop_recording') {
      FlutterForegroundTask.sendDataToMain('stop_recording');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[TaskHandler] destroyed — timeout: $isTimeout');
  }
}