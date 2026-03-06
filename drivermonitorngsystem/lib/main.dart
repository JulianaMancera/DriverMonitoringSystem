import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database_helper.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialize database
  await DatabaseHelper.instance.database;

  runApp(
    // Riverpod wrapper — required for state management
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
        fontFamily: 'SF Pro Display', // falls back to system default
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

// Riverpod provider for current nav index
final navIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static final List<Widget> _screens = [
    const DashboardScreen(),
    const MonitorScreen(),
    const AnalyticsScreen(),
    const SettingsScreen(),
    const ProfilePlaceholder(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navIndexProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: currentIndex,
        onTap: (index) =>
            ref.read(navIndexProvider.notifier).state = index,
      ),
    );
  }
}

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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_rounded, index: 0, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.videocam_rounded, index: 1, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.bar_chart_rounded, index: 2, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.settings_rounded, index: 3, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.person_rounded, index: 4, currentIndex: currentIndex, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
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

// Profile placeholder (replace later with real profile screen)
class ProfilePlaceholder extends StatelessWidget {
  const ProfilePlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF080E1A),
        body: Center(
          child: Text('Profile', style: TextStyle(color: Colors.white54)),
        ),
      );
}