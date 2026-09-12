import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nnbdc/widget/app_scaffold.dart';

/// 一步引导：高亮 [targetKey] 对应的控件区域，并在其附近给出说明。
class StudyGuideStep {
  const StudyGuideStep({
    required this.targetKey,
    required this.title,
    required this.text,
  });

  final GlobalKey targetKey;
  final String title;
  final String text;
}

/// 学习页新手引导：半透明遮罩 + 挖空高亮 + 排版驱动说明卡。
///
/// 用于向新用户讲清本 App 的学习模型（测评 → 巩固 → 本组小结，且整组横向推进），
/// 避免被误当作"认识 / 不认识"的翻卡软件而流失。
class StudyGuideOverlay extends StatefulWidget {
  const StudyGuideOverlay({
    super.key,
    required this.overlayKey,
    required this.steps,
    required this.onFinish,
  });

  /// 遮罩自身 key：用于把目标控件的全局坐标换算为遮罩内坐标
  final GlobalKey overlayKey;
  final List<StudyGuideStep> steps;

  /// 走完引导或主动跳过（调用方据此记为已看过）
  final VoidCallback onFinish;

  @override
  State<StudyGuideOverlay> createState() => _StudyGuideOverlayState();
}

class _StudyGuideOverlayState extends State<StudyGuideOverlay> {
  int _index = 0;
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  /// 把当前步骤目标控件的区域换算为遮罩内坐标（目标尚未挂载时退化为居中说明卡）
  void _measure() {
    final overlayBox =
        widget.overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox = widget.steps[_index].targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || targetBox == null || !targetBox.hasSize) {
      setState(() => _hole = null);
      return;
    }
    final topLeft = overlayBox.globalToLocal(targetBox.localToGlobal(Offset.zero));
    setState(() {
      _hole = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        targetBox.size.width,
        targetBox.size.height,
      ).inflate(8);
    });
  }

  void _goNext() {
    if (_index >= widget.steps.length - 1) {
      widget.onFinish();
      return;
    }
    setState(() {
      _index++;
      _hole = null;
    });
    _scheduleMeasure();
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    return LayoutBuilder(
      builder: (context, constraints) {
        final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);
        final isLast = _index == widget.steps.length - 1;
        // 目标位于屏幕上半部时说明卡放其下方，否则放上方，避免遮挡被高亮的区域
        final bool below = hole == null || hole.center.dy < overlaySize.height * 0.55;
        final card = _buildCard(context, isLast: isLast);

        return GestureDetector(
          key: widget.overlayKey,
          behavior: HitTestBehavior.opaque,
          // 引导期间遮罩吸收点击，只走"下一步 / 跳过"，保证说明被看到
          onTap: () {},
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GuideScrimPainter(
                    hole: hole,
                    scrimColor: Colors.black.withValues(alpha: 0.66),
                    ringColor: context.primaryColor.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (hole == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: card,
                  ),
                )
              else if (below)
                Positioned(
                  left: 20,
                  right: 20,
                  top: math.max(hole.bottom + 16,
                      MediaQuery.of(context).padding.top + 8),
                  child: card,
                )
              else
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: overlaySize.height - hole.top + 16,
                  child: card,
                ),
            ],
          ),
        );
      },
    );
  }

  /// 说明卡：近乎实底（浮在暗遮罩上需保证可读性），排版驱动，无多余容器
  Widget _buildCard(BuildContext context, {required bool isLast}) {
    final step = widget.steps[_index];
    final isDark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF21A2230) : const Color(0xFAFFFFFF),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  step.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: context.textPrimary,
                  ),
                ),
              ),
              _buildStepDots(context),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              height: 1.6,
              letterSpacing: 0.1,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (!isLast)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onFinish,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    child: Text(
                      '跳过',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: context.textMuted,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _goNext,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLast ? '开始学习' : '下一步',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: context.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11,
                        color: context.primaryColor.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepDots(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < widget.steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == _index
                  ? context.primaryColor
                  : context.textMuted.withValues(alpha: 0.3),
            ),
          ),
        ],
      ],
    );
  }
}

/// 遮罩绘制：整屏暗色 + 在目标区域挖出圆角透光洞，并描一圈极细的主题色轮廓
class _GuideScrimPainter extends CustomPainter {
  _GuideScrimPainter({
    required this.hole,
    required this.scrimColor,
    required this.ringColor,
  });

  final Rect? hole;
  final Color scrimColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final holeRect = hole;
    final rrect = holeRect == null
        ? null
        : RRect.fromRectAndRadius(holeRect, const Radius.circular(18));

    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRect(Offset.zero & size);
    if (rrect != null) path.addRRect(rrect);
    canvas.drawPath(path, Paint()..color = scrimColor);

    if (rrect != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuideScrimPainter oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.scrimColor != scrimColor ||
      oldDelegate.ringColor != ringColor;
}
