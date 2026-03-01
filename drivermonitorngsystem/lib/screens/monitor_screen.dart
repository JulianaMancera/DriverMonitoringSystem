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
  // Metrics state
  double alertness = 85;
  double drowsiness = 12;
  double distraction = 5;

  // Environment state
  bool clearGlasses = false;   // renamed from sunglasses
  bool isRecording = false;    // replaces isDay

  // Camera state
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraInitialized = false;
  String? _cameraError;

  // Warning state
  String? warning;

  // Timer for simulation
  Timer? _simulationTimer;

  // Animation controllers
  late AnimationController _faceBoxController;
  late Animation<Offset> _faceBoxAnimation;
  late AnimationController _warningController;
  late Animation<double> _warningAnimation;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _initCamera();

    // Face box animation
    _faceBoxController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _faceBoxAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(10, 5),
    ).animate(CurvedAnimation(
      parent: _faceBoxController,
      curve: Curves.easeInOut,
    ));

    // Warning pulse animation
    _warningController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _warningAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(_warningController);

    _startSimulation();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'No cameras found');
        return;
      }

      // Prefer front camera for driver monitoring
      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _cameraInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = 'Camera error: $e');
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_cameraController == null || !_cameraInitialized) return;

    try {
      if (isRecording) {
        final file = await _cameraController!.stopVideoRecording();
        setState(() => isRecording = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Recording saved: ${file.path}'),
              backgroundColor: const Color(0xFF10b981),
            ),
          );
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
        drowsiness = (drowsiness + (_random.nextDouble() * 4 - 1.5))
            .clamp(0.0, 100.0);
        alertness = (100 - drowsiness - (_random.nextDouble() * 5))
            .clamp(0.0, 100.0);
        distraction = (distraction + (_random.nextDouble() * 6 - 3))
            .clamp(0.0, 100.0);

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

    return Container(
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context, mobile: 16, tablet: 20, desktop: 16),
      ),
      child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 8,
          child: Column(
            children: [
              Expanded(child: _buildCameraFeed()),
              SizedBox(
                height: Responsive.responsiveSpacing(
                    context, mobile: 16, tablet: 20, desktop: 24),
              ),
              _buildEnvironmentBar(),
            ],
          ),
        ),
        SizedBox(
          width: Responsive.responsiveSpacing(
              context, mobile: 16, tablet: 24, desktop: 32),
        ),
        Expanded(flex: 4, child: _buildMetricsSidebar()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildCameraFeed(),
          SizedBox(
            height: Responsive.responsiveSpacing(
                context, mobile: 16, tablet: 20, desktop: 24),
          ),
          _buildEnvironmentBar(),
          SizedBox(
            height: Responsive.responsiveSpacing(
                context, mobile: 16, tablet: 20, desktop: 24),
          ),
          _buildMetricsSidebar(),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  // ── Camera Feed ──────────────────────────────────────────────────────────────
  Widget _buildCameraFeed() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
              context, mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(8, 8), blurRadius: 16),
          BoxShadow(
              color: Color(0xFF1e293b), offset: Offset(-8, -8), blurRadius: 16),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context, mobile: 6, tablet: 7, desktop: 8),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(
                context, mobile: 14, tablet: 15, desktop: 16),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Live camera or fallback ──
              _buildCameraPreview(),

              // Gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF0f172a).withOpacity(0.5),
                      ],
                    ),
                  ),
                ),
              ),

              // Recording indicator badge (top-right)
              if (isRecording)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
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
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'REC',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              _buildFaceTrackingBox(),

              if (warning != null) _buildWarningOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    // Camera initializing
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

    // Camera error
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Color(0xFF64748b), size: 48),
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

    // Live preview — mirror front camera
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationY(3.14159), // mirror effect
      child: CameraPreview(_cameraController!),
    );
  }

  // ── Face Tracking Box (unchanged logic) ─────────────────────────────────────
  Widget _buildFaceTrackingBox() {
    final boxWidth = Responsive.responsiveValue(
        context, mobile: 140.0, tablet: 170.0, desktop: 200.0);
    final boxHeight = Responsive.responsiveValue(
        context, mobile: 200.0, tablet: 240.0, desktop: 280.0);

    return AnimatedBuilder(
      animation: _faceBoxAnimation,
      builder: (context, child) {
        return Positioned(
          top: Responsive.responsiveValue(
                  context, mobile: 40.0, tablet: 50.0, desktop: 60.0) +
              _faceBoxAnimation.value.dy,
          left: Responsive.responsiveValue(
                  context, mobile: 80.0, tablet: 100.0, desktop: 120.0) +
              _faceBoxAnimation.value.dx,
          child: Container(
            width: boxWidth,
            height: boxHeight,
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF22d3ee).withOpacity(0.7),
                width: Responsive.responsiveValue(
                    context, mobile: 1.5, tablet: 1.75, desktop: 2.0),
              ),
              borderRadius: BorderRadius.circular(
                Responsive.responsiveBorderRadius(
                    context, mobile: 6, tablet: 7, desktop: 8),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22d3ee).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                _buildCornerMarker(Alignment.topLeft),
                _buildCornerMarker(Alignment.topRight),
                _buildCornerMarker(Alignment.bottomLeft),
                _buildCornerMarker(Alignment.bottomRight),
                Positioned(
                  top: -20,
                  left: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.responsivePadding(
                          context, mobile: 6, tablet: 7, desktop: 8),
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22d3ee).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'FACE DETECTED',
                      style: TextStyle(
                        color: const Color(0xFF22d3ee),
                        fontSize: Responsive.responsiveFont(
                            context, mobile: 9, tablet: 9.5, desktop: 10),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
    final bw = Responsive.responsiveValue(
        context, mobile: 1.5, tablet: 1.75, desktop: 2.0);

    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(isLeft ? -1 : 1, isTop ? -1 : 1),
        child: Container(
          width: Responsive.responsiveValue(
              context, mobile: 14.0, tablet: 15.0, desktop: 16.0),
          height: Responsive.responsiveValue(
              context, mobile: 14.0, tablet: 15.0, desktop: 16.0),
          decoration: BoxDecoration(
            border: Border(
              top: isTop
                  ? BorderSide(color: const Color(0xFF22d3ee), width: bw)
                  : BorderSide.none,
              bottom: !isTop
                  ? BorderSide(color: const Color(0xFF22d3ee), width: bw)
                  : BorderSide.none,
              left: isLeft
                  ? BorderSide(color: const Color(0xFF22d3ee), width: bw)
                  : BorderSide.none,
              right: !isLeft
                  ? BorderSide(color: const Color(0xFF22d3ee), width: bw)
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
                  padding: EdgeInsets.all(Responsive.responsivePadding(
                      context, mobile: 20, tablet: 22, desktop: 24)),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a).withOpacity(0.9),
                    border:
                        Border.all(color: Colors.red.withOpacity(0.5), width: 1),
                    borderRadius: BorderRadius.circular(
                        Responsive.responsiveBorderRadius(
                            context, mobile: 14, tablet: 15, desktop: 16)),
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
                          size: Responsive.responsiveIconSize(
                              context, mobile: 48, tablet: 56, desktop: 64),
                          color: Colors.red.shade500),
                      SizedBox(
                          height: Responsive.responsiveSpacing(
                              context, mobile: 12, tablet: 14, desktop: 16)),
                      Text(
                        warning!,
                        style: TextStyle(
                          fontSize: Responsive.responsiveFont(
                              context, mobile: 20, tablet: 24, desktop: 28),
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade500,
                          letterSpacing: 3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(
                          height: Responsive.responsiveSpacing(
                              context, mobile: 6, tablet: 7, desktop: 8)),
                      Text(
                        'Audible Alert Active',
                        style: TextStyle(
                          fontSize: Responsive.responsiveFont(
                              context, mobile: 12, tablet: 13, desktop: 14),
                          color: Colors.red.shade300,
                        ),
                      ),
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
    return Container(
      height: Responsive.responsiveHeight(
          context, mobile: 80, tablet: 88, desktop: 96),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(
                context, mobile: 20, tablet: 22, desktop: 24)),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(6, 6), blurRadius: 12),
          BoxShadow(
              color: Color(0xFF1e293b), offset: Offset(-6, -6), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // ── Clear Glasses toggle ──
          _buildStatusItem(
            active: clearGlasses,
            icon: Icons.visibility,          // glasses icon
            label: 'Clear Glasses',
            onToggle: () => setState(() => clearGlasses = !clearGlasses),
          ),

          // Divider
          Container(
            width: 1,
            height: Responsive.responsiveHeight(
                context, mobile: 40, tablet: 44, desktop: 48),
            color: const Color(0xFF1e293b),
          ),

          // ── Record button ──
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
        padding: EdgeInsets.all(Responsive.responsivePadding(
            context, mobile: 6, tablet: 7, desktop: 8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated record icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: Responsive.responsiveValue(
                  context, mobile: 40.0, tablet: 44.0, desktop: 48.0),
              height: Responsive.responsiveValue(
                  context, mobile: 40.0, tablet: 44.0, desktop: 48.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0f172a),
                borderRadius: BorderRadius.circular(
                    Responsive.responsiveBorderRadius(
                        context, mobile: 10, tablet: 11, desktop: 12)),
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
                size: Responsive.responsiveIconSize(
                    context, mobile: 20, tablet: 22, desktop: 24),
                color: isRecording ? Colors.red : const Color(0xFF64748b),
              ),
            ),
            SizedBox(
                width: Responsive.responsiveSpacing(
                    context, mobile: 8, tablet: 12, desktop: 16)),
            Text(
              isRecording ? 'Stop Rec' : 'Record',
              style: TextStyle(
                fontSize: Responsive.responsiveFont(
                    context, mobile: 13, tablet: 14, desktop: 16),
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
        padding: EdgeInsets.all(Responsive.responsivePadding(
            context, mobile: 6, tablet: 7, desktop: 8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: Responsive.responsiveValue(
                  context, mobile: 40.0, tablet: 44.0, desktop: 48.0),
              height: Responsive.responsiveValue(
                  context, mobile: 40.0, tablet: 44.0, desktop: 48.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0f172a),
                borderRadius: BorderRadius.circular(
                    Responsive.responsiveBorderRadius(
                        context, mobile: 10, tablet: 11, desktop: 12)),
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
              child: Icon(
                icon,
                size: Responsive.responsiveIconSize(
                    context, mobile: 20, tablet: 22, desktop: 24),
                color: active
                    ? const Color(0xFF22d3ee)
                    : const Color(0xFF64748b),
              ),
            ),
            SizedBox(
                width: Responsive.responsiveSpacing(
                    context, mobile: 8, tablet: 12, desktop: 16)),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                      context, mobile: 13, tablet: 14, desktop: 16),
                  fontWeight: FontWeight.w500,
                  color: active
                      ? const Color(0xFF22d3ee)
                      : const Color(0xFF64748b),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Metrics Sidebar (unchanged) ──────────────────────────────────────────────
  Widget _buildMetricsSidebar() {
    final isDesktop = Responsive.isDesktop(context);
    final spacing = SizedBox(
        height: Responsive.responsiveSpacing(
            context, mobile: 16, tablet: 20, desktop: 24));

    final cards = [
      _buildMetricCard(
          label: 'Alertness',
          value: alertness,
          color: const Color(0xFF22d3ee),
          icon: Icons.bolt,
          reverse: false),
      spacing,
      _buildMetricCard(
          label: 'Drowsiness',
          value: drowsiness,
          color: Colors.red.shade500,
          icon: Icons.visibility_off,
          reverse: true),
      spacing,
      _buildMetricCard(
          label: 'Distraction',
          value: distraction,
          color: const Color(0xFFfbbf24),
          icon: Icons.visibility,
          reverse: true),
      spacing,
    ];

    return Column(
      children: [
        ...cards,
        isDesktop
            ? Expanded(child: _buildSystemLog())
            : SizedBox(
                height: Responsive.responsiveHeight(
                    context, mobile: 250, tablet: 300, desktop: 350),
                child: _buildSystemLog(),
              ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String label,
    required double value,
    required Color color,
    required IconData icon,
    required bool reverse,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(
                context, mobile: 20, tablet: 22, desktop: 24)),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(6, 6), blurRadius: 12),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-6, -6),
              blurRadius: 12),
        ],
      ),
      padding: EdgeInsets.all(Responsive.responsivePadding(
          context, mobile: 20, tablet: 22, desktop: 24)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(Responsive.responsivePadding(
                        context, mobile: 6, tablet: 7, desktop: 8)),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1e293b),
                      borderRadius: BorderRadius.circular(
                          Responsive.responsiveBorderRadius(
                              context, mobile: 6, tablet: 7, desktop: 8)),
                    ),
                    child: Icon(icon,
                        size: Responsive.responsiveIconSize(
                            context, mobile: 18, tablet: 19, desktop: 20),
                        color: color),
                  ),
                  SizedBox(
                      width: Responsive.responsiveSpacing(
                          context, mobile: 10, tablet: 11, desktop: 12)),
                  Text(label,
                      style: TextStyle(
                        color: const Color(0xFFcbd5e1),
                        fontSize: Responsive.responsiveFont(
                            context, mobile: 15, tablet: 15.5, desktop: 16),
                        fontWeight: FontWeight.w500,
                      )),
                ],
              ),
              Text('${value.toInt()}%',
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                        context, mobile: 18, tablet: 19, desktop: 20),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: color,
                  )),
            ],
          ),
          SizedBox(
              height: Responsive.responsiveSpacing(
                  context, mobile: 12, tablet: 14, desktop: 16)),
          Container(
            height: Responsive.responsiveHeight(
                context, mobile: 14, tablet: 15, desktop: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              borderRadius: BorderRadius.circular(
                  Responsive.responsiveBorderRadius(
                      context, mobile: 6, tablet: 7, desktop: 8)),
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
              borderRadius: BorderRadius.circular(
                  Responsive.responsiveBorderRadius(
                      context, mobile: 6, tablet: 7, desktop: 8)),
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
                      borderRadius: BorderRadius.circular(
                          Responsive.responsiveBorderRadius(
                              context, mobile: 6, tablet: 7, desktop: 8)),
                    ),
                  ),
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
        borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(
                context, mobile: 20, tablet: 22, desktop: 24)),
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
      padding: EdgeInsets.all(Responsive.responsivePadding(
          context, mobile: 20, tablet: 22, desktop: 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SYSTEM LOG',
              style: TextStyle(
                color: const Color(0xFF94a3b8),
                fontSize: Responsive.responsiveFont(
                    context, mobile: 11, tablet: 11.5, desktop: 12),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              )),
          SizedBox(
              height: Responsive.responsiveSpacing(
                  context, mobile: 12, tablet: 14, desktop: 16)),
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
      padding: EdgeInsets.only(
          bottom: Responsive.responsiveSpacing(
              context, mobile: 10, tablet: 11, desktop: 12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('[$time]',
              style: TextStyle(
                color: const Color(0xFF475569),
                fontSize: Responsive.responsiveFont(
                    context, mobile: 10, tablet: 10.5, desktop: 11),
                fontFamily: 'monospace',
              )),
          SizedBox(
              width: Responsive.responsiveSpacing(
                  context, mobile: 10, tablet: 11, desktop: 12)),
          Expanded(
            child: Text(message,
                style: TextStyle(
                  color: color,
                  fontSize: Responsive.responsiveFont(
                      context, mobile: 10, tablet: 10.5, desktop: 11),
                  fontFamily: 'monospace',
                )),
          ),
        ],
      ),
    );
  }
}

enum LogType { info, warning, success }