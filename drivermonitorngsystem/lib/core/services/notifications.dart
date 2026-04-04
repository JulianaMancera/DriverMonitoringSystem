import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BantayDriveService {
  static final _notif = FlutterLocalNotificationsPlugin();

  static const _monitoringChannelId = 'bantay_drive_monitoring';
  static const _alertChannelId      = 'bantay_drive_alerts';

  static bool _ready = false;
  static bool get isReady => _ready;

  // ─── INIT ─────────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    try {
      debugPrint('>>> [BantayDrive] initialize() called');

      const android  = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);

      await _notif.initialize(settings: settings);
      debugPrint('>>> [BantayDrive] _notif.initialize done');

      final androidPlugin = _notif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final permResult = await androidPlugin.requestNotificationsPermission();
        debugPrint('>>> [BantayDrive] permission granted: $permResult');

        // Channel 1 — Persistent monitoring (silent, ongoing, cannot be swiped)
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _monitoringChannelId,
            'Bantay Drive Monitoring',
            description:
                'Persistent notification shown while Bantay Drive is actively monitoring.',
            importance:      Importance.low,
            playSound:       false,
            enableVibration: false,
            showBadge:       false,
          ),
        );
        debugPrint('>>> [BantayDrive] monitoring channel created');

        // Channel 2 — Alert notifications (heads-up, sound, vibration)
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _alertChannelId,
            'Bantay Drive Alerts',
            description:
                'Urgent alerts when drowsiness or distraction is detected.',
            importance:      Importance.high,
            playSound:       true,
            enableVibration: true,
            showBadge:       true,
          ),
        );
        debugPrint('>>> [BantayDrive] alerts channel created');
      } else {
        debugPrint('>>> [BantayDrive] WARNING: androidPlugin is null!');
      }

      _ready = true;
      debugPrint('>>> [BantayDrive] READY = true');

    } catch (e, stack) {
      debugPrint('>>> [BantayDrive] initialize() FAILED: $e');
      debugPrint('>>> [BantayDrive] $stack');
      _ready = false;
    }
  }

  // ─── START ────────────────────────────────────────────────────────────────
  static Future<void> startService({String state = 'neutral'}) async {
    debugPrint('>>> [BantayDrive] startService() isReady=$_ready state=$state');
    if (!_ready) return;
    try {
      await _notif.show(
        id:                  1001,
        title:               'Bantay Drive',
        body:                _monitoringText(state),
        notificationDetails: _monitoringDetails(),
      );
      debugPrint('>>> [BantayDrive] startService() notification shown OK');
    } catch (e) {
      debugPrint('>>> [BantayDrive] startService() FAILED: $e');
    }
  }

  // ─── STOP ─────────────────────────────────────────────────────────────────
  static Future<void> stopService() async {
    debugPrint('>>> [BantayDrive] stopService() called');
    if (!_ready) return;
    try {
      await _notif.cancel(id: 1001);
      await _notif.cancel(id: 1002);
      debugPrint('>>> [BantayDrive] notifications cancelled');
    } catch (e) {
      debugPrint('>>> [BantayDrive] stopService() FAILED: $e');
    }
  }

  // ─── UPDATE STATE ─────────────────────────────────────────────────────────
  static Future<void> updateState(String state) async {
    if (!_ready) return;
    try {
      await _notif.show(
        id:                  1001,
        title:               'Bantay Drive',
        body:                _monitoringText(state),
        notificationDetails: _monitoringDetails(),
      );
    } catch (e) {
      debugPrint('>>> [BantayDrive] updateState() FAILED: $e');
    }
  }

  // ─── ALERT NOTIFICATION ───────────────────────────────────────────────────
  static Future<void> showAlertNotification(String type) async {
    if (!_ready) return;
    try {
      final isDrowsy = type == 'DROWSY';
      await _notif.show(
        id:    1002,
        title: isDrowsy ? '⚠️ Drowsiness Detected!' : '⚠️ Distraction Detected!',
        body:  isDrowsy
            ? 'Stay alert — eyes on the road!'
            : 'Focus on the road ahead!',
        notificationDetails: _alertDetails(),
      );
      Future.delayed(const Duration(seconds: 8), () async {
        try {
          await _notif.cancel(id: 1002);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('>>> [BantayDrive] showAlertNotification() FAILED: $e');
    }
  }

  // ─── PRIVATE HELPERS ──────────────────────────────────────────────────────

  static String _monitoringText(String state) {
    switch (state) {
      case 'drowsy':
        return '😴 Drowsiness detected — stay alert!';
      case 'distracted':
        return '👀 Distraction detected — focus ahead!';
      default:
        return 'Bantay Drive is monitoring...';
    }
  }

  static NotificationDetails _monitoringDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _monitoringChannelId,
        'Bantay Drive Monitoring',
        channelDescription:
            'Persistent notification shown while Bantay Drive is actively monitoring.',
        importance:      Importance.low,
        priority:        Priority.low,
        ongoing:         true,
        onlyAlertOnce:   true,
        autoCancel:      false,
        playSound:       false,
        enableVibration: false,
        showWhen:        false,
      ),
    );
  }

  static NotificationDetails _alertDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannelId,
        'Bantay Drive Alerts',
        channelDescription:
            'Urgent alerts when drowsiness or distraction is detected.',
        importance:      Importance.high,
        priority:        Priority.high,
        ongoing:         false,
        onlyAlertOnce:   false,
        autoCancel:      true,
        playSound:       true,
        enableVibration: true,
        showWhen:        true,
      ),
    );
  }
}