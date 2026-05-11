import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BantayDriveService {
  static const _channelId = 'bantay_drive_monitoring';
  static const _serviceId = 256;
  static bool _serviceReady = false;
  static bool get isReady => _serviceReady;

  static String _lastState = '';
  static DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kUpdateThrottle = Duration(seconds: 2);

  // Reused across startService and updateState to avoid re-creating the list.
  static const _stopButton = [
    NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
  ];

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
    _lastState = '';
    _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Bantay Drive',
          notificationText: _statusText(state),
          notificationButtons: _stopButton,
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: _serviceId,
          notificationTitle: 'Bantay Drive',
          notificationText: _statusText(state),
          callback: startCallback,
          notificationButtons: _stopButton,
        );
      }
      _lastState = state;
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

  // Throttled: skips if state unchanged or if called within 2 seconds of last
  // update. Re-registering the notification too frequently drops tap events
  // on Android when the user is interacting with the Stop button.
  static Future<void> updateState(String state) async {
    if (!_serviceReady || state == _lastState) return;

    final now = DateTime.now();
    if (now.difference(_lastUpdateTime) < _kUpdateThrottle) return;

    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Bantay Drive',
        notificationText: _statusText(state),
        notificationButtons: _stopButton,
      );
      _lastState = state;
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
    FlutterForegroundTask.sendDataToMain('heartbeat');
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_recording') {
      FlutterForegroundTask.sendDataToMain('stop_recording');
    }
  }

  @override
  void onReceiveData(Object data) {
    // Some Android versions deliver button presses via onReceiveData as a Map.
    if (data is Map) {
      final buttonId = data['notification_button_id'];
      if (buttonId == 'stop_recording') {
        FlutterForegroundTask.sendDataToMain('stop_recording');
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[TaskHandler] destroyed — timeout: $isTimeout');
  }
}
