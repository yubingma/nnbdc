import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 全局自适应主题背景层组件
class AppThemeBackground extends StatelessWidget {
  final bool isDarkMode;
  final AppThemeStyle themeStyle;

  const AppThemeBackground({
    super.key,
    required this.isDarkMode,
    required this.themeStyle,
  });

  @override
  Widget build(BuildContext context) {
    switch (themeStyle) {
      case AppThemeStyle.aurora:
        return _buildAuroraBackground();
      case AppThemeStyle.emerald:
        return _buildEmeraldBackground();
      case AppThemeStyle.jade:
        return _buildJadeBackground();
      case AppThemeStyle.minimal:
        return _buildMinimalBackground();
    }
  }

  /// 1. 晨曦流光背景 (DeepSeek 空灵风)
  Widget _buildAuroraBackground() {
    final baseBg = isDarkMode ? const Color(0xFF070E0C) : const Color(0xFFF5F9F8);
    final glowBlue = isDarkMode ? const Color(0x383B82F6) : const Color(0x3860A5FA);
    final glowCyan = isDarkMode ? const Color(0x332CD88F) : const Color(0x2E2DD4BF);
    final glowIndigo = isDarkMode ? const Color(0x26818CF8) : const Color(0x26A5B4FC);
    final glowWhite = isDarkMode ? const Color(0x331E3A32) : const Color(0xB8FFFFFF);

    return Container(
      color: baseBg,
      child: Stack(
        children: [
          // 晕染 1：左上天空微蓝漫射光斑
          Positioned(
            top: 20,
            left: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 85, sigmaY: 85),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowBlue,
                ),
              ),
            ),
          ),
          // 晕染 2：右侧中上翡翠微青水晕
          Positioned(
            top: 130,
            right: -50,
            width: 340,
            height: 360,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowCyan,
                ),
              ),
            ),
          ),
          // 晕染 3：左下方柔和幽蓝浅紫
          Positioned(
            bottom: 60,
            left: 0,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowIndigo,
                ),
              ),
            ),
          ),
          // 晕染 4：中心透亮纯净高光
          Positioned(
            top: 230,
            left: 50,
            width: 280,
            height: 280,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowWhite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2. 经典翡翠背景 (扇贝纯净温润风)
  Widget _buildEmeraldBackground() {
    final baseBg = isDarkMode ? const Color(0xFF0C1613) : const Color(0xFFF7FAF8);
    return Container(color: baseBg);
  }

  /// 3. 东方羊脂玉背景 (温润水头微渐变)
  Widget _buildJadeBackground() {
    final gradientColors = isDarkMode
        ? const [Color(0xFF10201B), Color(0xFF091210)]
        : const [Color(0xFFF7FAF8), Color(0xFFEBF3F0)];
    final jadeTint = isDarkMode ? const Color(0x2B2CD88F) : const Color(0x2818BA7C);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 80,
            right: -60,
            width: 280,
            height: 280,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: jadeTint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 4. 极简纯黑白背景 (极客专注风)
  Widget _buildMinimalBackground() {
    final baseBg = isDarkMode ? const Color(0xFF0A0A0A) : const Color(0xFFF9F9FB);
    return Container(color: baseBg);
  }
}
