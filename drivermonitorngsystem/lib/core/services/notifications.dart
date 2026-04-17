import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

class BantayDriveService {
  static const _channelId = 'bantay_drive_monitoring';
  static const _serviceId = 256; // required by flutter_foreground_task v8+
  static bool _serviceReady = false;
  static bool get isReady => _serviceReady;

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
          // FIX: LOW gets suppressed on many devices — DEFAULT always shows
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
      // Android 14+ requires camera permission granted before
      // starting a foreground service with type=camera
      if (Platform.isAndroid) {
        final camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          final result = await Permission.camera.request();
          if (!result.isGranted) {
            debugPrint(
                '[BantayDrive] ❌ Camera permission denied — cannot start service');
            return;
          }
        }
      }

      final running = await FlutterForegroundTask.isRunningService;
      if (running) {
        // Already running — just sync the text
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Bantay Drive',
          notificationText: _statusText(state),
          notificationButtons: [
            const NotificationButton(id: 'stop_recording', text: '⏹ Stop'),
          ],
        );
      } else {
        // FIX: serviceId is required — without it the service never registers
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
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[TaskHandler] destroyed — timeout: $isTimeout');
  }
}