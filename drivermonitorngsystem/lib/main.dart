import 'package:flutter/material.dart';
import 'widgets/sidebar.dart';
import 'screens/dashboard_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/analytics_screen.dart';
import 'utils/responsive.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
  const MainScreen({super.key});

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
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      body: Container(
        // Gradient background
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
            // Sidebar (hidden on mobile)
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
                  _buildHeader(context),
                  
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

  Widget _buildHeader(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Container(
      height: Responsive.responsiveHeight(
        context,
        mobile: 64,
        tablet: 72,
        desktop: 80,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.responsivePadding(
          context,
          mobile: 16,
          tablet: 24,
          desktop: 32,
        ),
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title section
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMobile ? _getHeaderTitleMobile() : _getHeaderTitle(),
                  style: TextStyle(
                    fontSize: Responsive.responsiveFont(
                      context,
                      mobile: 18,
                      tablet: 20,
                      desktop: 24,
                    ),
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFf1f5f9),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(
                  height: Responsive.responsiveSpacing(
                    context,
                    mobile: 4,
                    tablet: 4,
                    desktop: 4,
                  ),
                ),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: Responsive.responsiveFont(
                        context,
                        mobile: 11,
                        tablet: 11.5,
                        desktop: 12,
                      ),
                      color: const Color(0xFF64748b),
                    ),
                    children: const [
                      TextSpan(text: 'Connected: '),
                      TextSpan(
                        text: 'USER',
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
          ),
          
          // Status indicators
          Row(
            children: [
              if (!isMobile)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.responsivePadding(
                      context,
                      mobile: 12,
                      tablet: 14,
                      desktop: 16,
                    ),
                    vertical: Responsive.responsivePadding(
                      context,
                      mobile: 6,
                      tablet: 7,
                      desktop: 8,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0b1120).withOpacity(0.8),
                        offset: const Offset(3, 3),
                        blurRadius: 4,
                        spreadRadius: -1,
                      ),
                      BoxShadow(
                        color: const Color(0xFF1e293b).withOpacity(0.5),
                        offset: const Offset(-1, -1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(
                    'SYSTEM ACTIVE',
                    style: TextStyle(
                      fontSize: Responsive.responsiveFont(
                        context,
                        mobile: 12,
                        tablet: 13,
                        desktop: 14,
                      ),
                      color: const Color(0xFF22d3ee),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              if (!isMobile)
                SizedBox(
                  width: Responsive.responsiveSpacing(
                    context,
                    mobile: 12,
                    tablet: 14,
                    desktop: 16,
                  ),
                ),
              
              // Status indicator circle
              Container(
                width: Responsive.responsiveValue(
                  context,
                  mobile: 32.0,
                  tablet: 36.0,
                  desktop: 40.0,
                ),
                height: Responsive.responsiveValue(
                  context,
                  mobile: 32.0,
                  tablet: 36.0,
                  desktop: 40.0,
                ),
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
                    width: Responsive.responsiveValue(
                      context,
                      mobile: 8.0,
                      tablet: 10.0,
                      desktop: 12.0,
                    ),
                    height: Responsive.responsiveValue(
                      context,
                      mobile: 8.0,
                      tablet: 10.0,
                      desktop: 12.0,
                    ),
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
        return const AnalyticsScreen();
      case 'settings':
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Module Under Development',
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                    context,
                    mobile: 18,
                    tablet: 19,
                    desktop: 20,
                  ),
                  color: const Color(0xFF475569),
                ),
              ),
              SizedBox(
                height: Responsive.responsiveSpacing(
                  context,
                  mobile: 8,
                  desktop: 8,
                ),
              ),
              Text(
                'Please return to Dashboard or Monitor',
                style: TextStyle(
                  fontSize: Responsive.responsiveFont(
                    context,
                    mobile: 13,
                    tablet: 13.5,
                    desktop: 14,
                  ),
                  color: const Color(0xFF475569),
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