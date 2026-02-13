import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
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
  bool sunglasses = false;
  bool isDay = true;

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

  // Mock driver image
  static const String driverImage =
      "https://images.unsplash.com/photo-1559840251-14feeadb3bd7?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w3Nzg4Nzd8MHwxfHNlYXJjaHwxfHxjYXIlMjBkcml2ZXIlMjBmYWNlJTIwY2xvc2UlMjB1cCUyMG1vbml0b3Jpbmd8ZW58MXx8fHwxNzcwNDU2NzE1fDA&ixlib=rb-4.1.0&q=80&w=1080";

  @override
  void initState() {
    super.initState();

    // Face box animation (moving box)
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

    // Start simulation
    _startSimulation();
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        // Update drowsiness
        drowsiness = (drowsiness + (_random.nextDouble() * 4 - 1.5))
            .clamp(0.0, 100.0);

        // Update alertness
        alertness = (100 - drowsiness - (_random.nextDouble() * 5))
            .clamp(0.0, 100.0);

        // Update distraction
        distraction = (distraction + (_random.nextDouble() * 6 - 3))
            .clamp(0.0, 100.0);

        // Trigger warnings
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Container(
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 16,
          tablet: 20,
          desktop: 16,
        ),
      ),
      child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left side - Camera feed
        Expanded(
          flex: 8,
          child: Column(
            children: [
              Expanded(child: _buildCameraFeed()),
              SizedBox(
                height: Responsive.responsiveSpacing(
                  context,
                  mobile: 16,
                  tablet: 20,
                  desktop: 24,
                ),
              ),
              _buildEnvironmentBar(),
            ],
          ),
        ),
        SizedBox(
          width: Responsive.responsiveSpacing(
            context,
            mobile: 16,
            tablet: 24,
            desktop: 32,
          ),
        ),

        // Right side - Metrics
        Expanded(
          flex: 4,
          child: _buildMetricsSidebar(),
        ),
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
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _buildEnvironmentBar(),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _buildMetricsSidebar(),
          const SizedBox(height: 96), // Space for bottom nav
        ],
      ),
    );
  }

  // Camera Feed with Face Tracking
  Widget _buildCameraFeed() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
            context,
            mobile: 20,
            tablet: 22,
            desktop: 24,
          ),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(8, 8),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-8, -8),
            blurRadius: 16,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 6,
          tablet: 7,
          desktop: 8,
        ),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            Responsive.responsiveBorderRadius(
              context,
              mobile: 14,
              tablet: 15,
              desktop: 16,
            ),
          ),
          child: Stack(
            children: [
              // Driver image
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: driverImage,
                  fit: BoxFit.cover,
                  color: Colors.white.withOpacity(0.8),
                  colorBlendMode: BlendMode.modulate,
                  placeholder: (context, url) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF22d3ee),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.black,
                    child: Center(
                      child: Icon(
                        Icons.person,
                        size: Responsive.responsiveIconSize(
                          context,
                          mobile: 48,
                          tablet: 56,
                          desktop: 64,
                        ),
                        color: const Color(0xFF64748b),
                      ),
                    ),
                  ),
                ),
              ),

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

              // Face tracking box
              _buildFaceTrackingBox(),

              // Warning overlay
              if (warning != null) _buildWarningOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFaceTrackingBox() {
    final boxWidth = Responsive.responsiveValue(
      context,
      mobile: 140.0,
      tablet: 170.0,
      desktop: 200.0,
    );
    final boxHeight = Responsive.responsiveValue(
      context,
      mobile: 200.0,
      tablet: 240.0,
      desktop: 280.0,
    );

    return AnimatedBuilder(
      animation: _faceBoxAnimation,
      builder: (context, child) {
        return Positioned(
          top: Responsive.responsiveValue(
                context,
                mobile: 40.0,
                tablet: 50.0,
                desktop: 60.0,
              ) +
              _faceBoxAnimation.value.dy,
          left: Responsive.responsiveValue(
                context,
                mobile: 80.0,
                tablet: 100.0,
                desktop: 120.0,
              ) +
              _faceBoxAnimation.value.dx,
          child: Container(
            width: boxWidth,
            height: boxHeight,
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF22d3ee).withOpacity(0.7),
                width: Responsive.responsiveValue(
                  context,
                  mobile: 1.5,
                  tablet: 1.75,
                  desktop: 2.0,
                ),
              ),
              borderRadius: BorderRadius.circular(
                Responsive.responsiveBorderRadius(
                  context,
                  mobile: 6,
                  tablet: 7,
                  desktop: 8,
                ),
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
                // Corner markers
                _buildCornerMarker(Alignment.topLeft),
                _buildCornerMarker(Alignment.topRight),
                _buildCornerMarker(Alignment.bottomLeft),
                _buildCornerMarker(Alignment.bottomRight),

                // Label
                Positioned(
                  top: -20,
                  left: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.responsivePadding(
                        context,
                        mobile: 6,
                        tablet: 7,
                        desktop: 8,
                      ),
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
                          context,
                          mobile: 9,
                          tablet: 9.5,
                          desktop: 10,
                        ),
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

    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(isLeft ? -1 : 1, isTop ? -1 : 1),
        child: Container(
          width: Responsive.responsiveValue(
            context,
            mobile: 14.0,
            tablet: 15.0,
            desktop: 16.0,
          ),
          height: Responsive.responsiveValue(
            context,
            mobile: 14.0,
            tablet: 15.0,
            desktop: 16.0,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: isTop
                  ? BorderSide(
                      color: const Color(0xFF22d3ee),
                      width: Responsive.responsiveValue(
                        context,
                        mobile: 1.5,
                        tablet: 1.75,
                        desktop: 2.0,
                      ),
                    )
                  : BorderSide.none,
              bottom: !isTop
                  ? BorderSide(
                      color: const Color(0xFF22d3ee),
                      width: Responsive.responsiveValue(
                        context,
                        mobile: 1.5,
                        tablet: 1.75,
                        desktop: 2.0,
                      ),
                    )
                  : BorderSide.none,
              left: isLeft
                  ? BorderSide(
                      color: const Color(0xFF22d3ee),
                      width: Responsive.responsiveValue(
                        context,
                        mobile: 1.5,
                        tablet: 1.75,
                        desktop: 2.0,
                      ),
                    )
                  : BorderSide.none,
              right: !isLeft
                  ? BorderSide(
                      color: const Color(0xFF22d3ee),
                      width: Responsive.responsiveValue(
                        context,
                        mobile: 1.5,
                        tablet: 1.75,
                        desktop: 2.0,
                      ),
                    )
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
                  padding: EdgeInsets.all(
                    Responsive.responsivePadding(
                      context,
                      mobile: 20,
                      tablet: 22,
                      desktop: 24,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a).withOpacity(0.9),
                    border: Border.all(
                      color: Colors.red.withOpacity(0.5),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(
                      Responsive.responsiveBorderRadius(
                        context,
                        mobile: 14,
                        tablet: 15,
                        desktop: 16,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 50,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: Responsive.responsiveIconSize(
                          context,
                          mobile: 48,
                          tablet: 56,
                          desktop: 64,
                        ),
                        color: Colors.red.shade500,
                      ),
                      SizedBox(
                        height: Responsive.responsiveSpacing(
                          context,
                          mobile: 12,
                          tablet: 14,
                          desktop: 16,
                        ),
                      ),
                      Text(
                        warning!,
                        style: TextStyle(
                          fontSize: Responsive.responsiveFont(
                            context,
                            mobile: 20,
                            tablet: 24,
                            desktop: 28,
                          ),
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade500,
                          letterSpacing: 3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(
                        height: Responsive.responsiveSpacing(
                          context,
                          mobile: 6,
                          tablet: 7,
                          desktop: 8,
                        ),
                      ),
                      Text(
                        'Audible Alert Active',
                        style: TextStyle(
                          fontSize: Responsive.responsiveFont(
                            context,
                            mobile: 12,
                            tablet: 13,
                            desktop: 14,
                          ),
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

  // Environment Status Bar
  Widget _buildEnvironmentBar() {
    return Container(
      height: Responsive.responsiveHeight(
        context,
        mobile: 80,
        tablet: 88,
        desktop: 96,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
            context,
            mobile: 20,
            tablet: 22,
            desktop: 24,
          ),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(6, 6),
            blurRadius: 12,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-6, -6),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusItem(
            active: sunglasses,
            icon: Icons.wb_sunny_outlined,
            label: 'Sunglasses',
            onToggle: () {
              setState(() {
                sunglasses = !sunglasses;
              });
            },
          ),
          Container(
            width: 1,
            height: Responsive.responsiveHeight(
              context,
              mobile: 40,
              tablet: 44,
              desktop: 48,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1e293b),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF1e293b),
                  offset: Offset(1, 0),
                ),
              ],
            ),
          ),
          _buildStatusItem(
            active: isDay,
            icon: isDay ? Icons.wb_sunny : Icons.nightlight_round,
            label: isDay ? 'Day Time' : 'Night Time',
            onToggle: () {
              setState(() {
                isDay = !isDay;
              });
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
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.all(
          Responsive.responsivePadding(
            context,
            mobile: 6,
            tablet: 7,
            desktop: 8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: Responsive.responsiveValue(
                context,
                mobile: 40.0,
                tablet: 44.0,
                desktop: 48.0,
              ),
              height: Responsive.responsiveValue(
                context,
                mobile: 40.0,
                tablet: 44.0,
                desktop: 48.0,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0f172a),
                borderRadius: BorderRadius.circular(
                  Responsive.responsiveBorderRadius(
                    context,
                    mobile: 10,
                    tablet: 11,
                    desktop: 12,
                  ),
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
                    : [
                        const BoxShadow(
                          color: Color(0xFF0b1120),
                          offset: Offset(4, 4),
                          blurRadius: 8,
                        ),
                        const BoxShadow(
                          color: Color(0xFF1e293b),
                          offset: Offset(-4, -4),
                          blurRadius: 8,
                        ),
                      ],
              ),
              child: Icon(
                icon,
                size: Responsive.responsiveIconSize(
                  context,
                  mobile: 20,
                  tablet: 22,
                  desktop: 24,
                ),
                color: active
                    ? const Color(0xFF22d3ee)
                    : const Color(0xFF64748b),
              ),
            ),
            SizedBox(
              width: Responsive.responsiveSpacing(
                context,
                mobile: 8,
                tablet: 12,
                desktop: 16,
              ),
            ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                    context,
                    mobile: 13,
                    tablet: 14,
                    desktop: 16,
                  ),
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

  // Metrics Sidebar
  Widget _buildMetricsSidebar() {
    final isDesktop = Responsive.isDesktop(context);
    
    if (isDesktop) {
      // Desktop: Use Column with Expanded for System Log
      return Column(
        children: [
          _buildMetricCard(
            label: 'Alertness',
            value: alertness,
            color: const Color(0xFF22d3ee),
            icon: Icons.bolt,
            reverse: false,
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _buildMetricCard(
            label: 'Drowsiness',
            value: drowsiness,
            color: Colors.red.shade500,
            icon: Icons.visibility_off,
            reverse: true,
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _buildMetricCard(
            label: 'Distraction',
            value: distraction,
            color: const Color(0xFFfbbf24),
            icon: Icons.visibility,
            reverse: true,
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          Expanded(child: _buildSystemLog()),
        ],
      );
    } else {
      // Mobile/Tablet: Use fixed height for System Log
      return Column(
        children: [
          _buildMetricCard(
            label: 'Alertness',
            value: alertness,
            color: const Color(0xFF22d3ee),
            icon: Icons.bolt,
            reverse: false,
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _buildMetricCard(
            label: 'Drowsiness',
            value: drowsiness,
            color: Colors.red.shade500,
            icon: Icons.visibility_off,
            reverse: true,
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _buildMetricCard(
            label: 'Distraction',
            value: distraction,
            color: const Color(0xFFfbbf24),
            icon: Icons.visibility,
            reverse: true,
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          SizedBox(
            height: Responsive.responsiveHeight(
              context,
              mobile: 250,
              tablet: 300,
              desktop: 350,
            ),
            child: _buildSystemLog(),
          ),
        ],
      );
    }
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
            context,
            mobile: 20,
            tablet: 22,
            desktop: 24,
          ),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(6, 6),
            blurRadius: 12,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-6, -6),
            blurRadius: 12,
          ),
        ],
      ),
      padding: EdgeInsets.all(
        Responsive.responsivePadding(
          context,
          mobile: 20,
          tablet: 22,
          desktop: 24,
        ),
      ),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(
                      Responsive.responsivePadding(
                        context,
                        mobile: 6,
                        tablet: 7,
                        desktop: 8,
                      ),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1e293b),
                      borderRadius: BorderRadius.circular(
                        Responsive.responsiveBorderRadius(
                          context,
                          mobile: 6,
                          tablet: 7,
                          desktop: 8,
                        ),
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: Responsive.responsiveIconSize(
                        context,
                        mobile: 18,
                        tablet: 19,
                        desktop: 20,
                      ),
                      color: color,
                    ),
                  ),
                  SizedBox(
                    width: Responsive.responsiveSpacing(
                      context,
                      mobile: 10,
                      tablet: 11,
                      desktop: 12,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: const Color(0xFFcbd5e1),
                      fontSize: Responsive.responsiveFont(
                        context,
                        mobile: 15,
                        tablet: 15.5,
                        desktop: 16,
                      ),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Text(
                '${value.toInt()}%',
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                    context,
                    mobile: 18,
                    tablet: 19,
                    desktop: 20,
                  ),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: color,
                ),
              ),
            ],
          ),

          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 12,
              tablet: 14,
              desktop: 16,
            ),
          ),

          // Progress bar
          Container(
            height: Responsive.responsiveHeight(
              context,
              mobile: 14,
              tablet: 15,
              desktop: 16,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              borderRadius: BorderRadius.circular(
                Responsive.responsiveBorderRadius(
                  context,
                  mobile: 6,
                  tablet: 7,
                  desktop: 8,
                ),
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
                Responsive.responsiveBorderRadius(
                  context,
                  mobile: 6,
                  tablet: 7,
                  desktop: 8,
                ),
              ),
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
                          context,
                          mobile: 6,
                          tablet: 7,
                          desktop: 8,
                        ),
                      ),
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

  // System Log
  Widget _buildSystemLog() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(
          Responsive.responsiveBorderRadius(
            context,
            mobile: 20,
            tablet: 22,
            desktop: 24,
          ),
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
        Responsive.responsivePadding(
          context,
          mobile: 20,
          tablet: 22,
          desktop: 24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SYSTEM LOG',
            style: TextStyle(
              color: const Color(0xFF94a3b8),
              fontSize: Responsive.responsiveFont(
                context,
                mobile: 11,
                tablet: 11.5,
                desktop: 12,
              ),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(
            height: Responsive.responsiveSpacing(
              context,
              mobile: 12,
              tablet: 14,
              desktop: 16,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _buildLogEntry(
                    '10:42:01', 'System Initialized', LogType.info),
                _buildLogEntry(
                    '10:42:05', 'Face Tracking Active', LogType.success),
                _buildLogEntry(
                    '10:42:15', 'Baseline Established', LogType.info),
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
    Color color;
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
        bottom: Responsive.responsiveSpacing(
          context,
          mobile: 10,
          tablet: 11,
          desktop: 12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[$time]',
            style: TextStyle(
              color: const Color(0xFF475569),
              fontSize: Responsive.responsiveFont(
                context,
                mobile: 10,
                tablet: 10.5,
                desktop: 11,
              ),
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(
            width: Responsive.responsiveSpacing(
              context,
              mobile: 10,
              tablet: 11,
              desktop: 12,
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: Responsive.responsiveFont(
                  context,
                  mobile: 10,
                  tablet: 10.5,
                  desktop: 11,
                ),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum LogType { info, warning, success }