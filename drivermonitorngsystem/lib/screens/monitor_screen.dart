// ─────────────────────────────────────────────────────────────────────────────
// monitor_screen.dart  —  v4 patched
//
// PATCHES APPLIED (from patch_notes_v4.dart):
//   1A: PiP entirely removed (channels, providers, _buildPipView, _pendingStopAfterPip, etc.)
//   1B: Original stream management restored in didChangeAppLifecycleState
//   1C: Original _onCameraFrame restored (200ms throttle, null = dropped frame)
//   1D: System log in onModelOutput now shows [source] subclass — X% format
//   1E: T02 warm-up badge removed from _buildCameraWithOverlay
//   1F: Alert log message fixed to show "consecutive frames"
//   1G: Notification permission block removed (apply to main.dart separately)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../core/inference/tflite_service.dart';
import '../core/services/notifications.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import '../utils/responsive.dart';

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

// PATCH 1A: isInPipProvider kept as always-false stub for main.dart compat
final isInPipProvider = NotifierProvider<_BoolNotifier, bool>(
    () => _BoolNotifier(false));

final activeSubclassProvider =
    NotifierProvider<_NullableStringNotifier, String?>(
        _NullableStringNotifier.new);
final activeSubclassIndexProvider = NotifierProvider<_IntNotifier, int>(
    () => _IntNotifier(0));

// PATCH 1A: pipOrientationProvider removed (was only used by PiP logic)

// ─────────────────────────────────────────────────────────────────────────────
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});
  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── Camera ───────────────────────────────────────────────────────────────
  final GlobalKey _cameraKey = GlobalKey();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool    _cameraInitialized = false;
  String? _cameraError;
  bool    _camDisposing      = false;

  // ── Session ───────────────────────────────────────────────────────────────
  int?      _currentSessionId;
  DateTime? _sessionStartTime;
  Timer?    _snapshotTimer;

  // ── Alert counters ────────────────────────────────────────────────────────
  int _consecutiveDrowsy     = 0;
  int _consecutiveDistracted = 0;
  int _alertLevel            = 0;

  // ── Logs ──────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _systemLogs = [];

  // ── Audio ─────────────────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _alarmPlayer = AudioPlayer();

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _warningController;
  late Animation<double>   _warningAnimation;
  AnimationController?     _notifController;
  Animation<Offset>?       _notifSlide;
  Animation<double>?       _notifFade;

  // ── Prefs ─────────────────────────────────────────────────────────────────
  int  _prefAlertSensitivity = 1;
  bool _prefAutoStart        = false;

  static const bool _mirrorCamera = false;

  static const Map<int, List<int>> _sensitivityThresholds = {
    0: [5, 10, 15], // Low
    1: [3,  6,  9], // Medium
    2: [2,  4,  6], // High
  };

  bool _modelLoaded = false;

  // PATCH 1C: 200ms throttle restored (was changed to 100ms in v4)
  DateTime _lastInferTs = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _kInferThrottleMs = 200;

  // ─── LIFECYCLE ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // PATCH 1A: _pipSubscription / _eventChannel removed

    _warningController = AnimationController(
      duration: const Duration(milliseconds: 1000), vsync: this,
    )..repeat(reverse: true);
    _warningAnimation =
        Tween<double>(begin: 0.8, end: 1.0).animate(_warningController);

    final nc = AnimationController(
        duration: const Duration(milliseconds: 550), vsync: this);
    _notifController = nc;
    _notifSlide = Tween<Offset>(
            begin: const Offset(0, -1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: nc, curve: Curves.elasticOut));
    _notifFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: nc,
            curve: const Interval(0.0, 0.35, curve: Curves.easeIn)));

    _loadPreferencesAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snapshotTimer?.cancel();
    _warningController.dispose();
    _notifController?.dispose();
    _camDisposing = true;
    _cameraController?.dispose();
    _audioPlayer.dispose();
    _alarmPlayer.dispose();
    TfliteService.instance.dispose();
    super.dispose();
  }

  // PATCH 1B: Original stream stop/start lifecycle restored
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final isRecording = ref.read(isRecordingProvider);
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        await _pauseCameraStream();
        if (isRecording) {
          await BantayDriveService.startService(
              state: ref.read(driverStateProvider));
        }
        break;
      case AppLifecycleState.resumed:
        await _resumeCameraStream();
        break;
      default:
        break;
    }
  }

  // PATCH 1B: Stream helpers
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

  Future<void> _resumeCameraStream() async {
    if (_cameraController == null || _camDisposing) return;
    if (!ref.read(isRecordingProvider)) return;
    try {
      if (!_cameraController!.value.isStreamingImages) {
        await _cameraController!.startImageStream(_onCameraFrame);
      }
    } catch (e) {
      debugPrint('[Camera] resumeStream error: $e');
    }
    if (mounted) setState(() {});
  }

  // ─── CAMERA ───────────────────────────────────────────────────────────────

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

      _cameraController = CameraController(
        cam,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();

      if (!mounted || _camDisposing) return;
      setState(() {
        _cameraInitialized = true;
        _cameraError       = null;
      });

      if (_prefAutoStart) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && !_camDisposing) await _startRecording();
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Size _getPreviewSize(bool isLandscape) {
    if (!_cameraInitialized ||
        _cameraController?.value.previewSize == null) {
      return isLandscape ? const Size(640, 480) : const Size(480, 640);
    }
    final ps = _cameraController!.value.previewSize!;
    return isLandscape
        ? Size(ps.width, ps.height)
        : Size(ps.height, ps.width);
  }

  // ─── SESSION ──────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    _currentSessionId      = await DatabaseHelper.instance.insertSession();
    await DatabaseHelper.instance.insertStateCount(_currentSessionId!);
    _sessionStartTime      = DateTime.now();
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
    ref.read(driverStateProvider.notifier).set('neutral');
    _startNotificationWithRetry();

    _addLogSync('System Initialized', 'INFO');
    _addLogSync(
      _modelLoaded ? 'DMS-HybridNet Active (T01+T02)' : 'Demo Mode — No Model',
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

  Future<void> _startNotificationWithRetry() async {
    for (int i = 0; i < 5; i++) {
      if (BantayDriveService.isReady) {
        await BantayDriveService.startService(state: 'neutral');
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    await BantayDriveService.startService(state: 'neutral');
  }

  Future<void> _stopRecording() async {
    if (_currentSessionId == null) return;

    _snapshotTimer?.cancel();
    await _pauseCameraStream();
    await _alarmPlayer.stop();
    _alertLevel            = 0;
    _consecutiveDrowsy     = 0;
    _consecutiveDistracted = 0;

    final durationSec = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;
    final alertness = ref.read(alertnessPctProvider);

    final alerts = await DatabaseHelper.instance
        .getAlertsBySession(_currentSessionId!);
    double penalty = 0.0;
    for (final a in alerts) {
      final level = (a['alert_level'] as int?) ?? 1;
      if (level == 1)      penalty += 2.0;
      else if (level == 2) penalty += 4.0;
      else                 penalty += 8.0;
    }
    final safetyScore = (alertness - penalty).clamp(0.0, 100.0);

    await DatabaseHelper.instance.endSession(
      sessionId:    _currentSessionId!,
      durationSec:  durationSec,
      alertnessAvg: alertness,
      safetyScore:  safetyScore,
    );

    _addLogSync('Session Ended — Score: ${safetyScore.toInt()}%', 'INFO');
    BantayDriveService.stopService();

    ref.read(isRecordingProvider.notifier).set(false);
    ref.read(driverStateProvider.notifier).set('neutral');
    ref.read(showAlertBannerProvider.notifier).set(false);
    ref.read(alertnessPctProvider.notifier).set(100.0);
    ref.read(drowsinessPctProvider.notifier).set(0.0);
    ref.read(distractionPctProvider.notifier).set(0.0);
    ref.read(activeSubclassProvider.notifier).set(null);
    ref.read(activeSubclassIndexProvider.notifier).set(0);
    _currentSessionId = null;
    _sessionStartTime = null;
    ref.read(dbChangeCounterProvider.notifier).increment();
  }

  // ─── CAMERA FRAME ─────────────────────────────────────────────────────────

  // PATCH 1C: Original _onCameraFrame restored — 200ms throttle, null = dropped
  Future<void> _onCameraFrame(CameraImage frame) async {
    if (_camDisposing) return;
    final now = DateTime.now();
    if (now.difference(_lastInferTs).inMilliseconds < _kInferThrottleMs) return;
    _lastInferTs = now;
    if (!mounted || !ref.read(isRecordingProvider)) return;
    final result = await TfliteService.instance.runInference(frame);
    if (result == null) return; // dropped frame — don't reset counters
    if (mounted && ref.read(isRecordingProvider)) onModelOutput(result);
  }

  // ─── MODEL OUTPUT ──────────────────────────────────────────────────────────

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
        _consecutiveDistracted = 0;
        // PATCH 1D: Log now shows [source] subclass — X% format
        _addLogSync(
          '[${modelSourceLabel(r.modelSource)}] '
          '${r.subclass} — ${r.drowsyPct.toInt()}% drowsy',
          'WARNING',
        );
        _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
        BantayDriveService.updateState('drowsy');
        break;

      case 'distracted':
        _consecutiveDistracted++;
        _consecutiveDrowsy = 0;
        // PATCH 1D: Log now shows [source] subclass — X% format
        _addLogSync(
          '[${modelSourceLabel(r.modelSource)}] '
          '${r.subclass} — ${r.distractedPct.toInt()}% distracted',
          'WARNING',
        );
        _checkAndTriggerAlert('DISTRACTED', _consecutiveDistracted);
        BantayDriveService.updateState('distracted');
        break;

      default:
        // Only confirmed NEUTRAL resets the counters
        _consecutiveDrowsy     = 0;
        _consecutiveDistracted = 0;
        if (_alertLevel > 0 && _alertLevel < 3) {
          _alertLevel = 0;
          _alarmPlayer.stop();
        }
        ref.read(activeSubclassProvider.notifier).set('safe_driving');
        ref.read(activeSubclassIndexProvider.notifier).set(0);
        BantayDriveService.updateState('neutral');
    }
  }

  // ─── ALERTS ───────────────────────────────────────────────────────────────

  Future<void> _checkAndTriggerAlert(String type, int consecutive) async {
    final thresholds =
        _sensitivityThresholds[_prefAlertSensitivity] ?? [3, 6, 9];
    if (consecutive < thresholds[0]) return;

    int newLevel = 1;
    if (consecutive >= thresholds[2])      newLevel = 3;
    else if (consecutive >= thresholds[1]) newLevel = 2;

    if (newLevel <= _alertLevel) return;
    _alertLevel = newLevel;

    ref.read(showAlertBannerProvider.notifier).set(true);
    ref.read(alertBannerTypeProvider.notifier).set(type);
    if (newLevel < 3) _notifController?.forward(from: 0.0);

    if (_currentSessionId != null) {
      await DatabaseHelper.instance.insertAlertEvent(
          sessionId:  _currentSessionId!,
          alertType:  type,
          alertLevel: newLevel);
      // PATCH 1F: Alert log now says "consecutive frames"
      _addLogSync(
        'ALERT Level $newLevel — '
        '${type == 'DROWSY' ? 'Drowsiness' : 'Distraction'} '
        '($consecutive consecutive frames)',
        'WARNING',
      );
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
    _alertLevel            = 0;
    _consecutiveDrowsy     = 0;
    _consecutiveDistracted = 0;
    if (mounted) ref.read(showAlertBannerProvider.notifier).set(false);
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────

  void _addLogSync(String message, String type) {
    if (!mounted) return;
    final now = DateTime.now();
    final t = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _systemLogs.add({'time': t, 'message': message, 'type': type});
      if (_systemLogs.length > 100) _systemLogs.removeAt(0);
    });
    if (_currentSessionId != null) {
      DatabaseHelper.instance.insertSystemLog(
          sessionId: _currentSessionId!,
          message:   message,
          logType:   type);
    }
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
    // PATCH 1A: PiP check removed — isInPipProvider is always false stub

    final isDesktop   = MediaQuery.of(context).size.width >= 1024;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);
    final isLevel3  = _alertLevel == 3;

    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Stack(
        children: [
          if (isDesktop)
            SafeArea(child: _buildDesktopLayout())
          else if (isLandscape)
            _buildLandscapeLayout()
          else
            SafeArea(bottom: false, child: _buildPortraitLayout()),

          if (showAlert && !isLevel3)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                  bottom: false,
                  child: _buildAlertBanner(alertType)),
            ),

          if (showAlert && isLevel3)
            Positioned.fill(child: _buildWarningOverlay(alertType)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYOUTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPortraitLayout() => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            const SizedBox(height: 28),
            _buildCameraWithOverlay(
                height:      MediaQuery.of(context).size.height * 0.40,
                isLandscape: false),
            const SizedBox(height: 12),
            _buildMetricsSidebar(isLandscape: false),
            const SizedBox(height: 16),
          ]),
        ),
      );

  Widget _buildLandscapeLayout() =>
      _buildCameraWithOverlay(isLandscape: true, fullscreen: true);

  Widget _buildDesktopLayout() => Column(children: [
        Expanded(child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 8, child: Column(children: [
              Expanded(child: _buildCameraWithOverlay(isLandscape: true)),
              SizedBox(height: Responsive.responsiveSpacing(context,
                  mobile: 16, tablet: 20, desktop: 24)),
              _buildMetricsSidebar(isLandscape: false),
            ])),
            SizedBox(width: Responsive.responsiveSpacing(context,
                mobile: 16, tablet: 24, desktop: 32)),
            Expanded(flex: 4,
                child: _buildMetricsSidebar(isLandscape: false)),
          ],
        )),
      ]);

  // ─── CAMERA WITH OVERLAY ──────────────────────────────────────────────────

  Widget _buildCameraWithOverlay({
    double? height,
    required bool isLandscape,
    bool fullscreen = false,
  }) {
    final isRecording  = ref.watch(isRecordingProvider);
    final clearGlasses = ref.watch(clearGlassesProvider);
    final previewSize  = _getPreviewSize(isLandscape);

    final cameraWidget = ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width:  previewSize.width,
          height: previewSize.height,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
                _mirrorCamera ? -1.0 : 1.0, 1.0, 1.0),
            child: (_cameraInitialized && !_camDisposing)
                ? CameraPreview(key: _cameraKey, _cameraController!)
                : _buildCameraFallback(),
          ),
        ),
      ),
    );

    final inner = ClipRRect(
      borderRadius:
          fullscreen ? BorderRadius.zero : BorderRadius.circular(14),
      child: Stack(fit: StackFit.expand, children: [
        cameraWidget,
        _buildGradientOverlay(),
        if (isRecording) _buildRecBadge(),

        // AI/DEMO badge
        Positioned(top: 12, left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (_modelLoaded
                      ? const Color(0xFF10b981)
                      : const Color(0xFFfbbf24))
                  .withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(_modelLoaded ? 'AI ON' : 'DEMO',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            ]),
          ),
        ),

        // PATCH 1E: T02 warm-up badge removed

        // Bottom control bar
        Positioned(
          bottom: fullscreen ? 20 : 14,
          left: 0, right: 0,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a).withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _CameraOverlayButton(
                      icon:        Icons.visibility,
                      label:       'Clear Glasses',
                      isActive:    clearGlasses,
                      activeColor: const Color(0xFF22d3ee),
                      onTap: () {
                        ref.read(clearGlassesProvider.notifier).toggle();
                        if (!clearGlasses && _currentSessionId != null) {
                          _addLogSync('Clear Glasses Mode Active', 'SUCCESS');
                        }
                      },
                    ),
                    Container(
                      width: 1, height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    _CameraOverlayButton(
                      icon: isRecording
                          ? Icons.stop_circle
                          : Icons.fiber_manual_record,
                      label:       isRecording ? 'Stop' : 'Record',
                      isActive:    isRecording,
                      activeColor: Colors.red,
                      onTap: () => isRecording
                          ? _stopRecording()
                          : _startRecording(),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );

    if (fullscreen) return SizedBox.expand(child: inner);
    return Container(
      height: height, width: double.infinity,
      decoration: const BoxDecoration(
        color:        Color(0xFF0f172a),
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(8, 8), blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-8, -8), blurRadius: 16),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: inner,
    );
  }

  Widget _buildCameraFallback() {
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off, color: Color(0xFF64748b), size: 48),
          const SizedBox(height: 12),
          Text(_cameraError!,
              style: const TextStyle(color: Color(0xFF64748b), fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
              onPressed: _initCamera,
              child: const Text('Retry',
                  style: TextStyle(color: Color(0xFF22d3ee)))),
        ])),
      );
    }
    return const ColoredBox(
      color: Colors.black,
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: Color(0xFF22d3ee)),
        SizedBox(height: 12),
        Text('Initializing camera...',
            style: TextStyle(color: Color(0xFF64748b), fontSize: 13)),
      ])),
    );
  }

  Widget _buildGradientOverlay() => Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end:   Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF0f172a).withValues(alpha: 0.5),
              ],
            ),
          ),
        ),
      );

  Widget _buildRecBadge() => Positioned(
        top: 12, right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color:        Colors.red.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('REC', style: TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
        ),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // ALERT BANNER — L1/L2
  // ═══════════════════════════════════════════════════════════════════════════

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
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: Colors.red.withValues(
                          alpha: 0.25 + 0.35 * pulse),
                      width: 1.2),
                  boxShadow: [
                    BoxShadow(
                        color:      Colors.black.withValues(alpha: 0.55),
                        blurRadius: 28, offset: const Offset(0, 8)),
                    BoxShadow(
                        color:        Colors.red.withValues(
                            alpha: 0.12 + 0.18 * pulse),
                        blurRadius:   20, spreadRadius: 1,
                        offset:       const Offset(0, 2)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(children: [
                        AnimatedBuilder(
                          animation: _warningAnimation,
                          builder: (context, child) {
                            final p = (_warningAnimation.value - 0.8) / 0.2;
                            return Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color:        Colors.red.shade800,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(
                                    color: Colors.red.withValues(
                                        alpha: 0.3 + 0.4 * p),
                                    blurRadius: 14, spreadRadius: 1)],
                              ),
                              child: const Icon(Icons.warning_amber_rounded,
                                  color: Colors.white, size: 24),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize:       MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('BANTAY DRIVE', style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize:      10,
                                    fontWeight:    FontWeight.w600,
                                    letterSpacing: 0.8)),
                                Text('now', style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isDrowsy
                                  ? 'Drowsiness Detected'
                                  : 'Distraction Detected',
                              style: const TextStyle(
                                  color:         Colors.white,
                                  fontSize:      15,
                                  fontWeight:    FontWeight.w700,
                                  letterSpacing: 0.2),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDrowsy
                                  ? 'Stay alert — tap to dismiss'
                                  : 'Focus on the road — tap to dismiss',
                              style: TextStyle(
                                  color:    Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12),
                            ),
                          ],
                        )),
                        const SizedBox(width: 8),
                        Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 14),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // WARNING OVERLAY — L3
  // ═══════════════════════════════════════════════════════════════════════════

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
                child: Container(
                    color: Colors.red.withValues(alpha: 0.15)),
              ),
              Container(decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3 + 0.5 * p),
                    width: 5),
                gradient: RadialGradient(
                  center: Alignment.center, radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.red.withValues(alpha: 0.06 + 0.10 * p),
                  ],
                ),
              )),
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    color:  Colors.red.shade900.withValues(alpha: 0.85),
                    shape:  BoxShape.circle,
                    border: Border.all(
                        color: Colors.red.shade400.withValues(alpha: 0.6),
                        width: 2),
                    boxShadow: [BoxShadow(
                        color: Colors.red.withValues(alpha: 0.2 + 0.2 * p),
                        blurRadius: 30, spreadRadius: 4)],
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      size: 48, color: Colors.red.shade300),
                ),
                const SizedBox(height: 20),
                Text(isDrowsy ? 'DROWSINESS' : 'DISTRACTION',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                        color: Colors.red.shade300, letterSpacing: 4)),
                Text('DETECTED', style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade400.withValues(alpha: 0.8),
                    letterSpacing: 6)),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.touch_app_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 8),
                    Text('Tap anywhere to dismiss', style: TextStyle(
                        fontSize:      13,
                        color:         Colors.white.withValues(alpha: 0.6),
                        fontWeight:    FontWeight.w500,
                        letterSpacing: 0.3)),
                  ]),
                ),
              ])),
              Positioned(top: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.shade800.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(
                        color:      Colors.red.withValues(alpha: 0.4 * pulse),
                        blurRadius: 10)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7,
                        decoration: BoxDecoration(
                            color: Colors.red.shade200,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('ALARM ACTIVE', style: TextStyle(
                        color:         Colors.red.shade100,
                        fontSize:      10,
                        fontWeight:    FontWeight.bold,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // METRICS + SYSTEM LOG
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetricsSidebar({required bool isLandscape}) {
    final alertness   = ref.watch(alertnessPctProvider);
    final drowsiness  = ref.watch(drowsinessPctProvider);
    final distraction = ref.watch(distractionPctProvider);

    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _MetricGauge(
            label: 'Alertness', value: alertness,
            color: const Color(0xFF22d3ee), icon: Icons.bolt)),
        const SizedBox(width: 12),
        Expanded(child: GestureDetector(
          onTap: drowsiness > 0 ? () => _showSubclassSheet('drowsy') : null,
          child: _MetricGauge(
              label: 'Drowsiness', value: drowsiness,
              color: const Color(0xFFef4444),
              icon: Icons.visibility_off, tapHint: drowsiness > 0),
        )),
        const SizedBox(width: 12),
        Expanded(child: GestureDetector(
          onTap: distraction > 0
              ? () => _showSubclassSheet('distracted') : null,
          child: _MetricGauge(
              label: 'Distraction', value: distraction,
              color: const Color(0xFFfbbf24),
              icon: Icons.visibility, tapHint: distraction > 0),
        )),
      ]),
      const SizedBox(height: 16),
      _buildSystemLog(),
    ]);
  }

  void _showSubclassSheet(String mainClass) {
    final subclass  = ref.read(activeSubclassProvider) ?? 'safe_driving';
    final isDrowsy  = mainClass == 'drowsy';
    final mainColor = isDrowsy
        ? const Color(0xFFef4444) : const Color(0xFFfbbf24);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color:        Color(0xFF0D1627),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color:        const Color(0xFF1E2D45),
                borderRadius: BorderRadius.circular(2)),
          )),
          Text(isDrowsy ? 'Drowsiness Detected' : 'Distraction Detected',
              style: const TextStyle(color: Colors.white,
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Current: $subclass',
              style: TextStyle(color: mainColor, fontSize: 13)),
          const SizedBox(height: 16),
          Text(
            isDrowsy
                ? 'Drowsy: Yawning, Head Droop, Eyes Closed (PERCLOS)'
                : 'Distracted: Texting, Phone Call, Radio, Drinking,\n'
                  'Reaching Behind, Hair/Makeup, Talking to Passenger',
            style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  Widget _buildSystemLog() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color:        const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0b1120).withValues(alpha: 0.5),
              offset: const Offset(4, 4), blurRadius: 8),
          BoxShadow(color: const Color(0xFF1e293b).withValues(alpha: 0.5),
              offset: const Offset(-4, -4), blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize:        MainAxisSize.min,
        children: [
          Row(children: [
            const Text('SYSTEM LOG', style: TextStyle(
                color:         Color(0xFF94a3b8),
                fontSize:      11,
                fontWeight:    FontWeight.w600,
                letterSpacing: 1.5)),
            const Spacer(),
            if (ref.watch(isRecordingProvider))
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '● LIVE',
                  style: TextStyle(
                    color: Color(0xFF10b981),
                    fontSize: 9, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          if (_systemLogs.isEmpty)
            const Align(
              alignment: Alignment.topCenter,
              child: Text('No logs yet. Start recording to begin.',
                  style:     TextStyle(color: Colors.white24, fontSize: 12),
                  textAlign: TextAlign.center),
            )
          else
            SizedBox(
              height: 120,
              child: ListView.builder(
                physics:   const BouncingScrollPhysics(),
                itemCount: _systemLogs.length > 20 ? 20 : _systemLogs.length,
                itemBuilder: (context, index) {
                  final log = _systemLogs.reversed.toList()[index];
                  Color textColor;
                  switch (log['type']) {
                    case 'SUCCESS':
                      textColor = const Color(0xFF10b981); break;
                    case 'WARNING':
                      textColor = const Color(0xFFfbbf24); break;
                    default:
                      textColor = const Color(0xFF94a3b8);
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('[${log['time']}]',
                            style: const TextStyle(
                                color:      Color(0xFF475569),
                                fontSize:   10,
                                fontFamily: 'monospace')),
                        const SizedBox(width: 8),
                        Expanded(child: Text(log['message'],
                            style: TextStyle(
                                color:      textColor,
                                fontSize:   10,
                                fontFamily: 'monospace'))),
                      ],
                    ),
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
  final String   label;
  final double   value;
  final Color    color;
  final IconData icon;
  final bool     tapHint;

  const _MetricGauge({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.tapHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 100.0);
    // Fixed gauge size so all three boxes are identical regardless of label length
    const double gaugeD = 72.0;
    const double fSize  = 22.0;
    const double pSize  = 11.0;

    return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0f172a),
          borderRadius: BorderRadius.circular(16),
          boxShadow: clamped >= 100.0
              ? [
                  BoxShadow(color: color.withValues(alpha: 0.30),
                      blurRadius: 16, spreadRadius: 2),
                  const BoxShadow(color: Color(0xFF0b1120),
                      offset: Offset(4, 4), blurRadius: 8),
                ]
              : const [
                  BoxShadow(color: Color(0xFF0b1120),
                      offset: Offset(6, 6), blurRadius: 12),
                  BoxShadow(color: Color(0xFF1e293b),
                      offset: Offset(-6, -6), blurRadius: 12),
                ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Flexible(child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF94a3b8), fontSize: 10,
                    fontWeight: FontWeight.w500))),
            if (tapHint) ...[
              const SizedBox(width: 3),
              Icon(Icons.touch_app_rounded,
                  size: 9, color: color.withValues(alpha: 0.6)),
            ],
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: gaugeD, height: gaugeD,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(width: gaugeD, height: gaugeD,
                child: CircularProgressIndicator(
                  value:           1.0,
                  strokeWidth:     4,
                  backgroundColor: Colors.transparent,
                  valueColor:      AlwaysStoppedAnimation<Color>(
                      color.withValues(alpha: 0.18)),
                  strokeCap: StrokeCap.round,
                ),
              ),
              TweenAnimationBuilder<double>(
                tween:    Tween<double>(begin: 0, end: clamped),
                duration: const Duration(milliseconds: 600),
                curve:    Curves.easeOut,
                builder: (_, v, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${v.toInt()}', style: TextStyle(
                        color:      color, fontSize: fSize,
                        fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    Text('%', style: TextStyle(
                        color:      color.withValues(alpha: 0.7),
                        fontSize:   pSize, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ]),
          ),
        ]),
      );
  }
}

// ─── CAMERA OVERLAY BUTTON ────────────────────────────────────────────────────

class _CameraOverlayButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final bool         isActive;
  final Color        activeColor;
  final VoidCallback onTap;

  const _CameraOverlayButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18,
              color: isActive ? activeColor : Colors.white60),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color:      isActive ? activeColor : Colors.white60,
              fontSize:   12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}