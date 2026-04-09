import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows only on the very first app launch.
/// Call [OnboardingScreen.markSeen] after the user completes it.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  static const _prefKey = 'onboarding_complete';

  static Future<bool> hasBeenSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.videocam_rounded,
      title: 'Live Monitoring',
      subtitle: 'Real-time dashcam feed with AI-powered driver alertness detection — always watching, always aware.',
      accent: Color(0xFF00D4FF),
    ),
    _OnboardingPage(
      icon: Icons.bar_chart_rounded,
      title: 'Drive Analytics',
      subtitle: 'Review your trips with detailed logs, speed graphs, and safety scores every time you park.',
      accent: Color(0xFF00D4FF),
    ),
    _OnboardingPage(
      icon: Icons.notifications_active_rounded,
      title: 'Instant Alerts',
      subtitle: 'Drowsiness, distraction, and harsh-braking alerts delivered instantly — before it becomes a risk.',
      accent: Color(0xFF00D4FF),
    ),
    _OnboardingPage(
      icon: Icons.history_rounded,
      title: 'Trip History',
      subtitle: 'Every journey stored safely on-device. Browse, filter, and replay any drive from your history.',
      accent: Color(0xFF00D4FF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await OnboardingScreen.markSeen();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: const Color(0xFF080E1A),
        // Prevent the onboarding from being affected by keyboard or
        // system UI insets that could cause layout shifts
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Background grid
            CustomPaint(
              painter: _OBGridPainter(),
              size: MediaQuery.of(context).size,
            ),

            // Ambient top glow
            Positioned(
              top: -100,
              left: 0,
              right: 0,
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00D4FF).withOpacity(0.07),
                      Colors.transparent,
                    ],
                    radius: 0.8,
                  ),
                ),
              ),
            ),

            // Content
            SafeArea(
              child: Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00D4FF).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF00D4FF).withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(Icons.show_chart,
                                  size: 18, color: Color(0xFF00D4FF)),
                            ),
                            const SizedBox(width: 8),
                            RichText(
                              text: const TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'BANTAY ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'DRIVE',
                                    style: TextStyle(
                                      color: Color(0xFF00D4FF),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_currentPage < _pages.length - 1)
                          GestureDetector(
                            onTap: _finish,
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Page view — Expanded so it takes all remaining space
                  Expanded(
                    child: PageView.builder(
                      controller: _pageCtrl,
                      itemCount: _pages.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (_, i) =>
                          _OnboardingPageWidget(page: _pages[i]),
                    ),
                  ),

                  // Dots + button — fixed at bottom, no overflow possible
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _pages.length,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeInOutCubic,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _currentPage ? 24 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _currentPage
                                    ? const Color(0xFF00D4FF)
                                    : Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: GestureDetector(
                            onTap: _nextPage,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 280),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF00B8D9),
                                    Color(0xFF00D4FF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00D4FF)
                                        .withOpacity(0.25),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _currentPage < _pages.length - 1
                                          ? 'Next'
                                          : 'Get Started',
                                      style: const TextStyle(
                                        color: Color(0xFF080E1A),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      _currentPage < _pages.length - 1
                                          ? Icons.arrow_forward_rounded
                                          : Icons.check_rounded,
                                      color: const Color(0xFF080E1A),
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Individual page data ───────────────────────────────────────────────────────
class _OnboardingPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });
}

// ── Individual page widget ─────────────────────────────────────────────────────
class _OnboardingPageWidget extends StatefulWidget {
  final _OnboardingPage page;
  const _OnboardingPageWidget({required this.page});

  @override
  State<_OnboardingPageWidget> createState() => _OnboardingPageWidgetState();
}

class _OnboardingPageWidgetState extends State<_OnboardingPageWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _iconScale;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();

    _iconScale = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic)));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use LayoutBuilder so the icon size scales down on small/landscape screens
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxHeight < 500;
        final iconOuter = isCompact ? 120.0 : 160.0;
        final iconMid   = isCompact ?  90.0 : 120.0;
        final iconInner = isCompact ?  60.0 :  80.0;
        final iconSize  = isCompact ?  26.0 :  36.0;
        final vGap1     = isCompact ?  24.0 :  48.0;
        final vGap2     = isCompact ?   8.0 :  16.0;
        final vGap3     = isCompact ?  12.0 :  24.0;

        return SingleChildScrollView(
          // Allow scrolling on very small screens so nothing overflows
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon
                  ScaleTransition(
                    scale: _iconScale,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: iconOuter, height: iconOuter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              const Color(0xFF00D4FF).withOpacity(0.10),
                              Colors.transparent,
                            ]),
                          ),
                        ),
                        Container(
                          width: iconMid, height: iconMid,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0D1627),
                            border: Border.all(
                              color: const Color(0xFF00D4FF).withOpacity(0.18),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D4FF).withOpacity(0.08),
                                blurRadius: 30, spreadRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: iconInner, height: iconInner,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00D4FF).withOpacity(0.12),
                          ),
                          child: Icon(widget.page.icon,
                              size: iconSize, color: const Color(0xFF00D4FF)),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: vGap1),

                  // Title
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Text(
                        widget.page.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isCompact ? 22 : 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: vGap2),

                  // Subtitle
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Text(
                        widget.page.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.50),
                          fontSize: isCompact ? 13 : 15,
                          height: 1.6,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: vGap3),

                  // Accent line
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Container(
                        width: 40, height: 2,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D4FF).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Background grid painter ────────────────────────────────────────────────────
class _OBGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.02)
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
  bool shouldRepaint(_OBGridPainter _) => false;
}