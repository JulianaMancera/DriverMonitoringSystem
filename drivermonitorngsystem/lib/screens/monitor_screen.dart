import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/database/database_helper.dart';
import '../core/database/db_change_notifier.dart';
import '../core/inference/tflite_service.dart';
import '../core/services/notifications.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../utils/responsive.dart';
import '../main.dart' show landscapeFullscreenProvider, sidebarOpenProvider;

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

  int?      _currentSessionId;
  DateTime? _sessionStartTime;
  Timer?    _snapshotTimer;

  int _consecutiveDrowsy     = 0;
  int _consecutiveDistracted = 0;
  int _alertLevel            = 0;

  final List<Map<String, dynamic>> _systemLogs = [];

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
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    WidgetsBinding.instance.removeObserver(this);
    _snapshotTimer?.cancel();
    _warningController.dispose();
    _notifController?.dispose();
    _camDisposing = true;
    _cameraController?.dispose();
    _audioPlayer.dispose();
    _alarmPlayer.dispose();
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    if (data is String && data == 'stop_recording') {
      if (mounted && ref.read(isRecordingProvider)) {
        _stopRecording();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        await _pauseCameraStream();
        break;
      case AppLifecycleState.resumed:
        await _resumeCameraStream();
        break;
      default:
        break;
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
    // Must grant camera permission before foreground service can use type=camera
    if (Platform.isAndroid) {
      await Permission.camera.request();
    }

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

      _cameraController = CameraController(cam, ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420);
      await _cameraController!.initialize();

      if (!mounted || _camDisposing) return;
      setState(() { _cameraInitialized = true; _cameraError = null; });

      if (_prefAutoStart) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && !_camDisposing) await _startRecording();
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
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

  Future<void> _startNotificationWithRetry() async {
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
        ? DateTime.now().difference(_sessionStartTime!).inSeconds : 0;
    final alertness = ref.read(alertnessPctProvider);

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
          '${r.subclass} — ${r.drowsyPct.toInt()}% drowsy',
          'WARNING',
        );
        _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
        BantayDriveService.updateState('drowsy');
        break;
      case 'distracted':
        _consecutiveDistracted++;
        _consecutiveDrowsy = (_consecutiveDrowsy - 1).clamp(0, 999);
        _addLogSync(
          '[${modelSourceLabel(r.modelSource)}] '
          '${r.subclass} — ${r.distractedPct.toInt()}% distracted',
          'WARNING',
        );
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
          sessionId:  _currentSessionId!,
          alertType:  type,
          alertLevel: newLevel);
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
    _alertLevel = _consecutiveDrowsy = _consecutiveDistracted = 0;
    if (mounted) ref.read(showAlertBannerProvider.notifier).set(false);
  }

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
    final isDesktop   = MediaQuery.of(context).size.width >= 1024;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);
    final isLevel3  = _alertLevel == 3;

    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: Stack(children: [
        if (isDesktop)
          SafeArea(child: _buildDesktopLayout())
        else if (isLandscape)
          _buildLandscapeLayout()
        else
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

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYOUTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPortraitLayout() => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.rp(14)),
          child: Column(children: [
            SizedBox(height: context.rs(20)),
            _buildCameraWithOverlay(
                height: MediaQuery.of(context).size.height *
                    (context.isSmallPhone ? 0.36 : 0.40),
                isLandscape: false),
            SizedBox(height: context.rs(10)),
            _buildMetricsSidebar(isLandscape: false),
            SizedBox(height: context.rs(14)),
          ]),
        ),
      );

  Widget _buildLandscapeLayout() {
    final lsFullscreen = ref.watch(landscapeFullscreenProvider);

    if (lsFullscreen) {
      return GestureDetector(
        onTap: () {
          ref.read(landscapeFullscreenProvider.notifier).set(false);
          ref.read(sidebarOpenProvider.notifier).set(false);
        },
        behavior: HitTestBehavior.translucent,
        child: _buildCameraWithOverlay(isLandscape: true, fullscreen: true),
      );
    }

    return GestureDetector(
      onTap: () {
        ref.read(landscapeFullscreenProvider.notifier).set(true);
        ref.read(sidebarOpenProvider.notifier).set(false);
      },
      behavior: HitTestBehavior.translucent,
      child: _buildCameraWithOverlay(isLandscape: true, fullscreen: false),
    );
  }

  Widget _buildDesktopLayout() => Column(children: [
        Expanded(child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 8, child: Column(children: [
              Expanded(child: _buildCameraWithOverlay(isLandscape: true)),
              SizedBox(height: context.rs(16)),
              _buildMetricsSidebar(isLandscape: false),
            ])),
            SizedBox(width: context.rp(24)),
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
    double camAspect;
    if (_cameraInitialized && _cameraController != null &&
        _cameraController!.value.previewSize != null) {
      final ps = _cameraController!.value.previewSize!;
      final sensorAspect = ps.width / ps.height;
      camAspect = isLandscape ? sensorAspect : (1.0 / sensorAspect);
    } else {
      camAspect = isLandscape ? 4.0 / 3.0 : 3.0 / 4.0;
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
            maxWidth:  camW,
            maxHeight: camH,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(
                  _mirrorCamera ? -1.0 : 1.0, 1.0, 1.0),
              child: SizedBox(
                width: camW, height: camH,
                child: (_cameraInitialized && !_camDisposing)
                    ? CameraPreview(key: _cameraKey, _cameraController!)
                    : _buildCameraFallback(),
              ),
            ),
          ),
        );
      },
    );

    final inner = ClipRRect(
      borderRadius: fullscreen
          ? BorderRadius.zero
          : BorderRadius.circular(context.rp(14)),
      child: Stack(fit: StackFit.expand, children: [
        cameraWidget,
        _buildGradientOverlay(),

        SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isRecording) _buildRecBadge(isLandscape: isLandscape, fullscreen: fullscreen),

              Positioned(
                top: (!fullscreen && isLandscape)
                    ? context.rs(5)
                    : (isLandscape ? context.rs(46) : context.rs(10)),
                left: isLandscape ? context.rp(24) : context.rp(10),
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
                            color:      Colors.white,
                            fontSize:   context.sp(9),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8)),
                  ]),
                ),
              ),

              if (fullscreen)
                Positioned(
                  bottom: context.rs(64),
                  right: context.rp(16),
                  child: Consumer(
                    builder: (ctx, ref2, _) {
                      final isFullNow = ref2.watch(landscapeFullscreenProvider);
                      return AnimatedOpacity(
                        opacity: isFullNow ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 350),
                        child: IgnorePointer(
                          ignoring: !isFullNow,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: context.rp(10), vertical: context.rs(5)),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(context.rp(20)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.touch_app_rounded,
                                  size: context.ri(12),
                                  color: Colors.white.withValues(alpha: 0.55)),
                              SizedBox(width: context.rp(4)),
                              Text('Tap to show controls',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: context.sp(10))),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              Positioned(
                bottom: fullscreen ? context.rs(16) : context.rs(12),
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
                            width: 1, height: context.rs(24),
                            margin: EdgeInsets.symmetric(horizontal: context.rp(5)),
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
            ],
          ),
        ),
      ]),
    );

    if (fullscreen) return SizedBox.expand(child: inner);
    return Container(
      height: height, width: double.infinity,
      decoration: BoxDecoration(
        color:        const Color(0xFF0f172a),
        borderRadius: BorderRadius.all(Radius.circular(context.rp(18))),
        boxShadow: const [
          BoxShadow(color: Color(0xFF0b1120),
              offset: Offset(8, 8), blurRadius: 16),
          BoxShadow(color: Color(0xFF1e293b),
              offset: Offset(-8, -8), blurRadius: 16),
        ],
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
              style: TextStyle(
                  color:    const Color(0xFF64748b),
                  fontSize: context.sp(12)),
              textAlign: TextAlign.center),
          SizedBox(height: context.rs(12)),
          TextButton(
              onPressed: _initCamera,
              child: Text('Retry',
                  style: TextStyle(
                      color:    const Color(0xFF22d3ee),
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
            style: TextStyle(
                color:    const Color(0xFF64748b),
                fontSize: context.sp(12))),
      ])),
    );
  }

  Widget _buildGradientOverlay() => Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF0f172a).withValues(alpha: 0.5),
              ],
            ),
          ),
        ),
      );

  Widget _buildRecBadge({required bool isLandscape, required bool fullscreen}) => Positioned(
        top: (!fullscreen && isLandscape)
            ? context.rs(5)
            : (isLandscape ? context.rs(46) : context.rs(10)),
        right: isLandscape ? context.rp(24) : context.rp(10),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.rp(9), vertical: context.rs(4)),
          decoration: BoxDecoration(
              color:        Colors.red.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(context.rp(16))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: context.ri(7), height: context.ri(7),
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle)),
            SizedBox(width: context.rp(5)),
            Text('REC', style: TextStyle(
                color:      Colors.white,
                fontSize:   context.sp(10),
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
                margin: EdgeInsets.fromLTRB(
                    context.rp(10), context.rs(8),
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
                        color:      Colors.red.withValues(
                            alpha: 0.12 + 0.18 * pulse),
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
                          horizontal: context.rp(12),
                          vertical:   context.rs(10)),
                      child: Row(children: [
                        AnimatedBuilder(
                          animation: _warningAnimation,
                          builder: (context, child) {
                            final p = (_warningAnimation.value - 0.8) / 0.2;
                            return Container(
                              width:  context.ri(40),
                              height: context.ri(40),
                              decoration: BoxDecoration(
                                color: Colors.red.shade800,
                                borderRadius:
                                    BorderRadius.circular(context.rp(10)),
                                boxShadow: [BoxShadow(
                                    color: Colors.red.withValues(
                                        alpha: 0.3 + 0.4 * p),
                                    blurRadius: 14, spreadRadius: 1)],
                              ),
                              child: Icon(Icons.warning_amber_rounded,
                                  color: Colors.white,
                                  size: context.ri(22)),
                            );
                          },
                        ),
                        SizedBox(width: context.rp(10)),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize:       MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('BANTAY DRIVE', style: TextStyle(
                                    color:      Colors.white
                                        .withValues(alpha: 0.45),
                                    fontSize:   context.sp(10),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8)),
                                Text('now', style: TextStyle(
                                    color:    Colors.white
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
                                  color:         Colors.white,
                                  fontSize:      context.sp(14),
                                  fontWeight:    FontWeight.w700,
                                  letterSpacing: 0.2),
                            ),
                            SizedBox(height: context.rs(2)),
                            Text(
                              isDrowsy
                                  ? 'Stay alert — tap to dismiss'
                                  : 'Focus on the road — tap to dismiss',
                              style: TextStyle(
                                  color:    Colors.white.withValues(alpha: 0.5),
                                  fontSize: context.sp(11)),
                            ),
                          ],
                        )),
                        SizedBox(width: context.rp(6)),
                        Container(
                          width:  context.ri(20), height: context.ri(20),
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
                child: Container(color: Colors.red.withValues(alpha: 0.15)),
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
                  width:  context.ri(80), height: context.ri(80),
                  decoration: BoxDecoration(
                    color:  Colors.red.shade900.withValues(alpha: 0.85),
                    shape:  BoxShape.circle,
                    border: Border.all(
                        color: Colors.red.shade400.withValues(alpha: 0.6),
                        width: 2),
                    boxShadow: [BoxShadow(
                        color:      Colors.red.withValues(alpha: 0.2 + 0.2 * p),
                        blurRadius: 30, spreadRadius: 4)],
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      size: context.ri(42),
                      color: Colors.red.shade300),
                ),
                SizedBox(height: context.rs(18)),
                Text(isDrowsy ? 'DROWSINESS' : 'DISTRACTION',
                    style: TextStyle(
                        fontSize:   context.sp(24),
                        fontWeight: FontWeight.w900,
                        color:      Colors.red.shade300,
                        letterSpacing: 4)),
                Text('DETECTED', style: TextStyle(
                    fontSize:   context.sp(16),
                    fontWeight: FontWeight.w700,
                    color:      Colors.red.shade400.withValues(alpha: 0.8),
                    letterSpacing: 6)),
                SizedBox(height: context.rs(24)),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.rp(20), vertical: context.rs(10)),
                  decoration: BoxDecoration(
                    color:        Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(context.rp(24)),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.touch_app_rounded,
                        size:  context.ri(15),
                        color: Colors.white.withValues(alpha: 0.6)),
                    SizedBox(width: context.rp(7)),
                    Text('Tap anywhere to dismiss', style: TextStyle(
                        fontSize:      context.sp(12),
                        color:         Colors.white.withValues(alpha: 0.6),
                        fontWeight:    FontWeight.w500,
                        letterSpacing: 0.3)),
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
                        color:      Colors.red.withValues(alpha: 0.4 * pulse),
                        blurRadius: 10)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: context.ri(6), height: context.ri(6),
                      decoration: BoxDecoration(
                          color: Colors.red.shade200, shape: BoxShape.circle)),
                    SizedBox(width: context.rp(5)),
                    Text('ALARM ACTIVE', style: TextStyle(
                        color:         Colors.red.shade100,
                        fontSize:      context.sp(9),
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
        SizedBox(width: context.rp(10)),
        Expanded(child: GestureDetector(
          onTap: drowsiness > 0 ? () => _showSubclassSheet('drowsy') : null,
          child: _MetricGauge(
              label: 'Drowsiness', value: drowsiness,
              color: const Color(0xFFef4444),
              icon: Icons.visibility_off, tapHint: drowsiness > 0),
        )),
        SizedBox(width: context.rp(10)),
        Expanded(child: GestureDetector(
          onTap: distraction > 0
              ? () => _showSubclassSheet('distracted') : null,
          child: _MetricGauge(
              label: 'Distraction', value: distraction,
              color: const Color(0xFFfbbf24),
              icon: Icons.visibility, tapHint: distraction > 0),
        )),
      ]),
      if (!isLandscape) ...[
        SizedBox(height: context.rs(12)),
        _buildSystemLog(),
      ],
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
        padding: EdgeInsets.fromLTRB(
            context.rp(20), context.rs(12),
            context.rp(20), context.rs(28)),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1627),
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(context.rp(22))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
            width: context.rp(36), height: context.rs(4),
            margin: EdgeInsets.only(bottom: context.rs(14)),
            decoration: BoxDecoration(
                color:        const Color(0xFF1E2D45),
                borderRadius: BorderRadius.circular(context.rp(2))),
          )),
          Text(isDrowsy ? 'Drowsiness Detected' : 'Distraction Detected',
              style: TextStyle(color: Colors.white,
                  fontSize: context.sp(16), fontWeight: FontWeight.w700)),
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
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0b1120).withValues(alpha: 0.5),
              offset: const Offset(4, 4), blurRadius: 8),
          BoxShadow(color: const Color(0xFF1e293b).withValues(alpha: 0.5),
              offset: const Offset(-4, -4), blurRadius: 8),
        ],
      ),
      padding: EdgeInsets.all(context.rp(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize:        MainAxisSize.min,
        children: [
          Row(children: [
            Text('SYSTEM LOG', style: TextStyle(
                color:         const Color(0xFF94a3b8),
                fontSize:      context.sp(10),
                fontWeight:    FontWeight.w600,
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
                child: Text('● LIVE', style: TextStyle(
                    color:      const Color(0xFF10b981),
                    fontSize:   context.sp(9),
                    fontWeight: FontWeight.w600)),
              ),
          ]),
          SizedBox(height: context.rs(8)),
          if (_systemLogs.isEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Text('No logs yet. Start recording to begin.',
                  style: TextStyle(
                      color:    Colors.white24,
                      fontSize: context.sp(11)),
                  textAlign: TextAlign.center),
            )
          else
            SizedBox(
              height: context.rs(context.isSmallPhone ? 90 : 115),
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
                    padding: EdgeInsets.only(bottom: context.rs(5)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('[${log['time']}]',
                            style: TextStyle(
                                color:    const Color(0xFF475569),
                                fontSize: context.sp(9),
                                fontFamily: 'monospace')),
                        SizedBox(width: context.rp(6)),
                        Expanded(child: Text(log['message'],
                            style: TextStyle(
                                color:      textColor,
                                fontSize:   context.sp(9),
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
    required this.label, required this.value,
    required this.color, required this.icon,
    this.tapHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 100.0);
    final gaugeD = context.ri(context.isSmallPhone ? 60.0 : 68.0);
    final fSize  = context.sp(context.isSmallPhone ? 18.0 : 20.0);
    final pSize  = context.sp(9.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(context.rp(14)),
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
      padding: EdgeInsets.symmetric(
          vertical: context.rs(10), horizontal: context.rp(5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: context.ri(11), color: color),
          SizedBox(width: context.rp(3)),
          Flexible(child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color:      const Color(0xFF94a3b8),
                  fontSize:   context.sp(9),
                  fontWeight: FontWeight.w500))),
          if (tapHint) ...[
            SizedBox(width: context.rp(3)),
            Icon(Icons.touch_app_rounded,
                size: context.ri(9), color: color.withValues(alpha: 0.6)),
          ],
        ]),
        SizedBox(height: context.rs(8)),
        SizedBox(
          width: gaugeD, height: gaugeD,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: gaugeD, height: gaugeD,
              child: CircularProgressIndicator(
                value:           1.0,
                strokeWidth:     context.isSmallPhone ? 3.0 : 4.0,
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
                      color:      color,
                      fontSize:   fSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace')),
                  Text('%', style: TextStyle(
                      color:      color.withValues(alpha: 0.7),
                      fontSize:   pSize,
                      fontWeight: FontWeight.w500)),
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
    required this.icon, required this.label,
    required this.isActive, required this.activeColor,
    required this.onTap,
  });

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
          Icon(icon, size: context.ri(16),
              color: isActive ? activeColor : Colors.white60),
          SizedBox(width: context.rp(5)),
          Text(label, style: TextStyle(
              color:      isActive ? activeColor : Colors.white60,
              fontSize:   context.sp(11),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}