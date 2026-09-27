import 'dart:async';
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
///
/// 性能：`BackdropFilter` 每帧都要重新采样下层。在滚动列表里卡片位置不停变化，
/// 实测词表页滚动时单帧光栅化会从 ~9ms 抬到 ~31ms（14/14 帧超预算）。
/// 而滚动过程中用户看到的是快速移动的内容，磨砂质感几乎无从感知——因此
/// **滚动期间（含惯性/回弹尾巴）自动退化为普通半透明卡片，停稳后恢复磨砂**。
class FrostedGlassCard extends StatefulWidget {
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
  State<FrostedGlassCard> createState() => _FrostedGlassCardState();
}

class _FrostedGlassCardState extends State<FrostedGlassCard> {
  /// 滚动停止后延迟恢复磨砂：惯性/回弹的尾巴仍在逐帧绘制，
  /// 此时立刻重算模糊等于白白掉帧。
  static const Duration _restoreDelay = Duration(milliseconds: 250);

  ValueNotifier<bool>? _scrollNotifier;
  Timer? _restoreTimer;
  bool _frosted = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindScrollNotifier(
        Scrollable.maybeOf(context)?.position.isScrollingNotifier);
  }

  void _bindScrollNotifier(ValueNotifier<bool>? notifier) {
    if (identical(notifier, _scrollNotifier)) return;
    _scrollNotifier?.removeListener(_handleScrollStateChanged);
    _scrollNotifier = notifier;
    _scrollNotifier?.addListener(_handleScrollStateChanged);
  }

  void _handleScrollStateChanged() {
    _restoreTimer?.cancel();
    if (_scrollNotifier?.value ?? false) {
      if (_frosted) setState(() => _frosted = false);
      return;
    }
    _restoreTimer = Timer(_restoreDelay, () {
      if (mounted && !_frosted) setState(() => _frosted = true);
    });
  }

  @override
  void dispose() {
    _restoreTimer?.cancel();
    _scrollNotifier?.removeListener(_handleScrollStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.borderRadius);
    final shadow = widget.shadow ?? context.cardShadow;
    final bg = widget.bgColor ?? context.cardBg;
    final border = widget.borderColor ?? context.cardBorder;

    final inner = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: r,
        border: Border.all(color: border, width: 1.0),
      ),
      padding: widget.padding,
      child: widget.child,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [shadow],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: _frosted
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(
                    sigmaX: widget.sigma, sigmaY: widget.sigma),
                child: inner,
              )
            : inner,
      ),
    );
  }
}
