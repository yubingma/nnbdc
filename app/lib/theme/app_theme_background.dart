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
          // 右上方：晨曦初照极光暖金微光
          Positioned(
            top: 10,
            right: -30,
            width: 300,
            height: 300,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x12FEF08A), // 约 7% 晨曦暖金光
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

  /// 2. 经典翡翠背景 (扇贝标志性极淡透光 - 98% 纯白基底，边角若有若无空气感微光)
  Widget _buildEmeraldBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFDFD), Color(0xFFF9FAF9)],
        ),
      ),
      child: Stack(
        children: [
          // 左上方：极淡生机薄荷微光（约 3%~4% 透明度，仅作天光漫透，绝不泛绿）
          Positioned(
            top: -40,
            left: -60,
            width: 380,
            height: 380,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 110, sigmaY: 110),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0910B981), // 约 3.5% 生机微光
                ),
              ),
            ),
          ),
          // 右上方：晨曦微光淡暖阳（约 2.5% 透明度，若有若无的舒适暖意）
          Positioned(
            top: -20,
            right: -60,
            width: 360,
            height: 360,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 110, sigmaY: 110),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x07FDE047), // 约 2.7% 极淡晨曦金光
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. 暮色落日背景 (温暖轻柔晚霞光晕 + 晨曦粉金 - 清爽微润，通透无浑浊)
  Widget _buildSunsetBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCFBF9), Color(0xFFF8F5F0)],
        ),
      ),
      child: Stack(
        children: [
          // 左上方：柔和落日暖橘（极淡空气感，约 4%）
          Positioned(
            top: -20,
            left: -30,
            width: 350,
            height: 350,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 110, sigmaY: 110),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0AFB923C), // 约 3.9% 晚霞橘
                ),
              ),
            ),
          ),
          // 右上方：蜜桃粉金暖光（约 3%）
          Positioned(
            top: 20,
            right: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 105, sigmaY: 105),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x08FDE047), // 约 3.1% 温暖淡金
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

  /// 6. 京都朱砂背景 (和纸质感与朱砂微光 + 晨曦暖杏 - 纯净雅致)
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
          // 左上方：典雅朱砂柔光（约 3.5%）
          Positioned(
            top: -20,
            left: -40,
            width: 350,
            height: 350,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 110, sigmaY: 110),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x09E11D48), // 约 3.5% 朱砂微光
                ),
              ),
            ),
          ),
          // 右上方：和纸暖杏晨曦金光（约 3%）
          Positioned(
            top: 20,
            right: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 105, sigmaY: 105),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x08FDE047), // 约 3.1% 和纸暖金光
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 7. 星云深靛背景 (Linear 风格极客冷灰与深靛光晕 + 星云暖光)
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
          // 左上方：工艺深靛蓝冷光（约 4%）
          Positioned(
            top: -20,
            left: -40,
            width: 350,
            height: 350,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 110, sigmaY: 110),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0B6366F1), // 约 4.3% 深靛冷光
                ),
              ),
            ),
          ),
          // 右上方：星云暖杏微光（约 3%）
          Positioned(
            top: 20,
            right: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 105, sigmaY: 105),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x08FED7AA), // 约 3.1% 暖杏微光
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 8. 鼠尾草森背景 (Gentler Streak 风格治愈海盐青木 + 浅草暖阳)
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
          // 左上方：舒缓海盐青木光（约 4%）
          Positioned(
            top: -20,
            left: -40,
            width: 350,
            height: 350,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 110, sigmaY: 110),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0A0D9488), // 约 3.9% 海盐青木光
                ),
              ),
            ),
          ),
          // 右上方：浅草柠檬金阳微光（约 3%）
          Positioned(
            top: 20,
            right: -40,
            width: 320,
            height: 320,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 105, sigmaY: 105),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x08D9F99D), // 约 3.1% 浅草柠檬金
                ),
              ),
            ),
          ),
          // 底部居中：薄荷微光
          Positioned(
            bottom: 60,
            left: 20,
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
