import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 全局自适应主题背景层组件 (独立 5 大主题)
class AppThemeBackground extends StatelessWidget {
  final AppThemeStyle themeStyle;
  final bool? isDarkMode; // 兼容保留

  const AppThemeBackground({
    super.key,
    required this.themeStyle,
    this.isDarkMode,
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
      case AppThemeStyle.midnight:
        return _buildMidnightBackground();
    }
  }

  /// 1. 晨曦流光背景 (DeepSeek 空灵风)
  Widget _buildAuroraBackground() {
    const baseBg = Color(0xFFF5F9F8);
    const glowBlue = Color(0x3860A5FA);
    const glowCyan = Color(0x2E2DD4BF);
    const glowIndigo = Color(0x26A5B4FC);
    const glowWhite = Color(0xB8FFFFFF);

    return Container(
      color: baseBg,
      child: Stack(
        children: [
          Positioned(
            top: 20,
            left: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 85, sigmaY: 85),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowBlue,
                ),
              ),
            ),
          ),
          Positioned(
            top: 130,
            right: -50,
            width: 340,
            height: 360,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowCyan,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowIndigo,
                ),
              ),
            ),
          ),
          Positioned(
            top: 230,
            left: 50,
            width: 280,
            height: 280,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                decoration: const BoxDecoration(
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
    return Container(color: const Color(0xFFF7FAF8));
  }

  /// 3. 东方羊脂玉背景 (温润水头微渐变)
  Widget _buildJadeBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FBF9), Color(0xFFEAF4F0)],
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x24059669),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 4. 极简白墨背景 (极客专注风)
  Widget _buildMinimalBackground() {
    return Container(color: const Color(0xFFFAFAFA));
  }

  /// 5. 深邃曜黑背景 (沉浸夜间风)
  Widget _buildMidnightBackground() {
    const baseBg = Color(0xFF080E0C);
    const glowBlue = Color(0x383B82F6);
    const glowCyan = Color(0x332CD88F);
    const glowIndigo = Color(0x26818CF8);
    const glowCenter = Color(0x33142B24);

    return Container(
      color: baseBg,
      child: Stack(
        children: [
          Positioned(
            top: 20,
            left: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 85, sigmaY: 85),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowBlue,
                ),
              ),
            ),
          ),
          Positioned(
            top: 130,
            right: -50,
            width: 340,
            height: 360,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowCyan,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowIndigo,
                ),
              ),
            ),
          ),
          Positioned(
            top: 230,
            left: 50,
            width: 280,
            height: 280,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowCenter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
