import 'package:flutter_riverpod/flutter_riverpod.dart';

class DbChangeCounter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final dbChangeCounterProvider = NotifierProvider<DbChangeCounter, int>(
  DbChangeCounter.new,
);
