import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../core/database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RIVERPOD PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

// Driver state: 'neutral', 'drowsy', 'distracted'
final driverStateProvider = StateProvider<String>((ref) => 'neutral');

// Live percentages
final alertnessPctProvider = StateProvider<double>((ref) => 100.0);
final drowsinessPctProvider = StateProvider<double>((ref) => 0.0);
final distractionPctProvider = StateProvider<double>((ref) => 0.0);

// Recording state
final isRecordingProvider = StateProvider<bool>((ref) => false);

// Alert banner visibility
final showAlertBannerProvider = StateProvider<bool>((ref) => false);
final alertBannerTypeProvider = StateProvider<String>((ref) => 'DROWSY');

// Clear glasses toggle
final clearGlassesProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────────────────────
// MONITORING SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  // Camera
  CameraController? _cameraController;
  bool _cameraInitialized = false;

  // Session tracking
  int? _currentSessionId;
  DateTime? _sessionStartTime;
  Timer? _snapshotTimer;
  Timer? _alertBannerTimer;

  // Alert tracking (3 consecutive detections)
  int _consecutiveDrowsy = 0;
  int _consecutiveDistracted = 0;
  int _alertLevel = 0;

  // System logs
  final List<Map<String, dynamic>> _systemLogs = [];

  // Audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _alarmPlayer = AudioPlayer();

  // ── LIFECYCLE ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _snapshotTimer?.cancel();
    _alertBannerTimer?.cancel();
    _audioPlayer.dispose();
    _alarmPlayer.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Use front camera
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => _cameraInitialized = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  // ── SESSION CONTROL ────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    // Create session in DB
    _currentSessionId = await DatabaseHelper.instance.insertSession();
    await DatabaseHelper.instance.insertStateCount(_currentSessionId!);

    _sessionStartTime = DateTime.now();

    ref.read(isRecordingProvider.notifier).state = true;
    ref.read(driverStateProvider.notifier).state = 'neutral';

    // Add initial system logs
    await _addLog('System Initialized', 'INFO');
    await Future.delayed(const Duration(milliseconds: 500));
    await _addLog('Face Tracking Active', 'SUCCESS');
    await Future.delayed(const Duration(milliseconds: 400));
    await _addLog('Baseline Established', 'INFO');

    // Start alertness snapshot timer (every 5 seconds)
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
    _alertLevel = 0;
    _consecutiveDrowsy = 0;
    _consecutiveDistracted = 0;

    // Calculate session duration
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

    ref.read(isRecordingProvider.notifier).state = false;
    ref.read(driverStateProvider.notifier).state = 'neutral';
    ref.read(showAlertBannerProvider.notifier).state = false;
    ref.read(alertnessPctProvider.notifier).state = 100.0;
    ref.read(drowsinessPctProvider.notifier).state = 0.0;
    ref.read(distractionPctProvider.notifier).state = 0.0;

    _currentSessionId = null;
    _sessionStartTime = null;
  }

  // ── MODEL OUTPUT HANDLER ──────────────────────────────────────────────────
  // Call this method when TFLite returns a result
  // This is where you plug in your model inference output

  void onModelOutput({
    required String state,          // 'neutral', 'drowsy', 'distracted'
    required double alertnessPct,
    required double drowsinessPct,
    required double distractionPct,
  }) {
    if (!ref.read(isRecordingProvider)) return;

    // Update live UI percentages
    ref.read(alertnessPctProvider.notifier).state = alertnessPct;
    ref.read(drowsinessPctProvider.notifier).state = drowsinessPct;
    ref.read(distractionPctProvider.notifier).state = distractionPct;
    ref.read(driverStateProvider.notifier).state = state;

    // Update state counts in DB
    if (_currentSessionId != null) {
      DatabaseHelper.instance.incrementStateCount(
        sessionId: _currentSessionId!,
        state: state,
      );
    }

    // Check consecutive detections for 3-level alert system
    if (state == 'drowsy') {
      _consecutiveDrowsy++;
      _consecutiveDistracted = 0;
      _checkAndTriggerAlert('DROWSY', _consecutiveDrowsy);
    } else if (state == 'distracted') {
      _consecutiveDistracted++;
      _consecutiveDrowsy = 0;
      _checkAndTriggerAlert('DISTRACTED', _consecutiveDistracted);
    } else {
      // Neutral — reset counters
      _consecutiveDrowsy = 0;
      _consecutiveDistracted = 0;
      _alertLevel = 0;
      ref.read(showAlertBannerProvider.notifier).state = false;
      _alarmPlayer.stop();
    }
  }

  // ── 3-LEVEL ALERT SYSTEM ──────────────────────────────────────────────────

  Future<void> _checkAndTriggerAlert(String type, int consecutive) async {
    if (consecutive < 3) return; // Need 3 consecutive before alerting

    // Determine level
    int newLevel = 1;
    if (consecutive >= 9) newLevel = 3;
    else if (consecutive >= 6) newLevel = 2;
    else newLevel = 1;

    if (newLevel <= _alertLevel && _alertLevel == 3) return; // Already at max
    _alertLevel = newLevel;

    // Show alert banner
    ref.read(showAlertBannerProvider.notifier).state = true;
    ref.read(alertBannerTypeProvider.notifier).state = type;

    // Save to DB
    if (_currentSessionId != null) {
      await DatabaseHelper.instance.insertAlertEvent(
        sessionId: _currentSessionId!,
        alertType: type,
        alertLevel: newLevel,
      );

      final msg = type == 'DROWSY' ? 'Microsleep detected' : 'Distraction detected';
      await _addLog(msg, 'WARNING');
    }

    // Play sound + vibrate
    await _playAlertSound(newLevel);
    await _triggerVibration(newLevel);

    // Auto-dismiss banner for levels 1 & 2
    if (newLevel < 3) {
      _alertBannerTimer?.cancel();
      _alertBannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          ref.read(showAlertBannerProvider.notifier).state = false;
        }
      });
    }
  }

  Future<void> _playAlertSound(int level) async {
    if (level == 1 || level == 2) {
      // Short notification ping
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
    } else {
      // Level 3 — looping alarm
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.play(AssetSource('sounds/alarm.mp3'));
    }
  }

  Future<void> _triggerVibration(int level) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;

    if (level == 1) {
      Vibration.vibrate(duration: 200);
    } else if (level == 2) {
      Vibration.vibrate(pattern: [0, 200, 100, 200]);
    } else {
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
    }
  }

  Future<void> _dismissAlert() async {
    await _alarmPlayer.stop();
    _alertLevel = 0;
    _consecutiveDrowsy = 0;
    _consecutiveDistracted = 0;
    ref.read(showAlertBannerProvider.notifier).state = false;
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  Future<void> _addLog(String message, String type) async {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    setState(() {
      _systemLogs.add({
        'time': timeStr,
        'message': message,
        'type': type,
      });
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

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showAlert = ref.watch(showAlertBannerProvider);
    final alertType = ref.watch(alertBannerTypeProvider);
    final isRecording = ref.watch(isRecordingProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Alert Banner
                    if (showAlert) _buildAlertBanner(alertType),

                    // Camera Feed
                    _buildCameraSection(),

                    const SizedBox(height: 12),

                    // Controls Row
                    _buildControlsRow(isRecording),

                    const SizedBox(height: 16),

                    // State Progress Bars
                    _buildStateBars(),

                    const SizedBox(height: 16),

                    // System Log
                    _buildSystemLog(),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Monitor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF88),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF88).withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RichText(
            text: const TextSpan(
              text: 'Connected: ',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              children: [
                TextSpan(
                  text: 'USER',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ALERT BANNER ──────────────────────────────────────────────────────────
  Widget _buildAlertBanner(String type) {
    final isDrowsy = type == 'DROWSY';
    return GestureDetector(
      onTap: _dismissAlert,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2A0A0A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4444).withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFF4444), size: 36),
            const SizedBox(height: 8),
            Text(
              isDrowsy ? 'DROWSINESS DETECTED' : 'DISTRACTION DETECTED',
              style: const TextStyle(
                color: Color(0xFFFF4444),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Audible Alert Active • Tap to dismiss',
              style: TextStyle(color: Color(0xFFFF8888), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── CAMERA SECTION ────────────────────────────────────────────────────────
  Widget _buildCameraSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF080E1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera preview or placeholder
          if (_cameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            Container(
              color: const Color(0xFF080E1A),
              child: const Center(
                child: Icon(Icons.videocam_off_rounded,
                    color: Colors.white24, size: 40),
              ),
            ),

          // Face detection rectangle (shown when recording)
          if (ref.watch(isRecordingProvider))
            Center(
              child: Container(
                width: 120,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF00D4FF),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── CONTROLS ROW ─────────────────────────────────────────────────────────
  Widget _buildControlsRow(bool isRecording) {
    final clearGlasses = ref.watch(clearGlassesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1627),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            // Clear Glasses Toggle
            Expanded(
              child: GestureDetector(
                onTap: () {
                  ref.read(clearGlassesProvider.notifier).state = !clearGlasses;
                  if (!clearGlasses && _currentSessionId != null) {
                    _addLog('Clear Glasses Mode Active', 'SUCCESS');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: clearGlasses
                        ? const Color(0xFF00D4FF).withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.remove_red_eye_outlined,
                        color: clearGlasses
                            ? const Color(0xFF00D4FF)
                            : Colors.white38,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Clear Glasses',
                        style: TextStyle(
                          color: clearGlasses
                              ? const Color(0xFF00D4FF)
                              : Colors.white38,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Divider
            Container(
              width: 1,
              height: 40,
              color: Colors.white.withOpacity(0.08),
            ),

            // Record / Stop Button
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (isRecording) {
                    _stopRecording();
                  } else {
                    _startRecording();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isRecording
                        ? const Color(0xFFFF4444).withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isRecording
                              ? const Color(0xFFFF4444)
                              : Colors.white38,
                          shape: isRecording
                              ? BoxShape.rectangle
                              : BoxShape.circle,
                          borderRadius: isRecording
                              ? BorderRadius.circular(3)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isRecording ? 'Stop Rec' : 'Record',
                        style: TextStyle(
                          color: isRecording
                              ? const Color(0xFFFF4444)
                              : Colors.white38,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── STATE PROGRESS BARS ──────────────────────────────────────────────────
  Widget _buildStateBars() {
    final alertness = ref.watch(alertnessPctProvider);
    final drowsiness = ref.watch(drowsinessPctProvider);
    final distraction = ref.watch(distractionPctProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          _StateBar(
            icon: Icons.flash_on_rounded,
            iconColor: const Color(0xFF00D4FF),
            label: 'Alertness',
            value: alertness,
            barColor: const Color(0xFF00D4FF),
            textColor: const Color(0xFF00D4FF),
          ),
          const SizedBox(height: 16),
          _StateBar(
            icon: Icons.visibility_off_rounded,
            iconColor: const Color(0xFFFF4444),
            label: 'Drowsiness',
            value: drowsiness,
            barColor: const Color(0xFFFF4444),
            textColor: const Color(0xFFFF4444),
          ),
          const SizedBox(height: 16),
          _StateBar(
            icon: Icons.remove_red_eye_rounded,
            iconColor: const Color(0xFFFFB800),
            label: 'Distraction',
            value: distraction,
            barColor: const Color(0xFFFFB800),
            textColor: const Color(0xFFFFB800),
          ),
        ],
      ),
    );
  }

  // ── SYSTEM LOG ────────────────────────────────────────────────────────────
  Widget _buildSystemLog() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SYSTEM LOG',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (_systemLogs.isEmpty)
            const Text(
              'No logs yet. Start recording to begin.',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            )
          else
            ..._systemLogs.reversed.take(8).map((log) {
              Color textColor;
              switch (log['type']) {
                case 'SUCCESS':
                  textColor = const Color(0xFF00FF88);
                  break;
                case 'WARNING':
                  textColor = const Color(0xFFFFB800);
                  break;
                default:
                  textColor = Colors.white54;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: '[${log['time']}] ',
                        style: const TextStyle(color: Colors.white38),
                      ),
                      TextSpan(
                        text: log['message'],
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE STATE BAR WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _StateBar extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final double value;
  final Color barColor;
  final Color textColor;

  const _StateBar({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.barColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}