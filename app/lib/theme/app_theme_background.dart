import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 全局自适应主题背景层组件
///
/// 浅色模式按屏幕分档：
/// - **窄高屏(手机，宽高比<0.62)**：低饱和的莫兰迪单色渐变(同主题色相，顶部浅→底部深，无光晕)；
/// - **方正屏(iPad/桌面，宽高比>=0.62)**：白底 + 主题色柔光晕(保持已认可的 iPad 质感)。
/// 深色模式：保留贯满全屏的"浅→深"纵向渐变带(带主题色相，无中心热点、无边缘骤退)。
///
/// [vibrancy]：各页可独立调节的"提气强度"(默认 0 即当前观感)。同一主题，
/// 需要更通透、更亮的页面(如登录页)传入更高强度，其余页面保持 0 不变。
/// 值越大提得越多，无上限；但只有"饱和度和明度"这两个物理量被收紧到 [0,1]，
/// 所以背景到纯白(亮度=1)即封顶，之后继续加大不再变亮。
class AppThemeBackground extends StatelessWidget {
  final AppThemeStyle themeStyle;
  final bool? isDarkMode;
  final double vibrancy;

  const AppThemeBackground({
    super.key,
    required this.themeStyle,
    this.isDarkMode,
    this.vibrancy = 0,
  });

  bool _resolveIsDark(BuildContext context) {
    if (isDarkMode != null) return isDarkMode!;
    return themeStyle.isDark;
  }

  /// 提气：在 HSL 空间内同时抬升饱和度和明度。两者各按 [0,1] 收紧，
  /// 因此 [vibrancy] 越大越亮，但到纯白即封顶。
  Color _lift(Color color) {
    if (vibrancy <= 0) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation((hsl.saturation + 0.10 * vibrancy).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + 0.14 * vibrancy).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    if (_resolveIsDark(context)) {
      final (top, mid, bottom) = _darkGradient(themeStyle);
      return _buildVerticalGradient(top, mid, bottom);
    }
    // 窄高屏(手机)用莫兰迪单色渐变；方正屏(iPad/桌面)保留白底+光晕
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width / size.height < 0.62;
    return isNarrow ? _buildLightMutedGradient(themeStyle) : _buildLightGlow(themeStyle);
  }

  /// 统一垂直渐变构建器：三段色贯穿全屏，上半段保持轻盈、下半段更快沉深
  Widget _buildVerticalGradient(Color top, Color mid, Color bottom) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, mid, bottom],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  /// 浅色·手机：低饱和单色渐变 —— 以主题色为基，降饱和度、调整明度，
  /// 生成"顶部浅 → 底部深"的同色相莫兰迪渐变(无光晕、安静统一)。
  /// [vibrancy] 越大，逐段抬升饱和度与明度越多，让基础色从"雾灰"透出主题色鲜活感。
  Widget _buildLightMutedGradient(AppThemeStyle style) {
    // 鼠尾草玻璃主题：用参考图的精确取样曲线(多点渐变)复现"安静高级"的灰绿质感
    if (style == AppThemeStyle.sageglass) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _lift(const Color(0xFFB8C4C0)), // 顶部
              _lift(const Color(0xFF9BAEAD)), // 62%
              _lift(const Color(0xFF91A3A2)), // 90%
              _lift(const Color(0xFF8B9E9D)), // 底部(比原版更浅)
            ],
            stops: const [0.0, 0.62, 0.90, 1.0],
          ),
        ),
      );
    }
    final hsl = HSLColor.fromColor(AppThemeConfig.of(style).primaryColor);
    Color shade(double sat, double light) =>
        hsl.withSaturation(sat).withLightness(light).toColor();
    return _buildVerticalGradient(
      _lift(shade(0.14, 0.79)),
      _lift(shade(0.14, 0.68)),
      _lift(shade(0.14, 0.56)),
    );
  }

  /// 浅色·iPad/桌面：白色高亮底 + 柔和主题色光晕
  Widget _buildLightGlow(AppThemeStyle style) {
    return CustomPaint(
      painter: _LightGlowPainter(style),
      size: Size.infinite,
    );
  }

  (Color, Color, Color) _darkGradient(AppThemeStyle style) => switch (style) {
        AppThemeStyle.aurora => (
            const Color(0xFF072032),
            const Color(0xFF061624),
            const Color(0xFF040D17),
          ),
        AppThemeStyle.emerald => (
            const Color(0xFF0C1A20),
            const Color(0xFF0A151B),
            const Color(0xFF071015),
          ),
        AppThemeStyle.sunset => (
            const Color(0xFF280E06),
            const Color(0xFF1D0A04),
            const Color(0xFF140703),
          ),
        AppThemeStyle.minimal => (
            const Color(0xFF17181C),
            const Color(0xFF111216),
            const Color(0xFF0C0D10),
          ),
        AppThemeStyle.midnight => (
            const Color(0xFF0B1D18),
            const Color(0xFF091511),
            const Color(0xFF060E0B),
          ),
        AppThemeStyle.crimson => (
            const Color(0xFF270810),
            const Color(0xFF1D060C),
            const Color(0xFF140408),
          ),
        AppThemeStyle.indigo => (
            const Color(0xFF12142E),
            const Color(0xFF0D0E22),
            const Color(0xFF080917),
          ),
        AppThemeStyle.sage => (
            const Color(0xFF09201E),
            const Color(0xFF071716),
            const Color(0xFF05100F),
          ),
        AppThemeStyle.sageglass => (
            const Color(0xFF09201E),
            const Color(0xFF071716),
            const Color(0xFF05100F),
          ),
        AppThemeStyle.twilight => (
            const Color(0xFF1C0B2C),
            const Color(0xFF150821),
            const Color(0xFF0E0516),
          ),
      };
}

/// 白底 + 主题色光晕绘制器(用于 iPad/桌面方正屏)
///
/// 基础：纯白 → 极浅冷白的纵向渐变；再叠加三团主题色同色系柔光晕。
class _LightGlowPainter extends CustomPainter {
  final AppThemeStyle style;
  _LightGlowPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final cfg = AppThemeConfig.of(style);
    final rect = Offset.zero & size;

    // 1) 基础底色：纯白 → 极浅冷白，保持明亮、给卡片留明度差
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFE6ECF2)],
        ).createShader(rect),
    );

    // 2) 三团主题色柔光晕(同色系) —— iPad 认可的宽屏参数
    _glow(canvas,
        center: Offset(size.width * 0.16, size.height * 0.26),
        radius: size.width * 0.80,
        color: cfg.primaryColor,
        alpha: 0.28);
    _glow(canvas,
        center: Offset(size.width * 0.94, size.height * 0.30),
        radius: size.width * 0.78,
        color: cfg.primaryColor,
        alpha: 0.24);
    _glow(canvas,
        center: Offset(size.width * 0.48, size.height * 1.00),
        radius: size.width * 0.98,
        color: cfg.primaryColor,
        alpha: 0.27);
  }

  void _glow(Canvas canvas,
      {required Offset center,
      required double radius,
      required Color color,
      required double alpha}) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.55),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _LightGlowPainter old) => old.style != style;
}
