import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dbChangeCounterProvider = StateProvider<int>((ref) => 0);
