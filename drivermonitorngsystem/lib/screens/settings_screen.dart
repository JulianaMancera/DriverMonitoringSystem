import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF080E1A),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.settings_rounded,
                color: Colors.white24,
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Coming soon',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}