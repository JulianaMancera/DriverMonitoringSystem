// monitor_screen.dart — v7 (definitive fixes)
//
// ROOT CAUSES FIXED IN THIS VERSION:
//
// BUG 1 — Notification stop never worked:
//   flutter_foreground_task v9.x wraps sendDataToMain payloads differently
//   depending on the platform bridge version. The old check "if (data is! String)"
//   silently dropped everything if the payload arrived as a Map<String,dynamic>
//   with key 'data'. Fixed: unwrap both String and Map forms.
//
// BUG 2 — Camera shows loading when returning from PiP:
//   CameraController loses its surface texture when the window resizes for PiP
//   on Android (known flutter/camera issue). isInitialized becomes false.
//   When the app returns to full screen, CameraPreview renders with an
//   uninitialized controller → shows a black/loading frame.
//   Fixed: _recoverCamera() detects this and re-initializes without full dispose.
//   Also: _cameraController! was force-unwrapped even when _cameraResuming=true
//   but controller could be null → null crash → error widget hides logs.
//   Fixed: null-safe camera widget selection.
//
// BUG 3 — System logs disappear after PiP:
//   This was a SYMPTOM of Bug 2. The null crash in _buildCameraWithOverlay
//   threw an exception that prevented the full layout from rendering,
//   making it appear the log panel was gone. Fix Bug 2 → logs reappear.
//   Added extra safety: _flushPendingLogs is also called in the build method
//   itself if pending logs exist and pip is no longer active.

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../core/inference/tflite_service.dart';
import '../core/services/notifications.dart';
import '../core/services/pip_service.dart';
import '../core/session_state.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../utils/responsive.dart';

// ─── GLOBAL — allows stop from notification even during PiP ──────────────────
_MonitorScreenState? _activeMonitorState;

// ─── PROVIDERS ────────────────────────────────────────────────────────────────

class _StringNotifier extends Notifier<String> {
  final String _initial;
  _StringNotifier(this._initial);
  @override
  String build() => _initial;
  void set(String v) => state = v;
}

class _DoubleNotifier extends Notifier<double> {
  final double _initial;
  _DoubleNotifier(this._initial);
  @override
  double build() => _initial;
  void set(double v) => state = v;
}

class _BoolNotifier extends Notifier<bool> {
  final bool _initial;
  _BoolNotifier(this._initial);
  @override
  bool build() => _initial;
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

class _NullableStringNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

class _IntNotifier extends Notifier<int> {
  final int _initial;
  _IntNotifier(this._initial);
  @override
  int build() => _initial;
  void set(int v) => state = v;
}

final driverStateProvider = NotifierProvider<_StringNotifier, String>(
    () => _StringNotifier('neutral'));
final alertnessPctProvider = NotifierProvider<_DoubleNotifier, double>(
    () => _DoubleNotifier(100.0));
final drowsinessPctProvider = NotifierProvider<_DoubleNotifier, double>(
    () => _DoubleNotifier(0.0));
final distractionPctProvider = NotifierProvider<_DoubleNotifier, double>(
    () => _DoubleNotifier(0.0));
final isRecordingProvider = NotifierProvider<_BoolNotifier, bool>(
    () => _BoolNotifier(false));
final showAlertBannerProvider = NotifierProvider<_BoolNotifier, bool>(
    () => _BoolNotifier(false));
final alertBannerTypeProvider = NotifierProvider<_StringNotifier, String>(
    () => _StringNotifier('DROWSY'));
final clearGlassesProvider = NotifierProvider<_BoolNotifier, bool>(
    () => _BoolNotifier(false));
final isInPipProvider = NotifierProvider<_BoolNotifier, bool>(
    () => _BoolNotifier(false));
final activeSubclassProvider =
    NotifierProvider<_NullableStringNotifier, String?>(
        _NullableStringNotifier.new);
final activeSubclassIndexProvider = NotifierProvider<_IntNotifier, int>(
    () => _IntNotifier(0));

// ─────────────────────────────────────────────────────────────────────────────
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});
  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  final GlobalKey _cameraKey = GlobalKey();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool    _cameraInitialized = false;
  String? _cameraError;
  bool    _camDisposing      = false;
  bool    _cameraResuming      = false;
  // true while CameraX is internally recovering its hardware session after
  // the MIUI buffer queue destruction on PiP resize. We show a semi-transparent
  // overlay OVER CameraPreview (not instead of it) so CameraX can reattach
  // its surface to the existing texture without interference from us.
  bool    _cameraReconnecting  = false;
  // Prevents _initCamera() from running while CameraX is recovering from
  // PiP. On Xiaomi, the CameraPreview widget rebuild after PiP exit can
  // trigger a new CameraController.initialize() which creates new
  // addUseCases → new CLOSING→REOPENING cycle on top of CameraX's own
  // internal recovery. Set true on paused, false when recovery is done.
  bool    _isInPipRecovery     = false;
  // Prevents _resumeAfterPip() from running twice when both pipEventStream
  // AND didChangeAppLifecycleState(resumed) fire on PiP exit (common on
  // Xiaomi/Samsung). The second call triggers a new CLOSING→REOPENING cycle
  // visible in logcat as triple camera restarts and 75+ skipped frames.
  // Reset to false in _stopRecording() so it re-arms for the next session.
  bool    _pipResumeHandled    = false;

  StreamSubscription<Map<String, dynamic>>? _pipSubscription;

  int?      _currentSessionId;
  DateTime? _sessionStartTime;
  Timer?    _snapshotTimer;

  int _consecutiveDrowsy     = 0;
  int _consecutiveDistracted = 0;
  int _alertLevel            = 0;

  final List<Map<String, dynamic>> _systemLogs  = [];
  final List<Map<String, dynamic>> _pendingLogs = [];

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _alarmPlayer = AudioPlayer();

  late AnimationController _warningController;
  late Animation<double>   _warningAnimation;
  AnimationController?     _notifController;
  Animation<Offset>?       _notifSlide;
  Animation<double>?       _notifFade;

  int  _prefAlertSensitivity = 1;
  bool _prefAutoStart        = false;

  static const bool _mirrorCamera = false;

  static const Map<int, List<int>> _sensitivityThresholds = {
    0: [5, 10, 15],
    1: [3,  6,  9],
    2: [2,  4,  6],
  };

  bool     _modelLoaded  = false;
  DateTime _lastInferTs  = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _kInferThrottleMs = 200;

  // ─── LIFECYCLE ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _warningController = AnimationController(
        duration: const Duration(milliseconds: 1000), vsync: this)
      ..repeat(reverse: true);
    _warningAnimation =
        Tween<double>(begin: 0.8, end: 1.0).animate(_warningController);

    final nc = AnimationController(
        duration: const Duration(milliseconds: 550), vsync: this);
    _notifController = nc;
    _notifSlide = Tween<Offset>(
            begin: const Offset(0, -1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: nc, curve: Curves.elasticOut));
    _notifFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: nc,
            curve: const Interval(0.0, 0.35, curve: Curves.easeIn)));

    _loadPreferencesAndInit();
    _activeMonitorState = this;

    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    _pipSubscription = PipService.pipEventStream.listen((event) {
      if (!mounted) return;
      final type  = event['type'] as String?;
      final value = event['value'];
      if (type == 'pip') {
        final inPip = value as bool;
        if (!inPip) {
          // FIX C: Flush BEFORE clearing isInPip. If isInPip is cleared first,
          // a setState rebuild fires before _pendingLogs are moved to _systemLogs
          // — the log panel briefly shows "No logs yet" on the first frame.
          _flushPendingLogs();
          // Pre-arm _cameraResuming so the first rebuild triggered by
          // isInPipProvider.set(false) already sees _cameraResuming=true.
          // Without this, there is one frame where canShow=false AND
          // _cameraResuming=false → _buildCameraFallback() (loading spinner).
          if (mounted && ref.read(isRecordingProvider)) {
            setState(() => _cameraResuming = true);
          }
          ref.read(isInPipProvider.notifier).set(false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          // Guard: both pipEventStream and didChangeAppLifecycleState(resumed)
          // fire on PiP exit. Without this, _resumeAfterPip() runs twice —
          // causing a triple CLOSING→REOPENING cycle in CameraX (logcat shows
          // 75+ skipped frames per extra cycle on Xiaomi devices).
          if (!_pipResumeHandled) {
            _pipResumeHandled = true;
            _resumeAfterPip();
          }
        } else {
          ref.read(isInPipProvider.notifier).set(true);
        }
      }
    });
  }

  @override
  void dispose() {
    if (_activeMonitorState == this) _activeMonitorState = null;
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    WidgetsBinding.instance.removeObserver(this);
    _snapshotTimer?.cancel();
    _warningController.dispose();
    _notifController?.dispose();
    _pipSubscription?.cancel();

    _camDisposing = true;
    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        _cameraController!.stopImageStream();
      }
    } catch (_) {}
    try {
      _cameraController?.removeListener(_onCameraValueChanged);
      _cameraController?.dispose();
    } catch (_) {}
    _cameraController = null;
    try { _audioPlayer.dispose(); } catch (_) {}
    try { _alarmPlayer.dispose(); } catch (_) {}
    super.dispose();
  }

  // ─── TASK DATA CALLBACK ───────────────────────────────────────────────────
  //
  // BUG 1 FIX: flutter_foreground_task v9.x changed how sendDataToMain delivers
  // payloads. In some build configurations the String is wrapped in a Map:
  //   {'data': 'stop_recording'}
  // or arrives as a completely different runtime type.
  //
  // The old "if (data is! String) return;" silently dropped all messages
  // that didn't arrive as a bare String — including stop_recording on many
  // devices. Fixed by extracting the string value from both forms.
  void _onReceiveTaskData(Object data) async {
    // Unwrap all known payload formats from flutter_foreground_task v9.x:
    //   1. Bare String:                    'stop_recording'
    //   2. Map with 'data' key:            {'data': 'stop_recording'}
    //   3. Map with button id key:         {'notification_button_id': 'stop_recording'}
    // Format 3 is how v9.x delivers notification button presses on some
    // Android versions (the button press bypasses onNotificationButtonPressed
    // and arrives directly as task data in the main isolate).
    String? message;
    if (data is String) {
      message = data;
    } else if (data is Map) {
      final raw = data['data'];
      if (raw is String) {
        message = raw;
      } else {
        // v9.x notification button press format
        final buttonId = data['notification_button_id'];
        if (buttonId is String) message = buttonId;
      }
    }

    // Log what we actually received so you can see it in logcat
    debugPrint('[Monitor] taskData received — type: ${data.runtimeType}, '
        'message: $message, this=$hashCode mounted=$mounted');

    if (message == null) return;
    if (message == 'heartbeat') return; // ignore keepalive ticks

    if (message != 'stop_recording') return;

    // Delegate to the most recently mounted instance
    if (_activeMonitorState != null &&
        _activeMonitorState != this &&
        _activeMonitorState!.mounted) {
      debugPrint('[Monitor] delegating to active mounted instance');
      _activeMonitorState!._onReceiveTaskData(data);
      return;
    }

    if (!mounted && (_activeMonitorState == null || _activeMonitorState == this)) {
      debugPrint('[Monitor] no mounted instance — stopping service only');
      BantayDriveService.stopService();
      PipService.setRecording(false);
      await ActiveSession.clear();
      return;
    }

    // Try in-memory first, then SharedPreferences fallback
    if (_currentSessionId == null) {
      final restored = await ActiveSession.restoreIfNeeded();
      if (restored) {
        _currentSessionId = ActiveSession.sessionId;
        _sessionStartTime = ActiveSession.startTime;
        debugPrint('[Monitor] restored sessionId from prefs: $_currentSessionId');
      }
    }

    debugPrint('[Monitor] stopping — sessionId=$_currentSessionId');
    if (_currentSessionId != null) {
      await _stopRecording();
      await PipService.exitPip();
    } else {
      BantayDriveService.stopService();
      PipService.setRecording(false);
      if (mounted) {
        ref.read(isRecordingProvider.notifier).set(false);
        ref.read(driverStateProvider.notifier).set('neutral');
        ref.read(showAlertBannerProvider.notifier).set(false);
        ref.read(isInPipProvider.notifier).set(false);
      }
    }
  }

  // ─── LIFECYCLE STATE ───────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
        // FIX: Do NOT call setRecording() when transitioning to inactive
        // while in PiP. On Xiaomi, PiP exit fires:
        //   onPictureinPictureModeChanged(false) → inactive → resumed
        // Calling setRecording() during inactive while CameraX is in its
        // CLOSING→REOPENING recovery cycle triggers a second native camera
        // open request, causing extra REOPENING cycles in logcat.
        // Only call setRecording() when we're actually going to background
        // (not as part of PiP exit sequence).
        if (!ref.read(isInPipProvider)) {
          await PipService.setRecording(ref.read(isRecordingProvider));
        }
        break;

      case AppLifecycleState.paused:
        if (ref.read(isRecordingProvider)) {
          if (mounted) ref.read(isInPipProvider.notifier).set(true);
          // Block camera reinit during PiP recovery — see _isInPipRecovery.
          _isInPipRecovery = true;
          // Reset resume guard so it's ready for when we come back from PiP.
          _pipResumeHandled = false;
          // Do NOT pause camera stream here — PiP preview needs it running.
        } else {
          await _pauseCameraStream();
        }
        break;

      case AppLifecycleState.resumed:
        // FIX C: Flush pending logs BEFORE clearing isInPip — same reason as
        // the pipEventStream listener above. Ensures logs are in _systemLogs
        // before the rebuild that isInPipProvider.set(false) triggers.
        if (mounted) _flushPendingLogs();
        // Pre-arm _cameraResuming before isInPipProvider clears so the first
        // rebuild after PiP exit shows black instead of the loading spinner.
        if (mounted && ref.read(isRecordingProvider)) {
          setState(() => _cameraResuming = true);
        }
        if (mounted) ref.read(isInPipProvider.notifier).set(false);
        // Guard against double-resume — _pipResumeHandled is set in paused
        // so it's always fresh for this PiP cycle. First caller (either
        // pipEventStream or this resumed handler) wins; the second is skipped.
        if (!_pipResumeHandled) {
          _pipResumeHandled = true;
          await _resumeAfterPip();
        }
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) setState(() {});
          });
        }
        break;

      default:
        break;
    }
  }

  // ─── CAMERA LIFECYCLE ─────────────────────────────────────────────────────

  // Called whenever CameraController.value changes (streaming state, errors, etc.)
  // CameraX fires this when it finishes internal hardware recovery after PiP.
  void _onCameraValueChanged() {
    if (!mounted || _camDisposing) return;
    final ctrl = _cameraController;
    if (ctrl == null) return;

    if (_cameraReconnecting && ctrl.value.isStreamingImages) {
      // CameraX has reattached the surface and resumed streaming — clear overlay
      setState(() => _cameraReconnecting = false);
      debugPrint('[Camera] CameraX recovery complete — streaming resumed');
    }
  }

  Future<void> _pauseCameraStream() async {
    if (_cameraController == null || _camDisposing) return;
    try {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      debugPrint('[Camera] pauseStream error: $e');
    }
  }

  // Called on PiP exit (both from pipEventStream and resumed lifecycle).
  //
  // LOGCAT FINDING: MIUI destroys the Camera2 BufferQueue when the window
  // resizes for PiP (ERROR_CAMERA_DEVICE code 4 + ERROR_CAMERA_SERVICE code 5).
  // CameraX handles this internally: CLOSING → REOPENING → OPENED.
  // We must NOT dispose/reinitialize the controller — that interrupts CameraX's
  // own recovery and causes a second recovery cycle (62 skipped frames in log).
  //
  // Correct approach: show a reconnecting overlay OVER the CameraPreview
  // and wait for CameraX to finish on its own. _onCameraValueChanged clears
  // the overlay when isStreamingImages becomes true again.
  Future<void> _resumeAfterPip() async {
    if (_cameraController == null || _camDisposing) return;
    if (!ref.read(isRecordingProvider)) return;
    // Guard: if already resuming (pipEventStream and resumed both fire on Xiaomi),
    // the second call is a no-op — CameraX only needs one recovery attempt.
    if (_cameraResuming) return;

    // Show reconnecting overlay immediately — CameraPreview stays mounted
    // so CameraX can reattach its surface without a new controller.
    if (mounted) setState(() { _cameraResuming = true; _cameraReconnecting = true; });

    // Give CameraX a moment to start its recovery before we try the stream.
    // If the stream is already running (surface was never lost), this is a no-op.
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted || _camDisposing) return;

    try {
      if (!_cameraController!.value.isStreamingImages) {
        await _cameraController!.startImageStream(_onCameraFrame);
      }
      // Stream is running — clear all recovery flags
      _isInPipRecovery = false;
      if (mounted) setState(() { _cameraResuming = false; _cameraReconnecting = false; });
    } catch (e) {
      // startImageStream failed — CameraX is still recovering internally.
      // Leave _cameraReconnecting=true; _onCameraValueChanged will clear it
      // when CameraX finishes its REOPENING cycle.
      debugPrint('[Camera] startImageStream during recovery: $e — waiting for CameraX');
      if (mounted) setState(() => _cameraResuming = false);
      // Retry stream start after CameraX finishes its cycle (~800ms on Xiaomi)
      Future.delayed(const Duration(milliseconds: 800), () async {
        if (!mounted || _camDisposing || _cameraController == null) return;
        try {
          if (!_cameraController!.value.isStreamingImages) {
            await _cameraController!.startImageStream(_onCameraFrame);
          }
          _isInPipRecovery = false;
          if (mounted) setState(() => _cameraReconnecting = false);
        } catch (e2) {
          debugPrint('[Camera] retry startImageStream failed: $e2');
          _isInPipRecovery = false;
          if (mounted) setState(() => _cameraReconnecting = false);
        }
      });
    }
  }

  // ─── CAMERA INIT ──────────────────────────────────────────────────────────

  Future<void> _loadPreferencesAndInit() async {
    final prefs = PreferencesHelper.instance;
    _prefAlertSensitivity = await prefs.getAlertSensitivity();
    _prefAutoStart        = await prefs.getAutoStart();
    final success = await TfliteService.instance.initialize();
    if (mounted) setState(() => _modelLoaded = success);
    await _initCamera();
  }

  Future<void> _initCamera() async {
    if (_camDisposing) return;
    // CRITICAL: Do NOT reinitialize the camera during PiP recovery.
    // On Xiaomi, the CameraPreview widget rebuild after PiP exit calls
    // back into _initCamera via the widget tree. Creating a new
    // CameraController here while CameraX is in CLOSING→REOPENING adds
    // a second addUseCases call → second REOPENING cycle → triple restart.
    // CameraX handles its own hardware recovery; we just need to wait.
    if (_isInPipRecovery) {
      debugPrint('[Camera] _initCamera skipped — PiP recovery in progress');
      return;
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No cameras found');
        return;
      }
      final cam = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      if (!_camDisposing) await _cameraController?.dispose();
      if (_camDisposing) return;

      _cameraController = CameraController(cam, ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420);
      await _cameraController!.initialize();

      if (!mounted || _camDisposing) return;
      setState(() { _cameraInitialized = true; _cameraError = null; });

      // Listen to CameraController value changes so we can detect when
      // CameraX finishes its internal hardware recovery after PiP resize.
      // When isStreamingImages flips back to true, we clear the reconnecting overlay.
      _cameraController!.addListener(_onCameraValueChanged);

      if (_prefAutoStart) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && !_camDisposing) await _startRecording();
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  // ─── LOG HELPERS ──────────────────────────────────────────────────────────

  void _flushPendingLogs() {
    if (_pendingLogs.isEmpty) return;

    // FIX B: Always persist pending logs to DB first — even if !mounted.
    // When stop comes from the notification while in PiP, this method may be
    // called after a rebuild where mounted=false. Without this, all logs
    // accumulated during PiP (drowsy/distracted detections, alerts) are
    // silently dropped and never appear in History's session detail.
    for (final entry in _pendingLogs) {
      if (_currentSessionId != null) {
        DatabaseHelper.instance.insertSystemLog(
          sessionId: _currentSessionId!,
          message:   entry['message'] as String,
          logType:   entry['type'] as String,
        );
      }
    }

    if (!mounted) {
      _pendingLogs.clear();
      return;
    }

    setState(() {
      _systemLogs.addAll(_pendingLogs);
      _pendingLogs.clear();
      if (_systemLogs.length > 100) {
        _systemLogs.removeRange(0, _systemLogs.length - 100);
      }
    });
  }

  void _addLogSync(String message, String type) {
    final now = DateTime.now();
    final t = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final entry = {'time': t, 'message': message, 'type': type};

    // Always persist to DB regardless of UI state
    if (_currentSessionId != null) {
      DatabaseHelper.instance.insertSystemLog(
          sessionId: _currentSessionId!, message: message, logType: type);
    }

    if (!mounted) return;

    final isInPip = ref.read(isInPipProvider);
    if (isInPip) {
      _pendingLogs.add(entry);
      return;
    }

    setState(() {
      _systemLogs.add(entry);
      if (_systemLogs.length > 100) _systemLogs.removeAt(0);
    });
  }

  // ─── SESSION ──────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    _currentSessionId      = await DatabaseHelper.instance.insertSession();
    await DatabaseHelper.instance.insertStateCount(_currentSessionId!);
    _sessionStartTime      = DateTime.now();
    await ActiveSession.start(_currentSessionId!);
    _consecutiveDrowsy     = 0;
    _consecutiveDistracted = 0;
    _alertLevel            = 0;

    if (_cameraInitialized && _modelLoaded && !_camDisposing) {
      try {
        if (!_cameraController!.value.isStreamingImages) {
          await _cameraController!.startImageStream(_onCameraFrame);
        }
      } catch (e) {
        _addLogSync('Inference stream error: $e', 'WARNING');
      }
    }

    ref.read(isRecordingProvider.notifier).set(true);
    PipService.setRecording(true);
    ref.read(driverStateProvider.notifier).set('neutral');
    await BantayDriveService.startService(state: 'neutral');

    _addLogSync('System Initialized', 'INFO');
    _addLogSync(
      _modelLoaded ? 'DMS-HybridNet V3 Active' : 'Demo Mode — No Model',
      _modelLoaded ? 'SUCCESS' : 'WARNING',
    );
    _addLogSync('Monitoring Started', 'INFO');
    if (ref.read(clearGlassesProvider)) {
      _addLogSync('Clear Glasses Mode Active', 'INFO');
    }

    _snapshotTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _saveAlertnessSnapshot());
    ref.read(dbChangeCounterProvider.notifier).increment();
  }

  Future<void> _stopRecording() async {
    if (_currentSessionId == null && ActiveSession.isActive) {
      _currentSessionId = ActiveSession.sessionId;
      _sessionStartTime = ActiveSession.startTime;
    }
    if (_currentSessionId == null) return;
    _snapshotTimer?.cancel();

    // FIX A: Save one last alertness snapshot right now, BEFORE pausing the
    // camera stream. This ensures the final alertness value in the provider
    // reflects actual inference data from this session — not the reset default
    // of 100.0 that gets set after PiP recovery when stop is triggered quickly.
    await _saveAlertnessSnapshot();

    await _pauseCameraStream();
    await _alarmPlayer.stop();
    _alertLevel = _consecutiveDrowsy = _consecutiveDistracted = 0;

    final durationSec = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds : 0;

    // FIX A: Use the average of all saved alertness snapshots for the final
    // score — much more accurate than the provider value (which may be stale
    // at 100.0 if the provider was reset during PiP recovery before stop ran).
    final snapshots = await DatabaseHelper.instance
        .getAlertnessSnapshots(_currentSessionId!);
    final double alertness;
    if (snapshots.isNotEmpty) {
      final sum = snapshots.fold<double>(
          0.0, (acc, s) => acc + ((s['alertness_pct'] as num).toDouble()));
      alertness = sum / snapshots.length;
    } else {
      // Fallback to provider if no snapshots were saved yet (very short session)
      alertness = ref.read(alertnessPctProvider);
    }

    final alerts =
        await DatabaseHelper.instance.getAlertsBySession(_currentSessionId!);
    double penalty = 0.0;
    for (final a in alerts) {
      final level = (a['alert_level'] as int?) ?? 1;
      if (level == 1) {
        penalty += 2.0;
      } else if (level == 2) {
        penalty += 4.0;
      } else {
        penalty += 8.0;
      }
    }
    final safetyScore = (alertness - penalty).clamp(0.0, 100.0);

    await DatabaseHelper.instance.endSession(
      sessionId:    _currentSessionId!,
      durationSec:  durationSec,
      alertnessAvg: alertness,
      safetyScore:  safetyScore,
    );

    debugPrint('[Monitor] Session $_currentSessionId ended — '
        'score: ${safetyScore.toInt()}%');
    await ActiveSession.clear();

    // FIX B+C — ORDER MATTERS. We must:
    //   1. Clear isInPipProvider FIRST — so _addLogSync below does NOT go to
    //      _pendingLogs (which would be lost when _currentSessionId is nulled).
    //   2. Call _addLogSync WHILE _currentSessionId is still set — so the
    //      "Session Ended" log is saved to DB correctly.
    //   3. Flush _pendingLogs while _currentSessionId is still valid — so any
    //      logs accumulated during PiP are persisted before the session closes.
    //   4. Only THEN null _currentSessionId and set isRecording=false.
    //
    // Old order: isRecording=false → isInPip=false → _currentSessionId=null
    //   Problem: isRecording=false triggers a rebuild. If _pendingLogs is not
    //   yet flushed, the log panel shows "No logs yet." And when isInPip=false
    //   triggers _flushPendingLogs, _currentSessionId is already null so the
    //   DB insertSystemLog calls inside _flushPendingLogs are silently skipped.
    if (mounted) {
      // Step 1: Clear PiP flag so _addLogSync writes to _systemLogs, not _pendingLogs
      ref.read(isInPipProvider.notifier).set(false);
      // Step 2: Flush any logs that accumulated during PiP — while sessionId is valid
      _flushPendingLogs();
    }
    // Step 3: Add final log — _currentSessionId still set, isInPip now false
    _addLogSync('Session Ended — Score: ${safetyScore.toInt()}%', 'INFO');

    BantayDriveService.stopService();
    PipService.setRecording(false);

    // Step 4: Now safe to null the session and flip providers
    _currentSessionId = null;
    _sessionStartTime = null;
    // Re-arm all PiP recovery guards for the next session.
    _pipResumeHandled = false;
    _isInPipRecovery  = false;

    ref.read(isRecordingProvider.notifier).set(false);
    ref.read(driverStateProvider.notifier).set('neutral');
    ref.read(showAlertBannerProvider.notifier).set(false);
    ref.read(alertnessPctProvider.notifier).set(100.0);
    ref.read(drowsinessPctProvider.notifier).set(0.0);
    ref.read(distractionPctProvider.notifier).set(0.0);
    ref.read(activeSubclassProvider.notifier).set(null);
    ref.read(activeSubclassIndexProvider.notifier).set(0);
    if (mounted) {
      ref.read(dbChangeCounterProvider.notifier).increment();
    }
  }

  // ─── INFERENCE ────────────────────────────────────────────────────────────

  bool _isInferring = false;

  Future<void> _onCameraFrame(CameraImage frame) async {
    if (_camDisposing) return;
    if (_isInferring) return;
    final now = DateTime.now();
    if (now.difference(_lastInferTs).inMilliseconds < _kInferThrottleMs) return;
    _lastInferTs = now;
    if (!mounted || !ref.read(isRecordingProvider)) return;
    _isInferring = true;
    try {
      final result = await TfliteService.instance.runInference(frame);
      if (result == null) return;
      if (mounted && ref.read(isRecordingProvider)) onModelOutput(result);
    } finally {
      _isInferring = false;
    }
  }

  void onModelOutput(InferenceResult r) {
    if (!ref.read(isRecordingProvider)) return;

    ref.read(alertnessPctProvider.notifier).set(r.alertnessPct);
    ref.read(drowsinessPctProvider.notifier).set(r.drowsyPct);
    ref.read(distractionPctProvider.notifier).set(r.distractedPct);
    ref.read(driverStateProvider.notifier).set(r.state);
    ref.read(activeSubclassProvider.notifier).set(r.subclass);
    ref.read(activeSubclassIndexProvider.notifier).set(r.subclassIndex);

    if (_currentSessionId != null) {
      DatabaseHelper.instance.incrementStateCount(
          sessionId: _currentSessionId!, state: r.state);
    }

    switch (r.state) {
      case 'drowsy':
        _consecutiveDrowsy++;
        _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 999);
        _addLogSync(
          '[${modelSourceLabel(r.modelSource)}] '
          '${r.subclass} — ${r.drowsyPct.toInt()}% drowsy', 'WARNING');
        _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
        BantayDriveService.updateState('drowsy');
        break;
      case 'distracted':
        _consecutiveDistracted++;
        _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 999);
        _addLogSync(
          '[${modelSourceLabel(r.modelSource)}] '
          '${r.subclass} — ${r.distractedPct.toInt()}% distracted', 'WARNING');
        _checkAndTriggerAlert('DISTRACTED', _consecutiveDistracted);
        BantayDriveService.updateState('distracted');
        break;
      default:
        _consecutiveDrowsy     = (_consecutiveDrowsy     - 1).clamp(0, 999);
        _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 999);
        if (_alertLevel > 0 && _alertLevel < 3) {
          _alertLevel = 0;
          _alarmPlayer.stop();
        }
        ref.read(activeSubclassProvider.notifier).set('safe_driving');
        ref.read(activeSubclassIndexProvider.notifier).set(0);
        BantayDriveService.updateState('neutral');
    }
  }

  Future<void> _checkAndTriggerAlert(String type, int consecutive) async {
    final thresholds =
        _sensitivityThresholds[_prefAlertSensitivity] ?? [3, 6, 9];
    if (consecutive < thresholds[0]) return;

    int newLevel = 1;
    if (consecutive >= thresholds[2]) {
      newLevel = 3;
    } else if (consecutive >= thresholds[1]) {
      newLevel = 2;
    }

    if (newLevel <= _alertLevel) return;
    _alertLevel = newLevel;

    ref.read(showAlertBannerProvider.notifier).set(true);
    ref.read(alertBannerTypeProvider.notifier).set(type);
    if (newLevel < 3) _notifController?.forward(from: 0.0);

    if (_currentSessionId != null) {
      await DatabaseHelper.instance.insertAlertEvent(
          sessionId: _currentSessionId!, alertType: type, alertLevel: newLevel);
      _addLogSync(
        'ALERT Level $newLevel — '
        '${type == 'DROWSY' ? 'Drowsiness' : 'Distraction'} '
        '($consecutive consecutive frames)', 'WARNING');
      ref.read(dbChangeCounterProvider.notifier).increment();
    }
    await _playAlertSound(newLevel);
  }

  Future<void> _playAlertSound(int level) async {
    if (level <= 2) {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('L1_L2_sound.mp3'));
    } else {
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.play(AssetSource('L3_critical_alert.wav'));
    }
  }

  Future<void> _dismissAlert() async {
    if (_alertLevel < 3 &&
        _notifController?.status != AnimationStatus.dismissed) {
      await _notifController?.reverse();
    }
    await _alarmPlayer.stop();
    _alertLevel = _consecutiveDrowsy = _consecutiveDistracted = 0;
    if (mounted) ref.read(showAlertBannerProvider.notifier).set(false);
  }

  Future<void> _saveAlertnessSnapshot() async {
    if (_currentSessionId == null) return;
    await DatabaseHelper.instance.insertAlertnessSnapshot(
        sessionId:    _currentSessionId!,
        alertnessPct: ref.read(alertnessPctProvider).clamp(0.0, 100.0));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isInPip = ref.watch(isInPipProvider);

    if (isInPip) return _buildPipView();

    // Safety flush: if we somehow have pending logs but pip is no longer active,
    // flush them now rather than waiting for the next lifecycle event.
    if (_pendingLogs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _flushPendingLogs());
    }

    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);
    final isLevel3  = _alertLevel == 3;

    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Stack(children: [
        SafeArea(bottom: false, child: _buildPortraitLayout()),

        if (showAlert && !isLevel3)
          Positioned(top: 0, left: 0, right: 0,
            child: SafeArea(bottom: false,
                child: _buildAlertBanner(alertType))),

        if (showAlert && isLevel3)
          Positioned.fill(child: _buildWarningOverlay(alertType)),
      ]),
    );
  }

  // ─── PiP VIEW ─────────────────────────────────────────────────────────────

  Widget _buildPipView() {
    final isRecording = ref.watch(isRecordingProvider);
    final driverState = ref.watch(driverStateProvider);
    final showAlert   = ref.watch(showAlertBannerProvider);
    final alertType   = ref.watch(alertBannerTypeProvider);

    final String stateLabel = switch (driverState) {
      'drowsy'     => 'Drowsy Detected',
      'distracted' => 'Distracted',
      _            => 'Alert',
    };
    final alertColor = alertType == 'DROWSY' ? Colors.orange : Colors.red;

    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [

        if (_cameraInitialized && !_camDisposing && _cameraController != null &&
            _cameraController!.value.isInitialized)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width:  _cameraController!.value.previewSize?.height ?? 480,
                height: _cameraController!.value.previewSize?.width  ?? 640,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),

        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
              ),
            ),
          ),
        ),

        if (isRecording)
          Positioned(
            top: 6, left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: Colors.white, size: 5),
                SizedBox(width: 3),
                Text('REC', style: TextStyle(
                    color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              ]),
            ),
          ),

        Positioned(
          bottom: 6, left: 6, right: 6,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: showAlert
                    ? alertColor.withValues(alpha: 0.92)
                    : Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  showAlert ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline_rounded,
                  color: Colors.white, size: 11),
                const SizedBox(width: 4),
                Flexible(child: Text(stateLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 10,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis, maxLines: 1)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ─── LAYOUTS ──────────────────────────────────────────────────────────────

  Widget _buildPortraitLayout() => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.rp(14)),
          child: Column(children: [
            SizedBox(height: context.rs(20)),
            _buildCameraWithOverlay(
                height: MediaQuery.of(context).size.height *
                    (context.isSmallPhone ? 0.36 : 0.40)),
            SizedBox(height: context.rs(10)),
            _buildMetricsSidebar(),
            SizedBox(height: context.rs(14)),
          ]),
        ),
      );

  // ─── CAMERA WITH OVERLAY ──────────────────────────────────────────────────

  // Shows CameraPreview whenever the controller exists and is initialized.
  // During MIUI's internal CameraX recovery (BufferQueue destroyed on PiP resize),
  // we keep CameraPreview mounted — removing it would interrupt CameraX's
  // surface reattachment. Instead we layer a semi-transparent reconnecting
  // overlay on top until _onCameraValueChanged clears _cameraReconnecting.
  Widget _buildCameraChild(double camW, double camH) {
    final ctrl = _cameraController;
    final canShow = _cameraInitialized &&
        !_camDisposing &&
        ctrl != null &&
        ctrl.value.isInitialized;

    if (canShow) {
      return Stack(children: [
        CameraPreview(key: _cameraKey, ctrl),
        // Reconnecting overlay — shown while CameraX recovers its hardware session.
        // Keeps the texture alive and gives the user visual feedback.
        if (_cameraReconnecting)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                      color: Color(0xFF22d3ee), strokeWidth: 2),
                ),
                const SizedBox(height: 8),
                Text('Reconnecting camera...',
                    style: TextStyle(
                        color: Colors.white70, fontSize: context.sp(10))),
              ])),
            ),
          ),
      ]);
    }

    // Show black box (not spinner) while CameraX is recovering its surface after
    // PiP resize. _cameraResuming covers the initial recovery attempt;
    // _cameraReconnecting covers the retry window after startImageStream fails
    // and CameraX is still in CLOSING→REOPENING. Without this check, the brief
    // window between those two states showed the loading spinner instead.
    if (_cameraResuming || _cameraReconnecting) {
      return const ColoredBox(color: Colors.black);
    }

    return _buildCameraFallback();
  }

  Widget _buildCameraWithOverlay({double? height}) {
    final isRecording  = ref.watch(isRecordingProvider);
    final clearGlasses = ref.watch(clearGlassesProvider);

    double camAspect;
    final ctrl = _cameraController;
    if (_cameraInitialized && ctrl != null &&
        ctrl.value.isInitialized &&
        ctrl.value.previewSize != null) {
      final ps = ctrl.value.previewSize!;
      camAspect = 1.0 / (ps.width / ps.height);
    } else {
      camAspect = 3.0 / 4.0;
    }

    final cameraWidget = LayoutBuilder(
      builder: (ctx, constraints) {
        final boxW = constraints.maxWidth;
        final boxH = constraints.maxHeight;
        double camW, camH;
        if (boxW / boxH > camAspect) {
          camW = boxW; camH = boxW / camAspect;
        } else {
          camH = boxH; camW = boxH * camAspect;
        }
        return ClipRect(
          child: OverflowBox(
            maxWidth: camW, maxHeight: camH,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(
                  _mirrorCamera ? -1.0 : 1.0, 1.0, 1.0),
              child: SizedBox(
                width: camW, height: camH,
                child: _buildCameraChild(camW, camH),
              ),
            ),
          ),
        );
      },
    );

    final inner = ClipRRect(
      borderRadius: BorderRadius.circular(context.rp(14)),
      child: Stack(fit: StackFit.expand, children: [
        cameraWidget,
        _buildGradientOverlay(),

        SafeArea(
          child: Stack(fit: StackFit.expand, children: [
            if (isRecording) _buildRecBadge(),

            if (!ref.watch(isInPipProvider))
              Positioned(
                top: context.rs(10),
                left: context.rp(10),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.rp(7), vertical: context.rs(4)),
                  decoration: BoxDecoration(
                    color: (_modelLoaded
                            ? const Color(0xFF10b981)
                            : const Color(0xFFfbbf24))
                        .withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(context.rp(10)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: context.ri(6), height: context.ri(6),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle)),
                    SizedBox(width: context.rp(4)),
                    Text(_modelLoaded ? 'AI ON' : 'DEMO',
                        style: TextStyle(
                            color: Colors.white, fontSize: context.sp(9),
                            fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ]),
                ),
              ),

            if (!ref.watch(isInPipProvider))
              Positioned(
                bottom: context.rs(12),
                left: 0, right: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(context.rp(24)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: context.rp(5), vertical: context.rs(5)),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0f172a).withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(context.rp(24)),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08), width: 1),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _CameraOverlayButton(
                            icon: Icons.visibility, label: 'Clear Glasses',
                            isActive: clearGlasses,
                            activeColor: const Color(0xFF22d3ee),
                            onTap: () {
                              ref.read(clearGlassesProvider.notifier).toggle();
                              if (!clearGlasses && _currentSessionId != null) {
                                _addLogSync('Clear Glasses Mode Active', 'SUCCESS');
                              }
                            },
                          ),
                          Container(
                            width: 1, height: context.rs(24),
                            margin: EdgeInsets.symmetric(horizontal: context.rp(5)),
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          _CameraOverlayButton(
                            icon: isRecording
                                ? Icons.stop_circle : Icons.fiber_manual_record,
                            label: isRecording ? 'Stop' : 'Record',
                            isActive: isRecording, activeColor: Colors.red,
                            onTap: () => isRecording
                                ? _stopRecording() : _startRecording(),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );

    return Container(
      height: height, width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.all(Radius.circular(context.rp(18))),
        border: Border.all(color: const Color(0xFF1E2D45), width: 1),
      ),
      padding: EdgeInsets.all(context.rp(5)),
      child: inner,
    );
  }

  Widget _buildCameraFallback() {
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off,
              color: const Color(0xFF64748b), size: context.ri(44)),
          SizedBox(height: context.rs(12)),
          Text(_cameraError!,
              style: TextStyle(color: const Color(0xFF64748b),
                  fontSize: context.sp(12)),
              textAlign: TextAlign.center),
          SizedBox(height: context.rs(12)),
          TextButton(
              onPressed: _initCamera,
              child: Text('Retry',
                  style: TextStyle(color: const Color(0xFF22d3ee),
                      fontSize: context.sp(13)))),
        ])),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Color(0xFF22d3ee)),
        SizedBox(height: context.rs(12)),
        Text('Initializing camera...',
            style: TextStyle(color: const Color(0xFF64748b),
                fontSize: context.sp(12))),
      ])),
    );
  }

  Widget _buildGradientOverlay() => Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent,
                  const Color(0xFF0f172a).withValues(alpha: 0.5)],
            ),
          ),
        ),
      );

  Widget _buildRecBadge() =>
      Positioned(
        top: context.rs(10),
        right: context.rp(10),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.rp(9), vertical: context.rs(4)),
          decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(context.rp(16))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: context.ri(7), height: context.ri(7),
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle)),
            SizedBox(width: context.rp(5)),
            Text('REC', style: TextStyle(
                color: Colors.white, fontSize: context.sp(10),
                fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
        ),
      );

  // ─── ALERT BANNER — L1/L2 ─────────────────────────────────────────────────

  Widget _buildAlertBanner(String type) {
    final isDrowsy  = type == 'DROWSY';
    final slideAnim = _notifSlide ?? AlwaysStoppedAnimation(Offset.zero);
    final fadeAnim  = _notifFade  ?? const AlwaysStoppedAnimation(1.0);

    return SlideTransition(
      position: slideAnim,
      child: FadeTransition(
        opacity: fadeAnim,
        child: GestureDetector(
          onTap: _dismissAlert,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200) _dismissAlert();
          },
          child: AnimatedBuilder(
            animation: _warningAnimation,
            builder: (context, _) {
              final pulse = (_warningAnimation.value - 0.8) / 0.2;
              return Container(
                width: double.infinity,
                margin: EdgeInsets.fromLTRB(context.rp(10), context.rs(8),
                    context.rp(10), context.rs(4)),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(context.rp(16)),
                  border: Border.all(
                      color: Colors.red.withValues(alpha: 0.25 + 0.35 * pulse),
                      width: 1.2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 28, offset: const Offset(0, 8)),
                    BoxShadow(
                        color: Colors.red.withValues(alpha: 0.12 + 0.18 * pulse),
                        blurRadius: 20, spreadRadius: 1,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(context.rp(16)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: context.rp(12), vertical: context.rs(10)),
                      child: Row(children: [
                        AnimatedBuilder(
                          animation: _warningAnimation,
                          builder: (context, child) {
                            final p = (_warningAnimation.value - 0.8) / 0.2;
                            return Container(
                              width: context.ri(40), height: context.ri(40),
                              decoration: BoxDecoration(
                                color: Colors.red.shade800,
                                borderRadius: BorderRadius.circular(context.rp(10)),
                                boxShadow: [BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.3 + 0.4 * p),
                                    blurRadius: 14, spreadRadius: 1)],
                              ),
                              child: Icon(Icons.warning_amber_rounded,
                                  color: Colors.white, size: context.ri(22)),
                            );
                          },
                        ),
                        SizedBox(width: context.rp(10)),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('BANTAY DRIVE', style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: context.sp(10),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8)),
                                Text('now', style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    fontSize: context.sp(10))),
                              ],
                            ),
                            SizedBox(height: context.rs(3)),
                            Text(isDrowsy ? 'Drowsiness Detected' : 'Distraction Detected',
                                style: TextStyle(color: Colors.white,
                                    fontSize: context.sp(14),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2)),
                            SizedBox(height: context.rs(2)),
                            Text(isDrowsy
                                ? 'Stay alert — tap to dismiss'
                                : 'Focus on the road — tap to dismiss',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: context.sp(11))),
                          ],
                        )),
                        SizedBox(width: context.rp(6)),
                        Container(
                          width: context.ri(20), height: context.ri(20),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: context.ri(13)),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── WARNING OVERLAY — L3 ─────────────────────────────────────────────────

  Widget _buildWarningOverlay(String type) {
    final isDrowsy = type == 'DROWSY';
    return GestureDetector(
      onTap: _dismissAlert,
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _warningAnimation,
          builder: (context, _) {
            final pulse = _warningAnimation.value;
            final p     = (pulse - 0.8) / 0.2;
            return Stack(fit: StackFit.expand, children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.red.withValues(alpha: 0.15)),
              ),
              Container(decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3 + 0.5 * p), width: 5),
                gradient: RadialGradient(center: Alignment.center, radius: 1.2,
                  colors: [Colors.transparent,
                      Colors.red.withValues(alpha: 0.06 + 0.10 * p)]),
              )),
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: context.ri(80), height: context.ri(80),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.red.shade400.withValues(alpha: 0.6), width: 2),
                    boxShadow: [BoxShadow(
                        color: Colors.red.withValues(alpha: 0.2 + 0.2 * p),
                        blurRadius: 30, spreadRadius: 4)],
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      size: context.ri(42), color: Colors.red.shade300),
                ),
                SizedBox(height: context.rs(18)),
                Text(isDrowsy ? 'DROWSINESS' : 'DISTRACTION',
                    style: TextStyle(fontSize: context.sp(24),
                        fontWeight: FontWeight.w900, color: Colors.red.shade300,
                        letterSpacing: 4)),
                Text('DETECTED', style: TextStyle(fontSize: context.sp(16),
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade400.withValues(alpha: 0.8),
                    letterSpacing: 6)),
                SizedBox(height: context.rs(24)),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.rp(20), vertical: context.rs(10)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(context.rp(24)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.touch_app_rounded,
                        size: context.ri(15), color: Colors.white.withValues(alpha: 0.6)),
                    SizedBox(width: context.rp(7)),
                    Text('Tap anywhere to dismiss', style: TextStyle(
                        fontSize: context.sp(12),
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500, letterSpacing: 0.3)),
                  ]),
                ),
              ])),
              Positioned(
                top: context.rs(10), right: context.rp(10),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.rp(9), vertical: context.rs(5)),
                  decoration: BoxDecoration(
                    color: Colors.red.shade800.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(context.rp(16)),
                    boxShadow: [BoxShadow(
                        color: Colors.red.withValues(alpha: 0.4 * pulse),
                        blurRadius: 10)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: context.ri(6), height: context.ri(6),
                        decoration: BoxDecoration(
                            color: Colors.red.shade200, shape: BoxShape.circle)),
                    SizedBox(width: context.rp(5)),
                    Text('ALARM ACTIVE', style: TextStyle(
                        color: Colors.red.shade100, fontSize: context.sp(9),
                        fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  // ─── METRICS + SYSTEM LOG ─────────────────────────────────────────────────

  Widget _buildMetricsSidebar() {
    final alertness   = ref.watch(alertnessPctProvider);
    final drowsiness  = ref.watch(drowsinessPctProvider);
    final distraction = ref.watch(distractionPctProvider);

    return Column(children: [
      // ClipRect prevents the 86px RenderFlex overflow exception that fires
      // during the PiP→fullscreen animation when Flutter briefly lays out
      // the full UI at PiP window width (~150dp). Clips instead of throwing.
      ClipRect(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _MetricGauge(label: 'Alertness', value: alertness,
              color: const Color(0xFF22d3ee), icon: Icons.bolt)),
          SizedBox(width: context.rp(10)),
          Expanded(child: GestureDetector(
            onTap: drowsiness > 0 ? () => _showSubclassSheet('drowsy') : null,
            child: _MetricGauge(label: 'Drowsiness', value: drowsiness,
                color: const Color(0xFFef4444),
                icon: Icons.visibility_off, tapHint: drowsiness > 0),
          )),
          SizedBox(width: context.rp(10)),
          Expanded(child: GestureDetector(
            onTap: distraction > 0 ? () => _showSubclassSheet('distracted') : null,
            child: _MetricGauge(label: 'Distraction', value: distraction,
                color: const Color(0xFFfbbf24),
                icon: Icons.visibility, tapHint: distraction > 0),
          )),
        ]),
      ),
      SizedBox(height: context.rs(12)),
      _buildSystemLog(),
    ]);
  }

  void _showSubclassSheet(String mainClass) {
    final subclass  = ref.read(activeSubclassProvider) ?? 'safe_driving';
    final isDrowsy  = mainClass == 'drowsy';
    final mainColor = isDrowsy ? const Color(0xFFef4444) : const Color(0xFFfbbf24);

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(context.rp(20), context.rs(12),
            context.rp(20), context.rs(28)),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1627),
          borderRadius: BorderRadius.vertical(top: Radius.circular(context.rp(22))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
            width: context.rp(36), height: context.rs(4),
            margin: EdgeInsets.only(bottom: context.rs(14)),
            decoration: BoxDecoration(color: const Color(0xFF1E2D45),
                borderRadius: BorderRadius.circular(context.rp(2))),
          )),
          Text(isDrowsy ? 'Drowsiness Detected' : 'Distraction Detected',
              style: TextStyle(color: Colors.white,
                  fontSize: context.sp(16), fontWeight: FontWeight.w700)),
          SizedBox(height: context.rs(4)),
          Text('Current: $subclass',
              style: TextStyle(color: mainColor, fontSize: context.sp(12))),
          SizedBox(height: context.rs(14)),
          Text(isDrowsy
              ? 'Drowsy: Yawning, Head Droop, Eyes Closed (PERCLOS)'
              : 'Distracted: Texting, Phone Call, Radio, Drinking,\n'
                'Reaching Behind, Hair/Makeup, Talking to Passenger',
              style: TextStyle(color: const Color(0xFF94a3b8),
                  fontSize: context.sp(12)),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildSystemLog() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
        border: Border.all(color: const Color(0xFF1E2D45), width: 1),
      ),
      padding: EdgeInsets.all(context.rp(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Text('SYSTEM LOG', style: TextStyle(
                color: const Color(0xFF94a3b8), fontSize: context.sp(10),
                fontWeight: FontWeight.w600, letterSpacing: 1.5)),
            const Spacer(),
            if (ref.watch(isRecordingProvider))
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: context.rp(6), vertical: context.rs(2)),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(context.rp(6)),
                ),
                child: Text('● LIVE', style: TextStyle(
                    color: const Color(0xFF10b981),
                    fontSize: context.sp(9), fontWeight: FontWeight.w600)),
              ),
          ]),
          SizedBox(height: context.rs(8)),
          if (_systemLogs.isEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Text('No logs yet. Start recording to begin.',
                  style: TextStyle(color: Colors.white24, fontSize: context.sp(11)),
                  textAlign: TextAlign.center),
            )
          else
            SizedBox(
              height: context.rs(context.isSmallPhone ? 90 : 115),
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: _systemLogs.length > 20 ? 20 : _systemLogs.length,
                itemBuilder: (context, index) {
                  final log = _systemLogs.reversed.toList()[index];
                  Color textColor;
                  switch (log['type']) {
                    case 'SUCCESS': textColor = const Color(0xFF10b981); break;
                    case 'WARNING': textColor = const Color(0xFFfbbf24); break;
                    default:        textColor = const Color(0xFF94a3b8);
                  }
                  return Padding(
                    padding: EdgeInsets.only(bottom: context.rs(5)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('[${log['time']}]',
                          style: TextStyle(color: const Color(0xFF475569),
                              fontSize: context.sp(9), fontFamily: 'monospace')),
                      SizedBox(width: context.rp(6)),
                      Expanded(child: Text(log['message'],
                          style: TextStyle(color: textColor,
                              fontSize: context.sp(9), fontFamily: 'monospace'))),
                    ]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
} // end _MonitorScreenState

// ─── METRIC GAUGE ─────────────────────────────────────────────────────────────
class _MetricGauge extends StatelessWidget {
  final String label; final double value;
  final Color color;  final IconData icon;
  final bool tapHint;
  const _MetricGauge({required this.label, required this.value,
      required this.color, required this.icon, this.tapHint = false});

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 100.0);
    final gaugeD  = context.ri(context.isSmallPhone ? 60.0 : 68.0);
    final fSize   = context.sp(context.isSmallPhone ? 18.0 : 20.0);
    final pSize   = context.sp(9.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
        border: Border.all(
          color: clamped >= 100.0 ? color.withValues(alpha: 0.5) : const Color(0xFF1E2D45),
          width: 1,
        ),
      ),
      padding: EdgeInsets.symmetric(
          vertical: context.rs(10), horizontal: context.rp(5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: context.ri(11), color: color),
          SizedBox(width: context.rp(3)),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: const Color(0xFF94a3b8),
                  fontSize: context.sp(9), fontWeight: FontWeight.w500))),
          if (tapHint) ...[
            SizedBox(width: context.rp(3)),
            Icon(Icons.touch_app_rounded,
                size: context.ri(9), color: color.withValues(alpha: 0.6)),
          ],
        ]),
        SizedBox(height: context.rs(8)),
        SizedBox(width: gaugeD, height: gaugeD,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: gaugeD, height: gaugeD,
              child: CircularProgressIndicator(value: 1.0,
                strokeWidth: context.isSmallPhone ? 3.0 : 4.0,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                    color.withValues(alpha: 0.18)),
                strokeCap: StrokeCap.round)),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${v.toInt()}', style: TextStyle(color: color,
                    fontSize: fSize, fontWeight: FontWeight.bold,
                    fontFamily: 'monospace')),
                Text('%', style: TextStyle(color: color.withValues(alpha: 0.7),
                    fontSize: pSize, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── CAMERA OVERLAY BUTTON ────────────────────────────────────────────────────
class _CameraOverlayButton extends StatelessWidget {
  final IconData icon; final String label;
  final bool isActive; final Color activeColor;
  final VoidCallback onTap;
  const _CameraOverlayButton({required this.icon, required this.label,
      required this.isActive, required this.activeColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
            horizontal: context.rp(12), vertical: context.rs(7)),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(context.rp(18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: context.ri(16),
              color: isActive ? activeColor : Colors.white60),
          SizedBox(width: context.rp(5)),
          Text(label, style: TextStyle(
              color: isActive ? activeColor : Colors.white60,
              fontSize: context.sp(11),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}