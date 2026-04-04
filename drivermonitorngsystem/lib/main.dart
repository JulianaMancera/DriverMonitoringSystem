import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/database/database_helper.dart';
import 'core/services/foreground_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await DatabaseHelper.instance.database;

  // Initialize foreground service (must be before runApp)
  BantayDriveService.initialize();

  runApp(const ProviderScope(child: BantayDriveApp()));
}

class BantayDriveApp extends StatelessWidget {
  const BantayDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      // WithForegroundTask wraps the app to handle foreground service lifecycle
      home: WithForegroundTask(child: const MainShell()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final navIndexProvider    = StateProvider<int>((ref) => 0);
final sidebarOpenProvider = StateProvider<bool>((ref) => false);

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

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SHELL
// ─────────────────────────────────────────────────────────────────────────────

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
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
    final isTransparent = isLandscape && isMonitor;

    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      extendBodyBehindAppBar: isTransparent,

      appBar: PreferredSize(
        preferredSize: Size.fromHeight(isLandscape ? 46 : 60),
        child: AppBar(
          backgroundColor: isTransparent
              ? const Color(0xFF0D1627).withOpacity(0.55)
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
                      sidebarOpen ? Icons.close_rounded : Icons.menu_rounded,
                      key: ValueKey(sidebarOpen),
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  onPressed: () => ref
                      .read(sidebarOpenProvider.notifier)
                      .state = !sidebarOpen,
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
              padding: const EdgeInsets.only(right: 20),
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
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00FF88).withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
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
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
        ),
      ),

      body: SafeArea(
        top: !isTransparent,
        child: isLandscape
            ? _LandscapeSidebarLayout(
                sidebarOpen:  sidebarOpen,
                currentIndex: currentIndex,
                navItems:     _navItems,
                screens:      _screens,
                onNavTap: (i) {
                  ref.read(navIndexProvider.notifier).state = i;
                },
              )
            : IndexedStack(
                index: currentIndex,
                children: _screens,
              ),
      ),

      bottomNavigationBar: isLandscape
          ? null
          : _BottomNav(
              currentIndex: currentIndex,
              onTap: (i) => ref.read(navIndexProvider.notifier).state = i,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDSCAPE SIDEBAR PUSH LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _LandscapeSidebarLayout extends StatelessWidget {
  final bool sidebarOpen;
  final int currentIndex;
  final List<_NavData> navItems;
  final List<Widget> screens;
  final ValueChanged<int> onNavTap;

  static const double _sidebarWidth = 200.0;

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
          width: sidebarOpen ? _sidebarWidth : 0,
          child: ClipRect(
            child: OverflowBox(
              maxWidth: _sidebarWidth,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: _sidebarWidth,
                child: _LandscapeSidebar(
                  currentIndex: currentIndex,
                  navItems:     navItems,
                  onNavTap:     onNavTap,
                ),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          width: sidebarOpen ? 1 : 0,
          color: Colors.white.withOpacity(0.05),
        ),
        Expanded(
          child: IndexedStack(
            index: currentIndex,
            children: screens,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDSCAPE SIDEBAR CONTENT
// ─────────────────────────────────────────────────────────────────────────────

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
    final isMonitor   = currentIndex == 1;
    final appBarH     = isMonitor ? 89.0 : 8.0;
    final screenH     = MediaQuery.of(context).size.height;
    final available   = screenH - appBarH - 16;
    final needsScroll = available < 240;

    return Container(
      color: const Color(0xFF0D1627),
      padding: EdgeInsets.only(
        top: appBarH, bottom: 16, left: 12, right: 12,
      ),
      child: SingleChildScrollView(
        physics: needsScroll
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                'NAVIGATION',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            ...navItems.asMap().entries.map((entry) {
              final i      = entry.key;
              final item   = entry.value;
              final active = i == currentIndex;

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () => onNavTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF00D4FF).withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF00D4FF).withOpacity(0.25)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 20,
                            color: active
                                ? const Color(0xFF00D4FF)
                                : Colors.white38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(item.label,
                              style: TextStyle(
                                color: active
                                    ? const Color(0xFF00D4FF)
                                    : Colors.white54,
                                fontSize: 14,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              )),
                        ),
                        if (active)
                          Container(
                            width: 4, height: 4,
                            decoration: const BoxDecoration(
                                color: Color(0xFF00D4FF),
                                shape: BoxShape.circle),
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

// ─────────────────────────────────────────────────────────────────────────────
// PORTRAIT BOTTOM NAV
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  static const List<_NavData> _items = [
    _NavData(icon: Icons.home_rounded,      label: 'Home'),
    _NavData(icon: Icons.videocam_rounded,  label: 'Monitor'),
    _NavData(icon: Icons.bar_chart_rounded, label: 'Analytics'),
    _NavData(icon: Icons.history_rounded,   label: 'History'),
    _NavData(icon: Icons.settings_rounded,  label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.05), width: 1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final itemWidth  = totalWidth / _items.length;
              const pillWidth  = 48.0;
              const pillHeight = 40.0;
              final pillLeft   =
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
                      width: pillWidth, height: pillHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D4FF).withOpacity(0.13),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.15),
                              blurRadius: 10, spreadRadius: 1),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: _items.asMap().entries.map((entry) {
                      final i      = entry.key;
                      final item   = entry.value;
                      final active = i == currentIndex;
                      return GestureDetector(
                        onTap: () => onTap(i),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: itemWidth, height: 56,
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

// ─────────────────────────────────────────────────────────────────────────────
// SHARED
// ─────────────────────────────────────────────────────────────────────────────

class _NavData {
  final IconData icon;
  final String label;
  const _NavData({required this.icon, required this.label});
}