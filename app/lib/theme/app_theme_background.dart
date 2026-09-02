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
      case AppThemeStyle.crimson:
        return _buildCrimsonBackground();
      case AppThemeStyle.indigo:
        return _buildIndigoBackground();
      case AppThemeStyle.sage:
        return _buildSageBackground();
      case AppThemeStyle.twilight:
        return _buildTwilightBackground();
    }
  }

  /// 1. 晨曦流光背景 (冰川冷蓝极光风 - 极轻透通透漫反射)
  Widget _buildAuroraBackground() {
    const baseBg = Color(0xFFF8FAFC);
    const glowBlue = Color(0x1A38BDF8); // 约 10% 轻柔冷蓝
    const glowCyan = Color(0x1406B6D4); // 约 8% 纯净青蓝
    const glowIndigo = Color(0x10818CF8); // 约 6% 空灵靛青
    const glowWhite = Color(0x80FFFFFF);

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
              imageFilter: ui.ImageFilter.blur(sigmaX: 95, sigmaY: 95),
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 95, sigmaY: 95),
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 75, sigmaY: 75),
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

  /// 2. 经典翡翠背景 (扇贝温润草本抹茶绿底 - 轻柔通透)
  Widget _buildEmeraldBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFAFDFB), Color(0xFFF2F7F4)],
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x1210B981), // 约 7% 清透翡翠微光
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 75, sigmaY: 75),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0F34D399), // 约 6% 浅草绿微光
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. 暮色落日背景 (温暖轻柔晚霞光晕 - 清爽微润，杜绝过浓发腻)
  Widget _buildSunsetBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFBF9), Color(0xFFF8F6F2)],
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 95, sigmaY: 95),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x14FB923C), // 约 8% 温暖晚霞微光
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0FF43F5E), // 约 6% 浅粉柔光
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 85, sigmaY: 85),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x10FBBF24), // 约 6% 金黄微光
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

  /// 6. 京都朱砂背景 (和纸质感与朱砂微光 - 纯净雅致)
  Widget _buildCrimsonBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFBF9), Color(0xFFF9F7F5)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 40,
            right: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 95, sigmaY: 95),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0DE11D48), // 约 5% 朱砂微光
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -30,
            width: 280,
            height: 280,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0DFB7185), // 约 5% 暖粉微光
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 7. 星云深靛背景 (Linear 风格极客冷灰与深靛光晕)
  Widget _buildIndigoBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 30,
            right: -50,
            width: 340,
            height: 340,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x146366F1), // 约 8% 深靛冷光
                ),
              ),
            ),
          ),
          Positioned(
            top: 200,
            left: -40,
            width: 300,
            height: 300,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x10818CF8), // 约 6% 星云紫蓝
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 8. 鼠尾草森背景 (Gentler Streak 风格治愈海盐青绿漫反射)
  Widget _buildSageBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFAFBFB), Color(0xFFF0FDF4)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 50,
            left: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 95, sigmaY: 95),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x120D9488), // 约 7% 海盐青木光
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 90,
            right: -30,
            width: 280,
            height: 280,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 85, sigmaY: 85),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0E2DD4BF), // 约 5% 薄荷微光
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 9. 暮光深空背景 (Arc & Linear 曜石深空星云霓虹紫)
  Widget _buildTwilightBackground() {
    const baseBg = Color(0xFF07090E);
    const glowIndigo = Color(0x38818CF8); // 星云紫蓝
    const glowDeep = Color(0x284F46E5); // 深邃靛青
    const glowPurple = Color(0x20A855F7); // 暮光紫罗兰

    return Container(
      color: baseBg,
      child: Stack(
        children: [
          Positioned(
            top: 20,
            right: -40,
            width: 340,
            height: 340,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 95, sigmaY: 95),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowIndigo,
                ),
              ),
            ),
          ),
          Positioned(
            top: 180,
            left: -50,
            width: 320,
            height: 340,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowDeep,
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 85, sigmaY: 85),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowPurple,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
