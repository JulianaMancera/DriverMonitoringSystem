import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Responsive — adaptive layout utilities for Bantay Drive
// Supports all Android phone sizes from 360×640 dp to 412×915 dp
// ─────────────────────────────────────────────────────────────────────────────

class Responsive {
  // ── Breakpoints ─────────────────────────────────────────────────────────────
  static const double mobileBreakpoint  = 768;
  static const double tabletBreakpoint  = 1024;
  static const double desktopBreakpoint = 1200;

  // ── Device type checks ───────────────────────────────────────────────────────
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < desktopBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;

  // ── Dimensions ──────────────────────────────────────────────────────────────
  static double getWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double getHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  // ── Responsive text ──────────────────────────────────────────────────────────
  static double responsiveFont(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return desktop ?? tablet ?? mobile * 1.3;
    if (w >= mobileBreakpoint)  return tablet ?? mobile * 1.15;
    return mobile;
  }

  // ── Responsive spacing ───────────────────────────────────────────────────────
  static double responsivePadding(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return desktop ?? tablet ?? mobile * 2;
    if (w >= mobileBreakpoint)  return tablet ?? mobile * 1.5;
    return mobile;
  }

  static double responsiveSpacing(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return desktop ?? tablet ?? mobile * 2;
    if (w >= mobileBreakpoint)  return tablet ?? mobile * 1.5;
    return mobile;
  }

  static double responsiveHeight(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return desktop ?? tablet ?? mobile * 1.25;
    if (w >= mobileBreakpoint)  return tablet ?? mobile * 1.15;
    return mobile;
  }

  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return desktop ?? tablet ?? mobile;
    if (w >= mobileBreakpoint)  return tablet ?? mobile;
    return mobile;
  }

  static double getScaleFactor(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return 1.3;
    if (w >= mobileBreakpoint)  return 1.15;
    return 1.0;
  }

  static double getMaxContentWidth(BuildContext context) {
    if (isDesktop(context)) return 1400;
    if (isTablet(context))  return 1024;
    return double.infinity;
  }

  static double responsiveBorderRadius(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return desktop ?? tablet ?? mobile * 1.2;
    if (w >= mobileBreakpoint)  return tablet ?? mobile * 1.1;
    return mobile;
  }

  static double responsiveIconSize(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    final w = MediaQuery.of(context).size.width;
    if (w >= desktopBreakpoint) return desktop ?? tablet ?? mobile * 1.3;
    if (w >= mobileBreakpoint)  return tablet ?? mobile * 1.15;
    return mobile;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext extensions — use these in all screens
//
// Usage:
//   context.sw        → screen width
//   context.sh        → screen height
//   context.sp(14)    → font size scaled to screen (14 is base for 360px wide)
//   context.wp(0.05)  → 5% of screen width
//   context.hp(0.10)  → 10% of screen height
//   context.rp(16)    → responsive padding (scales with screen)
//   context.rs(12)    → responsive spacing / SizedBox height/width
// ─────────────────────────────────────────────────────────────────────────────
extension ResponsiveContext on BuildContext {
  // Raw dimensions
  double get sw => MediaQuery.of(this).size.width;
  double get sh => MediaQuery.of(this).size.height;

  // Font scaling — base size is calibrated for 360px wide screen
  // Scales linearly: 360px = 1.0x, 412px = 1.08x, 768px = 1.15x
  double get _fontScale => (sw / 360.0).clamp(0.85, 1.3);
  double sp(double size) => (size * _fontScale).roundToDouble();

  // Percentage of screen dimensions
  double wp(double fraction) => sw * fraction;
  double hp(double fraction) => sh * fraction;

  // Responsive padding — scales with screen width
  double rp(double base) => (base * (sw / 390.0)).clamp(base * 0.7, base * 1.5);

  // Responsive spacing — for SizedBox height/width
  double rs(double base) => (base * (sh / 844.0)).clamp(base * 0.6, base * 1.4);

  // Icon size scaling
  double ri(double base) => (base * _fontScale).clamp(base * 0.85, base * 1.25);

  // Whether this is a small screen (< 380px wide, e.g. older 5" phones)
  bool get isSmallPhone => sw < 380;

  // Whether this is a compact height screen (< 700px, e.g. 16:9 ratio phones)
  bool get isShortPhone => sh < 700;

  // Safe horizontal padding (min 12, scales up to 20 on wide screens)
  double get hPad => rp(16).clamp(12.0, 24.0);

  // Responsive card padding
  EdgeInsets get cardPadding => EdgeInsets.symmetric(
    horizontal: rp(14).clamp(10.0, 20.0),
    vertical:   rs(12).clamp(8.0, 18.0),
  );

  // Responsive section padding
  EdgeInsets get sectionPadding => EdgeInsets.symmetric(
    horizontal: hPad,
    vertical:   rs(8).clamp(6.0, 14.0),
  );
}