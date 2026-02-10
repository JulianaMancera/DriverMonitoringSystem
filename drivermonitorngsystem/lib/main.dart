import 'package:flutter/material.dart';
import 'widgets/sidebar.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Monitoring System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'sans-serif',
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String activeTab = 'home'; // State management

  void setActiveTab(String tab) {
    setState(() {
      activeTab = tab;
    });
  }

  // Helper method to get header title
  String _getHeaderTitle() {
    switch (activeTab) {
      case 'home':
        return 'Dashboard Overview';
      case 'monitor':
        return 'Live Driver Monitoring';
      case 'analytics':
        return 'Analytics';
      case 'settings':
        return 'Settings';
      default:
        return 'Dashboard';
    }
  }

  String _getHeaderTitleMobile() {
    switch (activeTab) {
      case 'home':
        return 'Dashboard';
      case 'monitor':
        return 'Monitor';
      case 'analytics':
        return 'Analytics';
      case 'settings':
        return 'Settings';
      default:
        return 'Dashboard';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive design
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;

    return Scaffold(
      body: Container(
        // Gradient background (from-[#1e293b] via-[#0f172a] to-[#020617])
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1e293b),
              Color(0xFF0f172a),
              Color(0xFF020617),
            ],
          ),
        ),
        child: Row(
          children: [
            // Sidebar
            if (!isMobile)
              Sidebar(
                activeTab: activeTab,
                onTabChanged: setActiveTab,
              ),
            
            // Main content
            Expanded(
              child: Column(
                children: [
                  // Header
                  _buildHeader(isMobile),
                  
                  // Content Area
                  Expanded(
                    child: _buildContent(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      
      // Bottom navigation for mobile
      bottomNavigationBar: isMobile
          ? Sidebar(
              activeTab: activeTab,
              onTabChanged: setActiveTab,
              isMobile: true,
            )
          : null,
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      height: isMobile ? 64 : 80,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title section
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMobile ? _getHeaderTitleMobile() : _getHeaderTitle(),
                style: TextStyle(
                  fontSize: isMobile ? 18 : 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFf1f5f9),
                ),
              ),
              const SizedBox(height: 4),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748b),
                  ),
                  children: [
                    TextSpan(text: 'Connected: '),
                    TextSpan(
                      text: 'TES-X92',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF22d3ee),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Status indicators
          Row(
            children: [
              if (!isMobile)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      // Inset shadow effect (neumorphism)
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
                  child: const Text(
                    'SYSTEM ACTIVE',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF22d3ee),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              if (!isMobile) const SizedBox(width: 16),
              
              // Status indicator circle
              Container(
                width: isMobile ? 32 : 40,
                height: isMobile ? 32 : 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF0f172a),
                  shape: BoxShape.circle,
                  boxShadow: [
                    const BoxShadow(
                      color: Color(0xFF0b1120),
                      offset: Offset(3, 3),
                      blurRadius: 6,
                    ),
                    const BoxShadow(
                      color: Color(0xFF1e293b),
                      offset: Offset(-3, -3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: isMobile ? 8 : 12,
                    height: isMobile ? 8 : 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10b981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10b981).withOpacity(0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (activeTab) {
      case 'home':
        return const DashboardScreen();
      case 'monitor':
        return const MonitorScreen();
      case 'analytics':
      case 'settings':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Module Under Development',
                style: TextStyle(
                  fontSize: 20,
                  color: Color(0xFF475569),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Please return to Dashboard or Monitor',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        );
      default:
        return const DashboardScreen();
    }
  }
}