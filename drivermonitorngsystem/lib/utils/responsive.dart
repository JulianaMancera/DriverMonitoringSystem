import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 1200;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1200;

  // Responsive text scaling
  static double responsiveFont(
    BuildContext context, {
    required double mobile,
    double? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return desktop ?? mobile * 1.2;
    return mobile;
  }

  // Responsive padding
  static double responsivePadding(
    BuildContext context, {
    required double mobile,
    double? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return desktop ?? mobile * 2;
    return mobile;
  }
}
