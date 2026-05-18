import 'package:flutter_riverpod/flutter_riverpod.dart';

class StringNotifier extends Notifier<String> {
  final String _initial;
  StringNotifier(this._initial);
  @override
  String build() => _initial;
  void set(String v) => state = v;
}

class DoubleNotifier extends Notifier<double> {
  final double _initial;
  DoubleNotifier(this._initial);
  @override
  double build() => _initial;
  void set(double v) => state = v;
}

class BoolNotifier extends Notifier<bool> {
  final bool _initial;
  BoolNotifier(this._initial);
  @override
  bool build() => _initial;
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

class NullableStringNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

class IntNotifier extends Notifier<int> {
  final int _initial;
  IntNotifier(this._initial);
  @override
  int build() => _initial;
  void set(int v) => state = v;
}

final driverStateProvider = NotifierProvider<StringNotifier, String>(
    () => StringNotifier('neutral'));
final alertnessPctProvider = NotifierProvider<DoubleNotifier, double>(
    () => DoubleNotifier(100.0));
final drowsinessPctProvider = NotifierProvider<DoubleNotifier, double>(
    () => DoubleNotifier(0.0));
final distractionPctProvider = NotifierProvider<DoubleNotifier, double>(
    () => DoubleNotifier(0.0));
final isRecordingProvider = NotifierProvider<BoolNotifier, bool>(
    () => BoolNotifier(false));
final showAlertBannerProvider = NotifierProvider<BoolNotifier, bool>(
    () => BoolNotifier(false));
final alertBannerTypeProvider = NotifierProvider<StringNotifier, String>(
    () => StringNotifier('DROWSY'));
final isInPipProvider = NotifierProvider<BoolNotifier, bool>(
    () => BoolNotifier(false));
final activeSubclassProvider =
    NotifierProvider<NullableStringNotifier, String?>(
        NullableStringNotifier.new);
final activeSubclassIndexProvider = NotifierProvider<IntNotifier, int>(
    () => IntNotifier(0));

class _NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int index) => state = index;
}

final navIndexProvider = NotifierProvider<_NavIndexNotifier, int>(
  _NavIndexNotifier.new,
);
