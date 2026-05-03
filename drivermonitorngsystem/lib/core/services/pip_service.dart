import 'dart:async';
import 'package:flutter/services.dart';

class PipService {
  static const _method = MethodChannel('com.bantaydrive/pip');
  static const _events = EventChannel('com.bantaydrive/pip_events');

  // EventChannel.receiveBroadcastStream() must be called only once —
  // a second call silently cancels the previous subscription.
  static Stream<Map<String, dynamic>>? _cachedStream;

  static Stream<Map<String, dynamic>> get pipEventStream {
    _cachedStream ??= _events
        .receiveBroadcastStream()
        .map((event) => event is Map
            ? Map<String, dynamic>.from(event)
            : <String, dynamic>{})
        .asBroadcastStream();
    return _cachedStream!;
  }

  static Future<void> setRecording(bool isRecording) async {
    try {
      await _method.invokeMethod('setRecording', {'isRecording': isRecording});
    } catch (_) {}
  }

  static Future<bool> enterPip({bool isLandscape = false}) async {
    try {
      final result = await _method.invokeMethod<bool>(
          'enterPip', {'isLandscape': isLandscape});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> exitPip() async {
    try {
      await _method.invokeMethod('stopInPip');
    } catch (_) {}
  }
}
