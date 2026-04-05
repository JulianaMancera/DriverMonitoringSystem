import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BantayDriveService {
  static final _notif = FlutterLocalNotificationsPlugin();
  static const _alertChannelId = 'bantay_drive_alerts';

  static bool _ready = false;
  static bool get isReady => _ready;

  // ─── INIT ─────────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    try {
      // 1️⃣ Local notifications setup
      const android  = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _notif.initialize(settings: settings);

      // ✅ Generic type kept on ONE line to avoid parser error
      final androidPlugin = _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _alertChannelId,
            'Bantay Drive Alerts',
            description:     'Urgent alerts for drowsiness or distraction.',
            importance:      Importance.high,
            playSound:       true,
            enableVibration: true,
          ),
        );
      }

      // 2️⃣ Foreground task setup
      // ✅ No iconData param in v9.x
      // ✅ ForegroundTaskOptions is NOT const because repeat() is not const
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId:          'bantay_drive_monitoring',
          channelName:        'Bantay Drive Monitoring',
          channelDescription: 'Shown while Bantay Drive is actively monitoring.',
          channelImportance:  NotificationChannelImportance.LOW,
          priority:           NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction:   ForegroundTaskEventAction.repeat(5000),
          autoRunOnBoot: false,
          allowWifiLock: true,
        ),
      );

      // 3️⃣ Battery optimization exemption
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();

      _ready = true;
      debugPrint('>>> [BantayDrive] READY = true');
    } catch (e, stack) {
      debugPrint('>>> [BantayDrive] initialize() FAILED: $e\n$stack');
      _ready = false;
    }
  }

  // ─── START FOREGROUND SERVICE ─────────────────────────────────────────────
  static Future<void> startService({String state = 'neutral'}) async {
    if (!_ready) return;
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
      debugPrint('>>> [BantayDrive] startService() OK — state=$state');
    } catch (e) {
      debugPrint('>>> [BantayDrive] startService() FAILED: $e');
    }
  }

  // ─── STOP FOREGROUND SERVICE ──────────────────────────────────────────────
  static Future<void> stopService() async {
    if (!_ready) return;
    try {
      await FlutterForegroundTask.stopService();
      await _notif.cancel(id: 1002); // ✅ named param for v21
      debugPrint('>>> [BantayDrive] stopService() OK');
    } catch (e) {
      debugPrint('>>> [BantayDrive] stopService() FAILED: $e');
    }
  }

  // ─── UPDATE STATE TEXT ────────────────────────────────────────────────────
  static Future<void> updateState(String state) async {
    if (!_ready) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Bantay Drive',
        notificationText:  _monitoringText(state),
      );
    } catch (e) {
      debugPrint('>>> [BantayDrive] updateState() FAILED: $e');
    }
  }

  // ─── ALERT LOCAL NOTIFICATION ─────────────────────────────────────────────
  static Future<void> showAlertNotification(String type) async {
    if (!_ready) return;
    try {
      final isDrowsy = type == 'DROWSY';

      // ✅ All named params for flutter_local_notifications v21
      await _notif.show(
        id:    1002,
        title: isDrowsy
            ? '⚠️ Drowsiness Detected!'
            : '⚠️ Distraction Detected!',
        body: isDrowsy
            ? 'Stay alert — eyes on the road!'
            : 'Focus on the road ahead!',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannelId,
            'Bantay Drive Alerts',
            importance:      Importance.high,
            priority:        Priority.high,
            autoCancel:      true,
            playSound:       true,
            enableVibration: true,
            showWhen:        true,
          ),
        ),
      );

      // Auto-cancel after 8 seconds
      Future.delayed(const Duration(seconds: 8), () {
        _notif.cancel(id: 1002); // ✅ named param for v21
      });

      debugPrint('>>> [BantayDrive] showAlertNotification() OK — type=$type');
    } catch (e) {
      debugPrint('>>> [BantayDrive] showAlertNotification() FAILED: $e');
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

// ─── FOREGROUND TASK CALLBACK ─────────────────────────────────────────────────
// ✅ Must be a top-level function with @pragma annotation
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
    // Heartbeat every 5 seconds — can send data to main isolate if needed
    FlutterForegroundTask.sendDataToMain('heartbeat');
  }

  // ✅ v9.2.x requires bool isTimeout as second param
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('>>> [TaskHandler] onDestroy isTimeout=$isTimeout');
  }
}