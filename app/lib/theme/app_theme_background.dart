import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 全局自适应主题背景层组件
///
/// 浅色模式：**以白色为主的高亮透光背景** + 几团柔和的主题色光晕（Radial 光斑）。
/// 让页面整体明亮通透，避免"低饱和色调渐变"在大屏(如 iPad)上被放大成灰暗、不通透。
/// 深色模式：保留贯满全屏的"浅→深"纵向渐变带（带主题色相，无中心热点、无边缘骤退）。
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
    if (!_resolveIsDark(context)) return _buildLightGlow(themeStyle);
    final (top, mid, bottom) = _darkGradient(themeStyle);
    return _buildVerticalGradient(top, mid, bottom);
  }

  /// 深色模式：统一垂直渐变构建器，三段色贯穿全屏，上半段保持轻盈、下半段更快沉深
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

  /// 浅色模式：白色高亮底 + 柔和主题色光晕（用 CustomPainter 以归一化坐标绘制，任意尺寸自适应）
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
        AppThemeStyle.twilight => (
            const Color(0xFF1C0B2C),
            const Color(0xFF150821),
            const Color(0xFF0E0516),
          ),
      };
}

/// 白色底 + 主题色光晕的绘制器
///
/// 光晕基色 = 主题主色向白色靠拢的"淡彩"，避免直接用深主色把白底染灰。
/// 三团光晕用略微不同的白化比例制造微妙色温差，层次更自然。
class _LightGlowPainter extends CustomPainter {
  final AppThemeStyle style;
  _LightGlowPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final cfg = AppThemeConfig.of(style);
    final rect = Offset.zero & size;

    // 1) 基础白底：纯白 → 极淡的冷白，保持整屏高亮通透
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFFAFBFD)],
        ).createShader(rect),
    );

    // 2) 三团柔和光晕
    _glow(canvas,
        center: Offset(size.width * 0.12, size.height * 0.10),
        radius: size.width * 0.58,
        color: Color.lerp(cfg.primaryColor, Colors.white, 0.48)!,
        alpha: 0.18);
    _glow(canvas,
        center: Offset(size.width * 0.94, size.height * 0.28),
        radius: size.width * 0.62,
        color: Color.lerp(cfg.primaryColor, Colors.white, 0.68)!,
        alpha: 0.13);
    _glow(canvas,
        center: Offset(size.width * 0.42, size.height * 1.00),
        radius: size.width * 0.80,
        color: Color.lerp(cfg.primaryColor, Colors.white, 0.42)!,
        alpha: 0.10);
  }

  void _glow(Canvas canvas,
      {required Offset center,
      required double radius,
      required Color color,
      required double alpha}) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0.0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _LightGlowPainter old) => old.style != style;
}
