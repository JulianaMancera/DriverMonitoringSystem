import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/responsive.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ─── Metrics State ────────────────────────────────────────────────────────
  double alertness = 85;
  double drowsiness = 12;
  double distraction = 5;

  // ─── Environment State ────────────────────────────────────────────────────
  bool sunglasses = false;
  bool isDay = true;

  // ─── Warning State ────────────────────────────────────────────────────────
  String? warning;

  // ─── Simulation Timer ─────────────────────────────────────────────────────
  Timer? _simulationTimer;

  // ─── Animation Controllers ────────────────────────────────────────────────
  late AnimationController _faceBoxController;
  late Animation<Offset> _faceBoxAnimation;
  late AnimationController _warningController;
  late Animation<double> _warningAnimation;

  final Random _random = Random();

  // ─── Camera State ─────────────────────────────────────────────────────────
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _cameraPermissionDenied = false;
  bool _isInitializingCamera = false;

  static const String driverImage =
      'https://images.unsplash.com/photo-1559840251-14feeadb3bd7?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w3Nzg4Nzd8MHwxfHNlYXJjaHwxfHxjYXIlMjBkcml2ZXIlMjBmYWNlJTIwY2xvc2UlMjB1cCUyMG1vbml0b3Jpbmd8ZW58MXx8fHwxNzcwNDU2NzE1fDA&ixlib=rb-4.1.0&q=80&w=1080';

  // ─── System Log Entries ───────────────────────────────────────────────────
  final List<_LogEntry> _logEntries = [];

  @override
  void initState() {
    super.initState();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Face box animation
    _faceBoxController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _faceBoxAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(10, 5)).animate(
          CurvedAnimation(parent: _faceBoxController, curve: Curves.easeInOut),
        );

    // Warning pulse animation
    _warningController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);

    _warningAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _warningController, curve: Curves.easeInOut));

    // Initial log entries
    _addLog('System Initialized', LogType.info);

    // Initialize camera then start simulation
    _initializeCamera();
    _startSimulation();
  }

  // ─── App Lifecycle ────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCameraInitialized && !_cameraPermissionDenied) {
        _initializeCamera();
      }
    }
  }

  // ─── Camera Init ──────────────────────────────────────────────────────────
  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) return;
    setState(() => _isInitializingCamera = true);

    try {
      // Request permission
      final status = await Permission.camera.request();

      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            _cameraPermissionDenied = true;
            _isInitializingCamera = false;
          });
          _addLog('Camera permission permanently denied', LogType.warning);
        }
        openAppSettings();
        return;
      }

      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            _cameraPermissionDenied = true;
            _isInitializingCamera = false;
          });
          _addLog('Camera permission denied', LogType.warning);
        }
        return;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) setState(() => _isInitializingCamera = false);
        _addLog('No cameras found on device', LogType.warning);
        return;
      }

      // Prefer front camera for driver monitoring
      final targetCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        targetCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _isInitializingCamera = false;
        _cameraPermissionDenied = false;
      });

      _addLog('Camera initialized (${targetCamera.lensDirection.name})', LogType.success);
      _addLog('Face Tracking Active', LogType.success);

    } on CameraException catch (e) {
      debugPrint('CameraException: ${e.code} — ${e.description}');
      if (mounted) {
        setState(() => _isInitializingCamera = false);
        _addLog('Camera error: ${e.code}', LogType.warning);
      }
    } catch (e) {
      debugPrint('Unknown camera error: $e');
      if (mounted) {
        setState(() => _isInitializingCamera = false);
        _addLog('Camera unavailable — using fallback', LogType.warning);
      }
    }
  }

  Future<void> _disposeCamera() async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
    }
    if (mounted) setState(() => _isCameraInitialized = false);
  }

  // ─── Simulation ───────────────────────────────────────────────────────────
  void _startSimulation() {
    _addLog('Baseline Established', LogType.info);

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        drowsiness = (drowsiness + (_random.nextDouble() * 4 - 1.5))
            .clamp(0.0, 100.0);
        alertness = (100 - drowsiness - (_random.nextDouble() * 5))
            .clamp(0.0, 100.0);
        distraction = (distraction + (_random.nextDouble() * 6 - 3))
            .clamp(0.0, 100.0);

        final prevWarning = warning;

        if (drowsiness > 40) {
          warning = 'DROWSINESS DETECTED';
          if (prevWarning != warning) {
            _addLog('Microsleep / eye-closure detected', LogType.warning);
          }
        } else if (distraction > 30) {
          warning = 'DISTRACTION DETECTED';
          if (prevWarning != warning) {
            _addLog('Gaze diversion > 2s', LogType.warning);
          }
        } else {
          warning = null;
        }
      });
    });
  }

  // ─── Logging ──────────────────────────────────────────────────────────────
  void _addLog(String message, LogType type) {
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}';
    if (mounted) {
      setState(() {
        _logEntries.insert(0, _LogEntry(time: time, message: message, type: type));
        if (_logEntries.length > 20) _logEntries.removeLast();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _simulationTimer?.cancel();
    _faceBoxController.dispose();
    _warningController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Container(
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context,
            mobile: 16, tablet: 20, desktop: 16),
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
                height: Responsive.responsiveSpacing(context,
                    mobile: 16, tablet: 20, desktop: 24),
              ),
              _buildEnvironmentBar(),
            ],
          ),
        ),
        SizedBox(
          width: Responsive.responsiveSpacing(context,
              mobile: 16, tablet: 24, desktop: 32),
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
            height: Responsive.responsiveSpacing(context,
                mobile: 16, tablet: 20, desktop: 24),
          ),
          _buildEnvironmentBar(),
          SizedBox(
            height: Responsive.responsiveSpacing(context,
                mobile: 16, tablet: 20, desktop: 24),
          ),
          _buildMetricsSidebar(),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  // ─── Camera Feed ──────────────────────────────────────────────────────────
  Widget _buildCameraFeed() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context,
              mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(8, 8),
            blurRadius: 16,
          ),
          BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-8, -8),
            blurRadius: 16,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context, mobile: 6, tablet: 7, desktop: 8),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(context,
                mobile: 14, tablet: 15, desktop: 16),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview or fallback
              _buildCameraOrFallback(),

              // Bottom gradient vignette
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

              // Top-left status chip
              Positioned(
                top: 12,
                left: 12,
                child: _buildStatusChip(),
              ),

              // Top-right camera indicator
              Positioned(
                top: 12,
                right: 12,
                child: _buildRecordingDot(),
              ),

              // Face tracking box (only when camera or image is ready)
              if (!_cameraPermissionDenied) _buildFaceTrackingBox(),

              // Warning overlay
              if (warning != null) _buildWarningOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraOrFallback() {
    // ── Permission denied state ──
    if (_cameraPermissionDenied) {
      return Container(
        color: const Color(0xFF0f172a),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Color(0xFF64748b),
              size: 56,
            ),
            const SizedBox(height: 16),
            const Text(
              'Camera access required',
              style: TextStyle(
                color: Color(0xFFcbd5e1),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enable camera permission for driver monitoring',
              style: TextStyle(color: Color(0xFF64748b), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                await openAppSettings();
                // Re-try after returning from settings
                await Future.delayed(const Duration(seconds: 1));
                setState(() => _cameraPermissionDenied = false);
                _initializeCamera();
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22d3ee),
                foregroundColor: const Color(0xFF0f172a),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    // ── Camera live preview ──
    if (_isCameraInitialized && _cameraController != null) {
      final previewSize = _cameraController!.value.previewSize;
      if (previewSize != null) {
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            // Swap width/height for portrait sensor on mobile
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(_cameraController!),
          ),
        );
      }
      return CameraPreview(_cameraController!);
    }

    // ── Loading / fallback image ──
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: driverImage,
          fit: BoxFit.cover,
          color: Colors.white.withOpacity(0.8),
          colorBlendMode: BlendMode.modulate,
          placeholder: (context, url) => Container(
            color: const Color(0xFF0b1120),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFF22d3ee)),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: const Color(0xFF0b1120),
            child: Icon(
              Icons.person_outline,
              size: Responsive.responsiveIconSize(context,
                  mobile: 48, tablet: 56, desktop: 64),
              color: const Color(0xFF64748b),
            ),
          ),
        ),
        // Spinner overlay while camera initialises
        if (_isInitializingCamera)
          Container(
            color: Colors.black54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: Color(0xFF22d3ee),
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Initializing camera…',
                  style: TextStyle(
                    color: const Color(0xFF22d3ee),
                    fontSize: Responsive.responsiveFont(context,
                        mobile: 13, tablet: 14, desktop: 15),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Status chip top-left
  Widget _buildStatusChip() {
    final isActive = _isCameraInitialized && !_cameraPermissionDenied;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a).withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? const Color(0xFF10b981).withOpacity(0.5)
              : const Color(0xFF64748b).withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF10b981)
                  : const Color(0xFF64748b),
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFF10b981).withOpacity(0.5),
                        blurRadius: 6,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isActive ? 'LIVE' : (_isInitializingCamera ? 'INIT' : 'DEMO'),
            style: TextStyle(
              color: isActive
                  ? const Color(0xFF10b981)
                  : const Color(0xFF64748b),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  // Recording dot top-right
  Widget _buildRecordingDot() {
    if (!_isCameraInitialized) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _warningAnimation,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF0f172a).withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_outlined,
                color: Colors.red.withOpacity(0.7 + 0.3 * _warningAnimation.value),
                size: 14,
              ),
              const SizedBox(width: 5),
              const Text(
                'REC',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Face Tracking Box ────────────────────────────────────────────────────
  Widget _buildFaceTrackingBox() {
    final boxW = Responsive.responsiveValue(context,
        mobile: 140.0, tablet: 170.0, desktop: 200.0);
    final boxH = Responsive.responsiveValue(context,
        mobile: 200.0, tablet: 240.0, desktop: 280.0);
    final startLeft = Responsive.responsiveValue(context,
        mobile: 80.0, tablet: 100.0, desktop: 120.0);
    final startTop = Responsive.responsiveValue(context,
        mobile: 40.0, tablet: 50.0, desktop: 60.0);

    return AnimatedBuilder(
      animation: _faceBoxAnimation,
      builder: (context, _) {
        return Positioned(
          top: startTop + _faceBoxAnimation.value.dy,
          left: startLeft + _faceBoxAnimation.value.dx,
          child: SizedBox(
            width: boxW,
            height: boxH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Main border
                Container(
                  width: boxW,
                  height: boxH,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF22d3ee).withOpacity(0.65),
                      width: Responsive.responsiveValue(context,
                          mobile: 1.5, tablet: 1.75, desktop: 2.0),
                    ),
                    borderRadius: BorderRadius.circular(
                      Responsive.responsiveBorderRadius(context,
                          mobile: 6, tablet: 7, desktop: 8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22d3ee).withOpacity(0.25),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),

                // Corner markers
                _buildCornerMarker(Alignment.topLeft),
                _buildCornerMarker(Alignment.topRight),
                _buildCornerMarker(Alignment.bottomLeft),
                _buildCornerMarker(Alignment.bottomRight),

                // Label
                Positioned(
                  top: -22,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22d3ee).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'FACE DETECTED',
                      style: TextStyle(
                        color: const Color(0xFF22d3ee),
                        fontSize: Responsive.responsiveFont(context,
                            mobile: 9, tablet: 9.5, desktop: 10),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                // Confidence score
                Positioned(
                  bottom: -22,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22d3ee).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CONF: ${(90 + _random.nextInt(9)).toString()}%',
                      style: TextStyle(
                        color: const Color(0xFF22d3ee),
                        fontSize: Responsive.responsiveFont(context,
                            mobile: 9, tablet: 9.5, desktop: 10),
                        fontFamily: 'monospace',
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
    final size = Responsive.responsiveValue(context,
        mobile: 14.0, tablet: 15.0, desktop: 16.0);
    final strokeW = Responsive.responsiveValue(context,
        mobile: 1.5, tablet: 1.75, desktop: 2.0);

    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(isLeft ? -1 : 1, isTop ? -1 : 1),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border(
              top: isTop
                  ? BorderSide(color: const Color(0xFF22d3ee), width: strokeW)
                  : BorderSide.none,
              bottom: !isTop
                  ? BorderSide(color: const Color(0xFF22d3ee), width: strokeW)
                  : BorderSide.none,
              left: isLeft
                  ? BorderSide(color: const Color(0xFF22d3ee), width: strokeW)
                  : BorderSide.none,
              right: !isLeft
                  ? BorderSide(color: const Color(0xFF22d3ee), width: strokeW)
                  : BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Warning Overlay ──────────────────────────────────────────────────────
  Widget _buildWarningOverlay() {
    return AnimatedBuilder(
      animation: _warningAnimation,
      builder: (context, _) {
        return Container(
          color: Colors.red.withOpacity(0.35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Center(
              child: Transform.scale(
                scale: _warningAnimation.value,
                child: Container(
                  padding: EdgeInsets.all(
                    Responsive.responsivePadding(context,
                        mobile: 20, tablet: 22, desktop: 24),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a).withOpacity(0.92),
                    border: Border.all(
                        color: Colors.red.withOpacity(0.45), width: 1),
                    borderRadius: BorderRadius.circular(
                      Responsive.responsiveBorderRadius(context,
                          mobile: 14, tablet: 15, desktop: 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.35),
                        blurRadius: 50,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: Responsive.responsiveIconSize(context,
                            mobile: 48, tablet: 56, desktop: 64),
                        color: Colors.red.shade400,
                      ),
                      SizedBox(
                        height: Responsive.responsiveSpacing(context,
                            mobile: 12, tablet: 14, desktop: 16),
                      ),
                      Text(
                        warning!,
                        style: TextStyle(
                          fontSize: Responsive.responsiveFont(context,
                              mobile: 20, tablet: 24, desktop: 28),
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade400,
                          letterSpacing: 3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(
                        height: Responsive.responsiveSpacing(context,
                            mobile: 6, tablet: 7, desktop: 8),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_up_outlined,
                              color: Colors.red.shade300, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Audible Alert Active',
                            style: TextStyle(
                              fontSize: Responsive.responsiveFont(context,
                                  mobile: 12, tablet: 13, desktop: 14),
                              color: Colors.red.shade300,
                            ),
                          ),
                        ],
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

  // ─── Environment Bar ──────────────────────────────────────────────────────
  Widget _buildEnvironmentBar() {
    return Container(
      height: Responsive.responsiveHeight(context,
          mobile: 80, tablet: 88, desktop: 96),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context,
              mobile: 20, tablet: 22, desktop: 24),
        ),
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
          _buildStatusItem(
            active: sunglasses,
            icon: Icons.wb_sunny_outlined,
            label: 'Sunglasses',
            onToggle: () => setState(() => sunglasses = !sunglasses),
          ),
          Container(
            width: 1,
            height: Responsive.responsiveHeight(context,
                mobile: 40, tablet: 44, desktop: 48),
            color: const Color(0xFF1e293b),
          ),
          _buildStatusItem(
            active: isDay,
            icon: isDay ? Icons.wb_sunny : Icons.nightlight_round,
            label: isDay ? 'Day Time' : 'Night Time',
            onToggle: () => setState(() => isDay = !isDay),
          ),
          Container(
            width: 1,
            height: Responsive.responsiveHeight(context,
                mobile: 40, tablet: 44, desktop: 48),
            color: const Color(0xFF1e293b),
          ),
          // Camera toggle
          _buildStatusItem(
            active: _isCameraInitialized,
            icon: _isCameraInitialized
                ? Icons.videocam_outlined
                : Icons.videocam_off_outlined,
            label: _isCameraInitialized ? 'Camera On' : 'Camera Off',
            onToggle: () async {
              if (_isCameraInitialized) {
                await _disposeCamera();
                _addLog('Camera disabled by user', LogType.info);
              } else {
                setState(() => _cameraPermissionDenied = false);
                await _initializeCamera();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onToggle,
  }) {
    final iconSize = Responsive.responsiveValue(context,
        mobile: 40.0, tablet: 44.0, desktop: 48.0);

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.all(
          Responsive.responsivePadding(context, mobile: 6, tablet: 7, desktop: 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: const Color(0xFF0f172a),
                borderRadius: BorderRadius.circular(
                  Responsive.responsiveBorderRadius(context,
                      mobile: 10, tablet: 11, desktop: 12),
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: const Color(0xFF0b1120).withOpacity(0.8),
                          offset: const Offset(3, 3),
                          blurRadius: 6,
                        ),
                        BoxShadow(
                          color: const Color(0xFF1e293b).withOpacity(0.8),
                          offset: const Offset(-3, -3),
                          blurRadius: 6,
                        ),
                      ]
                    : const [
                        BoxShadow(
                          color: Color(0xFF0b1120),
                          offset: Offset(4, 4),
                          blurRadius: 8,
                        ),
                        BoxShadow(
                          color: Color(0xFF1e293b),
                          offset: Offset(-4, -4),
                          blurRadius: 8,
                        ),
                      ],
              ),
              child: Icon(
                icon,
                size: Responsive.responsiveIconSize(context,
                    mobile: 20, tablet: 22, desktop: 24),
                color: active
                    ? const Color(0xFF22d3ee)
                    : const Color(0xFF64748b),
              ),
            ),
            SizedBox(
              width: Responsive.responsiveSpacing(context,
                  mobile: 8, tablet: 12, desktop: 16),
            ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(context,
                      mobile: 13, tablet: 14, desktop: 16),
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

  // ─── Metrics Sidebar ──────────────────────────────────────────────────────
  Widget _buildMetricsSidebar() {
    final isDesktop = Responsive.isDesktop(context);

    final metrics = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMetricCard(
          label: 'Alertness',
          value: alertness,
          color: const Color(0xFF22d3ee),
          icon: Icons.bolt,
        ),
        SizedBox(
          height: Responsive.responsiveSpacing(context,
              mobile: 16, tablet: 20, desktop: 24),
        ),
        _buildMetricCard(
          label: 'Drowsiness',
          value: drowsiness,
          color: Colors.red.shade500,
          icon: Icons.visibility_off,
        ),
        SizedBox(
          height: Responsive.responsiveSpacing(context,
              mobile: 16, tablet: 20, desktop: 24),
        ),
        _buildMetricCard(
          label: 'Distraction',
          value: distraction,
          color: const Color(0xFFfbbf24),
          icon: Icons.visibility,
        ),
        SizedBox(
          height: Responsive.responsiveSpacing(context,
              mobile: 16, tablet: 20, desktop: 24),
        ),
      ],
    );

    if (isDesktop) {
      return Column(
        children: [
          metrics,
          Expanded(child: _buildSystemLog()),
        ],
      );
    }

    return Column(
      children: [
        metrics,
        SizedBox(
          height: Responsive.responsiveHeight(context,
              mobile: 250, tablet: 300, desktop: 350),
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
  }) {
    // Determine severity colour override
    Color barColor = color;
    if (label == 'Drowsiness' && value > 40) {
      barColor = Colors.red.shade700;
    } else if (label == 'Distraction' && value > 30) {
      barColor = Colors.orange.shade600;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context,
              mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(6, 6), blurRadius: 12),
          BoxShadow(
              color: Color(0xFF1e293b), offset: Offset(-6, -6), blurRadius: 12),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context,
            mobile: 20, tablet: 22, desktop: 24),
      ),
      child: Column(
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(
                      Responsive.responsivePadding(context,
                          mobile: 6, tablet: 7, desktop: 8),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1e293b),
                      borderRadius: BorderRadius.circular(
                        Responsive.responsiveBorderRadius(context,
                            mobile: 6, tablet: 7, desktop: 8),
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: Responsive.responsiveIconSize(context,
                          mobile: 18, tablet: 19, desktop: 20),
                      color: barColor,
                    ),
                  ),
                  SizedBox(
                    width: Responsive.responsiveSpacing(context,
                        mobile: 10, tablet: 11, desktop: 12),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: const Color(0xFFcbd5e1),
                      fontSize: Responsive.responsiveFont(context,
                          mobile: 15, tablet: 15.5, desktop: 16),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Text(
                '${value.toInt()}%',
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(context,
                      mobile: 18, tablet: 19, desktop: 20),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: barColor,
                ),
              ),
            ],
          ),

          SizedBox(
            height: Responsive.responsiveSpacing(context,
                mobile: 12, tablet: 14, desktop: 16),
          ),

          // Progress bar
          Container(
            height: Responsive.responsiveHeight(context,
                mobile: 14, tablet: 15, desktop: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              borderRadius: BorderRadius.circular(
                Responsive.responsiveBorderRadius(context,
                    mobile: 6, tablet: 7, desktop: 8),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0b1120).withOpacity(0.5),
                  offset: const Offset(2, 2),
                  blurRadius: 4,
                ),
                BoxShadow(
                  color: const Color(0xFF1e293b).withOpacity(0.5),
                  offset: const Offset(-2, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                Responsive.responsiveBorderRadius(context,
                    mobile: 6, tablet: 7, desktop: 8),
              ),
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                widthFactor: value / 100,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(
                      Responsive.responsiveBorderRadius(context,
                          mobile: 6, tablet: 7, desktop: 8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: barColor.withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── System Log ───────────────────────────────────────────────────────────
  Widget _buildSystemLog() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(context,
              mobile: 20, tablet: 22, desktop: 24),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0b1120).withOpacity(0.5),
            offset: const Offset(4, 4),
            blurRadius: 8,
          ),
          BoxShadow(
            color: const Color(0xFF1e293b).withOpacity(0.5),
            offset: const Offset(-4, -4),
            blurRadius: 8,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(context,
            mobile: 20, tablet: 22, desktop: 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SYSTEM LOG',
                style: TextStyle(
                  color: const Color(0xFF94a3b8),
                  fontSize: Responsive.responsiveFont(context,
                      mobile: 11, tablet: 11.5, desktop: 12),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '${_logEntries.length} entries',
                style: TextStyle(
                  color: const Color(0xFF475569),
                  fontSize: Responsive.responsiveFont(context,
                      mobile: 10, tablet: 10.5, desktop: 11),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(context,
                mobile: 12, tablet: 14, desktop: 16),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _logEntries.length,
              itemBuilder: (_, i) {
                final e = _logEntries[i];
                return _buildLogEntry(e.time, e.message, e.type);
              },
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
        break;
      case LogType.warning:
        color = const Color(0xFFfbbf24);
        break;
      case LogType.success:
        color = const Color(0xFF10b981);
        break;
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: Responsive.responsiveSpacing(context,
            mobile: 10, tablet: 11, desktop: 12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type indicator dot
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Text(
            '[$time]',
            style: TextStyle(
              color: const Color(0xFF475569),
              fontSize: Responsive.responsiveFont(context,
                  mobile: 10, tablet: 10.5, desktop: 11),
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(
            width: Responsive.responsiveSpacing(context,
                mobile: 8, tablet: 10, desktop: 12),
          ),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: Responsive.responsiveFont(context,
                    mobile: 10, tablet: 10.5, desktop: 11),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────
enum LogType { info, warning, success }

class _LogEntry {
  final String time;
  final String message;
  final LogType type;
  const _LogEntry({
    required this.time,
    required this.message,
    required this.type,
  });
}