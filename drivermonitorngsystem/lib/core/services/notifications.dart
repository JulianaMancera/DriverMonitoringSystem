import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BantayDriveService {
  static const _channelId = 'bantay_drive_monitoring';
  static const _serviceId = 256;
  static bool _serviceReady = false;
  static bool get isReady => _serviceReady;

  static Future<void> initialize() async {
    try {
      // Request notification permission once at startup (Android 13+)
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
      debugPrint('[BantayDrive] ✅ startService — state: $state');
    } catch (e) {
      debugPrint('[BantayDrive] ❌ startService() failed: $e');
    }
  }

  static Future<void> stopService() async {
    if (!_serviceReady) return;
    try {
      await FlutterForegroundTask.stopService();
      debugPrint('[BantayDrive] ✅ stopService');
    } catch (e) {
      debugPrint('[BantayDrive] ❌ stopService() failed: $e');
    }
  }

  static Future<void> updateState(String state) async {
    if (!_serviceReady) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Bantay Drive',
        notificationText: _statusText(state),
        notificationButtons: [
          const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
        ],
      );
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
    // Heartbeat keeps service alive — monitor_screen ignores it
    FlutterForegroundTask.sendDataToMain('heartbeat');
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Only send data to main isolate — do NOT call stopService() here.
    // stopService() here kills the service before Flutter receives the message,
    // so _onReceiveTaskData in monitor_screen never fires and session never saves.
    if (id == 'stop_recording') {
      FlutterForegroundTask.sendDataToMain('stop_recording');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[TaskHandler] destroyed — timeout: $isTimeout');
  }
}