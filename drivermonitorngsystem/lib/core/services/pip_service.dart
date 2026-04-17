import 'dart:async';
import 'package:flutter/services.dart';

class PipService {
  static const _method = MethodChannel('com.bantaydrive/pip');
  static const _events = EventChannel('com.bantaydrive/pip_events');

  /// Tell native whether we're recording so onUserLeaveHint can trigger PiP
  static Future<void> setRecording(bool isRecording) async {
    try {
      await _method.invokeMethod('setRecording', {'isRecording': isRecording});
    } catch (_) {}
  }

  /// Manually trigger PiP entry (used when user navigates away while recording)
  static Future<bool> enterPip({bool isLandscape = false}) async {
    try {
      final result = await _method.invokeMethod<bool>(
          'enterPip', {'isLandscape': isLandscape});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Exit PiP programmatically — called after stop_recording from notification.
  /// On all Android devices: collapses the PiP window back to the launcher.
  static Future<void> exitPip() async {
    try {
      await _method.invokeMethod('exitPip');
    } catch (_) {}
  }

  /// Stream of PiP and orientation events from native.
  /// Events are Maps: {'type': 'pip', 'value': bool}
  ///                  {'type': 'orientation', 'value': 'landscape'|'portrait'}
  static Stream<Map<String, dynamic>> get pipEventStream =>
      _events.receiveBroadcastStream().map((event) {
        if (event is Map) {
          return Map<String, dynamic>.from(event);
        }
        return <String, dynamic>{};
      });
}