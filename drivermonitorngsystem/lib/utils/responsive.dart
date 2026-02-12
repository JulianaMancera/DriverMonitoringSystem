import 'package:flutter/material.dart';

class Responsive {
  // Consistent breakpoints
  static const double mobileBreakpoint = 768;
  static const double tabletBreakpoint = 1024;
  static const double desktopBreakpoint = 1200;

  // Device type checks
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < desktopBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;

  // Get current device width
  static double getWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  // Responsive text scaling with better granularity
  static double responsiveFont(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= desktopBreakpoint) {
      return desktop ?? tablet ?? mobile * 1.3;
    } else if (width >= mobileBreakpoint) {
      return tablet ?? mobile * 1.15;
    }
    return mobile;
  }

  // Responsive padding
  static double responsivePadding(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= desktopBreakpoint) {
      return desktop ?? tablet ?? mobile * 2;
    } else if (width >= mobileBreakpoint) {
      return tablet ?? mobile * 1.5;
    }
    return mobile;
  }

  // Responsive spacing (for SizedBox, margins, etc.)
  static double responsiveSpacing(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= desktopBreakpoint) {
      return desktop ?? tablet ?? mobile * 2;
    } else if (width >= mobileBreakpoint) {
      return tablet ?? mobile * 1.5;
    }
    return mobile;
  }

  // Responsive height (useful for containers)
  static double responsiveHeight(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= desktopBreakpoint) {
      return desktop ?? tablet ?? mobile * 1.25;
    } else if (width >= mobileBreakpoint) {
      return tablet ?? mobile * 1.15;
    }
    return mobile;
  }

  // Get responsive value based on screen size
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= desktopBreakpoint) {
      return desktop ?? tablet ?? mobile;
    } else if (width >= mobileBreakpoint) {
      return tablet ?? mobile;
    }
    return mobile;
  }

  // Scale factor based on screen width 
  static double getScaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= desktopBreakpoint) {
      return 1.3;
    } else if (width >= mobileBreakpoint) {
      return 1.15;
    }
    return 1.0;
  }

  // Get maximum content width 
  static double getMaxContentWidth(BuildContext context) {
    if (isDesktop(context)) {
      return 1400;
    } else if (isTablet(context)) {
      return 1024;
    }
    return double.infinity;
  }
}