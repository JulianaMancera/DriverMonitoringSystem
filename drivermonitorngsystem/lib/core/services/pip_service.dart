import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class PipService {
  static const _method = MethodChannel('com.bantaydrive/pip');
  static const _events = EventChannel('com.bantaydrive/pip_events');

  /// Tell native side whether recording is active
  static Future<void> setRecording(bool isRecording) async {
    try {
      await _method.invokeMethod('setRecording', {'isRecording': isRecording});
    } catch (e) {
      debugPrint('[PiP] setRecording failed: $e');
    }
  }

  /// Enter PiP — pass current orientation
  static Future<void> enterPip({bool isLandscape = false}) async {
    try {
      await _method.invokeMethod('enterPip', {'isLandscape': isLandscape});
    } catch (e) {
      debugPrint('[PiP] enterPip failed: $e');
    }
  }

  /// Stream of events from native — pip state and orientation changes
  /// Each event is a Map: {'type': 'pip'|'orientation', 'value': bool|String}
  static Stream<Map<String, dynamic>> get pipEventStream {
    return _events
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
  }
}