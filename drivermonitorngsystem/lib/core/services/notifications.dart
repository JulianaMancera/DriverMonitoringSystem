import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// Prefixed to avoid ambiguous clash with flutter_foreground_task's
// NotificationVisibility, NotificationChannelImportance, etc.
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;

// ─────────────────────────────────────────────────────────────────────────────
// BantayDriveService
//
// Background notification fix checklist:
//   1. Alert channel uses Importance.max (not just .high) — heads-up in bg.
//   2. fullScreenIntent: true — forces notification onto the lock screen.
//   3. visibility: NotificationVisibility.public — visible on lock screen.
//   4. Unique IDs per alert type (1003 drowsy, 1004 distracted) so a new
//      alert replaces the old one instead of stacking.
//   5. showAlertNotification() uses _notifReady (not _serviceReady) so
//      alerts fire even if the foreground service isn't up yet.
//   6. initialize() is idempotent — safe to call multiple times.
// ─────────────────────────────────────────────────────────────────────────────

class BantayDriveService {
  static final _notif = fln.FlutterLocalNotificationsPlugin();

  static const _alertChannelId   = 'bantay_drive_alerts';
  static const _monitorChannelId = 'bantay_drive_monitoring';

  static const _idDrowsy     = 1003;
  static const _idDistracted = 1004;

  static bool _notifReady   = false;
  static bool _serviceReady = false;
  static bool get isReady => _serviceReady;

  // ─── INIT ──────────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    try {
      // ── 1. Local notifications ─────────────────────────────────────────────
      const android  = fln.AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = fln.InitializationSettings(android: android);
      await _notif.initialize(settings: settings);

      final androidPlugin =
          _notif.resolvePlatformSpecificImplementation<
              fln.AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();

        // Android 14+ requires explicit permission for fullScreenIntent
        // This prompts the user once if not already granted
        await androidPlugin.requestFullScreenIntentPermission();

        // HIGH-PRIORITY alert channel — must be max for heads-up in background
        await androidPlugin.createNotificationChannel(
          const fln.AndroidNotificationChannel(
            _alertChannelId,
            'Bantay Drive Alerts',
            description:     'Drowsiness and distraction alerts.',
            importance:      fln.Importance.max,
            playSound:       true,
            enableVibration: true,
            showBadge:       true,
          ),
        );

        // Low-priority persistent monitoring channel
        await androidPlugin.createNotificationChannel(
          const fln.AndroidNotificationChannel(
            _monitorChannelId,
            'Bantay Drive Monitoring',
            description:     'Shown while Bantay Drive is actively monitoring.',
            importance:      fln.Importance.low,
            playSound:       false,
            enableVibration: false,
          ),
        );
      }

      _notifReady = true;
      debugPrint('>>> [BantayDrive] local notifications READY');

      // ── 2. Foreground service ──────────────────────────────────────────────
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
      await _notif.cancel(id: _idDrowsy);
      await _notif.cancel(id: _idDistracted);
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

  // ─── ALERT NOTIFICATION ────────────────────────────────────────────────────
  /// Shows a high-priority heads-up notification even when backgrounded.
  /// Uses _notifReady (not _serviceReady) so it fires before foreground
  /// service is confirmed ready.
  static Future<void> showAlertNotification(String type) async {
    if (!_notifReady) {
      debugPrint('>>> [BantayDrive] showAlertNotification skipped — not ready');
      return;
    }
    try {
      final isDrowsy = type == 'DROWSY';
      final notifId  = isDrowsy ? _idDrowsy : _idDistracted;

      await _notif.show(
        id:    notifId,
        title: isDrowsy ? '⚠️ Drowsiness Detected!' : '⚠️ Distraction Detected!',
        body:  isDrowsy
            ? 'Stay alert — eyes on the road!'
            : 'Focus on the road ahead!',
        notificationDetails: fln.NotificationDetails(
          android: fln.AndroidNotificationDetails(
            _alertChannelId,
            'Bantay Drive Alerts',
            importance:       fln.Importance.max,
            priority:         fln.Priority.max,
            fullScreenIntent: true,
            visibility:       fln.NotificationVisibility.public,
            autoCancel:       true,
            playSound:        true,
            enableVibration:  true,
            showWhen:         true,
            ticker:           'Bantay Drive Alert',
          ),
        ),
      );

      // Auto-cancel after 8 seconds
      Future.delayed(const Duration(seconds: 8), () async {
        await _notif.cancel(id: notifId);
      });

      debugPrint('>>> [BantayDrive] showAlertNotification OK — type=$type');
    } catch (e) {
      debugPrint('>>> [BantayDrive] showAlertNotification FAILED: $e');
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