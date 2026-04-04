import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BantayDriveService {
  static final _notif      = FlutterLocalNotificationsPlugin();
  static const  _channelId = 'bantay_drive_monitoring';
  static bool   _ready     = false;

  // ── INIT — call in main() before runApp(), no await needed ───────────────

  static Future<void> initialize() async {
    try {
      const android  = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _notif.initialize(settings: settings);

      // Request notification permission (Android 13+)
      final androidPlugin = _notif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }

      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  // ── START — call when recording begins ───────────────────────────────────

  static Future<void> startService({String state = 'neutral'}) async {
    if (!_ready) return;
    try {
      await _notif.show(
        id:                  1001,
        title:               'Bantay Drive',
        body:                _notifText(state),
        notificationDetails: _details(),
      );
    } catch (_) {}
  }

  // ── STOP — call when recording ends ──────────────────────────────────────

  static Future<void> stopService() async {
    if (!_ready) return;
    try {
      await _notif.cancel(id: 1001);
      await _notif.cancel(id: 1002);
    } catch (_) {}
  }

  // ── UPDATE STATE — call when driver state changes ─────────────────────────

  static Future<void> updateState(String state) async {
    if (!_ready) return;
    try {
      await _notif.show(
        id:                  1001,
        title:               'Bantay Drive',
        body:                _notifText(state),
        notificationDetails: _details(),
      );
    } catch (_) {}
  }

  // ── ALERT NOTIFICATION — shows when alert triggers ───────────────────────

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
        notificationDetails: _details(important: true),
      );
      // Auto-dismiss alert notification after 8 seconds
      Future.delayed(const Duration(seconds: 8), () async {
        try { await _notif.cancel(id: 1002); } catch (_) {}
      });
    } catch (_) {}
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  static String _notifText(String state) {
    switch (state) {
      case 'drowsy':     return '😴 Drowsiness detected — stay alert!';
      case 'distracted': return '👀 Distraction detected — focus ahead!';
      default:           return '🟢 Monitoring Active — driving safely';
    }
  }

  static NotificationDetails _details({bool important = false}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Bantay Drive Monitoring',
        channelDescription: 'Shows when Bantay Drive is actively monitoring.',
        importance:    important ? Importance.high : Importance.defaultImportance,
        priority:      important ? Priority.high   : Priority.defaultPriority,
        ongoing:       !important,
        onlyAlertOnce: true,
        autoCancel:    important,
        playSound:     important,
        enableVibration: important,
      ),
    );
  }
}