import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_scaffold.dart' show AppThemeContextExtension;

/// 全站统一基础卡片组件（对标本背：局部精确模糊 + 通透乳白磨砂 + 外发光微阴影）
///
/// 这一处收敛了所有「卡片基本效果」——圆角、边框、底色、阴影——的**公用实现**：
/// - **底色** 默认取 [AppThemeContextExtension.cardBg]（= base 卡片色，随 cardOpacity 联动，透明卡不拖黑影）；
/// - **边框** 默认取 [AppThemeContextExtension.cardBorder]（主题统一描边色）；
/// - **阴影** 默认取 [AppThemeContextExtension.cardShadow]（随卡片透明度联动，卡越透影越淡）；
/// - **圆角** 默认 24（主卡片用 28 可传 [borderRadius]）。
///
/// 任何主卡片都应渲染在 `FrostedGlassCard` 里，而非手写 BoxDecoration。
/// 页面如需覆盖（如选中态高亮、页面专属透明度），传入对应参数即可，其余保持统一。
///
/// 规避规范里的三个坑：
/// 1. 阴影放在 ClipRRect **外层**，避免被圆角裁剪吞掉；
/// 2. `BackdropFilter` 放内层做**局部精确模糊**，`sigma=7` 既能晕开轮廓又不把底层抹成死白；
/// 3. 浅色底用通透乳白，保留底层透来的朦胧色块，而非实心白。
class FrostedGlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? bgColor;
  final Color? borderColor;
  final BoxShadow? shadow;
  final double sigma;
  final EdgeInsetsGeometry? padding;

  const FrostedGlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.bgColor,
    this.borderColor,
    this.shadow,
    this.sigma = 7,
    this.padding,
  });

  /// 主卡片（一级卡片）标准外观：更大的圆角、统一的 28px。
  const FrostedGlassCard.primary({
    super.key,
    required this.child,
    this.borderRadius = 28,
    this.bgColor,
    this.borderColor,
    this.shadow,
    this.sigma = 7,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);
    final effectiveShadow = shadow ?? context.cardShadow;
    final effectiveBg = bgColor ?? context.cardBg;
    final effectiveBorder = borderColor ?? context.cardBorder;
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [effectiveShadow],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: effectiveBg,
              borderRadius: r,
              border: Border.all(color: effectiveBorder, width: 1.0),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
