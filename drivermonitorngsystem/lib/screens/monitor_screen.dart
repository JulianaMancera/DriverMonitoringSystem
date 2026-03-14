import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gal/gal.dart';
import '../core/database/database_helper.dart';
import 'package:bantaydrive/core/preference/preference_helper.dart';
import '../utils/responsive.dart';

// RIVERPOD PROVIDERS
final driverStateProvider       = StateProvider<String>((ref) => 'neutral');
final alertnessPctProvider      = StateProvider<double>((ref) => 100.0);
final drowsinessPctProvider     = StateProvider<double>((ref) => 0.0);
final distractionPctProvider    = StateProvider<double>((ref) => 0.0);
final isRecordingProvider       = StateProvider<bool>((ref) => false);
final showAlertBannerProvider   = StateProvider<bool>((ref) => false);
final alertBannerTypeProvider   = StateProvider<String>((ref) => 'DROWSY');
final clearGlassesProvider      = StateProvider<bool>((ref) => false);

// MONITOR SCREEN
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen>
    with TickerProviderStateMixin {

  // CAMERA 
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraInitialized = false;
  String? _cameraError;

  // SESSION 
  int? _currentSessionId;
  DateTime? _sessionStartTime;
  Timer? _snapshotTimer;
  Timer? _alertBannerTimer;

  // ALERT TRACKING 
  int _consecutiveDrowsy     = 0;
  int _consecutiveDistracted = 0;
  int _alertLevel            = 0;

  // SYSTEM LOGS 
  final List<Map<String, dynamic>> _systemLogs = [];

  // AUDIO
  final AudioPlayer _audioPlayer  = AudioPlayer();
  final AudioPlayer _alarmPlayer  = AudioPlayer();

  // ANIMATIONS 
  late AnimationController _warningController;
  late Animation<double>   _warningAnimation;

  // PREFERENCES (loaded on init)
  // These mirror the values saved in SharedPreferences via PreferencesHelper.
  // They are loaded once in initState and re-read when the screen resumes.
  int    _prefAlertSensitivity= 1;    // 0=Low, 1=Medium, 2=High
  bool   _prefAutoStart       = false;

  // SENSITIVITY THRESHOLDS 
  // Maps sensitivity setting → [level1, level2, level3] consecutive counts
  // Low    → harder to trigger (needs more consecutive detections)
  // Medium → default
  // High   → easier to trigger (fewer consecutive detections needed)
  static const Map<int, List<int>> _sensitivityThresholds = {
    0: [5, 10, 15], // Low
    1: [3,  6,  9], // Medium (default)
    2: [2,  4,  6], // High
  };

  // LIFECYCLE
  @override
  void initState() {
    super.initState();

    _warningController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _warningAnimation =
        Tween<double>(begin: 0.8, end: 1.0).animate(_warningController);

    // Load preferences FIRST, then init camera
    // so auto-start and camera position are ready before camera fires up
    _loadPreferencesAndInit();
  }

  @override
  void dispose() {
    _snapshotTimer?.cancel();
    _alertBannerTimer?.cancel();
    _warningController.dispose();
    _cameraController?.dispose();
    _audioPlayer.dispose();
    _alarmPlayer.dispose();
    super.dispose();
  }

  // PREFERENCES
  /// Load all relevant preferences then initialize camera.
  /// Called once on initState.
  Future<void> _loadPreferencesAndInit() async {
    final prefs = PreferencesHelper.instance;

    // Sound and volume are read fresh on every alert trigger
    // so they don't need to be cached here
    _prefAlertSensitivity = await prefs.getAlertSensitivity();
    _prefAutoStart        = await prefs.getAutoStart();

    // Now initialize camera
    await _initCamera();
  }

  /// Re-read preferences — call this if you need to refresh mid-session.
  /// Useful if user changes settings and navigates back to monitor.
  Future<void> _refreshPreferences() async {
    final prefs = PreferencesHelper.instance;
    // Sound and volume read fresh on each alert — only sensitivity and
    // auto-start need to be cached
    _prefAlertSensitivity = await prefs.getAlertSensitivity();
    _prefAutoStart        = await prefs.getAutoStart();
  }

  // CAMERA
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'No cameras found');
        return;
      }

      // Always use front-facing (selfie) camera
      final selectedCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _cameraInitialized = true);

        // AUTO-START — triggers recording automatically if enabled in Settings
        if (_prefAutoStart) {
          await Future.delayed(const Duration(milliseconds: 500));
          await _startRecording();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Size _getPreviewSize(bool isLandscape) {
    if (!_cameraInitialized) {
      return isLandscape ? const Size(1920, 1080) : const Size(1080, 1920);
    }
    final ps = _cameraController!.value.previewSize!;
    if (isLandscape) return Size(ps.width, ps.height);
    return Size(ps.height, ps.width);
  }

  // SESSION CONTROL
  Future<void> _startRecording() async {
    _currentSessionId = await DatabaseHelper.instance.insertSession();
    await DatabaseHelper.instance.insertStateCount(_currentSessionId!);
    _sessionStartTime = DateTime.now();

    if (_cameraInitialized) {
      await _cameraController!.startVideoRecording();
    }

    ref.read(isRecordingProvider.notifier).state      = true;
    ref.read(driverStateProvider.notifier).state      = 'neutral';

    await _addLog('System Initialized', 'INFO');
    await Future.delayed(const Duration(milliseconds: 500));
    await _addLog('Face Tracking Active', 'SUCCESS');
    await Future.delayed(const Duration(milliseconds: 400));
    await _addLog('Baseline Established', 'INFO');

    _snapshotTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveAlertnessSnapshot();
    });

    if (ref.read(clearGlassesProvider)) {
      await Future.delayed(const Duration(milliseconds: 300));
      await _addLog('Clear Glasses Detected', 'INFO');
    }
  }

  Future<void> _stopRecording() async {
    if (_currentSessionId == null) return;

    _snapshotTimer?.cancel();
    await _alarmPlayer.stop();
    _alertLevel            = 0;
    _consecutiveDrowsy     = 0;
    _consecutiveDistracted = 0;

    // Stop video recording and save to gallery
    if (_cameraInitialized && _cameraController!.value.isRecordingVideo) {
      try {
        final XFile videoFile =
            await _cameraController!.stopVideoRecording();
        await Gal.putVideo(videoFile.path, album: 'Bantay Drive');
        await _addLog('Video saved to gallery', 'SUCCESS');
      } catch (e) {
        await _addLog('Failed to save video: $e', 'WARNING');
      }
    }

    final durationSec = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;

    final alertness = ref.read(alertnessPctProvider);

    await DatabaseHelper.instance.endSession(
      sessionId: _currentSessionId!,
      durationSec: durationSec,
      alertnessAvg: alertness,
      safetyScore: alertness.clamp(0.0, 100.0),
    );

    await _addLog('Session Ended', 'INFO');

    ref.read(isRecordingProvider.notifier).state      = false;
    ref.read(driverStateProvider.notifier).state      = 'neutral';
    ref.read(showAlertBannerProvider.notifier).state  = false;
    ref.read(alertnessPctProvider.notifier).state     = 100.0;
    ref.read(drowsinessPctProvider.notifier).state    = 0.0;
    ref.read(distractionPctProvider.notifier).state   = 0.0;

    _currentSessionId = null;
    _sessionStartTime = null;
  }

  // MODEL OUTPUT
  // Plug TFLite inference results here. Not activated yet.
  void onModelOutput({
    required String state,
    required double alertnessPct,
    required double drowsinessPct,
    required double distractionPct,
  }) {
    if (!ref.read(isRecordingProvider)) return;

    ref.read(alertnessPctProvider.notifier).state    = alertnessPct;
    ref.read(drowsinessPctProvider.notifier).state   = drowsinessPct;
    ref.read(distractionPctProvider.notifier).state  = distractionPct;
    ref.read(driverStateProvider.notifier).state     = state;

    if (_currentSessionId != null) {
      DatabaseHelper.instance.incrementStateCount(
        sessionId: _currentSessionId!,
        state: state,
      );
    }

    if (state == 'drowsy') {
      _consecutiveDrowsy++;
      _consecutiveDistracted = 0;
      _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
    } else if (state == 'distracted') {
      _consecutiveDistracted++;
      _consecutiveDrowsy = 0;
      _checkAndTriggerAlert('DISTRACTED', _consecutiveDistracted);
    } else {
      // Back to neutral — reset all counters and stop alarm
      _consecutiveDrowsy     = 0;
      _consecutiveDistracted = 0;
      _alertLevel            = 0;
      ref.read(showAlertBannerProvider.notifier).state = false;
      _alarmPlayer.stop();
    }
  }

  // 3-LEVEL ALERT SYSTEM
  // Thresholds are driven by Alert Sensitivity preference:
  //   Low    → [5, 10, 15]
  //   Medium → [3,  6,  9]  (default)
  //   High   → [2,  4,  6]
  Future<void> _checkAndTriggerAlert(
      String type, int consecutive) async {
    // Get thresholds based on current sensitivity preference
    final thresholds =
        _sensitivityThresholds[_prefAlertSensitivity] ?? [3, 6, 9];
    final t1 = thresholds[0]; // Level 1 threshold
    final t2 = thresholds[1]; // Level 2 threshold
    final t3 = thresholds[2]; // Level 3 threshold

    // Not enough consecutive detections yet
    if (consecutive < t1) return;

    // Determine new alert level
    int newLevel = 1;
    if (consecutive >= t3)      newLevel = 3;
    else if (consecutive >= t2) newLevel = 2;

    // Don't re-trigger level 3 if already at level 3
    if (newLevel <= _alertLevel && _alertLevel == 3) return;
    _alertLevel = newLevel;

    ref.read(showAlertBannerProvider.notifier).state = true;
    ref.read(alertBannerTypeProvider.notifier).state = type;

    // Save alert to DB
    if (_currentSessionId != null) {
      await DatabaseHelper.instance.insertAlertEvent(
        sessionId: _currentSessionId!,
        alertType: type,
        alertLevel: newLevel,
      );
      final msg =
          type == 'DROWSY' ? 'Microsleep detected' : 'Distraction detected';
      await _addLog(msg, 'WARNING');
    }

    // Always play sound — volume controlled via slider in Settings
    await _playAlertSound(newLevel);

    // Level 1 & 2 banners auto-dismiss after 3 seconds
    // Level 3 stays until driver manually dismisses
    if (newLevel < 3) {
      _alertBannerTimer?.cancel();
      _alertBannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          ref.read(showAlertBannerProvider.notifier).state = false;
        }
      });
    }
  }

  // AUDIO
  // Volume and on/off are read fresh from prefs on every alert trigger
  // so changes in Settings apply immediately without app restart
  Future<void> _playAlertSound(int level) async {
    // Always read volume fresh from prefs so changes in Settings
    // take effect immediately without needing an app restart
    final volume = await PreferencesHelper.instance.getAlertVolume();
    await _audioPlayer.setVolume(volume);
    await _alarmPlayer.setVolume(volume);

    if (level == 1 || level == 2) {
      // Short notification ping — plays once
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('L1_L2_sound.mp3'));
    } else {
      // Level 3 — long looping alarm until driver dismisses
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.play(AssetSource('L3_critical_alert.wav'));
    }
  }

  Future<void> _dismissAlert() async {
    await _alarmPlayer.stop();
    _alertLevel            = 0;
    _consecutiveDrowsy     = 0;
    _consecutiveDistracted = 0;
    ref.read(showAlertBannerProvider.notifier).state = false;
  }

  // HELPERS
  Future<void> _addLog(String message, String type) async {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _systemLogs.add({'time': timeStr, 'message': message, 'type': type});
    });
    if (_currentSessionId != null) {
      await DatabaseHelper.instance.insertSystemLog(
        sessionId: _currentSessionId!,
        message: message,
        logType: type,
      );
    }
  }

  Future<void> _saveAlertnessSnapshot() async {
    if (_currentSessionId == null) return;
    final alertness = ref.read(alertnessPctProvider);
    await DatabaseHelper.instance.insertAlertnesSnapshot(
      sessionId: _currentSessionId!,
      alertnessPct: alertness,
    );
  }

  // BUILD
  @override
  Widget build(BuildContext context) {
    final isDesktop   = Responsive.isDesktop(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return ColoredBox(
      color: const Color(0xFF080E1A),
      child: isDesktop
          ? _buildDesktopLayout()
          : isLandscape
              ? _buildLandscapeLayout()
              : _buildPortraitLayout(),
    );
  }

  // PORTRAIT LAYOUT
  Widget _buildPortraitLayout() {
    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);

    return SingleChildScrollView(
      child: Column(
        children: [
          if (showAlert) _buildAlertBanner(alertType),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildCameraContainer(height: 280, isLandscape: false),
                const SizedBox(height: 12),
                _buildEnvironmentBar(isLandscape: false),
                const SizedBox(height: 12),
                _buildMetricsSidebar(isLandscape: false),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // LANDSCAPE LAYOUT
  Widget _buildLandscapeLayout() {
    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);

    return Column(
      children: [
        if (showAlert) _buildAlertBanner(alertType),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 55,
                child: Column(
                  children: [
                    Expanded(
                        child: _buildCameraContainer(isLandscape: true)),
                    const SizedBox(height: 8),
                    _buildEnvironmentBar(isLandscape: true),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 45,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildMetricsSidebar(isLandscape: true),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // DESKTOP LAYOUT
  Widget _buildDesktopLayout() {
    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);

    return Column(
      children: [
        if (showAlert) _buildAlertBanner(alertType),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 8,
                child: Column(
                  children: [
                    Expanded(
                        child: _buildCameraContainer(isLandscape: true)),
                    SizedBox(
                        height: Responsive.responsiveSpacing(context,
                            mobile: 16, tablet: 20, desktop: 24)),
                    _buildEnvironmentBar(isLandscape: false),
                  ],
                ),
              ),
              SizedBox(
                  width: Responsive.responsiveSpacing(context,
                      mobile: 16, tablet: 24, desktop: 32)),
              Expanded(
                  flex: 4,
                  child: _buildMetricsSidebar(isLandscape: false)),
            ],
          ),
        ),
      ],
    );
  }

  // ALERT BANNER
  Widget _buildAlertBanner(String type) {
    final isDrowsy = type == 'DROWSY';
    return GestureDetector(
      onTap: _dismissAlert,
      child: AnimatedBuilder(
        animation: _warningAnimation,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2A0A0A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    Colors.red.withOpacity(0.5 * _warningAnimation.value),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.red.shade500, size: 36),
                const SizedBox(height: 8),
                Text(
                  isDrowsy
                      ? 'DROWSINESS DETECTED'
                      : 'DISTRACTION DETECTED',
                  style: TextStyle(
                    color: Colors.red.shade500,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Audible Alert Active • Tap to dismiss',
                  style:
                      TextStyle(color: Colors.red.shade300, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // CAMERA CONTAINER
  Widget _buildCameraContainer(
      {double? height, required bool isLandscape}) {
    final previewSize  = _getPreviewSize(isLandscape);
    final isRecording  = ref.watch(isRecordingProvider);

    Widget cameraWidget = ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.width,
          height: previewSize.height,
          child: Transform.scale(
            scaleX: 1,
            child: _cameraInitialized
                ? CameraPreview(_cameraController!)
                : _buildCameraFallback(),
          ),
        ),
      ),
    );

    Widget inner = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          cameraWidget,
          _buildGradientOverlay(),
          if (isRecording) _buildRecBadge(),
          if (ref.watch(showAlertBannerProvider))
            _buildWarningOverlay(ref.watch(alertBannerTypeProvider)),
        ],
      ),
    );

    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Color(0xFF0b1120),
              offset: Offset(8, 8),
              blurRadius: 16),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-8, -8),
              blurRadius: 16),
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off,
                  color: Color(0xFF64748b), size: 48),
              const SizedBox(height: 12),
              Text(_cameraError!,
                  style: const TextStyle(
                      color: Color(0xFF64748b), fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _initCamera,
                child: const Text('Retry',
                    style: TextStyle(color: Color(0xFF22d3ee))),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF22d3ee)),
            SizedBox(height: 12),
            Text('Initializing camera…',
                style:
                    TextStyle(color: Color(0xFF64748b), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              const Color(0xFF0f172a).withOpacity(0.4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecBadge() {
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text('REC',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningOverlay(String type) {
    final isDrowsy = type == 'DROWSY';
    return AnimatedBuilder(
      animation: _warningAnimation,
      builder: (context, child) {
        return Container(
          color: Colors.red.withOpacity(0.4),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Center(
              child: Transform.scale(
                scale: _warningAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF0f172a).withOpacity(0.9),
                    border: Border.all(
                        color: Colors.red.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 50,
                          spreadRadius: 10),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 48, color: Colors.red.shade500),
                      const SizedBox(height: 12),
                      Text(
                        isDrowsy
                            ? 'DROWSINESS DETECTED'
                            : 'DISTRACTION DETECTED',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade500,
                            letterSpacing: 3),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text('Audible Alert Active',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade300)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ENVIRONMENT BAR (Clear Glasses + Record button)
  Widget _buildEnvironmentBar({required bool isLandscape}) {
    final clearGlasses = ref.watch(clearGlassesProvider);
    final isRecording  = ref.watch(isRecordingProvider);

    return Container(
      height: isLandscape ? 52 : 68,
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Color(0xFF0b1120),
              offset: Offset(6, 6),
              blurRadius: 12),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-6, -6),
              blurRadius: 12),
        ],
      ),
      child: Row(
        children: [
          // Clear Glasses
          Expanded(
            child: InkWell(
              onTap: () {
                ref.read(clearGlassesProvider.notifier).state =
                    !clearGlasses;
                if (!clearGlasses && _currentSessionId != null) {
                  _addLog('Clear Glasses Mode Active', 'SUCCESS');
                }
              },
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: isLandscape ? 32 : 36,
                    height: isLandscape ? 32 : 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0f172a),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: clearGlasses
                          ? [
                              BoxShadow(
                                  color: const Color(0xFF0b1120)
                                      .withOpacity(0.8),
                                  offset: const Offset(3, 3),
                                  blurRadius: 6),
                              BoxShadow(
                                  color: const Color(0xFF1e293b)
                                      .withOpacity(0.8),
                                  offset: const Offset(-3, -3),
                                  blurRadius: 6),
                            ]
                          : const [
                              BoxShadow(
                                  color: Color(0xFF0b1120),
                                  offset: Offset(4, 4),
                                  blurRadius: 8),
                              BoxShadow(
                                  color: Color(0xFF1e293b),
                                  offset: Offset(-4, -4),
                                  blurRadius: 8),
                            ],
                    ),
                    child: Icon(Icons.visibility,
                        size: isLandscape ? 16 : 18,
                        color: clearGlasses
                            ? const Color(0xFF22d3ee)
                            : const Color(0xFF64748b)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Clear Glasses',
                    style: TextStyle(
                      fontSize: isLandscape ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color: clearGlasses
                          ? const Color(0xFF22d3ee)
                          : const Color(0xFF64748b),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Divider
          Container(
              width: 1,
              height: isLandscape ? 28 : 36,
              color: const Color(0xFF1e293b)),

          // Record / Stop 
          Expanded(
            child: InkWell(
              onTap: () {
                if (isRecording) {
                  _stopRecording();
                } else {
                  _startRecording();
                }
              },
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isLandscape ? 32 : 36,
                    height: isLandscape ? 32 : 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0f172a),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isRecording
                          ? [
                              BoxShadow(
                                  color: Colors.red.withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2),
                            ]
                          : const [
                              BoxShadow(
                                  color: Color(0xFF0b1120),
                                  offset: Offset(4, 4),
                                  blurRadius: 8),
                              BoxShadow(
                                  color: Color(0xFF1e293b),
                                  offset: Offset(-4, -4),
                                  blurRadius: 8),
                            ],
                    ),
                    child: Icon(
                      isRecording
                          ? Icons.stop_circle
                          : Icons.fiber_manual_record,
                      size: isLandscape ? 16 : 18,
                      color: isRecording
                          ? Colors.red
                          : const Color(0xFF64748b),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isRecording ? 'Stop Rec' : 'Record',
                    style: TextStyle(
                      fontSize: isLandscape ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color: isRecording
                          ? Colors.red
                          : const Color(0xFF64748b),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // METRICS SIDEBAR
  Widget _buildMetricsSidebar({required bool isLandscape}) {
    final alertness   = ref.watch(alertnessPctProvider);
    final drowsiness  = ref.watch(drowsinessPctProvider);
    final distraction = ref.watch(distractionPctProvider);
    const spacing     = SizedBox(height: 16);

    return Column(
      children: [
        _buildMetricCard(
            label: 'Alertness',
            value: alertness,
            color: const Color(0xFF22d3ee),
            icon: Icons.bolt),
        spacing,
        _buildMetricCard(
            label: 'Drowsiness',
            value: drowsiness,
            color: Colors.red.shade500,
            icon: Icons.visibility_off),
        spacing,
        _buildMetricCard(
            label: 'Distraction',
            value: distraction,
            color: const Color(0xFFfbbf24),
            icon: Icons.visibility),
        const SizedBox(height: 20),
        SizedBox(
            height: isLandscape ? 260.0 : 320.0,
            child: _buildSystemLog()),
        const SizedBox(height: 16),
        _buildTestButtons(),
      ],
    );
  }

  Widget _buildMetricCard({
    required String label,
    required double value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
        borderRadius: BorderRadius.all(Radius.circular(16)),
        boxShadow: [
          BoxShadow(
              color: Color(0xFF0b1120),
              offset: Offset(6, 6),
              blurRadius: 12),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-6, -6),
              blurRadius: 12),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1e293b),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(
                          color: Color(0xFFcbd5e1),
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ],
              ),
              Text('${value.toInt()}%',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: color)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF0b1120).withOpacity(0.5),
                    offset: const Offset(2, 2),
                    blurRadius: 4),
                BoxShadow(
                    color: const Color(0xFF1e293b).withOpacity(0.5),
                    offset: const Offset(-2, -2),
                    blurRadius: 4),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value / 100,
                  child: Container(
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(5))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // SYSTEM LOG
  Widget _buildSystemLog() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0b1120).withOpacity(0.5),
              offset: const Offset(4, 4),
              blurRadius: 8),
          BoxShadow(
              color: const Color(0xFF1e293b).withOpacity(0.5),
              offset: const Offset(-4, -4),
              blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Text('SYSTEM LOG',
              style: TextStyle(
                  color: Color(0xFF94a3b8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5)),
          const SizedBox(height: 10),
          if (_systemLogs.isEmpty)
            const Align(
              alignment: Alignment.topCenter,
              child: Text(
                'No logs yet. Start recording to begin.',
                style:
                    TextStyle(color: Colors.white24, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._systemLogs.reversed.take(8).map((log) {
              Color textColor;
              switch (log['type']) {
                case 'SUCCESS':
                  textColor = const Color(0xFF10b981);
                  break;
                case 'WARNING':
                  textColor = const Color(0xFFfbbf24);
                  break;
                default:
                  textColor = const Color(0xFF94a3b8);
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('[${log['time']}]',
                        style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 10,
                            fontFamily: 'monospace')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(log['message'],
                          style: TextStyle(
                              color: textColor,
                              fontSize: 10,
                              fontFamily: 'monospace')),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ⚠️ DEV ONLY — REMOVE BEFORE FINAL BUILD
  // Test buttons to trigger alert levels without the model
  Widget _buildTestButtons() {
    final isRecording = ref.watch(isRecordingProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFfbbf24).withOpacity(0.4),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120),
              offset: Offset(4, 4),
              blurRadius: 8),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-4, -4),
              blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.bug_report_rounded,
                  color: Color(0xFFfbbf24), size: 14),
              const SizedBox(width: 6),
              const Text(
                'DEV — ALERT TEST',
                style: TextStyle(
                  color: Color(0xFFfbbf24),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (!isRecording)
                const Text(
                  'Start recording first',
                  style: TextStyle(
                      color: Color(0xFF475569), fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // DROWSY row
          const Text('DROWSY',
              style: TextStyle(
                  color: Color(0xFF64748b),
                  fontSize: 10,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Row(
            children: [
              _testButton(
                label: 'Level 1',
                color: const Color(0xFF22d3ee),
                onTap: isRecording
                    ? () {
                        _consecutiveDrowsy = 3;
                        _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              _testButton(
                label: 'Level 2',
                color: const Color(0xFFfbbf24),
                onTap: isRecording
                    ? () {
                        _consecutiveDrowsy = 6;
                        _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              _testButton(
                label: 'Level 3',
                color: Colors.red,
                onTap: isRecording
                    ? () {
                        _consecutiveDrowsy = 9;
                        _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
                      }
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 10),

          // DISTRACTED row
          const Text('DISTRACTED',
              style: TextStyle(
                  color: Color(0xFF64748b),
                  fontSize: 10,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Row(
            children: [
              _testButton(
                label: 'Level 1',
                color: const Color(0xFF22d3ee),
                onTap: isRecording
                    ? () {
                        _consecutiveDistracted = 3;
                        _checkAndTriggerAlert(
                            'DISTRACTED', _consecutiveDistracted);
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              _testButton(
                label: 'Level 2',
                color: const Color(0xFFfbbf24),
                onTap: isRecording
                    ? () {
                        _consecutiveDistracted = 6;
                        _checkAndTriggerAlert(
                            'DISTRACTED', _consecutiveDistracted);
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              _testButton(
                label: 'Level 3',
                color: Colors.red,
                onTap: isRecording
                    ? () {
                        _consecutiveDistracted = 9;
                        _checkAndTriggerAlert(
                            'DISTRACTED', _consecutiveDistracted);
                      }
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Reset button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                _consecutiveDrowsy     = 0;
                _consecutiveDistracted = 0;
                _alertLevel            = 0;
                _alarmPlayer.stop();
                ref.read(showAlertBannerProvider.notifier).state = false;
                _addLog('Alert reset by dev', 'INFO');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF475569), width: 1),
                ),
                child: const Text(
                  'Reset All Alerts',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF94a3b8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _testButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isEnabled
                ? color.withOpacity(0.12)
                : const Color(0xFF1e293b),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEnabled
                  ? color.withOpacity(0.5)
                  : const Color(0xFF1e293b),
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isEnabled ? color : const Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}