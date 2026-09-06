import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 通用毛玻璃卡片（对标不背：局部精确模糊 + 通透乳白磨砂 + 外发光微阴影）
///
/// 规避规范里的三个坑：
/// 1. 阴影放在 ClipRRect **外层**，避免被圆角裁剪吞掉；
/// 2. `BackdropFilter` 放内层做**局部精确模糊**，`sigma=7` 既能晕开轮廓又不把底层抹成死白；
/// 3. 浅色底用通透乳白（默认 30%），保留底层透来的朦胧色块，而非实心白。
class FrostedGlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color bgColor;
  final Color borderColor;
  final BoxShadow shadow;
  final double sigma;
  final EdgeInsetsGeometry? padding;

  const FrostedGlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.bgColor = const Color(0x80FFFFFF),
    this.borderColor = const Color(0x24FFFFFF),
    this.shadow = const BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 5),
    ),
    this.sigma = 7,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [shadow],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: r,
              border: Border.all(color: borderColor, width: 1.0),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
