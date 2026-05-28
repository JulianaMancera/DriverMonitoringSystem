import 'package:flutter_riverpod/flutter_riverpod.dart';

class SimpleNotifier<T> extends Notifier<T> {
  final T _initial;
  SimpleNotifier(this._initial);
  @override
  T build() => _initial;
  void set(T v) => state = v;
}

class BoolNotifier extends Notifier<bool> {
  final bool _initial;
  BoolNotifier(this._initial);
  @override
  bool build() => _initial;
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

final driverStateProvider = NotifierProvider<SimpleNotifier<String>, String>(
    () => SimpleNotifier('neutral'));
final alertnessPctProvider = NotifierProvider<SimpleNotifier<double>, double>(
    () => SimpleNotifier(100.0));
final drowsinessPctProvider = NotifierProvider<SimpleNotifier<double>, double>(
    () => SimpleNotifier(0.0));
final distractionPctProvider = NotifierProvider<SimpleNotifier<double>, double>(
    () => SimpleNotifier(0.0));
final isRecordingProvider = NotifierProvider<BoolNotifier, bool>(
    () => BoolNotifier(false));
final showAlertBannerProvider = NotifierProvider<BoolNotifier, bool>(
    () => BoolNotifier(false));
final alertBannerTypeProvider = NotifierProvider<SimpleNotifier<String>, String>(
    () => SimpleNotifier('DROWSY'));
final isInPipProvider = NotifierProvider<BoolNotifier, bool>(
    () => BoolNotifier(false));
final activeSubclassProvider =
    NotifierProvider<SimpleNotifier<String?>, String?>(
        () => SimpleNotifier(null));
final activeSubclassIndexProvider = NotifierProvider<SimpleNotifier<int>, int>(
    () => SimpleNotifier(0));

final navIndexProvider = NotifierProvider<SimpleNotifier<int>, int>(
  () => SimpleNotifier(0),
);
