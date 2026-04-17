import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Responsive — adaptive layout utilities for Bantay Drive
//
// DESIGN BASE (the phone all sizes scale FROM):
//   Width  : 390 dp  (Pixel 6 / mid-range reference)
//   Height : 844 dp  (same reference)
//
// PHONE SIZE TIERS (portrait width):
//   Compact  < 360 dp  → older/budget phones (e.g. Galaxy A03)
//   Small    360–379   → common budget phones (e.g. Redmi Note)
//   Medium   380–409   → mid-range standard  (e.g. Pixel 6, Galaxy A54)
//   Large    410–429   → big phones          (e.g. Pixel 7 Pro)
//   XLarge   ≥ 430 dp  → max size phones     (e.g. Galaxy S23 Ultra)
//
// BRAND-AWARE SCALING:
//   Samsung  → 0.95×  (One UI inflates default UI chrome & text)
//   Xiaomi   → 0.97×  (MIUI renders slightly larger than stock)
//   Others   → 1.00×  (no adjustment)
//
// ALL scaling (fonts, padding, spacing, icons) uses the SAME scale factor
// so nothing drifts relative to anything else.
// ─────────────────────────────────────────────────────────────────────────────

// ── Android OEM brand enum ────────────────────────────────────────────────────
enum DeviceBrand { samsung, xiaomi, oppo, vivo, pixel, other }

class Responsive {
  // ── Design base ─────────────────────────────────────────────────────────────
  static const double _baseW = 390.0;
  static const double _baseH = 844.0;

  // ── Brand-aware scale tweak ───────────────────────────────────────────────
  // Set once at app startup via Responsive.setBrand(). All scale functions
  // read this so every font, padding, and icon shrinks or grows together.
  static DeviceBrand _deviceBrand = DeviceBrand.other;

  /// Call this from main() after reading DeviceInfoPlugin.
  static void setBrand(DeviceBrand brand) => _deviceBrand = brand;

  /// The currently detected brand (readable from anywhere).
  static DeviceBrand get deviceBrand => _deviceBrand;

  /// Per-brand multiplier applied on top of the screen-size scale.
  /// Samsung One UI and MIUI ship with larger default UI chrome and a
  /// textScaleFactor above 1.0 even on "Normal" — this nudge compensates
  /// so layouts don't overflow on those devices.
  static double _brandFactor() {
    switch (_deviceBrand) {
      case DeviceBrand.samsung: return 0.92;
      case DeviceBrand.xiaomi:  return 0.97;
      case DeviceBrand.oppo:    return 0.97;
      case DeviceBrand.vivo:    return 0.97;
      case DeviceBrand.pixel:   return 1.00;
      case DeviceBrand.other:   return 1.00;
    }
  }

  // ── Legacy breakpoints (kept for tablet/desktop guards) ───────────────────
  static const double mobileBreakpoint  = 600;
  static const double tabletBreakpoint  = 900;
  static const double desktopBreakpoint = 1200;

  // ── Device type ───────────────────────────────────────────────────────────
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final s = MediaQuery.of(context).size.shortestSide;
    return s >= mobileBreakpoint && s < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= desktopBreakpoint;

  // ── Portrait width for phone tier detection ───────────────────────────────
  /// Always returns the SHORTER side so tier is stable in landscape too.
  static double _shortSide(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide;

  // ── Unified scale factor (width-driven + brand-aware) ────────────────────
  /// All sp / rp / rs / ri use this ONE factor so they stay proportional.
  /// Clamped to [0.82, 1.20] to prevent extreme sizes on very small or
  /// very large phones. Multiplied by _brandFactor() to compensate for
  /// OEM-specific UI inflation (e.g. Samsung One UI, MIUI).
  static double scaleFactor(BuildContext context) =>
      (_shortSide(context) / _baseW * _brandFactor()).clamp(0.82, 1.20);

  // ── Height scale (for vertical spacing only) ──────────────────────────────
  /// Separate vertical scale so tall/short phones don't break layouts.
  /// Uses the LONGER side so it's stable in landscape.
  static double _heightScale(BuildContext context) {
    final longSide = MediaQuery.of(context).size.longestSide;
    return (longSide / _baseH).clamp(0.80, 1.25);
  }

  // ── Phone size tier ───────────────────────────────────────────────────────
  static PhoneTier phoneTier(BuildContext context) {
    final w = _shortSide(context);
    if (w < 360) return PhoneTier.compact;
    if (w < 380) return PhoneTier.small;
    if (w < 410) return PhoneTier.medium;
    if (w < 430) return PhoneTier.large;
    return PhoneTier.xlarge;
  }

  // ── Font ─────────────────────────────────────────────────────────────────
  /// Pass your design-base font size (designed for 390dp phone).
  /// It scales up/down uniformly across all phone sizes.
  static double sp(BuildContext context, double size) =>
      (size * scaleFactor(context)).roundToDouble();

  // ── Padding / horizontal spacing ─────────────────────────────────────────
  static double rp(BuildContext context, double base) =>
      (base * scaleFactor(context)).clamp(base * 0.75, base * 1.30);

  // ── Vertical spacing ─────────────────────────────────────────────────────
  static double rs(BuildContext context, double base) =>
      (base * _heightScale(context)).clamp(base * 0.75, base * 1.25);

  // ── Icon size ─────────────────────────────────────────────────────────────
  static double ri(BuildContext context, double base) =>
      (base * scaleFactor(context)).clamp(base * 0.80, base * 1.20);

  // ── Responsive value helper ───────────────────────────────────────────────
  /// Returns a different value per phone tier.
  /// If a tier value is omitted, falls back to [base].
  static T tier<T>(
    BuildContext context, {
    required T base,       // medium — your default design value
    T? compact,            // < 360dp
    T? small,              // 360–379dp
    T? large,              // 410–429dp
    T? xlarge,             // ≥ 430dp
    T? tablet,             // shortestSide ≥ 600dp
  }) {
    if (isTablet(context) || isDesktop(context)) return tablet ?? base;
    switch (phoneTier(context)) {
      case PhoneTier.compact: return compact ?? small ?? base;
      case PhoneTier.small:   return small   ?? base;
      case PhoneTier.medium:  return base;
      case PhoneTier.large:   return large   ?? base;
      case PhoneTier.xlarge:  return xlarge  ?? large ?? base;
    }
  }

  // ── Legacy helpers (kept so existing screens don't break) ────────────────
  static double responsiveFont(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) => sp(context, isTablet(context) || isDesktop(context)
      ? (tablet ?? mobile * 1.15)
      : mobile);

  static double responsivePadding(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) => rp(context, isTablet(context) || isDesktop(context)
      ? (tablet ?? mobile * 1.5)
      : mobile);

  static double responsiveSpacing(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) => rs(context, isTablet(context) || isDesktop(context)
      ? (tablet ?? mobile * 1.5)
      : mobile);

  static double responsiveHeight(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) => rs(context, isTablet(context) || isDesktop(context)
      ? (tablet ?? mobile * 1.15)
      : mobile);

  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context))  return tablet ?? mobile;
    return mobile;
  }

  static double responsiveBorderRadius(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) => rp(context, isTablet(context) || isDesktop(context)
      ? (tablet ?? mobile * 1.1)
      : mobile);

  static double responsiveIconSize(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) => ri(context, isTablet(context) || isDesktop(context)
      ? (tablet ?? mobile * 1.15)
      : mobile);

  // ── Dimensions ──────────────────────────────────────────────────────────
  static double getWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double getHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static double getScaleFactor(BuildContext context) =>
      scaleFactor(context);

  static double getMaxContentWidth(BuildContext context) {
    if (isDesktop(context)) return 1400;
    if (isTablet(context))  return 1024;
    return double.infinity;
  }
}

// ── Phone size enum ───────────────────────────────────────────────────────────
enum PhoneTier { compact, small, medium, large, xlarge }

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext extensions
//
// All methods use the SAME scale factor so fonts, padding, and spacing
// stay visually consistent with each other across all phone sizes.
//
// Usage (unchanged from before — drop-in replacement):
//   context.sw          → screen width
//   context.sh          → screen height
//   context.sp(14)      → font size (scales from 390dp base)
//   context.rp(16)      → horizontal padding/spacing
//   context.rs(12)      → vertical spacing
//   context.ri(20)      → icon size
//   context.wp(0.05)    → 5% of screen width
//   context.hp(0.10)    → 10% of screen height
//   context.phoneTier   → current PhoneTier enum value
// ─────────────────────────────────────────────────────────────────────────────
extension ResponsiveContext on BuildContext {
  // ── Dimensions ──────────────────────────────────────────────────────────
  double get sw => MediaQuery.of(this).size.width;
  double get sh => MediaQuery.of(this).size.height;

  // ── Unified scale factor ─────────────────────────────────────────────────
  /// Width-driven. All sp/rp/ri use this.
  double get _scale => Responsive.scaleFactor(this);

  /// Height-driven. Only rs uses this.
  double get _hScale => (sh / 844.0).clamp(0.80, 1.25);

  // ── Phone tier ───────────────────────────────────────────────────────────
  PhoneTier get phoneTier => Responsive.phoneTier(this);

  // ── Font ─────────────────────────────────────────────────────────────────
  /// Design your font sizes for a 390dp phone — they scale uniformly.
  double sp(double size) => (size * _scale).roundToDouble();

  // ── Horizontal padding / spacing ─────────────────────────────────────────
  double rp(double base) =>
      (base * _scale).clamp(base * 0.75, base * 1.30);

  // ── Vertical spacing ─────────────────────────────────────────────────────
  double rs(double base) =>
      (base * _hScale).clamp(base * 0.75, base * 1.25);

  // ── Icon size ─────────────────────────────────────────────────────────────
  double ri(double base) =>
      (base * _scale).clamp(base * 0.80, base * 1.20);

  // ── Percentage helpers ───────────────────────────────────────────────────
  double wp(double fraction) => sw * fraction;
  double hp(double fraction) => sh * fraction;

  // ── Named shortcuts ───────────────────────────────────────────────────────
  bool get isSmallPhone =>
      Responsive.phoneTier(this) == PhoneTier.compact ||
      Responsive.phoneTier(this) == PhoneTier.small;

  bool get isShortPhone => sh < 700;

  // ── Padding helpers ───────────────────────────────────────────────────────
  /// Safe horizontal page padding — tighter on small phones.
  double get hPad {
    switch (phoneTier) {
      case PhoneTier.compact: return rp(12);
      case PhoneTier.small:   return rp(14);
      default:                return rp(16).clamp(14.0, 24.0);
    }
  }

  /// Responsive card padding.
  EdgeInsets get cardPadding => EdgeInsets.symmetric(
    horizontal: rp(14).clamp(10.0, 20.0),
    vertical:   rs(12).clamp(8.0, 18.0),
  );

  /// Responsive section padding.
  EdgeInsets get sectionPadding => EdgeInsets.symmetric(
    horizontal: hPad,
    vertical:   rs(8).clamp(6.0, 14.0),
  );

  // ── Tier-based value picker ───────────────────────────────────────────────
  /// Pick a different value per phone size tier.
  /// Example: context.forTier(base: 14.0, compact: 11.0, large: 16.0)
  T forTier<T>({
    required T base,
    T? compact,
    T? small,
    T? large,
    T? xlarge,
  }) {
    switch (phoneTier) {
      case PhoneTier.compact: return compact ?? small ?? base;
      case PhoneTier.small:   return small ?? base;
      case PhoneTier.medium:  return base;
      case PhoneTier.large:   return large ?? base;
      case PhoneTier.xlarge:  return xlarge ?? large ?? base;
    }
  }
}