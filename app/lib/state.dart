import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

class DarkMode with ChangeNotifier {
  bool _isDarkMode = false;
  AppThemeStyle _themeStyle = AppThemeStyle.aurora;

  bool get isDarkMode => _isDarkMode;
  AppThemeStyle get themeStyle => _themeStyle;

  void setIsDarkMode(bool value) {
    _isDarkMode = value;
    notifyListeners();
  }

  void setThemeStyle(AppThemeStyle style) {
    _themeStyle = style;
    notifyListeners();
  }
}
