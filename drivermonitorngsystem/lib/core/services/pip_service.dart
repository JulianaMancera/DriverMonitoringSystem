// pip_service.dart
//
// FIX: pipEventStream was a getter that called receiveBroadcastStream() on
// every access. EventChannel only supports ONE active listener at a time —
// each new call to receiveBroadcastStream() silently kills the previous one.
//
// Consequence in the old code:
//   • monitor_screen.initState() subscribes → listener A is active
//   • Any Riverpod state change that causes a full widget rebuild (e.g.
//     isRecordingProvider changing) could trigger a second pipEventStream
//     access → listener A dies silently → native PiP events stop reaching
//     Flutter → isInPipProvider never clears → UI stuck in PiP view.
//
// Fix: cache _cachedStream. receiveBroadcastStream() is called exactly ONCE
// for the lifetime of the app. All callers share the same broadcast stream.

import 'dart:async';
import 'package:flutter/services.dart';

class PipService {
  static const _method = MethodChannel('com.bantaydrive/pip');
  static const _events = EventChannel('com.bantaydrive/pip_events');

  // Cached broadcast stream — created once, shared by all listeners.
  // This is the critical fix: EventChannel.receiveBroadcastStream() must
  // only be called once. Calling it again cancels the previous subscription
  // silently, which caused PiP events to stop arriving after any rebuild.
  static Stream<Map<String, dynamic>>? _cachedStream;

  static Stream<Map<String, dynamic>> get pipEventStream {
    _cachedStream ??= _events
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) {
            return Map<String, dynamic>.from(event);
          }
          return <String, dynamic>{};
        })
        // asBroadcastStream() allows multiple listeners on the cached stream
        // without each listen() call creating a new EventChannel subscription.
        .asBroadcastStream();
    return _cachedStream!;
  }

  /// Tell native whether we're recording so onUserLeaveHint can trigger PiP.
  static Future<void> setRecording(bool isRecording) async {
    try {
      await _method.invokeMethod('setRecording', {'isRecording': isRecording});
    } catch (_) {}
  }

  /// Manually trigger PiP entry (used when user navigates away while recording).
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
  /// Native side (MainActivity) handles the Android version differences.
  static Future<void> exitPip() async {
    try {
      await _method.invokeMethod('exitPip');
    } catch (_) {}
  }
}