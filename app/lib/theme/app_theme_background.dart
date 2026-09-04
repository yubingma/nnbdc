import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 全局自适应主题背景层组件 (对标不背单词原版：非对称自然双光源漫反射流光系统)
class AppThemeBackground extends StatelessWidget {
  final AppThemeStyle themeStyle;
  final bool? isDarkMode;

  const AppThemeBackground({
    super.key,
    required this.themeStyle,
    this.isDarkMode,
  });

  bool _resolveIsDark(BuildContext context) {
    if (isDarkMode != null) return isDarkMode!;
    return themeStyle.isDark;
  }

  @override
  Widget build(BuildContext context) {
    final dark = _resolveIsDark(context);

    switch (themeStyle) {
      case AppThemeStyle.aurora:
        return _buildAuroraBackground(dark);
      case AppThemeStyle.emerald:
        return _buildEmeraldBackground(dark);
      case AppThemeStyle.sunset:
        return _buildSunsetBackground(dark);
      case AppThemeStyle.minimal:
        return _buildMinimalBackground(dark);
      case AppThemeStyle.midnight:
        return _buildMidnightBackground(dark);
      case AppThemeStyle.crimson:
        return _buildCrimsonBackground(dark);
      case AppThemeStyle.indigo:
        return _buildIndigoBackground(dark);
      case AppThemeStyle.sage:
        return _buildSageBackground(dark);
      case AppThemeStyle.twilight:
        return _buildTwilightBackground(dark);
    }
  }

  /// 统一的高阶非对称自然双光源漫反射构建器 (奥卡姆剃刀：消除重复样板代码)
  Widget _buildAsymmetricGlow({
    required Color baseColor,
    required Color primaryGlowColor,
    required Alignment primaryAlign,
    required double primarySize,
    required double primaryBlur,
    required Color secondaryGlowColor,
    required Alignment secondaryAlign,
    required double secondarySize,
    required double secondaryBlur,
    Color? tertiaryGlowColor,
    Alignment? tertiaryAlign,
    double? tertiarySize,
    double? tertiaryBlur,
  }) {
    return Container(
      color: baseColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 主光源漫反射 (如晨曦白光或深邃极光)
          Align(
            alignment: primaryAlign,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: primaryBlur,
                sigmaY: primaryBlur,
              ),
              child: Container(
                width: primarySize,
                height: primarySize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryGlowColor,
                ),
              ),
            ),
          ),
          // 辅光源漫反射 (如青绿薄雾或深邃暗潮)
          Align(
            alignment: secondaryAlign,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: secondaryBlur,
                sigmaY: secondaryBlur,
              ),
              child: Container(
                width: secondarySize,
                height: secondarySize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: secondaryGlowColor,
                ),
              ),
            ),
          ),
          // 可选第三环境微光
          if (tertiaryGlowColor != null && tertiaryAlign != null)
            Align(
              alignment: tertiaryAlign,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: tertiaryBlur ?? 90,
                  sigmaY: tertiaryBlur ?? 90,
                ),
                child: Container(
                  width: tertiarySize ?? 280,
                  height: tertiarySize ?? 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tertiaryGlowColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 1. 晨曦流光背景 (冰川冷蓝)
  Widget _buildAuroraBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF040D17),
        primaryGlowColor: const Color(0x660E4466),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x40061C2E),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFD6E8F5),
      primaryGlowColor: const Color(0xCCFFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 110,
      secondaryGlowColor: const Color(0x400284C7),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }

  /// 2. 经典翡翠背景 (不背单词原版截图同款：浅色高岭土珍珠晨雾 / 深色黑曜石幽微极光)
  Widget _buildEmeraldBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF0A1411),
        primaryGlowColor: const Color(0x66183C30),
        primaryAlign: const Alignment(0.85, -0.75),
        primarySize: 400,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x380E221B),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 340,
        secondaryBlur: 100,
        tertiaryGlowColor: const Color(0x2810B981),
        tertiaryAlign: const Alignment(0.6, -0.4),
        tertiarySize: 260,
        tertiaryBlur: 80,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFDCE7E1),
      primaryGlowColor: const Color(0xD9FFFFFF), // 晨曦纯净透白高光
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 105,
      secondaryGlowColor: const Color(0x4D10B981), // 生机翡翠晨雾青绿
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
      tertiaryGlowColor: const Color(0x33BCE2CE),
      tertiaryAlign: const Alignment(0.2, 0.4),
      tertiarySize: 300,
      tertiaryBlur: 90,
    );
  }

  /// 3. 暮色落日背景 (温暖晚霞杏橙)
  Widget _buildSunsetBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF140703),
        primaryGlowColor: const Color(0x664E1C0C),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x38200C05),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFF5EAE4),
      primaryGlowColor: const Color(0xCCFFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 110,
      secondaryGlowColor: const Color(0x40F97316),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }

  /// 4. 极简白墨背景 (纯粹黑白珍珠灰)
  Widget _buildMinimalBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF0C0D10),
        primaryGlowColor: const Color(0x4D2D2D34),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x28141418),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFE5E7EB),
      primaryGlowColor: const Color(0xF2FFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 105,
      secondaryGlowColor: const Color(0x2B71717A),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }

  /// 5. 深邃曜黑背景 (极光墨玉)
  Widget _buildMidnightBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF060E0B),
        primaryGlowColor: const Color(0x66163A30),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x380A1814),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
        tertiaryGlowColor: const Color(0x332CD88F),
        tertiaryAlign: const Alignment(0.4, -0.3),
        tertiarySize: 260,
        tertiaryBlur: 85,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFD6EAE3),
      primaryGlowColor: const Color(0xCCFFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 110,
      secondaryGlowColor: const Color(0x402CD88F),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }

  /// 6. 京都朱砂背景 (山茶绯红)
  Widget _buildCrimsonBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF140408),
        primaryGlowColor: const Color(0x664C1020),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x3820080E),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFF5E5E8),
      primaryGlowColor: const Color(0xCCFFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 110,
      secondaryGlowColor: const Color(0x40E11D48),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }

  /// 7. 星云深靛背景 (梦幻夜空紫)
  Widget _buildIndigoBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF080917),
        primaryGlowColor: const Color(0x6626285C),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x3810112A),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFE3E6F8),
      primaryGlowColor: const Color(0xCCFFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 110,
      secondaryGlowColor: const Color(0x406366F1),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }

  /// 8. 鼠尾草森背景 (静谧苔原青)
  Widget _buildSageBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF05100F),
        primaryGlowColor: const Color(0x66123E3A),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x38081A18),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFD7E7E5),
      primaryGlowColor: const Color(0xCCFFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 110,
      secondaryGlowColor: const Color(0x400D9488),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }

  /// 9. 暮光深空背景 (曜石深空星云霓虹紫)
  Widget _buildTwilightBackground(bool dark) {
    if (dark) {
      return _buildAsymmetricGlow(
        baseColor: const Color(0xFF0E0516),
        primaryGlowColor: const Color(0x66381858),
        primaryAlign: const Alignment(0.8, -0.7),
        primarySize: 380,
        primaryBlur: 110,
        secondaryGlowColor: const Color(0x38180A26),
        secondaryAlign: const Alignment(-0.8, 0.8),
        secondarySize: 320,
        secondaryBlur: 95,
        tertiaryGlowColor: const Color(0x33A855F7),
        tertiaryAlign: const Alignment(0.5, -0.4),
        tertiarySize: 260,
        tertiaryBlur: 85,
      );
    }
    return _buildAsymmetricGlow(
      baseColor: const Color(0xFFECE4F6),
      primaryGlowColor: const Color(0xCCFFFFFF),
      primaryAlign: const Alignment(-0.7, -0.85),
      primarySize: 380,
      primaryBlur: 110,
      secondaryGlowColor: const Color(0x40A855F7),
      secondaryAlign: const Alignment(0.9, -0.3),
      secondarySize: 360,
      secondaryBlur: 120,
    );
  }
}
