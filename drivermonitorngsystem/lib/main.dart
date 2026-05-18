import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/database/database_helper.dart';
import 'core/providers.dart';
import 'core/services/notifications.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'utils/responsive.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'core/services/pip_service.dart';
import 'widgets/exit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Brand detection runs before runApp so scaleFactor is ready for first frame.
  if (Platform.isAndroid) {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      Responsive.setBrand(_detectBrand(info.brand.toLowerCase()));
    } catch (_) {
      Responsive.setBrand(DeviceBrand.other);
    }
  }

  await DatabaseHelper.instance.database;
  await BantayDriveService.initialize();

  // Registers the IsolateNameServer port so the background isolate can deliver
  // stop_recording messages to the main isolate via sendDataToMain().
  FlutterForegroundTask.initCommunicationPort();

  runApp(const ProviderScope(child: BantayDriveApp()));
}

DeviceBrand _detectBrand(String brand) {
  if (brand.contains('samsung')) return DeviceBrand.samsung;
  if (brand.contains('xiaomi') || brand.contains('redmi') || brand.contains('poco')) {
    return DeviceBrand.xiaomi;
  }
  if (brand.contains('oppo') || brand.contains('realme') || brand.contains('oneplus')) {
    return DeviceBrand.oppo;
  }
  if (brand.contains('vivo') || brand.contains('iqoo')) return DeviceBrand.vivo;
  if (brand.contains('google') || brand.contains('pixel')) return DeviceBrand.pixel;
  return DeviceBrand.other;
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
  // DEV TOGGLE — set true to preview onboarding during development.
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
        if (ref.read(isInPipProvider)) return;
        final shouldExit = await showExitDialog(context,
            isRecording: ref.read(isRecordingProvider));
        if (shouldExit && context.mounted) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navIndexProvider);
    final isRecording  = ref.watch(isRecordingProvider);
    final isInPip      = ref.watch(isInPipProvider);

    final deviceName = ref.watch(deviceNameProvider).when(
      data: (name) => name,
      loading: () => 'USER',
      error: (err, stack) => 'USER',
    );

    // Keep a single consistent widget tree in both PIP and non-PIP modes so
    // that _MonitorScreenState is never disposed and recreated during PIP
    // transitions, which would destroy session state and system logs.
    return Scaffold(
      backgroundColor: isInPip ? Colors.black : const Color(0xFF080E1A),

      appBar: isInPip ? null : PreferredSize(
        preferredSize: Size.fromHeight(context.rs(58)),
        child: AppBar(
          backgroundColor: const Color(0xFF0D1627),
          elevation: 0,
          centerTitle: false,

          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _titles[currentIndex],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: context.sp(24),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              RichText(
                text: TextSpan(
                  text: 'Connected: ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: context.sp(12),
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

          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ),
      ),

      body: SafeArea(
        top: !isInPip,
        child: IndexedStack(
          index: isInPip ? 1 : currentIndex,
          children: _screens,
        ),
      ),

      bottomNavigationBar: isInPip ? null : _BottomNav(
        currentIndex: currentIndex,
        onTap: (i) => ref.read(navIndexProvider.notifier).set(i),
      ),
    );
  }
}

// ─── BOTTOM NAV ───────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  static const List<_NavData> _items = [
    _NavData(Icons.home_rounded),
    _NavData(Icons.videocam_rounded),
    _NavData(Icons.bar_chart_rounded),
    _NavData(Icons.history_rounded),
    _NavData(Icons.settings_rounded),
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
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
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

class _NavData {
  final IconData icon;
  const _NavData(this.icon);
}
