import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/database/database_helper.dart';
import 'core/services/notifications.dart';
import 'screens/monitor_screen.dart';
import 'screens/dashboard_screen.dart' show DashboardScreen;
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'utils/responsive.dart';
import 'constants/layout_constants.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
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

  await DatabaseHelper.instance.database;

  // ── Brand detection — set once so Responsive uses the right scale factor ──
  if (Platform.isAndroid) {
    try {
      final mfr =
          (await DeviceInfoPlugin().androidInfo).manufacturer.toLowerCase();
      if (mfr.contains('samsung')) {
        Responsive.setBrand(DeviceBrand.samsung);
      } else if (mfr.contains('xiaomi') || mfr.contains('redmi')) {
        Responsive.setBrand(DeviceBrand.xiaomi);
      } else if (mfr.contains('oppo') || mfr.contains('realme')) {
        Responsive.setBrand(DeviceBrand.oppo);
      } else if (mfr.contains('vivo')) {
        Responsive.setBrand(DeviceBrand.vivo);
      } else if (mfr.contains('google')) {
        Responsive.setBrand(DeviceBrand.pixel);
      }
    } catch (_) {}
  }

  if (Platform.isAndroid) {
    final plugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.requestNotificationsPermission();
  }

  await BantayDriveService.initialize();

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
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final maxScale =
              Responsive.deviceBrand == DeviceBrand.samsung ? 1.05 : 1.10;
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: maxScale,
              ),
            ),
            child: child!,
          );
        },
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
        _AppState.main => const MainShell(key: ValueKey('main')),
      },
    );
  }
}

// ─── PROVIDERS ────────────────────────────────────────────────────────────────

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

// ─── MAIN SHELL ───────────────────────────────────────────────────────────────

cclass MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}
 
class _MainShellState extends ConsumerState<MainShell> {
  // ── NEW: controls whether AppBar/nav are visible in landscape-monitor ──
  bool _uiVisible = true;
 
  static const List<String> _titles = [
    'Dashboard', 'Monitor', 'Analytics', 'History', 'Settings',
  ];
 
  static final List<Widget> _screens = [
    const DashboardScreen(),
    const MonitorScreen(),
    const AnalyticsScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];
 
  static const List<_NavData> _navItems = [
    _NavData(icon: Icons.home_rounded,      label: 'Home'),
    _NavData(icon: Icons.videocam_rounded,  label: 'Monitor'),
    _NavData(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavData(icon: Icons.history_rounded,   label: 'History'),
    _NavData(icon: Icons.settings_rounded,  label: 'Settings'),
  ];
 
  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navIndexProvider);
    final isRecording  = ref.watch(isRecordingProvider);
    final sidebarOpen  = ref.watch(sidebarOpenProvider);
    final isLandscape  =
        MediaQuery.of(context).orientation == Orientation.landscape;
 
    final deviceName = ref.watch(deviceNameProvider).when(
      data:    (name) => name,
      loading: () => 'USER',
      error:   (_, __) => 'USER',
    );
 
    final isMonitor     = currentIndex == 1;
    // ── In landscape+monitor the shell becomes "cinematic" by default ──
    final isCinematic   = isLandscape && isMonitor;
    // AppBar is transparent overlay when cinematic
    final isTransparent = isCinematic;
 
    // ── Tap anywhere on the body to toggle chrome visibility ──────────────
    Widget body = isLandscape
        ? _LandscapeSidebarLayout(
            sidebarOpen:  sidebarOpen,
            currentIndex: currentIndex,
            navItems:     _navItems,
            screens:      _screens,
            onNavTap: (i) {
              ref.read(navIndexProvider.notifier).set(i);
              // Switching away from monitor → always show UI
              if (i != 1) setState(() => _uiVisible = true);
            },
          )
        : IndexedStack(index: currentIndex, children: _screens);
 
    if (isCinematic) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _uiVisible = !_uiVisible),
        child: body,
      );
    }
 
    // ── When cinematic + hidden, show only a small "tap hint" ─────────────
    final showChrome = !isCinematic || _uiVisible;
 
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await showExitDialog(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF080E1A),
        extendBodyBehindAppBar: isTransparent,
        // ── AppBar: animate in/out ─────────────────────────────────────────
        appBar: showChrome
            ? PreferredSize(
                preferredSize: Size.fromHeight(isLandscape ? 46 : 60),
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
                            transitionBuilder: (child, anim) => RotationTransition(
                              turns: Tween(begin: 0.875, end: 1.0).animate(anim),
                              child: FadeTransition(opacity: anim, child: child),
                            ),
                            child: Icon(
                              sidebarOpen
                                  ? Icons.close_rounded
                                  : Icons.menu_rounded,
                              key: ValueKey(sidebarOpen),
                              color: Colors.white,
                              size: 26,
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
                          fontSize: isLandscape ? 18 : 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      RichText(
                        text: TextSpan(
                          text: 'Connected: ',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: isLandscape ? 10 : 13,
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
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isRecording
                              ? const Color(0xFF00FF88)
                              : const Color(0xFF3A4A5C),
                          shape: BoxShape.circle,
                          boxShadow: isRecording
                              ? [BoxShadow(
                                  color: const Color(0xFF00FF88)
                                      .withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )]
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
              )
            : null, // AppBar hidden → camera takes full screen
 
        body: SafeArea(
          top: !isTransparent,
          child: Stack(children: [
            body,
            // ── "Tap to show controls" hint when chrome is hidden ─────────
            if (isCinematic && !_uiVisible)
              Positioned(
                bottom: context.rs(24),
                left: 0,
                right: 0,
                child: Center(
                  child: IgnorePointer( // GestureDetector above handles tap
                    child: AnimatedOpacity(
                      opacity: 0.55,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rp(14),
                          vertical:   context.rs(6),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(context.rp(20)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.touch_app_rounded,
                              size: context.ri(14),
                              color: Colors.white60),
                          SizedBox(width: context.rp(6)),
                          Text('Tap to show controls',
                              style: TextStyle(
                                color:    Colors.white60,
                                fontSize: context.sp(11),
                              )),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
 
        bottomNavigationBar: isLandscape
            ? null
            : _BottomNav(
                currentIndex: currentIndex,
                onTap: (i) => ref.read(navIndexProvider.notifier).set(i),
              ),
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
      padding: EdgeInsets.only(top: appBarH, bottom: 16, left: 12, right: 12),
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
                      borderRadius: BorderRadius.circular(12),
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
                          size: 20,
                          color:
                              active ? const Color(0xFF00D4FF) : Colors.white38,
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
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w400,
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
          height: 56,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final itemWidth = totalWidth / _items.length;
              const pillWidth = 48.0;
              const pillHeight = 40.0;
              final pillLeft =
                  currentIndex * itemWidth + (itemWidth - pillWidth) / 2;

              return Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    left: pillLeft,
                    top: (56 - pillHeight) / 2,
                    child: Container(
                      width: pillWidth,
                      height: pillHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF00D4FF).withValues(alpha: 0.15),
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
                          height: 56,
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Icon(
                                item.icon,
                                key: ValueKey('nav_${i}_$active'),
                                size: active ? 25 : 23,
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
