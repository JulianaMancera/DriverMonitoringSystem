import 'package:flutter/foundation.dart';

class DbChangeNotifier extends ChangeNotifier {
  DbChangeNotifier._();
  static final DbChangeNotifier instance = DbChangeNotifier._();

  void notifyDataChanged() => notifyListeners();
}