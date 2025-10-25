import 'package:flutter/material.dart';

class DarkMode with ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void setIsDarkMode(bool value) {
    _isDarkMode = value;
    notifyListeners();
  }
}
