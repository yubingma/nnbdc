import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 全局自适应主题背景层组件 (5 款极具鲜明辨识度的主题专属背景)
class AppThemeBackground extends StatelessWidget {
  final AppThemeStyle themeStyle;
  final bool? isDarkMode;

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
      case AppThemeStyle.sunset:
        return _buildSunsetBackground();
      case AppThemeStyle.minimal:
        return _buildMinimalBackground();
      case AppThemeStyle.midnight:
        return _buildMidnightBackground();
    }
  }

  /// 1. 晨曦流光背景 (冰川冷蓝极光风)
  Widget _buildAuroraBackground() {
    const baseBg = Color(0xFFF0F7FA);
    const glowBlue = Color(0x4538BDF8);
    const glowCyan = Color(0x3D06B6D4);
    const glowIndigo = Color(0x33818CF8);
    const glowWhite = Color(0xCCFFFFFF);

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

  /// 2. 经典翡翠背景 (扇贝温润草本抹茶绿底)
  Widget _buildEmeraldBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2F9F5), Color(0xFFE5F3EB)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 60,
            right: -50,
            width: 300,
            height: 300,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x2E10B981),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -40,
            width: 260,
            height: 260,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 65, sigmaY: 65),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x2434D399),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. 暮色落日背景 (温暖活力晚霞粉橙光晕)
  Widget _buildSunsetBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF7F2), Color(0xFFFFECE0)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 30,
            right: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 85, sigmaY: 85),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x40FB923C),
                ),
              ),
            ),
          ),
          Positioned(
            top: 180,
            left: -40,
            width: 300,
            height: 300,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x33F43F5E),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            right: 20,
            width: 280,
            height: 280,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 75, sigmaY: 75),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x3DFBBF24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 4. 极简白墨背景 (极客纯白高对比)
  Widget _buildMinimalBackground() {
    return Container(color: const Color(0xFFFFFFFF));
  }

  /// 5. 深邃曜黑背景 (赛博暗黑极光荧光翡翠)
  Widget _buildMidnightBackground() {
    const baseBg = Color(0xFF060B09);
    const glowBlue = Color(0x383B82F6);
    const glowCyan = Color(0x402CD88F);
    const glowIndigo = Color(0x26818CF8);
    const glowCenter = Color(0x3810B981);

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
