import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'core/database/database_helper.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';          // ← replaced ProfilePlaceholder

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allows portrait and landscape orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialize database
  await DatabaseHelper.instance.database;

  runApp(
    const ProviderScope(
      child: BantayDriveApp(),
    ),
  );
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
      home: const MainShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SHELL — Bottom Navigation
// ─────────────────────────────────────────────────────────────────────────────

final navIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static final List<Widget> _screens = [
    const DashboardScreen(),
    const MonitorScreen(),
    const AnalyticsScreen(),
    const HistoryScreen(),             // ← index 3
    const SettingsScreen(),            // ← index 4
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navIndexProvider);
    // Green + glow when recording, grey + no glow when idle
    final isRecording  = ref.watch(isRecordingProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          backgroundColor: const Color(0xFF0D1627),
          elevation: 0,
          centerTitle: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                ['Dashboard', 'Monitor', 'Analytics', 'History', 'Settings']
                    [currentIndex],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              RichText(
                text: const TextSpan(
                  text: 'Connected: ',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  children: [
                    TextSpan(
                      text: 'USER',
                      style: TextStyle(
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
                      ? const Color(0xFF00FF88)   // green when recording
                      : const Color(0xFF3A4A5C),  // grey when idle
                  shape: BoxShape.circle,
                  boxShadow: isRecording
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00FF88).withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],                        // no glow when idle
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: currentIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: currentIndex,
        onTap: (index) =>
            ref.read(navIndexProvider.notifier).state = index,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM NAV — Telegram-style sliding pill indicator
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
          top: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
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
              final itemWidth  = totalWidth / _items.length;
              const pillWidth  = 48.0;
              const pillHeight = 40.0;
              final pillLeft   = currentIndex * itemWidth + (itemWidth - pillWidth) / 2;

              return Stack(
                alignment: Alignment.center,
                children: [

                  // ── SLIDING PILL ──────────────────────────────────────
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    left: pillLeft,
                    top: (56 - pillHeight) / 2,
                    child: Container(
                      width: pillWidth,
                      height: pillHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D4FF).withOpacity(0.13),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D4FF).withOpacity(0.15),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── ICONS ─────────────────────────────────────────────
                  Row(
                    children: _items.asMap().entries.map((entry) {
                      final i      = entry.key;
                      final item   = entry.value;
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

class _NavData {
  final IconData icon;
  final String label;
  const _NavData({required this.icon, required this.label});
}