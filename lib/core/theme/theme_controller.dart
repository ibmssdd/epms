import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void setTheme(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;
    notifyListeners();
  }
}
