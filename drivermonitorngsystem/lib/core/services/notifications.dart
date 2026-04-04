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
      const android  = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);

      // v21: initialize() uses named parameter 'settings'
      await _notif.initialize(settings: settings);

      final androidPlugin = _notif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();

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
      }

      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  // ─── START ────────────────────────────────────────────────────────────────
  static Future<void> startService({String state = 'neutral'}) async {
    if (!_ready) return;
    try {
      // v21: show() uses all named parameters
      await _notif.show(
        id:                  1001,
        title:               'Bantay Drive',
        body:                _monitoringText(state),
        notificationDetails: _monitoringDetails(),
      );
    } catch (_) {}
  }

  // ─── STOP ─────────────────────────────────────────────────────────────────
  static Future<void> stopService() async {
    if (!_ready) return;
    try {
      // v21: cancel() uses named parameter 'id'
      await _notif.cancel(id: 1001);
      await _notif.cancel(id: 1002);
    } catch (_) {}
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
    } catch (_) {}
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
    } catch (_) {}
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
        ongoing:         true,   // ← cannot be swiped away (like Waze)
        onlyAlertOnce:   true,   // ← silent re-updates
        autoCancel:      false,  // ← stays even if tapped
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