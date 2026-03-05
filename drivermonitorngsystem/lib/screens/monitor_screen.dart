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
    ).animate(
        CurvedAnimation(parent: _faceBoxController, curve: Curves.easeInOut));

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

  // ── Get correct preview dimensions based on orientation ──────────────────────
  // Android cameras always report landscape previewSize (width > height).
  // In portrait we swap them so FittedBox.cover fills portrait containers properly.
  Size _getPreviewSize(bool isLandscape) {
    if (!_cameraInitialized) {
      return isLandscape ? const Size(1920, 1080) : const Size(1080, 1920);
    }
    final ps = _cameraController!.value.previewSize!;
    // ps.width >= ps.height always on Android (landscape native)
    if (isLandscape) {
      return Size(ps.width, ps.height); // keep landscape
    } else {
      return Size(ps.height, ps.width); // swap → portrait
    }
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
  // PORTRAIT
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildCameraContainer(
            height: 280,
            isLandscape: false,
          ),
          const SizedBox(height: 12),
          _buildEnvironmentBar(isLandscape: false),
          const SizedBox(height: 12),
          _buildMetricsSidebar(isLandscape: false),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // LANDSCAPE
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildLandscapeLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 55,
          child: Column(
            children: [
              Expanded(
                child: _buildCameraContainer(
                  isLandscape: true,
                  // no fixed height — fills Expanded
                ),
              ),
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DESKTOP
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 8,
          child: Column(
            children: [
              Expanded(
                child: _buildCameraContainer(isLandscape: true),
              ),
              SizedBox(
                  height: Responsive.responsiveSpacing(
                      context, mobile: 16, tablet: 20, desktop: 24)),
              _buildEnvironmentBar(isLandscape: false),
            ],
          ),
        ),
        SizedBox(
            width: Responsive.responsiveSpacing(
                context, mobile: 16, tablet: 24, desktop: 32)),
        Expanded(
            flex: 4,
            child: _buildMetricsSidebar(isLandscape: false)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CAMERA CONTAINER — wraps camera with correct fill behavior
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildCameraContainer({
    double? height,
    required bool isLandscape,
  }) {
    final previewSize = _getPreviewSize(isLandscape);

    Widget cameraWidget = ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // Give FittedBox the CORRECT oriented dimensions
          // so it scales/crops properly to fill the container
          width: previewSize.width,
          height: previewSize.height,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(3.14159), // mirror front cam
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
          _buildFaceTrackingBox(isLandscape: isLandscape),
          if (warning != null) _buildWarningOverlay(),
        ],
      ),
    );

    return Container(
      height: height, // null = fills Expanded parent
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
                style: TextStyle(color: Color(0xFF64748b), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SHARED UI WIDGETS
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

  Widget _buildFaceTrackingBox({required bool isLandscape}) {
    final boxW = isLandscape ? 120.0 : 110.0;
    final boxH = isLandscape ? 150.0 : 150.0;
    final startTop = isLandscape ? 15.0 : 25.0;
    final startLeft = isLandscape ? 60.0 : 55.0;

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
                            letterSpacing: 3),
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

  // ── Environment Bar — equal width buttons ────────────────────────────────────
  Widget _buildEnvironmentBar({required bool isLandscape}) {
    return Container(
      height: isLandscape ? 52 : 68,
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
        children: [
          // ── Clear Glasses — Expanded so it takes exactly half ──
          Expanded(
            child: InkWell(
              onTap: () => setState(() => clearGlasses = !clearGlasses),
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
                                  color:
                                      const Color(0xFF0b1120).withOpacity(0.8),
                                  offset: const Offset(3, 3),
                                  blurRadius: 6),
                              BoxShadow(
                                  color:
                                      const Color(0xFF1e293b).withOpacity(0.8),
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

          // ── Record — Expanded so it takes exactly half ──
          Expanded(
            child: InkWell(
              onTap: _toggleRecording,
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
                      color:
                          isRecording ? Colors.red : const Color(0xFF64748b),
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

  // ── Metrics Sidebar ──────────────────────────────────────────────────────────
  Widget _buildMetricsSidebar({required bool isLandscape}) {
    const spacing = SizedBox(height: 10);
    final logHeight = isLandscape ? 160.0 : 200.0;

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
                _buildLogEntry(
                    '10:42:01', 'System Initialized', LogType.info),
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
                    color: color,
                    fontSize: 10,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

enum LogType { info, warning, success }