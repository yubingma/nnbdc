import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'theme/font_scale.dart';

/// 全局视觉主题状态管理
class DarkMode with ChangeNotifier {
  AppThemeStyle _themeStyle = AppThemeStyle.emerald;
  AppFontScale _fontScale = AppFontScale.medium;

  AppThemeStyle get themeStyle => _themeStyle;

  /// 全局字体大小档位（小 / 中 / 大）
  AppFontScale get fontScale => _fontScale;

  /// 是否为深底暗色模式（由当前选中的主题样式自动决定）
  bool get isDarkMode => _themeStyle.isDark;

  void setThemeStyle(AppThemeStyle style) {
    if (_themeStyle == style) return;
    _themeStyle = style;
    notifyListeners();
  }

  void setFontScale(AppFontScale scale) {
    if (_fontScale == scale) return;
    _fontScale = scale;
    notifyListeners();
  }

  /// 兼容旧方法调用：如果切换为暗色则选用 midnight，否则选用 aurora
  void setIsDarkMode(bool value) {
    if (value && !_themeStyle.isDark) {
      setThemeStyle(AppThemeStyle.midnight);
    } else if (!value && _themeStyle.isDark) {
      setThemeStyle(AppThemeStyle.emerald);
    }
  }
}
