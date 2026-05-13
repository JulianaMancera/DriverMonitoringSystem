import 'package:flutter/material.dart';

enum DeviceBrand { samsung, xiaomi, oppo, vivo, pixel, other }

class Responsive {
  static const double _baseW = 390.0;
  static const double _baseH = 844.0;

  static DeviceBrand _deviceBrand = DeviceBrand.other;

  static void setBrand(DeviceBrand brand) => _deviceBrand = brand;
  static DeviceBrand get deviceBrand => _deviceBrand;

  // Per-brand multiplier compensates for OEM UI chrome inflation
  // (Samsung One UI, MIUI, ColorOS all scale text/chrome above stock Android).
  static double _brandFactor() => switch (_deviceBrand) {
    DeviceBrand.samsung => 0.92,
    DeviceBrand.xiaomi || DeviceBrand.oppo || DeviceBrand.vivo => 0.97,
    DeviceBrand.pixel || DeviceBrand.other => 1.00,
  };

  static const double mobileBreakpoint  = 600;
  static const double tabletBreakpoint  = 900;
  static const double desktopBreakpoint = 1200;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final s = MediaQuery.of(context).size.shortestSide;
    return s >= mobileBreakpoint && s < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= desktopBreakpoint;

  static double _shortSide(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide;

  // All sp / rp / rs / ri use this one factor so they stay proportional.
  // Clamped to [0.82, 1.20] to prevent extreme sizes on edge-case phones.
  static double scaleFactor(BuildContext context) =>
      (_shortSide(context) / _baseW * _brandFactor()).clamp(0.82, 1.20);

  static double _heightScale(BuildContext context) {
    final longSide = MediaQuery.of(context).size.longestSide;
    return (longSide / _baseH).clamp(0.80, 1.25);
  }

  static PhoneTier phoneTier(BuildContext context) {
    final w = _shortSide(context);
    if (w < 360) return PhoneTier.compact;
    if (w < 380) return PhoneTier.small;
    if (w < 410) return PhoneTier.medium;
    if (w < 430) return PhoneTier.large;
    return PhoneTier.xlarge;
  }

  static double sp(BuildContext context, double size) =>
      (size * scaleFactor(context)).roundToDouble();

  static double rp(BuildContext context, double base) =>
      (base * scaleFactor(context)).clamp(base * 0.75, base * 1.30);

  static double rs(BuildContext context, double base) =>
      (base * _heightScale(context)).clamp(base * 0.75, base * 1.25);

  static double ri(BuildContext context, double base) =>
      (base * scaleFactor(context)).clamp(base * 0.80, base * 1.20);

  static T tier<T>(
    BuildContext context, {
    required T base,
    T? compact,
    T? small,
    T? large,
    T? xlarge,
    T? tablet,
  }) {
    if (isTablet(context) || isDesktop(context)) return tablet ?? base;
    return switch (phoneTier(context)) {
      PhoneTier.compact => compact ?? small ?? base,
      PhoneTier.small   => small   ?? base,
      PhoneTier.medium  => base,
      PhoneTier.large   => large   ?? base,
      PhoneTier.xlarge  => xlarge  ?? large ?? base,
    };
  }

  static double getWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double getHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static double getScaleFactor(BuildContext context) => scaleFactor(context);

  static double getMaxContentWidth(BuildContext context) {
    if (isDesktop(context)) return 1400;
    if (isTablet(context))  return 1024;
    return double.infinity;
  }
}

enum PhoneTier { compact, small, medium, large, xlarge }

extension ResponsiveContext on BuildContext {
  double get sw => MediaQuery.of(this).size.width;
  double get sh => MediaQuery.of(this).size.height;

  double get _scale => Responsive.scaleFactor(this);
  double get _hScale => (sh / 844.0).clamp(0.80, 1.25);

  PhoneTier get phoneTier => Responsive.phoneTier(this);

  double sp(double size) => (size * _scale).roundToDouble();

  double rp(double base) =>
      (base * _scale).clamp(base * 0.75, base * 1.30);

  double rs(double base) =>
      (base * _hScale).clamp(base * 0.75, base * 1.25);

  double ri(double base) =>
      (base * _scale).clamp(base * 0.80, base * 1.20);

  double wp(double fraction) => sw * fraction;
  double hp(double fraction) => sh * fraction;

  bool get isSmallPhone =>
      Responsive.phoneTier(this) == PhoneTier.compact ||
      Responsive.phoneTier(this) == PhoneTier.small;

  bool get isShortPhone => sh < 700;

  double get hPad => switch (phoneTier) {
    PhoneTier.compact => rp(12),
    PhoneTier.small   => rp(14),
    _                 => rp(16).clamp(14.0, 24.0),
  };

  EdgeInsets get cardPadding => EdgeInsets.symmetric(
    horizontal: rp(14).clamp(10.0, 20.0),
    vertical:   rs(12).clamp(8.0, 18.0),
  );

  EdgeInsets get sectionPadding => EdgeInsets.symmetric(
    horizontal: hPad,
    vertical:   rs(8).clamp(6.0, 14.0),
  );

  T forTier<T>({
    required T base,
    T? compact,
    T? small,
    T? large,
    T? xlarge,
  }) => switch (phoneTier) {
    PhoneTier.compact => compact ?? small ?? base,
    PhoneTier.small   => small ?? base,
    PhoneTier.medium  => base,
    PhoneTier.large   => large ?? base,
    PhoneTier.xlarge  => xlarge ?? large ?? base,
  };
}
