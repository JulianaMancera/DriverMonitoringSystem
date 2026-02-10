import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Top section with Safety Score and Stats
            LayoutBuilder(
              builder: (context, constraints) {
                if (isMobile) {
                  // Mobile layout: Stack vertically
                  return Column(
                    children: [
                      _buildSafetyScoreCard(),
                      const SizedBox(height: 32),
                      _buildQuickStatsGrid(),
                    ],
                  );
                } else {
                  // Desktop Layout: Side by side
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: _buildSafetyScoreCard()),
                      const SizedBox(width: 32),
                      Expanded(flex: 8, child: _buildQuickStatsGrid()),
                    ],
                  );
                }
              },
            ),

            const SizedBox(height: 32),

            // Chart section
            _buildAlertnesChart(),

            SizedBox(
              height: isMobile ? 64 : 32,
            ), // Extra padding for mobile bottom nav
          ],
        ),
      ),
    );
  }

  // Safety Score Card
  Widget _buildSafetyScoreCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(8, 8),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-8, -8),
            blurRadius: 16,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top gradient bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 8,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF22d3ee),
                    Color(0xFF3b82f6),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
            ),
          ),

          // Main content
        ],
      )
    );
  }
}
