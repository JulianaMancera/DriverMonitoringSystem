import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../core/inference/tflite_service.dart';
import '../core/providers.dart';
import '../core/services/notifications.dart';
import '../core/services/pip_service.dart';
import '../core/services/video_clip_service.dart';
import '../core/services/head_pose_service.dart';
import '../core/session_state.dart';
import '../widgets/head_pose_indicator.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../utils/responsive.dart';

// GLOBAL — allows stop from notification even during PiP
_MonitorScreenState? _activeMonitorState;

// ─────────────────────────────────────────────────────────────────────────────
// MONITOR SCREEN
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
  bool _cameraInitialized = false;
  String? _cameraError;
  bool _camDisposing = false;
  bool _cameraResuming = false;
  bool _cameraReconnecting = false;
  bool _isInPipRecovery = false;
  bool _pipResumeHandled = false;

  StreamSubscription<Map<String, dynamic>>? _pipSubscription;

  int? _currentSessionId;
  DateTime? _sessionStartTime;
  Timer? _snapshotTimer;
  Timer? _sessionTimer;
  int _sessionElapsedSec = 0;

  int _consecutiveDrowsy = 0;
  int _consecutiveDistracted = 0;
  int _alertLevel = 0;

  final List<Map<String, dynamic>> _systemLogs = [];
  final List<Map<String, dynamic>> _pendingLogs = [];

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _alarmPlayer = AudioPlayer();

  late AnimationController _warningController;
  late Animation<double> _warningAnimation;
  AnimationController? _notifController;
  Animation<Offset>? _notifSlide;
  Animation<double>? _notifFade;

  int _prefAlertSensitivity = 1;
  bool _prefAutoStart = false;

  static const bool _mirrorCamera = false;

  static const Map<int, List<int>> _sensitivityThresholds = {
    0: [5, 10, 15],
    1: [3, 6, 9],
    2: [2, 4, 6],
  };

  bool _modelLoaded = false;

  // HEAD POSE — (roll in degrees, hasFace)
  final ValueNotifier<(double, bool)> _headPose = ValueNotifier((0.0, false));
  CameraImage? _latestFrame;
  Timer? _headPoseTimer;
  bool _isHeadPoseRunning = false;

  // ── LIFECYCLE ────────────────────────────────────────────────────────────────
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
    _notifSlide = Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: nc, curve: Curves.elasticOut));
    _notifFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: nc, curve: const Interval(0.0, 0.35, curve: Curves.easeIn)));

    _loadPreferencesAndInit();
    _activeMonitorState = this;

    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    _pipSubscription = PipService.pipEventStream.listen((event) {
      if (!mounted) return;
      final type = event['type'] as String?;
      final value = event['value'];
      if (type == 'pip') {
        final inPip = value as bool;
        if (!inPip) {
          _flushPendingLogs();
          if (mounted && ref.read(isRecordingProvider)) {
            setState(() => _cameraResuming = true);
          }
          ref.read(isInPipProvider.notifier).set(false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
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
    _sessionTimer?.cancel();
    _warningController.dispose();
    _notifController?.dispose();
    _pipSubscription?.cancel();

    _headPoseTimer?.cancel();
    _headPoseTimer = null;
    HeadPoseService.instance.dispose();
    _headPose.dispose();

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
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    try {
      _alarmPlayer.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ── TASK DATA CALLBACK ───────────────────────────────────────────────────────
  void _onReceiveTaskData(Object data) async {
    String? message;
    if (data is String) {
      message = data;
    } else if (data is Map) {
      final raw = data['data'];
      if (raw is String) {
        message = raw;
      } else {
        final buttonId = data['notification_button_id'];
        if (buttonId is String) message = buttonId;
      }
    }

    debugPrint('[Monitor] taskData received — type: ${data.runtimeType}, '
        'message: $message, this=$hashCode mounted=$mounted');

    if (message == null) return;
    if (message == 'heartbeat') return;
    if (message != 'stop_recording') return;

    if (_activeMonitorState != null &&
        _activeMonitorState != this &&
        _activeMonitorState!.mounted) {
      debugPrint('[Monitor] delegating to active mounted instance');
      _activeMonitorState!._onReceiveTaskData(data);
      return;
    }

    if (!mounted &&
        (_activeMonitorState == null || _activeMonitorState == this)) {
      debugPrint('[Monitor] no mounted instance — stopping service only');
      BantayDriveService.stopService();
      PipService.setRecording(false);
      await ActiveSession.clear();
      return;
    }

    if (_currentSessionId == null) {
      final restored = await ActiveSession.restoreIfNeeded();
      if (restored) {
        _currentSessionId = ActiveSession.sessionId;
        _sessionStartTime = ActiveSession.startTime;
        debugPrint(
            '[Monitor] restored sessionId from prefs: $_currentSessionId');
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
      await PipService.exitPip();
    }
  }

  // ── LIFECYCLE STATE ──────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
        if (!ref.read(isInPipProvider)) {
          await PipService.setRecording(ref.read(isRecordingProvider));
        }
        break;

      case AppLifecycleState.paused:
        if (ref.read(isRecordingProvider)) {
          if (mounted) ref.read(isInPipProvider.notifier).set(true);
          _isInPipRecovery = true;
          _pipResumeHandled = false;
        } else {
          await _pauseCameraStream();
        }
        break;

      case AppLifecycleState.resumed:
        if (mounted) _flushPendingLogs();
        if (mounted && ref.read(isRecordingProvider)) {
          setState(() => _cameraResuming = true);
        }
        if (mounted) ref.read(isInPipProvider.notifier).set(false);
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

  // ── CAMERA LIFECYCLE ─────────────────────────────────────────────────────────
  void _onCameraValueChanged() {
    if (!mounted || _camDisposing) return;
    final ctrl = _cameraController;
    if (ctrl == null) return;

    if (_cameraReconnecting && ctrl.value.isStreamingImages) {
      setState(() => _cameraReconnecting = false);
      debugPrint('[Camera] CameraX recovery complete — streaming resumed');
    }
  }

  Future<void> _pauseCameraStream() async {
    _stopHeadPoseUpdates();
    if (_cameraController == null || _camDisposing) return;
    try {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      debugPrint('[Camera] pauseStream error: $e');
    }
  }

  Future<void> _resumeAfterPip() async {
    if (_cameraController == null || _camDisposing) return;
    if (!ref.read(isRecordingProvider)) return;
    if (_cameraResuming) return;

    if (mounted) {
      setState(() {
        _cameraResuming = true;
        _cameraReconnecting = true;
      });
    }

    // ✅ Exponential backoff with maximum retries (instead of arbitrary delays)
    const maxRetries = 3;
    var retryCount = 0;
    var backoffMs = 300;

    while (retryCount < maxRetries && !_camDisposing && mounted) {
      try {
        await Future.delayed(Duration(milliseconds: backoffMs));

        if (!mounted || _camDisposing || _cameraController == null) return;

        if (!_cameraController!.value.isStreamingImages) {
          await _cameraController!.startImageStream(_onCameraFrame);
          debugPrint('[Camera] ✅ Image stream resumed after PiP recovery');
        }

        _isInPipRecovery = false;
        if (mounted) {
          setState(() {
            _cameraResuming = false;
            _cameraReconnecting = false;
          });
        }
        return; // ✅ Success - exit retry loop
      } catch (e) {
        retryCount++;
        debugPrint(
            '[Camera] startImageStream retry $retryCount/$maxRetries failed: $e');
        backoffMs = (backoffMs * 1.5).toInt(); // ✅ Exponential backoff

        if (retryCount >= maxRetries) {
          debugPrint(
              '[Camera] ❌ Failed to resume image stream after $maxRetries retries');
          _isInPipRecovery = false;
          if (mounted) {
            setState(() {
              _cameraResuming = false;
              _cameraReconnecting = false;
            });
          }
        }
      }
    }
  }

  // ── CAMERA INIT ──────────────────────────────────────────────────────────────
  Future<void> _loadPreferencesAndInit() async {
    final prefs = PreferencesHelper.instance;
    _prefAlertSensitivity = await prefs.getAlertSensitivity();
    _prefAutoStart = await prefs.getAutoStart();
    final success = await TfliteService.instance.initialize();
    if (mounted) setState(() => _modelLoaded = success);
    if (!await _ensureCameraPermission()) return;
    await _initCamera();
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (mounted) _showPermDeniedDialog();
      return false;
    }

    if (mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0f172a),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Camera Access Needed',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'Bantay Drive uses your camera to monitor driver alertness in real time. '
            'Please grant camera access on the next screen.',
            style: TextStyle(color: Color(0xFF94a3b8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not Now',
                  style: TextStyle(color: Color(0xFF64748b))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue',
                  style: TextStyle(color: Color(0xFF22d3ee))),
            ),
          ],
        ),
      );
      if (proceed != true) return false;
    }

    status = await Permission.camera.request();
    if (status.isGranted) return true;
    if ((status.isDenied || status.isPermanentlyDenied) && mounted) {
      _showPermDeniedDialog();
    }
    return false;
  }

  void _showPermDeniedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0f172a),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Camera Permission Required',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Camera access was denied. Open Settings and enable the camera '
          'permission for Bantay Drive to use monitoring.',
          style: TextStyle(color: Color(0xFF94a3b8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF64748b))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings',
                style: TextStyle(color: Color(0xFF22d3ee))),
          ),
        ],
      ),
    );
  }

  Future<void> _initCamera() async {
    if (_camDisposing) return;
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
          imageFormatGroup: ImageFormatGroup.yuv420,
          fps: 30);
      await _cameraController!.initialize();

      if (!mounted || _camDisposing) return;
      setState(() {
        _cameraInitialized = true;
        _cameraError = null;
      });

      HeadPoseService.instance.init(cam.sensorOrientation);
      _startHeadPoseUpdates();

      _cameraController!.addListener(_onCameraValueChanged);

      if (_prefAutoStart) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && !_camDisposing) await _startRecording();
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  // ── LOG HELPERS ──────────────────────────────────────────────────────────────
  void _flushPendingLogs() {
    if (_pendingLogs.isEmpty) return;

    for (final entry in _pendingLogs) {
      if (_currentSessionId != null) {
        DatabaseHelper.instance.insertSystemLog(
          sessionId: _currentSessionId!,
          message: entry['message'] as String,
          logType: entry['type'] as String,
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

  // ── SESSION ──────────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    // Show camera-alignment guide on first use
    final guideSeen = await PreferencesHelper.instance.getCameraGuideSeen();
    if (!guideSeen && mounted) {
      final proceed = await _showCameraGuide();
      if (!proceed || !mounted) return;
    }

    _currentSessionId = await DatabaseHelper.instance.insertSession();
    await DatabaseHelper.instance.insertStateCount(_currentSessionId!);
    _sessionStartTime = DateTime.now();
    await ActiveSession.start(_currentSessionId!);

    _consecutiveDrowsy = 0;
    _consecutiveDistracted = 0;
    _alertLevel = 0;
    _isStopping = false; // reset guard in case it got stuck
    TfliteService.instance.resetSession();

    if (_cameraInitialized && _modelLoaded && !_camDisposing) {
      try {
        if (!_cameraController!.value.isStreamingImages) {
          await _cameraController!.startImageStream(_onCameraFrame);
        }
      } catch (e) {
        _addLogSync('Inference stream error: $e', 'WARNING');
      }
    }

    _startHeadPoseUpdates();

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

    _snapshotTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _saveAlertnessSnapshot());

    _sessionElapsedSec = 0;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _sessionStartTime != null) {
        setState(() {
          _sessionElapsedSec =
              DateTime.now().difference(_sessionStartTime!).inSeconds;
        });
      }
    });

    ref.read(dbChangeCounterProvider.notifier).increment();
  }

  double _computeAlertnessAvg(
      List<Map<String, dynamic>> snapshots, double fallback) {
    if (snapshots.isEmpty) return fallback;
    final sum = snapshots.fold<double>(
        0.0, (acc, s) => acc + (s['alertness_pct'] as num).toDouble());
    return sum / snapshots.length;
  }

  double _computeSafetyScore(
      List<Map<String, dynamic>> alerts, int durationSec) {
    double totalPenalty = 0.0;
    for (final a in alerts) {
      final level = (a['alert_level'] as int?) ?? 1;
      totalPenalty += switch (level) { 1 => 2.0, 2 => 4.0, _ => 8.0 };
    }
    // 2-minute floor prevents inflated per-minute penalty rates on short test sessions.
    final durationMin = (durationSec > 0 ? durationSec / 60.0 : 1.0)
        .clamp(2.0, double.infinity);
    return (100.0 - (totalPenalty / durationMin) * 10.0).clamp(0.0, 100.0);
  }

  // Re-entrancy guard: prevents _stopRecording from running twice simultaneously.
  // The double-call happens when the Stop button is tapped AND the notification
  // stop button fires at the same time (both call _stopRecording).
  bool _isStopping = false;
  bool _isCapturingClip = false;

  Future<void> _stopRecording() async {
    // Prevent double-call: if already stopping, bail immediately
    if (_isStopping) {
      debugPrint(
          '[Monitor] _stopRecording called while already stopping — ignoring');
      return;
    }
    _isStopping = true;

    // ✅ Timeout mechanism to prevent _isStopping flag from getting stuck
    const maxStopDuration = Duration(seconds: 30);
    var stopCompleted = false;

    try {
      // Execute stop logic with timeout
      await Future.any([
        _performStopRecording().then((_) {
          stopCompleted = true;
        }),
        Future.delayed(maxStopDuration).then((_) {
          if (!stopCompleted) {
            debugPrint(
                '[Monitor] ⚠️ _stopRecording exceeded 30s timeout, forcing cleanup');
            _performStopRecordingCleanup();
          }
        }),
      ]).catchError((_) {
        // Ignore timeout error
        if (!stopCompleted) {
          _performStopRecordingCleanup();
        }
      });
    } catch (e) {
      debugPrint('[Monitor] ❌ Unexpected error in _stopRecording: $e');
      _performStopRecordingCleanup();
    } finally {
      _isStopping = false;
    }
  }

  /// Main stop recording logic (extracted for timeout handling)
  Future<void> _performStopRecording() async {
    if (_currentSessionId == null && ActiveSession.isActive) {
      _currentSessionId = ActiveSession.sessionId;
      _sessionStartTime = ActiveSession.startTime;
    }
    // Guard: if still null after restore, nothing to stop
    if (_currentSessionId == null) {
      BantayDriveService.stopService();
      PipService.setRecording(false);
      if (mounted) {
        ref.read(isRecordingProvider.notifier).set(false);
        ref.read(driverStateProvider.notifier).set('neutral');
        ref.read(showAlertBannerProvider.notifier).set(false);
      }
      return;
    }

    _snapshotTimer?.cancel();
    _sessionTimer?.cancel();
    _sessionTimer = null;
    if (mounted) setState(() => _sessionElapsedSec = 0);

    await _saveAlertnessSnapshot();

    await _pauseCameraStream();
    await _alarmPlayer.stop();
    _alertLevel = _consecutiveDrowsy = _consecutiveDistracted = 0;

    final durationSec = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;

    final snapshots =
        await DatabaseHelper.instance.getAlertnessSnapshots(_currentSessionId!);
    final alertness =
        _computeAlertnessAvg(snapshots, ref.read(alertnessPctProvider));

    final alerts =
        await DatabaseHelper.instance.getAlertsBySession(_currentSessionId!);
    final safetyScore = _computeSafetyScore(alerts, durationSec);

    await DatabaseHelper.instance.endSession(
      sessionId: _currentSessionId!,
      durationSec: durationSec,
      alertnessAvg: alertness,
      safetyScore: safetyScore,
    );

    debugPrint('[Monitor] Session $_currentSessionId ended — '
        'score: ${safetyScore.toInt()}%');
    await ActiveSession.clear();

    if (mounted) {
      ref.read(isInPipProvider.notifier).set(false);
      _flushPendingLogs();
    }
    _addLogSync('Session Ended — Score: ${safetyScore.toInt()}%', 'INFO');

    BantayDriveService.stopService();
    PipService.setRecording(false);

    _currentSessionId = null;
    _sessionStartTime = null;
    _pipResumeHandled = false;
    _isInPipRecovery = false;

    final drowsyAlerts =
        alerts.where((a) => a['alert_type'] == 'DROWSY').length;
    final distractedAlerts =
        alerts.where((a) => a['alert_type'] == 'DISTRACTED').length;

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

      final showSummary =
          await PreferencesHelper.instance.getShowSessionSummary();
      if (mounted && showSummary) {
        _showSessionSummaryModal(
          durationSec: durationSec,
          safetyScore: safetyScore,
          drowsyAlerts: drowsyAlerts,
          distractedAlerts: distractedAlerts,
        );
      }
    }
  }

  /// Cleanup when stop recording times out or fails
  void _performStopRecordingCleanup() {
    BantayDriveService.stopService();
    PipService.setRecording(false);

    _snapshotTimer?.cancel();
    _sessionTimer?.cancel();
    _sessionTimer = null;

    _currentSessionId = null;
    _sessionStartTime = null;
    _pipResumeHandled = false;
    _isInPipRecovery = false;
    _alertLevel = _consecutiveDrowsy = _consecutiveDistracted = 0;

    if (mounted) {
      ref.read(isRecordingProvider.notifier).set(false);
      ref.read(driverStateProvider.notifier).set('neutral');
      ref.read(showAlertBannerProvider.notifier).set(false);
      ref.read(alertnessPctProvider.notifier).set(100.0);
      setState(() => _sessionElapsedSec = 0);
    }
  }

  void _showSessionSummaryModal({
    required int durationSec,
    required double safetyScore,
    required int drowsyAlerts,
    required int distractedAlerts,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      enableDrag: true,
      builder: (_) => _SessionSummaryModal(
        durationSec: durationSec,
        safetyScore: safetyScore,
        drowsyAlerts: drowsyAlerts,
        distractedAlerts: distractedAlerts,
      ),
    );
  }

  // ── INFERENCE ────────────────────────────────────────────────────────────────
  bool _isInferring = false;

  // Non-async so the camera system isn't blocked waiting for inference.
  void _onCameraFrame(CameraImage frame) {
    _latestFrame = frame;
    if (_camDisposing || _isInferring) return;
    if (!mounted || !ref.read(isRecordingProvider)) return;
    _isInferring = true;
    TfliteService.instance.runInference(frame).then((result) {
      _isInferring = false;
      if (result != null && mounted && ref.read(isRecordingProvider)) {
        onModelOutput(result);
      }
    }).catchError((_) {
      _isInferring = false;
    });
  }

  // ── HEAD POSE UPDATES ─────────────────────────────────────────────────────────
  void _startHeadPoseUpdates() {
    _headPoseTimer?.cancel();
    _headPoseTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      // ✅ Skip if already running (prevent overlapping calls)
      if (_isHeadPoseRunning || _camDisposing) return;

      final frame = _latestFrame;
      if (frame == null) return;

      _isHeadPoseRunning = true;
      try {
        final result = await HeadPoseService.instance.detectPose(frame);

        // Update circle indicator
        if (mounted) {
          _headPose.value = (result?.roll ?? 0.0, result != null);
        }

        if (result != null) {
          TfliteService.instance.updateFaceData(
            earL: result.earL,
            earR: result.earR,
            mar: result.mar,
            pitch: result.pitch,
            yaw: result.yaw,
            rollEulerZ: result.roll,
          );
        }
        // When face is not detected, keep the last known face values.
        // Zeroing EAR to 0.0 would falsely signal "eyes completely closed"
        // and corrupt the temporal buffer used for drowsy detection.
      } catch (e) {
        debugPrint('[HeadPose] Error detecting pose: $e');
      } finally {
        _isHeadPoseRunning = false;
      }
    });
  }

  void _stopHeadPoseUpdates() {
    _headPoseTimer?.cancel();
    _headPoseTimer = null;
    if (mounted) _headPose.value = (0.0, false);
  }

  // 55° avoids false warnings for typical side-mount angles (30–45°).
  bool _isInRedZone(double rollDeg, bool hasFace) {
    if (!hasFace) return false;
    return rollDeg.abs() >= 55.0;
  }

  Future<bool> _showCameraGuide() async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: false,
      builder: (_) => _CameraGuideDialog(headPose: _headPose),
    );
    if (result == true) {
      await PreferencesHelper.instance.setCameraGuideSeen(true);
    }
    return result == true;
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
      DatabaseHelper.instance
          .incrementStateCount(sessionId: _currentSessionId!, state: r.state);
    }

    switch (r.state) {
      case 'drowsy':
        _consecutiveDrowsy++;
        _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 999);
        _addLogSync(
            '[${modelSourceLabel(r.modelSource)}] '
                '${r.subclass} — ${r.drowsyPct.toInt()}% drowsy',
            'WARNING');
        _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
        BantayDriveService.updateState('drowsy');
        break;
      case 'distracted':
        _consecutiveDistracted++;
        _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 999);
        _addLogSync(
            '[${modelSourceLabel(r.modelSource)}] '
                '${r.subclass} — ${r.distractedPct.toInt()}% distracted',
            'WARNING');
        _checkAndTriggerAlert('DISTRACTED', _consecutiveDistracted);
        BantayDriveService.updateState('distracted');
        break;
      default:
        _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 999);
        _consecutiveDistracted = (_consecutiveDistracted - 1).clamp(0, 999);
        // Only clear an active L1/L2 alert once both counters drop below the
        // L1 threshold. A single neutral frame during borderline drowsiness was
        // previously zeroing _alertLevel immediately, making L2/L3 unreachable.
        final thresholds =
            _sensitivityThresholds[_prefAlertSensitivity] ?? [3, 6, 9];
        if (_alertLevel > 0 &&
            _alertLevel < 3 &&
            _consecutiveDrowsy < thresholds[0] &&
            _consecutiveDistracted < thresholds[0]) {
          _alertLevel = 0;
          _alarmPlayer.stop();
          ref.read(showAlertBannerProvider.notifier).set(false);
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

    if (_currentSessionId != null && newLevel >= 2) {
      _saveVideoClip(type, newLevel);
    }

    if (_currentSessionId != null) {
      await DatabaseHelper.instance.insertAlertEvent(
          sessionId: _currentSessionId!, alertType: type, alertLevel: newLevel);
      _addLogSync(
          'ALERT Level $newLevel — '
              '${type == 'DROWSY' ? 'Drowsiness' : 'Distraction'} '
              '($consecutive consecutive frames)',
          'WARNING');
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
        sessionId: _currentSessionId!,
        alertnessPct: ref.read(alertnessPctProvider).clamp(0.0, 100.0));
    if (mounted) ref.read(dbChangeCounterProvider.notifier).increment();
  }

  Future<void> _saveVideoClip(String alertType, int alertLevel) async {
    if (_currentSessionId == null) return;
    if (_isCapturingClip) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_camDisposing) return;

    final sessionId = _currentSessionId!;
    _isCapturingClip = true;

    // startVideoRecording and startImageStream are mutually exclusive, so we
    // alternate: record a chunk → save it → briefly resume inference to check
    // if the alert is still active → repeat until clear or 3-min cap.
    // Each chunk is saved as its own clip entry so its file length always
    // matches the displayed duration.
    const chunkDuration = Duration(seconds: 10);
    const inferenceWindow = Duration(milliseconds: 1000);
    const maxTotalDuration = Duration(minutes: 3);
    // ✅ Buffer delay after stopping image stream before starting video recording
    const surfaceRecoveryDelay = Duration(milliseconds: 150);
    final clipStart = DateTime.now();

    try {
      bool keepRecording = true;
      int recordingAttempts = 0;
      int consecutiveErrors = 0;

      while (keepRecording) {
        if (_camDisposing || !ref.read(isRecordingProvider)) break;
        if (DateTime.now().difference(clipStart) >= maxTotalDuration) break;

        recordingAttempts++;

        // ✅ Stop image stream with proper state management
        if (_cameraController!.value.isStreamingImages) {
          try {
            await _cameraController!.stopImageStream();
            debugPrint('[VideoClip] Image stream stopped for chunk recording');
          } catch (e) {
            debugPrint('[VideoClip] ❌ Error stopping image stream: $e');
            consecutiveErrors++;
            if (consecutiveErrors >= 3) break;
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
        }

        // ✅ Wait for surface to be ready before starting video recording
        await Future.delayed(surfaceRecoveryDelay);

        try {
          await _cameraController!.startVideoRecording();
          consecutiveErrors = 0; // Reset error counter on success
          debugPrint(
              '[VideoClip] Video recording started (attempt $recordingAttempts)');
        } catch (e) {
          debugPrint('[VideoClip] ❌ Error starting video recording: $e');
          consecutiveErrors++;
          if (consecutiveErrors >= 3) {
            debugPrint(
                '[VideoClip] ❌ Too many consecutive errors, stopping recording');
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        await Future.delayed(chunkDuration);

        if (_camDisposing) {
          try {
            await _cameraController!.stopVideoRecording();
          } catch (_) {}
          break;
        }

        XFile? videoFile;
        try {
          videoFile = await _cameraController!.stopVideoRecording();
          debugPrint(
              '[VideoClip] Video recording stopped, file: ${videoFile.path}');
        } catch (e) {
          debugPrint('[VideoClip] ❌ Error stopping video recording: $e');
          consecutiveErrors++;
          if (consecutiveErrors >= 3) break;
          continue;
        }

        // ✅ Verify file was created and attempt to save
        final savedPath = await VideoClipService.saveClip(
          sourcePath: videoFile.path,
          sessionId: sessionId,
        );

        if (savedPath != null && mounted) {
          try {
            await DatabaseHelper.instance.insertVideoClip(
              sessionId: sessionId,
              filePath: savedPath,
              alertTypes: alertType,
              durationSec: chunkDuration.inSeconds,
            );
            ref.read(dbChangeCounterProvider.notifier).increment();
            debugPrint('[VideoClip] ✅ Clip saved and recorded: $savedPath');
          } catch (e) {
            debugPrint('[VideoClip] ❌ Error inserting clip into database: $e');
            // Continue even if DB insert fails
          }
        } else {
          debugPrint('[VideoClip] ❌ Failed to save clip (savedPath was null)');
          consecutiveErrors++;
          if (consecutiveErrors >= 3) break;
        }

        // Brief inference window: check whether the alert is still active.
        if (!_camDisposing && ref.read(isRecordingProvider)) {
          try {
            await _cameraController!.startImageStream(_onCameraFrame);
            debugPrint('[VideoClip] Image stream resumed for inference check');
            await Future.delayed(inferenceWindow);
            if (_cameraController!.value.isStreamingImages) {
              await _cameraController!.stopImageStream();
              debugPrint(
                  '[VideoClip] Image stream stopped after inference check');
            }
          } catch (e) {
            debugPrint('[VideoClip] ❌ Inference check error: $e');
            consecutiveErrors++;
            if (consecutiveErrors >= 3) {
              keepRecording = false;
              break;
            }
          }
          keepRecording = _alertLevel > 0;
        } else {
          keepRecording = false;
        }
      }
    } catch (e) {
      debugPrint('[VideoClip] _saveVideoClip error: $e');
    } finally {
      if (!_camDisposing && ref.read(isRecordingProvider)) {
        try {
          if (!_cameraController!.value.isStreamingImages) {
            await _cameraController!.startImageStream(_onCameraFrame);
          }
        } catch (_) {}
      }
      _isCapturingClip = false;
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isInPip = ref.watch(isInPipProvider);

    if (isInPip) return _buildPipView();

    if (_pendingLogs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _flushPendingLogs());
    }

    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);
    final isLevel3 = _alertLevel == 3;

    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Stack(children: [
        SafeArea(bottom: false, child: _buildPortraitLayout()),
        if (showAlert && !isLevel3)
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child:
                  SafeArea(bottom: false, child: _buildAlertBanner(alertType))),
        if (showAlert && isLevel3)
          Positioned.fill(child: _buildWarningOverlay(alertType)),
      ]),
    );
  }

  // ── PiP VIEW ─────────────────────────────────────────────────────────────────
  Widget _buildPipView() {
    final isRecording = ref.watch(isRecordingProvider);

    if (!isRecording) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.stop_circle_outlined, color: Colors.white54, size: 28),
            SizedBox(height: 6),
            Text('Monitoring Stopped',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Tap here to close',
                style: TextStyle(color: Colors.white54, fontSize: 9)),
          ]),
        ),
      );
    }

    final driverState = ref.watch(driverStateProvider);
    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);

    final String stateLabel = switch (driverState) {
      'drowsy' => 'Drowsy Detected',
      'distracted' => 'Distracted',
      _ => 'Alert',
    };
    final alertColor = alertType == 'DROWSY' ? Colors.orange : Colors.red;

    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (_cameraInitialized &&
            !_camDisposing &&
            _cameraController != null &&
            _cameraController!.value.isInitialized)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 480,
                height: _cameraController!.value.previewSize?.width ?? 640,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ),
        if (isRecording)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: Colors.white, size: 5),
                SizedBox(width: 3),
                Text('REC',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0)),
              ]),
            ),
          ),
        Positioned(
          bottom: 6,
          left: 6,
          right: 6,
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
                    showAlert
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 11),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(stateLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── LAYOUTS ──────────────────────────────────────────────────────────────────
  Widget _buildPortraitLayout() => LayoutBuilder(
        builder: (context, constraints) {
          final availH = constraints.maxHeight;
          final camH = availH * (context.isSmallPhone ? 0.50 : 0.52);

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: context.rp(14)),
            child: Column(
              children: [
                SizedBox(height: context.rs(20)),
                _buildCameraWithOverlay(height: camH),
                SizedBox(height: context.rs(10)),
                Expanded(child: _buildMetricsSidebar()),
                SizedBox(height: context.rs(14)),
              ],
            ),
          );
        },
      );

  Widget _buildCameraChild(double camW, double camH) {
    final ctrl = _cameraController;
    final canShow = _cameraInitialized &&
        !_camDisposing &&
        ctrl != null &&
        ctrl.value.isInitialized;

    if (canShow) {
      return Stack(children: [
        CameraPreview(key: _cameraKey, ctrl),
        if (_cameraReconnecting)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                  width: 24,
                  height: 24,
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

    if (_cameraResuming || _cameraReconnecting) {
      return const ColoredBox(color: Colors.black);
    }

    return _buildCameraFallback();
  }

  Widget _buildCameraWithOverlay({double? height}) {
    final isRecording = ref.watch(isRecordingProvider);

    double camAspect;
    final ctrl = _cameraController;
    if (_cameraInitialized &&
        ctrl != null &&
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
          camW = boxW;
          camH = boxW / camAspect;
        } else {
          camH = boxH;
          camW = boxH * camAspect;
        }
        return ClipRect(
          child: OverflowBox(
            maxWidth: camW,
            maxHeight: camH,
            child: Transform(
              alignment: Alignment.center,
              transform:
                  Matrix4.diagonal3Values(_mirrorCamera ? -1.0 : 1.0, 1.0, 1.0),
              child: SizedBox(
                width: camW,
                height: camH,
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
                        width: context.ri(6),
                        height: context.ri(6),
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle)),
                    SizedBox(width: context.rp(4)),
                    Text(_modelLoaded ? 'AI ON' : 'DEMO',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: context.sp(9),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8)),
                  ]),
                ),
              ),

            // Head pose indicator — always visible when camera is active
            if (!ref.watch(isInPipProvider) &&
                _cameraInitialized &&
                !_camDisposing)
              Positioned(
                bottom: context.rs(58),
                right: context.rp(10),
                child: ValueListenableBuilder<(double, bool)>(
                  valueListenable: _headPose,
                  builder: (_, pose, __) {
                    final roll = pose.$1;
                    final hasFace = pose.$2;
                    final inRed = _isInRedZone(roll, hasFace);

                    final String statusLabel;
                    final Color statusColor;
                    if (!hasFace) {
                      statusLabel = 'No Face';
                      statusColor = Colors.white38;
                    } else if (inRed) {
                      statusLabel = 'Reposition';
                      statusColor = const Color(0xFFef4444);
                    } else if (roll.abs() >= 30) {
                      statusLabel = 'Angle OK';
                      statusColor = const Color(0xFFfbbf24);
                    } else {
                      statusLabel = 'Aligned';
                      statusColor = const Color(0xFF22c55e);
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (inRed)
                          Container(
                            margin: EdgeInsets.only(bottom: context.rs(4)),
                            padding: EdgeInsets.symmetric(
                                horizontal: context.rp(6),
                                vertical: context.rs(3)),
                            decoration: BoxDecoration(
                              color: const Color(0xFFef4444)
                                  .withValues(alpha: 0.92),
                              borderRadius:
                                  BorderRadius.circular(context.rp(6)),
                            ),
                            child: Text(
                              'Camera position not\nsuitable for detection',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: context.sp(8),
                                  fontWeight: FontWeight.w600,
                                  height: 1.3),
                            ),
                          ),
                        HeadPoseIndicator(
                          roll: roll,
                          hasFace: hasFace,
                          size: 75,
                        ),
                        SizedBox(height: context.rs(4)),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: context.rp(6),
                              vertical: context.rs(2)),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(context.rp(4)),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: context.sp(8),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            if (!ref.watch(isInPipProvider))
              Positioned(
                bottom: context.rs(12),
                left: 0,
                right: 0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(context.rp(24)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: context.rp(5), vertical: context.rs(5)),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0f172a).withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(context.rp(24)),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1),
                        ),
                        child: _CameraOverlayButton(
                          icon: isRecording
                              ? Icons.stop_circle
                              : Icons.fiber_manual_record,
                          label: isRecording ? 'Stop' : 'Record',
                          isActive: isRecording,
                          activeColor: Colors.red,
                          onTap: () => isRecording
                              ? _stopRecording()
                              : _startRecording(),
                        ),
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
      height: height,
      width: double.infinity,
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
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off,
              color: const Color(0xFF64748b), size: context.ri(44)),
          SizedBox(height: context.rs(12)),
          Text(_cameraError!,
              style: TextStyle(
                  color: const Color(0xFF64748b), fontSize: context.sp(12)),
              textAlign: TextAlign.center),
          SizedBox(height: context.rs(12)),
          TextButton(
              onPressed: _initCamera,
              child: Text('Retry',
                  style: TextStyle(
                      color: const Color(0xFF22d3ee),
                      fontSize: context.sp(13)))),
        ])),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Color(0xFF22d3ee)),
        SizedBox(height: context.rs(12)),
        Text('Initializing camera...',
            style: TextStyle(
                color: const Color(0xFF64748b), fontSize: context.sp(12))),
      ])),
    );
  }

  Widget _buildGradientOverlay() => Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF0f172a).withValues(alpha: 0.5)
              ],
            ),
          ),
        ),
      );

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildRecBadge() => Positioned(
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
                width: context.ri(7),
                height: context.ri(7),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle)),
            SizedBox(width: context.rp(5)),
            Text('REC',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: context.sp(10),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            Container(
              width: 1,
              height: context.rs(10),
              color: Colors.white38,
              margin: EdgeInsets.symmetric(horizontal: context.rp(6)),
            ),
            Text(
              _formatDuration(_sessionElapsedSec),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: context.sp(10),
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      );

  // ── ALERT BANNER — L1/L2 ────────────────────────────────────────────────────
  Widget _buildAlertBanner(String type) {
    final isDrowsy = type == 'DROWSY';
    final slideAnim = _notifSlide ?? AlwaysStoppedAnimation(Offset.zero);
    final fadeAnim = _notifFade ?? const AlwaysStoppedAnimation(1.0);

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
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 28,
                        offset: const Offset(0, 8)),
                    BoxShadow(
                        color:
                            Colors.red.withValues(alpha: 0.12 + 0.18 * pulse),
                        blurRadius: 20,
                        spreadRadius: 1,
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
                        Container(
                          width: context.ri(40),
                          height: context.ri(40),
                          decoration: BoxDecoration(
                            color: Colors.red.shade800,
                            borderRadius: BorderRadius.circular(context.rp(10)),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.red
                                      .withValues(alpha: 0.3 + 0.4 * pulse),
                                  blurRadius: 14,
                                  spreadRadius: 1)
                            ],
                          ),
                          child: Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: context.ri(22)),
                        ),
                        SizedBox(width: context.rp(10)),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('BANTAY DRIVE',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.45),
                                        fontSize: context.sp(10),
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8)),
                                Text('now',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.35),
                                        fontSize: context.sp(10))),
                              ],
                            ),
                            SizedBox(height: context.rs(3)),
                            Text(
                                isDrowsy
                                    ? 'Drowsiness Detected'
                                    : 'Distraction Detected',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: context.sp(14),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2)),
                            SizedBox(height: context.rs(2)),
                            Text(
                                isDrowsy
                                    ? 'Stay alert — tap to dismiss'
                                    : 'Focus on the road — tap to dismiss',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: context.sp(11))),
                          ],
                        )),
                        SizedBox(width: context.rp(6)),
                        Container(
                          width: context.ri(20),
                          height: context.ri(20),
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

  // ── WARNING OVERLAY — L3 ─────────────────────────────────────────────────────
  Widget _buildWarningOverlay(String type) {
    final isDrowsy = type == 'DROWSY';
    return GestureDetector(
      onTap: _dismissAlert,
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _warningAnimation,
          builder: (context, _) {
            final pulse = _warningAnimation.value;
            final p = (pulse - 0.8) / 0.2;
            return Stack(fit: StackFit.expand, children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.red.withValues(alpha: 0.15)),
              ),
              Container(
                  decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3 + 0.5 * p),
                    width: 5),
                gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.red.withValues(alpha: 0.06 + 0.10 * p)
                    ]),
              )),
              Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: context.ri(80),
                  height: context.ri(80),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.red.shade400.withValues(alpha: 0.6),
                        width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.red.withValues(alpha: 0.2 + 0.2 * p),
                          blurRadius: 30,
                          spreadRadius: 4)
                    ],
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      size: context.ri(42), color: Colors.red.shade300),
                ),
                SizedBox(height: context.rs(18)),
                Text(isDrowsy ? 'DROWSINESS' : 'DISTRACTION',
                    style: TextStyle(
                        fontSize: context.sp(24),
                        fontWeight: FontWeight.w900,
                        color: Colors.red.shade300,
                        letterSpacing: 4)),
                Text('DETECTED',
                    style: TextStyle(
                        fontSize: context.sp(16),
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
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.touch_app_rounded,
                        size: context.ri(15),
                        color: Colors.white.withValues(alpha: 0.6)),
                    SizedBox(width: context.rp(7)),
                    Text('Tap anywhere to dismiss',
                        style: TextStyle(
                            fontSize: context.sp(12),
                            color: Colors.white.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3)),
                  ]),
                ),
              ])),
              Positioned(
                top: context.rs(10),
                right: context.rp(10),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.rp(9), vertical: context.rs(5)),
                  decoration: BoxDecoration(
                    color: Colors.red.shade800.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(context.rp(16)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4 * pulse),
                          blurRadius: 10)
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: context.ri(6),
                        height: context.ri(6),
                        decoration: BoxDecoration(
                            color: Colors.red.shade200,
                            shape: BoxShape.circle)),
                    SizedBox(width: context.rp(5)),
                    Text('ALARM ACTIVE',
                        style: TextStyle(
                            color: Colors.red.shade100,
                            fontSize: context.sp(9),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0)),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  // ── METRICS + SYSTEM LOG ─────────────────────────────────────────────────────
  Widget _buildMetricsSidebar() {
    final alertness = ref.watch(alertnessPctProvider);
    final drowsiness = ref.watch(drowsinessPctProvider);
    final distraction = ref.watch(distractionPctProvider);

    return Column(children: [
      ClipRect(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: _MetricGauge(
                  label: 'Alertness',
                  value: alertness,
                  color: const Color(0xFF22d3ee),
                  icon: Icons.bolt)),
          SizedBox(width: context.rp(10)),
          Expanded(
              child: GestureDetector(
            onTap: drowsiness > 0 ? () => _showSubclassSheet('drowsy') : null,
            child: _MetricGauge(
                label: 'Drowsiness',
                value: drowsiness,
                color: const Color(0xFFef4444),
                icon: Icons.visibility_off,
                tapHint: drowsiness > 0),
          )),
          SizedBox(width: context.rp(10)),
          Expanded(
              child: GestureDetector(
            onTap:
                distraction > 0 ? () => _showSubclassSheet('distracted') : null,
            child: _MetricGauge(
                label: 'Distraction',
                value: distraction,
                color: const Color(0xFFfbbf24),
                icon: Icons.visibility,
                tapHint: distraction > 0),
          )),
        ]),
      ),
      SizedBox(height: context.rs(12)),
      Expanded(child: _buildSystemLog()),
    ]);
  }

  void _showSubclassSheet(String mainClass) {
    final subclass = ref.read(activeSubclassProvider) ?? 'safe_driving';
    final isDrowsy = mainClass == 'drowsy';
    final mainColor =
        isDrowsy ? const Color(0xFFef4444) : const Color(0xFFfbbf24);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
            context.rp(20), context.rs(12), context.rp(20), context.rs(28)),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1627),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(context.rp(22))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
              child: Container(
            width: context.rp(36),
            height: context.rs(4),
            margin: EdgeInsets.only(bottom: context.rs(14)),
            decoration: BoxDecoration(
                color: const Color(0xFF1E2D45),
                borderRadius: BorderRadius.circular(context.rp(2))),
          )),
          Text(isDrowsy ? 'Drowsiness Detected' : 'Distraction Detected',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: context.sp(16),
                  fontWeight: FontWeight.w700)),
          SizedBox(height: context.rs(4)),
          Text('Current: $subclass',
              style: TextStyle(color: mainColor, fontSize: context.sp(12))),
          SizedBox(height: context.rs(14)),
          Text(
              isDrowsy
                  ? 'Drowsy: Yawning, Head Droop, Eyes Closed (PERCLOS)'
                  : 'Distracted: Texting, Phone Call, Radio, Drinking,\n'
                      'Reaching Behind, Hair/Makeup, Talking to Passenger',
              style: TextStyle(
                  color: const Color(0xFF94a3b8), fontSize: context.sp(12)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('SYSTEM LOG',
                style: TextStyle(
                    color: const Color(0xFF94a3b8),
                    fontSize: context.sp(10),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5)),
            const Spacer(),
            if (ref.watch(isRecordingProvider))
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: context.rp(6), vertical: context.rs(2)),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(context.rp(6)),
                ),
                child: Text('● LIVE',
                    style: TextStyle(
                        color: const Color(0xFF10b981),
                        fontSize: context.sp(9),
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          SizedBox(height: context.rs(8)),
          Expanded(
            child: _systemLogs.isEmpty
                ? Align(
                    alignment: Alignment.topCenter,
                    child: Text('No logs yet. Start recording to begin.',
                        style: TextStyle(
                            color: Colors.white24, fontSize: context.sp(11)),
                        textAlign: TextAlign.center),
                  )
                : Builder(builder: (context) {
                    final recentLogs = _systemLogs.reversed.take(20).toList();
                    return ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: recentLogs.length,
                      itemBuilder: (context, index) {
                        final log = recentLogs[index];
                        final textColor = switch (log['type']) {
                          'SUCCESS' => const Color(0xFF10b981),
                          'WARNING' => const Color(0xFFfbbf24),
                          _ => const Color(0xFF94a3b8),
                        };
                        return Padding(
                          padding: EdgeInsets.only(bottom: context.rs(5)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('[${log['time']}]',
                                  style: TextStyle(
                                      color: const Color(0xFF475569),
                                      fontSize: context.sp(9),
                                      fontFamily: 'monospace')),
                              SizedBox(width: context.rp(6)),
                              Expanded(
                                  child: Text(log['message'],
                                      style: TextStyle(
                                          color: textColor,
                                          fontSize: context.sp(9),
                                          fontFamily: 'monospace'))),
                            ],
                          ),
                        );
                      },
                    );
                  }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// METRIC GAUGE
// ─────────────────────────────────────────────────────────────────────────────
class _MetricGauge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final bool tapHint;
  const _MetricGauge(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon,
      this.tapHint = false});

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 100.0);
    final gaugeD = context.ri(context.isSmallPhone ? 60.0 : 68.0);
    final fSize = context.sp(context.isSmallPhone ? 18.0 : 20.0);
    final pSize = context.sp(9.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
        border: Border.all(
          color: clamped >= 100.0
              ? color.withValues(alpha: 0.5)
              : const Color(0xFF1E2D45),
          width: 1,
        ),
      ),
      padding: EdgeInsets.symmetric(
          vertical: context.rs(10), horizontal: context.rp(5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: context.ri(11), color: color),
          SizedBox(width: context.rp(3)),
          Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: const Color(0xFF94a3b8),
                      fontSize: context.sp(9),
                      fontWeight: FontWeight.w500))),
          if (tapHint) ...[
            SizedBox(width: context.rp(3)),
            Icon(Icons.touch_app_rounded,
                size: context.ri(9), color: color.withValues(alpha: 0.6)),
          ],
        ]),
        SizedBox(height: context.rs(8)),
        SizedBox(
          width: gaugeD,
          height: gaugeD,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
                width: gaugeD,
                height: gaugeD,
                child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: context.isSmallPhone ? 3.0 : 4.0,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        color.withValues(alpha: 0.18)),
                    strokeCap: StrokeCap.round)),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (_, v, __) =>
                  Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${v.toInt()}',
                    style: TextStyle(
                        color: color,
                        fontSize: fSize,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace')),
                Text('%',
                    style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: pSize,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CAMERA OVERLAY BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _CameraOverlayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  const _CameraOverlayButton(
      {required this.icon,
      required this.label,
      required this.isActive,
      required this.activeColor,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
            horizontal: context.rp(12), vertical: context.rs(7)),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(context.rp(18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: context.ri(16),
              color: isActive ? activeColor : Colors.white60),
          SizedBox(width: context.rp(5)),
          Text(label,
              style: TextStyle(
                  color: isActive ? activeColor : Colors.white60,
                  fontSize: context.sp(11),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SUMMARY MODAL
// ─────────────────────────────────────────────────────────────────────────────
class _SessionSummaryModal extends StatefulWidget {
  final int durationSec;
  final double safetyScore;
  final int drowsyAlerts;
  final int distractedAlerts;

  const _SessionSummaryModal({
    required this.durationSec,
    required this.safetyScore,
    required this.drowsyAlerts,
    required this.distractedAlerts,
  });

  @override
  State<_SessionSummaryModal> createState() => _SessionSummaryModalState();
}

class _SessionSummaryModalState extends State<_SessionSummaryModal>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF0D1627);
  static const Color _surface = Color(0xFF1A2235);
  static const Color _divider = Color(0xFF1E2D45);
  static const Color _cyan = Color(0xFF00D4FF);
  static const Color _green = Color(0xFF00FF88);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _red = Color(0xFFEF4444);
  static const Color _drowsy = Color(0xFFF59E0B);
  static const Color _dist = Color(0xFFA855F7);
  static const Color _txtPri = Color(0xFFEEF2FF);
  static const Color _txtMuted = Color(0xFF94A3B8);
  static const Color _txtDim = Color(0xFF6B7A99);

  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _scoreColor {
    if (widget.safetyScore >= 80) return _green;
    if (widget.safetyScore >= 50) return _amber;
    return _red;
  }

  String _formatDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m ${sec}s';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    final totalAlerts = widget.drowsyAlerts + widget.distractedAlerts;
    final allClear = totalAlerts == 0;
    final headerColor = _scoreColor;

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(_scale),
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 40,
                  offset: const Offset(0, -8)),
              BoxShadow(
                  color: headerColor.withValues(alpha: 0.05),
                  blurRadius: 60,
                  spreadRadius: 4),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: _divider,
                        borderRadius: BorderRadius.circular(2))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 14),
                child: Row(children: [
                  Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: headerColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: headerColor.withValues(alpha: 0.35),
                              width: 2)),
                      child: Icon(
                          allClear
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          color: headerColor,
                          size: 24)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Session Complete',
                            style: TextStyle(
                                color: _txtPri,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(_formatDuration(widget.durationSec),
                            style: TextStyle(color: _txtMuted, fontSize: 13)),
                      ])),
                  GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: _surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: _divider, width: 1)),
                          child: Icon(Icons.close_rounded,
                              color: _txtMuted, size: 18))),
                ]),
              ),
              Divider(color: _divider, height: 1, thickness: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: headerColor.withValues(alpha: 0.25), width: 1),
                    ),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('SAFETY SCORE',
                                style: TextStyle(
                                    color: _txtDim,
                                    fontSize: 11,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${widget.safetyScore.toInt()}',
                                      style: TextStyle(
                                          color: headerColor,
                                          fontSize: 42,
                                          fontWeight: FontWeight.w800,
                                          height: 1)),
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 6, left: 3),
                                      child: Text('%',
                                          style: TextStyle(
                                              color: headerColor.withValues(
                                                  alpha: 0.7),
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600))),
                                ]),
                          ])),
                      _ScoreRing(score: widget.safetyScore, color: headerColor),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: _AlertChip(
                      label: 'Drowsy',
                      count: widget.drowsyAlerts,
                      color: _drowsy,
                      icon: Icons.bedtime_outlined,
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _AlertChip(
                      label: 'Distracted',
                      count: widget.distractedAlerts,
                      color: _dist,
                      icon: Icons.visibility_off_outlined,
                    )),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cyan.withValues(alpha: 0.12),
                        foregroundColor: _cyan,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: _cyan.withValues(alpha: 0.35),
                                width: 1)),
                      ),
                      child: const Text('Done',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;
  final Color color;
  const _ScoreRing({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 5,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
            strokeCap: StrokeCap.round,
          ),
        ),
        Text('${score.toInt()}%',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _AlertChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlerts = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2235),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: hasAlerts
                ? color.withValues(alpha: 0.30)
                : const Color(0xFF1E2D45),
            width: 1),
      ),
      child: Row(children: [
        Icon(icon,
            color: hasAlerts ? color : const Color(0xFF6B7A99), size: 18),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 1),
          Text('$count alert${count == 1 ? '' : 's'}',
              style: TextStyle(
                  color: hasAlerts ? color : const Color(0xFF6B7A99),
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CAMERA ALIGNMENT GUIDE DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _CameraGuideDialog extends StatelessWidget {
  final ValueNotifier<(double, bool)> headPose;
  const _CameraGuideDialog({required this.headPose});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: Color(0xFFe2e8f0), shape: BoxShape.circle),
                child:
                    const Icon(Icons.close, size: 20, color: Color(0xFF1e293b)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<(double, bool)>(
            valueListenable: headPose,
            builder: (_, pose, __) => HeadPoseIndicator(
              roll: pose.$1,
              hasFace: pose.$2,
              size: 170,
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<(double, bool)>(
            valueListenable: headPose,
            builder: (_, pose, __) {
              final inGreen = pose.$2 && pose.$1.abs() < 30.0;
              return Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: inGreen
                        ? const Color(0xFF22c55e)
                        : const Color(0xFFe2e8f0),
                    width: 2.5,
                  ),
                ),
                child: Column(children: [
                  const Text(
                    'Position your phone to the right side of the driver at '
                    '30–45°. The camera icon should be in the green or yellow zone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1e293b),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22c55e),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('OK',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}