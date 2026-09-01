import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

/// 全局视觉主题状态管理
class DarkMode with ChangeNotifier {
  AppThemeStyle _themeStyle = AppThemeStyle.aurora;

  AppThemeStyle get themeStyle => _themeStyle;

  /// 是否为深底暗色模式（由当前选中的主题样式自动决定）
  bool get isDarkMode => _themeStyle.isDark;

  void setThemeStyle(AppThemeStyle style) {
    if (_themeStyle == style) return;
    _themeStyle = style;
    notifyListeners();
  }

  /// 兼容旧方法调用：如果切换为暗色则选用 midnight，否则选用 aurora
  void setIsDarkMode(bool value) {
    if (value && !_themeStyle.isDark) {
      setThemeStyle(AppThemeStyle.midnight);
    } else if (!value && _themeStyle.isDark) {
      setThemeStyle(AppThemeStyle.aurora);
    }
  }
}
