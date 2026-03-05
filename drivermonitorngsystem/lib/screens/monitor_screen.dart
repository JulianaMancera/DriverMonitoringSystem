import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import '../utils/responsive.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with TickerProviderStateMixin {
  double alertness = 85;
  double drowsiness = 12;
  double distraction = 5;

  bool clearGlasses = false;
  bool isRecording = false;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraInitialized = false;
  String? _cameraError;

  String? warning;
  Timer? _simulationTimer;

  late AnimationController _faceBoxController;
  late Animation<Offset> _faceBoxAnimation;
  late AnimationController _warningController;
  late Animation<double> _warningAnimation;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initCamera();

    _faceBoxController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _faceBoxAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(10, 5),
    ).animate(CurvedAnimation(
        parent: _faceBoxController, curve: Curves.easeInOut));

    _warningController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _warningAnimation =
        Tween<double>(begin: 0.8, end: 1.0).animate(_warningController);

    _startSimulation();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'No cameras found');
        return;
      }

      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => _cameraInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_cameraController == null || !_cameraInitialized) return;
    try {
      if (isRecording) {
        final file = await _cameraController!.stopVideoRecording();
        setState(() => isRecording = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Recording saved: ${file.path}'),
            backgroundColor: const Color(0xFF10b981),
          ));
        }
      } else {
        await _cameraController!.startVideoRecording();
        setState(() => isRecording = true);
      }
    } catch (e) {
      setState(() => isRecording = false);
    }
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        drowsiness =
            (drowsiness + (_random.nextDouble() * 4 - 1.5)).clamp(0.0, 100.0);
        alertness =
            (100 - drowsiness - (_random.nextDouble() * 5)).clamp(0.0, 100.0);
        distraction =
            (distraction + (_random.nextDouble() * 6 - 3)).clamp(0.0, 100.0);

        if (drowsiness > 40) {
          warning = "DROWSINESS DETECTED";
        } else if (distraction > 30) {
          warning = "DISTRACTION DETECTED";
        } else {
          warning = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _faceBoxController.dispose();
    _warningController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
            context, mobile: 12, tablet: 16, desktop: 16),
      ),
      child: isDesktop
          ? _buildDesktopLayout()
          : isLandscape
              ? _buildLandscapeLayout()
              : _buildPortraitLayout(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PORTRAIT: fixed-height square-ish box, cover fill (no stretch), metrics below
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildPortraitCameraBox(),
          const SizedBox(height: 12),
          _buildEnvironmentBar(),
          const SizedBox(height: 12),
          _buildMetricsSidebar(isLandscape: false),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  /// Fixed-height box. Camera fills it with BoxFit.cover — no stretching.
  Widget _buildPortraitCameraBox() {
    return Container(
      height: 280,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(8, 8), blurRadius: 16),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-8, -8),
              blurRadius: 16),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover fill — camera fills the box without stretching
            _buildCoverCamera(),
            _buildGradientOverlay(),
            if (isRecording) _buildRecBadge(),
            _buildFaceTrackingBox(),
            if (warning != null) _buildWarningOverlay(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // LANDSCAPE: camera uses its NATIVE landscape ratio, controls on the right
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildLandscapeLayout() {
    // Native landscape ratio from camera (e.g. 16/9 = 1.77)
    // Don't invert — in landscape we WANT the wide view
    final double cameraRatio = _cameraInitialized
        ? _cameraController!.value.aspectRatio
        : 16 / 9;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: landscape camera — fills height, ratio-correct width
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Expanded(
                child: _buildLandscapeCameraBox(cameraRatio),
              ),
              const SizedBox(height: 8),
              _buildEnvironmentBar(),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right: scrollable metrics
        Expanded(
          flex: 4,
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
    );
  }

  /// Landscape camera — AspectRatio with native landscape ratio, no stretching
  Widget _buildLandscapeCameraBox(double cameraRatio) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(8, 8), blurRadius: 16),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-8, -8),
              blurRadius: 16),
        ],
      ),
      padding: const EdgeInsets.all(6),
      // AspectRatio with the LANDSCAPE ratio — fills width naturally in landscape
      child: AspectRatio(
        aspectRatio: cameraRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCoverCamera(),
              _buildGradientOverlay(),
              if (isRecording) _buildRecBadge(),
              _buildFaceTrackingBox(),
              if (warning != null) _buildWarningOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DESKTOP
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout() {
    final double rawRatio = _cameraInitialized
        ? _cameraController!.value.aspectRatio
        : 16 / 9;
    final double aspectRatio = rawRatio > 1 ? 1 / rawRatio : rawRatio;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 8,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a),
                    borderRadius: BorderRadius.circular(
                        Responsive.responsiveBorderRadius(
                            context,
                            mobile: 20,
                            tablet: 22,
                            desktop: 24)),
                    boxShadow: const [
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
                  padding: const EdgeInsets.all(8),
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildCoverCamera(),
                          _buildGradientOverlay(),
                          if (isRecording) _buildRecBadge(),
                          _buildFaceTrackingBox(),
                          if (warning != null) _buildWarningOverlay(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                  height: Responsive.responsiveSpacing(
                      context, mobile: 16, tablet: 20, desktop: 24)),
              _buildEnvironmentBar(),
            ],
          ),
        ),
        SizedBox(
            width: Responsive.responsiveSpacing(
                context, mobile: 16, tablet: 24, desktop: 32)),
        Expanded(flex: 4, child: _buildMetricsSidebar(isLandscape: false)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CAMERA PREVIEW — BoxFit.cover so it fills ANY container shape without stretch
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildCoverCamera() {
    if (!_cameraInitialized && _cameraError == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF22d3ee)),
              SizedBox(height: 12),
              Text('Initializing camera…',
                  style: TextStyle(color: Color(0xFF64748b), fontSize: 13)),
            ],
          ),
        ),
      );
    }

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

    final double rawRatio = _cameraController!.value.aspectRatio;

    // FittedBox with cover:
    // We give CameraPreview its native size, then FittedBox.cover
    // scales it up to fill the container — no distortion, just cropping edges.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // Native camera dimensions (use landscape values always)
          width: rawRatio * 1000,
          height: 1000,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(3.14159), // mirror front cam
            child: CameraPreview(_cameraController!),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  Widget _buildFaceTrackingBox() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final boxW = isLandscape ? 110.0 : 110.0;
    final boxH = isLandscape ? 140.0 : 150.0;
    final startTop = isLandscape ? 15.0 : 25.0;
    final startLeft = isLandscape ? 50.0 : 55.0;

    return AnimatedBuilder(
      animation: _faceBoxAnimation,
      builder: (context, child) {
        return Positioned(
          top: startTop + _faceBoxAnimation.value.dy,
          left: startLeft + _faceBoxAnimation.value.dx,
          child: Container(
            width: boxW,
            height: boxH,
            decoration: BoxDecoration(
              border: Border.all(
                  color: const Color(0xFF22d3ee).withOpacity(0.7), width: 1.5),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF22d3ee).withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2),
              ],
            ),
            child: Stack(
              children: [
                _buildCornerMarker(Alignment.topLeft),
                _buildCornerMarker(Alignment.topRight),
                _buildCornerMarker(Alignment.bottomLeft),
                _buildCornerMarker(Alignment.bottomRight),
                Positioned(
                  top: -18,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22d3ee).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('FACE DETECTED',
                        style: TextStyle(
                            color: Color(0xFF22d3ee),
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCornerMarker(Alignment alignment) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(isLeft ? -1 : 1, isTop ? -1 : 1),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            border: Border(
              top: isTop
                  ? const BorderSide(color: Color(0xFF22d3ee), width: 1.5)
                  : BorderSide.none,
              bottom: !isTop
                  ? const BorderSide(color: Color(0xFF22d3ee), width: 1.5)
                  : BorderSide.none,
              left: isLeft
                  ? const BorderSide(color: Color(0xFF22d3ee), width: 1.5)
                  : BorderSide.none,
              right: !isLeft
                  ? const BorderSide(color: Color(0xFF22d3ee), width: 1.5)
                  : BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarningOverlay() {
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
                    color: const Color(0xFF0f172a).withOpacity(0.9),
                    border: Border.all(
                        color: Colors.red.withOpacity(0.5), width: 1),
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
                        warning!,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade500,
                          letterSpacing: 3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text('Audible Alert Active',
                          style: TextStyle(
                              fontSize: 12, color: Colors.red.shade300)),
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

  // ── Environment Bar ──────────────────────────────────────────────────────────
  Widget _buildEnvironmentBar() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      height: isLandscape ? 56 : 72,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(6, 6), blurRadius: 12),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-6, -6),
              blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusItem(
            active: clearGlasses,
            icon: Icons.visibility,
            label: 'Clear Glasses',
            onToggle: () => setState(() => clearGlasses = !clearGlasses),
          ),
          Container(width: 1, height: 36, color: const Color(0xFF1e293b)),
          _buildRecordButton(),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    return InkWell(
      onTap: _toggleRecording,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 36,
              height: 36,
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
                isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                size: 18,
                color: isRecording ? Colors.red : const Color(0xFF64748b),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isRecording ? 'Stop Rec' : 'Record',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isRecording ? Colors.red : const Color(0xFF64748b),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onToggle,
  }) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0f172a),
                borderRadius: BorderRadius.circular(10),
                boxShadow: active
                    ? [
                        BoxShadow(
                            color: const Color(0xFF0b1120).withOpacity(0.8),
                            offset: const Offset(3, 3),
                            blurRadius: 6),
                        BoxShadow(
                            color: const Color(0xFF1e293b).withOpacity(0.8),
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
              child: Icon(icon,
                  size: 18,
                  color: active
                      ? const Color(0xFF22d3ee)
                      : const Color(0xFF64748b)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color:
                    active ? const Color(0xFF22d3ee) : const Color(0xFF64748b),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Metrics Sidebar ──────────────────────────────────────────────────────────
  Widget _buildMetricsSidebar({required bool isLandscape}) {
    const spacing = SizedBox(height: 10);
    final logHeight = isLandscape ? 180.0 : 220.0;

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
        spacing,
        SizedBox(height: logHeight, child: _buildSystemLog()),
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
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(6, 6), blurRadius: 12),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-6, -6),
              blurRadius: 12),
        ],
      ),
      padding: const EdgeInsets.all(14),
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

  Widget _buildSystemLog() {
    return Container(
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
        children: [
          const Text('SYSTEM LOG',
              style: TextStyle(
                  color: Color(0xFF94a3b8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5)),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                _buildLogEntry('10:42:01', 'System Initialized', LogType.info),
                _buildLogEntry(
                    '10:42:05', 'Face Tracking Active', LogType.success),
                _buildLogEntry(
                    '10:42:15', 'Baseline Established', LogType.info),
                if (clearGlasses)
                  _buildLogEntry(
                      '10:42:20', 'Clear Glasses Detected', LogType.info),
                if (isRecording)
                  _buildLogEntry(
                      '10:42:30', 'Recording Started', LogType.success),
                if (drowsiness > 30)
                  _buildLogEntry(
                      '10:42:45', 'Microsleep detected', LogType.warning),
                if (distraction > 20)
                  _buildLogEntry(
                      '10:42:52', 'Gaze diversion > 2s', LogType.warning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(String time, String message, LogType type) {
    final Color color;
    switch (type) {
      case LogType.info:
        color = const Color(0xFF94a3b8);
      case LogType.warning:
        color = const Color(0xFFfbbf24);
      case LogType.success:
        color = const Color(0xFF10b981);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('[$time]',
              style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 10,
                  fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: color, fontSize: 10, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

enum LogType { info, warning, success }