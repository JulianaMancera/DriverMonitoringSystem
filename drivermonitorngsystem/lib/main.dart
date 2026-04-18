import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/database/database_helper.dart';
import 'core/services/notifications.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'utils/responsive.dart';
import 'constants/layout_constants.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'core/services/pip_service.dart';
import 'widgets/exit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // ── Brand detection — runs BEFORE runApp so scaleFactor is ready ──────────
  // Samsung One UI, MIUI, ColorOS, OriginOS all inflate default text scale
  // and UI chrome — layouts overflow on phones that report "normal" size.
  // Responsive.setBrand() applies a per-brand multiplier to every
  // sp() / rp() / rs() / ri() call in every screen.
  if (Platform.isAndroid) {
    try {
      final info  = await DeviceInfoPlugin().androidInfo;
      final brand = info.brand.toLowerCase();
      if (brand.contains('samsung')) {
  Responsive.setBrand(DeviceBrand.samsung); // change 0.95 → 0.92 in responsive.dart
      }else if (brand.contains('xiaomi') ||
                 brand.contains('redmi') ||
                 brand.contains('poco')) {
        Responsive.setBrand(DeviceBrand.xiaomi);  // 0.97× — MIUI
      } else if (brand.contains('oppo') ||
                 brand.contains('realme') ||
                 brand.contains('oneplus')) {
        Responsive.setBrand(DeviceBrand.oppo);    // 0.97× — ColorOS
      } else if (brand.contains('vivo') ||
                 brand.contains('iqoo')) {
        Responsive.setBrand(DeviceBrand.vivo);    // 0.97× — OriginOS
      } else if (brand.contains('google') ||
                 brand.contains('pixel')) {
        Responsive.setBrand(DeviceBrand.pixel);   // 1.00× — stock Android
      } else {
        Responsive.setBrand(DeviceBrand.other);   // 1.00× — unknown OEM
      }
    } catch (_) {
      Responsive.setBrand(DeviceBrand.other);
    }
  }

  await DatabaseHelper.instance.database;

  // FIX: Notification permission popup removed — foreground service only.
  // The system dialog was appearing unexpectedly on first launch.
  // BantayDriveService handles the notification channel internally.

  await BantayDriveService.initialize();

  // CRITICAL: registers the IsolateNameServer port so sendDataToMain() in the
  // background isolate can deliver messages (heartbeats, stop_recording) to the
  // main isolate's DataCallbacks. Without this call every sendDataToMain() call
  // silently drops its payload — notification Stop button never fires.
  FlutterForegroundTask.initCommunicationPort();

  runApp(const ProviderScope(child: BantayDriveApp()));
}

// ─── APP ──────────────────────────────────────────────────────────────────────

class BantayDriveApp extends StatelessWidget {
  const BantayDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Bantay Drive',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF080E1A),
          fontFamily: 'SF Pro Display',
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00D4FF),
            secondary: Color(0xFF00D4FF),
            surface: Color(0xFF0D1627),
          ),
          useMaterial3: true,
        ),
        home: const EntryPoint(),
      ),
    );
  }
}

// ─── ENTRY POINT  (splash → onboarding? → shell) ─────────────────────────────

enum _AppState { splash, onboarding, main }

class EntryPoint extends StatefulWidget {
  const EntryPoint({super.key});

  @override
  State<EntryPoint> createState() => _EntryPointState();
}

class _EntryPointState extends State<EntryPoint> {
  // DEV TOGGLE — set true temporarily to preview onboarding UI
  static const bool _forceOnboarding = false;

  _AppState _state = _AppState.splash;
  bool _onboardingNeeded = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    if (_forceOnboarding) {
      setState(() => _onboardingNeeded = true);
      return;
    }
    final seen = await OnboardingScreen.hasBeenSeen();
    setState(() => _onboardingNeeded = !seen);
  }

  void _onSplashComplete() {
    setState(() {
      _state = _onboardingNeeded ? _AppState.onboarding : _AppState.main;
    });
  }

  void _onOnboardingComplete() {
    setState(() => _state = _AppState.main);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: switch (_state) {
        _AppState.splash => SplashScreen(
          key: const ValueKey('splash'),
          onComplete: _onSplashComplete,
        ),
        _AppState.onboarding => OnboardingScreen(
          key: const ValueKey('onboarding'),
          onComplete: _onOnboardingComplete,
        ),
        _AppState.main => _ExitWrapper(key: const ValueKey('main')),
      },
    );
  }
}

class _ExitWrapper extends ConsumerWidget {
  const _ExitWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Don't show exit dialog if in PiP — back is handled natively
        if (ref.read(isInPipProvider)) return;
        final shouldExit = await showExitDialog(context);
        if (shouldExit && context.mounted) {
          // Stop service if recording before exit
          if (ref.read(isRecordingProvider)) {
            await BantayDriveService.stopService();
            PipService.setRecording(false);
          }
          SystemNavigator.pop();
        }
      },
      child: const MainShell(),
    );
  }
}

// ─── PROVIDERS ────────────────────────────────────────────────────────────────

// FIX: Riverpod 3.x — StateProvider is replaced by NotifierProvider.
// All providers that held simple state (int, bool) now use Notifier classes.

class _NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int index) => state = index;
}

final navIndexProvider = NotifierProvider<_NavIndexNotifier, int>(
  _NavIndexNotifier.new,
);

class _SidebarNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final sidebarOpenProvider = NotifierProvider<_SidebarNotifier, bool>(
  _SidebarNotifier.new,
);

// Landscape fullscreen provider
// false = AppBar/sidebar visible (default when entering Monitor)
// true  = AppBar hidden, camera fills screen (after user closes sidebar)
class _LandscapeFullscreenNotifier extends Notifier<bool> {
  @override
  bool build() => false; // start with nav visible
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

final landscapeFullscreenProvider =
    NotifierProvider<_LandscapeFullscreenNotifier, bool>(
        _LandscapeFullscreenNotifier.new);

// FIX: FutureProvider is unchanged in Riverpod 3.x — no changes needed here.
final deviceNameProvider = FutureProvider<String>((ref) async {
  try {
    if (Platform.isAndroid) {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty &&
          hostname != 'localhost' &&
          hostname != 'android') {
        return hostname;
      }
      final android = await DeviceInfoPlugin().androidInfo;
      return '${android.brand} ${android.model}'.trim();
    } else if (Platform.isIOS) {
      final ios = await DeviceInfoPlugin().iosInfo;
      return ios.name;
    }
  } catch (_) {}
  return 'USER';
});

// MAIN SHELL 
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const List<String> _titles = [
    'Dashboard',
    'Monitor',
    'Analytics',
    'History',
    'Settings',
  ];

  static final List<Widget> _screens = [
    const DashboardScreen(),
    const MonitorScreen(),
    const AnalyticsScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];

  static const List<_NavData> _navItems = [
    _NavData(icon: Icons.home_rounded, label: 'Home'),
    _NavData(icon: Icons.videocam_rounded, label: 'Monitor'),
    _NavData(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavData(icon: Icons.history_rounded, label: 'History'),
    _NavData(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navIndexProvider);
    final isRecording  = ref.watch(isRecordingProvider);
    final sidebarOpen  = ref.watch(sidebarOpenProvider);
    final isInPip = ref.watch(isInPipProvider);
    final lsFullscreen = ref.watch(landscapeFullscreenProvider);
    final isLandscape  =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final deviceName = ref.watch(deviceNameProvider).when(
      data: (name) => name,
      loading: () => 'USER',
      error: (err, stack) => 'USER',
    );

    final isMonitor = currentIndex == 1;
    // Fullscreen: landscape + Monitor + user hasn't tapped to reveal nav
    final isFullscreen  = isLandscape && isMonitor && lsFullscreen;
    final isTransparent = isLandscape && isMonitor && !lsFullscreen;

    if (isInPip) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: IndexedStack(   // ← use IndexedStack, not _screens[1] directly
          index: 1,
          children: _screens,
        ),
      );
    }
      
    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      extendBodyBehindAppBar: isFullscreen || isTransparent,

      appBar: isFullscreen
          ? PreferredSize(
              preferredSize: Size.zero,
              child: const SizedBox.shrink(),
            )
          : PreferredSize(
              preferredSize: Size.fromHeight(
                  isLandscape ? context.rs(44) : context.rs(58)),
              child: AppBar(
                backgroundColor: isTransparent
                    ? const Color(0xFF0D1627).withValues(alpha: 0.55)
                    : const Color(0xFF0D1627),
                elevation: 0,
                centerTitle: false,

                leading: isLandscape
                    ? IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, anim) =>
                              RotationTransition(
                                turns: Tween(begin: 0.875, end: 1.0)
                                    .animate(anim),
                                child: FadeTransition(
                                    opacity: anim, child: child),
                              ),
                          child: Icon(
                            sidebarOpen
                                ? Icons.close_rounded
                                : Icons.menu_rounded,
                            key: ValueKey(sidebarOpen),
                            color: Colors.white,
                            size: context.ri(24),
                          ),
                        ),
                        onPressed: () =>
                            ref.read(sidebarOpenProvider.notifier).toggle(),
                      )
                    : null,

                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _titles[currentIndex],
                      style: TextStyle(
                        color: Colors.white,
                        // FIX: was hardcoded 18/26
                        fontSize: isLandscape
                            ? context.sp(16)
                            : context.sp(24),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        text: 'Connected: ',
                        style: TextStyle(
                          color: Colors.white54,
                          // FIX: was hardcoded 10/13
                          fontSize: isLandscape
                              ? context.sp(9)
                              : context.sp(12),
                        ),
                        children: [
                          TextSpan(
                            text: deviceName,
                            style: const TextStyle(
                              color: Color(0xFF00D4FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                actions: [
                  Padding(
                    padding: EdgeInsets.only(right: context.rp(20)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      // FIX: was hardcoded 10/10
                      width: context.ri(10), height: context.ri(10),
                      decoration: BoxDecoration(
                        color: isRecording
                            ? const Color(0xFF00FF88)
                            : const Color(0xFF3A4A5C),
                        shape: BoxShape.circle,
                        boxShadow: isRecording
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00FF88)
                                      .withValues(alpha: 0.6),
                                  blurRadius: 8, spreadRadius: 1,
                                ),
                              ]
                            : [],
                      ),
                    ),
                  ),
                ],

                bottom: isTransparent
                    ? null
                    : PreferredSize(
                        preferredSize: const Size.fromHeight(1),
                        child: Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                  ),

      body: SafeArea(
        top: !isFullscreen && !isTransparent,
        child: isLandscape
            ? _LandscapeSidebarLayout(
                // Sidebar rules:
                //   fullscreen → always closed (camera must fill screen)
                //   Monitor not fullscreen → closed (sidebar overlaps camera)
                //   other screens → respects sidebarOpen
                sidebarOpen: sidebarOpen && !isFullscreen,
                currentIndex: currentIndex,
                navItems: _navItems,
                screens: _screens,
                onNavTap: (i) {
                  ref.read(navIndexProvider.notifier).set(i);
                  ref.read(landscapeFullscreenProvider.notifier).set(false);
                },
              )
            : IndexedStack(index: currentIndex, children: _screens),
      ),

      bottomNavigationBar: isFullscreen
          ? const SizedBox.shrink()
          : isLandscape
          ? null
          : _BottomNav(
              currentIndex: currentIndex,
              onTap: (i) => ref.read(navIndexProvider.notifier).set(i),
            ),
    );
  }
}

// ─── LANDSCAPE SIDEBAR PUSH LAYOUT ───────────────────────────────────────────

class _LandscapeSidebarLayout extends StatelessWidget {
  final bool sidebarOpen;
  final int currentIndex;
  final List<_NavData> navItems;
  final List<Widget> screens;
  final ValueChanged<int> onNavTap;

  const _LandscapeSidebarLayout({
    required this.sidebarOpen,
    required this.currentIndex,
    required this.navItems,
    required this.screens,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          width: sidebarOpen ? kSidebarWidth : 0,
          child: ClipRect(
            child: OverflowBox(
              maxWidth: kSidebarWidth,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: kSidebarWidth,
                child: _LandscapeSidebar(
                  currentIndex: currentIndex,
                  navItems: navItems,
                  onNavTap: onNavTap,
                ),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          width: sidebarOpen ? 1 : 0,
          color: Colors.white.withValues(alpha: 0.05),
        ),
        Expanded(
          child: IndexedStack(index: currentIndex, children: screens),
        ),
      ],
    );
  }
}

// ─── LANDSCAPE SIDEBAR CONTENT ────────────────────────────────────────────────

class _LandscapeSidebar extends StatelessWidget {
  final int currentIndex;
  final List<_NavData> navItems;
  final ValueChanged<int> onNavTap;

  const _LandscapeSidebar({
    required this.currentIndex,
    required this.navItems,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMonitor = currentIndex == 1;
    final appBarH = isMonitor ? 89.0 : 8.0;
    final screenH = MediaQuery.of(context).size.height;
    final available = screenH - appBarH - 16;
    final needsScroll = available < 240;

    return Container(
      color: const Color(0xFF0D1627),
      padding: EdgeInsets.only(top: appBarH, bottom: context.rs(14), left: context.rp(10), right: context.rp(10)),
      child: SingleChildScrollView(
        physics: needsScroll
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: context.rp(8),
                bottom: context.rs(12),
              ),
              child: Text(
                'NAVIGATION',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: context.sp(10),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            ...navItems.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final active = i == currentIndex;

              return Padding(
                padding: EdgeInsets.only(bottom: context.rs(4)),
                child: GestureDetector(
                  onTap: () => onNavTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF00D4FF).withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(context.rp(12)),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF00D4FF).withValues(alpha: 0.25)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          size: context.ri(20),
                          color: active
                              ? const Color(0xFF00D4FF)
                              : Colors.white38,
                        ),
                        SizedBox(width: context.rp(12)),
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              color: active
                                  ? const Color(0xFF00D4FF)
                                  : Colors.white54,
                              fontSize: context.sp(14),
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (active)
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00D4FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── PORTRAIT BOTTOM NAV ──────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  static const List<_NavData> _items = [
    _NavData(icon: Icons.home_rounded, label: 'Home'),
    _NavData(icon: Icons.videocam_rounded, label: 'Monitor'),
    _NavData(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavData(icon: Icons.history_rounded, label: 'History'),
    _NavData(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: context.rs(54),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final itemWidth  = totalWidth / _items.length;
              final pillWidth  = context.rp(46);
              final pillHeight = context.rs(38);
              final pillLeft   =
                  currentIndex * itemWidth + (itemWidth - pillWidth) / 2;

              return Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    left: pillLeft,
                    top: (context.rs(54) - pillHeight) / 2,
                    child: Container(
                      width: pillWidth,
                      height: pillHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(context.rp(12)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF00D4FF,
                            ).withValues(alpha: 0.15),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: _items.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      final active = i == currentIndex;
                      return GestureDetector(
                        onTap: () => onTap(i),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: itemWidth,
                          height: context.rs(54),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Icon(
                                item.icon,
                                key: ValueKey('nav_${i}_$active'),
                                size: active ? context.ri(24) : context.ri(22),
                                color: active
                                    ? const Color(0xFF00D4FF)
                                    : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── SHARED ───────────────────────────────────────────────────────────────────

class _NavData {
  final IconData icon;
  final String label;
  const _NavData({required this.icon, required this.label});
}