import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgGlowCtrl;
  late AnimationController _logoCtrl;
  late AnimationController _wordmarkCtrl;
  late AnimationController _taglineCtrl;
  late AnimationController _progressCtrl;
  late AnimationController _exitCtrl;

  late Animation<double> _bgGlow;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<Offset>  _logoSlide;
  late Animation<double> _wordmarkOpacity;
  late Animation<Offset>  _wordmarkSlide;
  late Animation<double> _taglineOpacity;
  late Animation<double> _progressValue;
  late Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    _bgGlowCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _bgGlow = CurvedAnimation(parent: _bgGlowCtrl, curve: Curves.easeInOut);

    _logoCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _logoCtrl,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(-0.25, 0.0),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));

    _wordmarkCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 700),
    );
    _wordmarkOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _wordmarkCtrl, curve: Curves.easeOut),
    );
    _wordmarkSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end:   Offset.zero,
    ).animate(
        CurvedAnimation(parent: _wordmarkCtrl, curve: Curves.easeOutCubic));

    _taglineCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut),
    );

    _progressCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1800),
    );
    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOut),
    );

    _exitCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 400),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _wordmarkCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _taglineCtrl.forward();
    _progressCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 2000));
    await _exitCtrl.forward();
    widget.onComplete();
  }

  @override
  void dispose() {
    _bgGlowCtrl.dispose();
    _logoCtrl.dispose();
    _wordmarkCtrl.dispose();
    _taglineCtrl.dispose();
    _progressCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _exitOpacity,
      builder: (context, child) =>
          Opacity(opacity: _exitOpacity.value, child: child),
      child: Scaffold(
        backgroundColor: const Color(0xFF080E1A),
        body: Stack(
          children: [
            // ── Background grid ─────────────────────────────────────────────
            CustomPaint(
              painter: _GridPainter(),
              size:    MediaQuery.of(context).size,
            ),

            // ── Radial ambient glow ─────────────────────────────────────────
            AnimatedBuilder(
              animation: _bgGlow,
              builder: (_, __) => Center(
                child: Container(
                  width:  500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF00D4FF)
                            .withOpacity(0.04 + _bgGlow.value * 0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Main content ────────────────────────────────────────────────
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Logo (car icon without text) ────────────────────────
                  // Asset path: update to match your project's asset location.
                  // Declare in pubspec.yaml under: flutter > assets
                  //   - assets/images/bantay_drive_icon.png   ← car only (Image 2)
                  SlideTransition(
                    position: _logoSlide,
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Image.asset(
                          'assets/bantay_drive_logo.png',
                          width:  220,
                          height: 160,
                          fit:    BoxFit.contain,
                          // Shows a fallback icon if the asset path isn't set yet
                          errorBuilder: (_, __, ___) => Container(
                            width:  220,
                            height: 160,
                            decoration: BoxDecoration(
                              color:         const Color(0xFF0D1627),
                              borderRadius:  BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF00D4FF).withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.directions_car_rounded,
                                size:  72,
                                color: Color(0xFF00D4FF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Wordmark ────────────────────────────────────────────
                  SlideTransition(
                    position: _wordmarkSlide,
                    child: FadeTransition(
                      opacity: _wordmarkOpacity,
                      child: Column(
                        children: [
                          RichText(
                            text: const TextSpan(
                              children: [
                                TextSpan(
                                  text: 'BANTAY ',
                                  style: TextStyle(
                                    color:         Colors.white,
                                    fontSize:      34,
                                    fontWeight:    FontWeight.w800,
                                    letterSpacing: 4,
                                    fontFamily:    'SF Pro Display',
                                  ),
                                ),
                                TextSpan(
                                  text: 'DRIVE',
                                  style: TextStyle(
                                    color:         Color(0xFF00D4FF),
                                    fontSize:      34,
                                    fontWeight:    FontWeight.w800,
                                    letterSpacing: 4,
                                    fontFamily:    'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          FadeTransition(
                            opacity: _taglineOpacity,
                            child: Text(
                              'DRIVE AWARE.  ARRIVE SAFE',
                              style: TextStyle(
                                color:         Colors.white.withOpacity(0.38),
                                fontSize:      11,
                                fontWeight:    FontWeight.w500,
                                letterSpacing: 3.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Progress bar ────────────────────────────────────────
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: SizedBox(
                      width: 180,
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: _progressValue,
                            builder: (_, __) => ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value:           _progressValue.value,
                                minHeight:       2,
                                backgroundColor: Colors.white.withOpacity(0.08),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF00D4FF)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Initializing systems...',
                            style: TextStyle(
                              color:         Colors.white.withOpacity(0.22),
                              fontSize:      11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Version stamp ────────────────────────────────────────────────
            Positioned(
              bottom: 14,
              left:   0,
              right:  0,
              child: FadeTransition(
                opacity: _taglineOpacity,
                child: Text(
                  'v1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:         Colors.white.withOpacity(0.12),
                    fontSize:      11,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subtle background grid ─────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}