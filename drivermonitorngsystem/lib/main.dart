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
    const HistoryScreen(),             
    const SettingsScreen(),          
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
// BOTTOM NAV
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        border: Border(
          top: BorderSide(
              color: Colors.white.withOpacity(0.05), width: 1),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_rounded,      label: 'Home',      index: 0, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.videocam_rounded,  label: 'Monitor',   index: 1, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.bar_chart_rounded, label: 'Analytics', index: 2, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.history_rounded,   label: 'History',   index: 3, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.settings_rounded,  label: 'Settings',  index: 4, currentIndex: currentIndex, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF00D4FF).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isActive ? const Color(0xFF00D4FF) : Colors.white38,
          size: 24,
        ),
      ),
    );
  }
}