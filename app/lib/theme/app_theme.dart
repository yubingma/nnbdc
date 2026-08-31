import 'package:flutter/material.dart';

class AppTheme {
  // 扇贝护眼主题绿体系
  // 主品牌色：扇贝翡翠绿
  static const Color primaryColor = Color(0xFF18BA7C);

  // 主题色的深色版本（用于按钮阴影、渐变终点等）
  static const Color primaryDarkColor = Color(0xFF109E69);

  // 主题色的浅色版本（用于悬浮、高亮等）
  static const Color primaryLightColor = Color(0xFF2CD88F);

  // 渐变开始色
  static const Color gradientStartColor = Color(0xFF18BA7C);

  // 渐变结束色
  static const Color gradientEndColor = Color(0xFF109E69);

  // 创建亮色主题
  static ThemeData lightTheme() {
    return ThemeData(
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        primaryContainer: primaryLightColor,
        surface: Colors.white,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      useMaterial3: true,
      // 应用栏主题
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      // 浮动操作按钮主题
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1), width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      // 进度指示器主题
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
      ),
      // 底部导航栏主题
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF6B7280), // 更深一些的灰色，提升可见性
      ),
    );
  }

  // 创建暗色主题
  static ThemeData darkTheme() {
    return ThemeData(
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        primaryContainer: primaryLightColor,
        surface: const Color(0xFF1E1E1E),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      useMaterial3: true,
      // 应用栏主题
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      // 浮动操作按钮主题
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      // 进度指示器主题
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
      ),
      // 底部导航栏主题
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF9CA3AF), // 亮一些的灰色，提升暗深色背景下的可见性
      ),
    );
  }

  // 创建渐变AppBar
  static PreferredSizeWidget createGradientAppBar({
    required String title,
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
  }) {
    return AppBar(
      title: Text(title),
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradientStartColor, gradientEndColor],
          ),
        ),
      ),
    );
  }
}
