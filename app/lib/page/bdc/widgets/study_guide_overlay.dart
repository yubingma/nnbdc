import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/widget/app_scaffold.dart';

/// 引导正文随当前学习环节变化：要说的是"什么"由环节决定，
/// 英译汉说中文意思、汉译英说英文单词，例句环节得先按住「按住说话」。
String studyGuideTextFor(StudyStep step) {
  switch (step) {
    case StudyStep.en2Ch:
      return '现在你只需要说出这个单词的中文意思，剩下的交给我——不用点选项，也不用打字。';
    case StudyStep.ch2En:
      return '现在你只需要看着中文意思，说出对应的英文单词，剩下的交给我——不用点选项，也不用打字。';
    case StudyStep.enSentence2Ch:
      return '现在你只需要按住下方「按住说话」，说出例句的中文意思，剩下的交给我。';
    case StudyStep.chSentence2En:
      return '现在你只需要按住下方「按住说话」，说出例句的英文，剩下的交给我。';
    case StudyStep.list:
    case StudyStep.unknown:
      return '现在你只需要开口说出答案，剩下的交给我——不用点选项，也不用打字。';
  }
}

/// 学习页新手引导：半透明遮罩 + 挖空高亮 + 排版驱动说明卡。
///
/// 只讲一件事——你说、我来听：高亮语音识别区，告诉用户开口说就是答题。
/// 其余功能留给自己探索，不做逐屏教学。
class StudyGuideOverlay extends StatefulWidget {
  const StudyGuideOverlay({
    super.key,
    required this.overlayKey,
    required this.targetKey,
    required this.title,
    required this.text,
    required this.onFinish,
  });

  /// 遮罩自身 key：用于把目标控件的全局坐标换算为遮罩内坐标
  final GlobalKey overlayKey;

  /// 高亮目标：说明卡贴着它展示
  final GlobalKey targetKey;
  final String title;
  final String text;

  /// 点「开始学习」收起引导（调用方据此记为已看过）
  final VoidCallback onFinish;

  @override
  State<StudyGuideOverlay> createState() => _StudyGuideOverlayState();
}

class _StudyGuideOverlayState extends State<StudyGuideOverlay> {
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  /// 把目标控件的区域换算为遮罩内坐标（目标尚未挂载时退化为居中说明卡）
  void _measure() {
    final overlayBox =
        widget.overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox =
        widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || targetBox == null || !targetBox.hasSize) return;
    final topLeft =
        overlayBox.globalToLocal(targetBox.localToGlobal(Offset.zero));
    setState(() {
      _hole = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        targetBox.size.width,
        targetBox.size.height,
      ).inflate(8);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    return LayoutBuilder(
      builder: (context, constraints) {
        final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);
        // 目标位于屏幕上半部时说明卡放其下方，否则放上方，避免遮挡被高亮的区域
        final bool below =
            hole == null || hole.center.dy < overlaySize.height * 0.55;
        final card = _buildCard(context);

        return GestureDetector(
          key: widget.overlayKey,
          behavior: HitTestBehavior.opaque,
          // 引导期间遮罩吸收点击，只走「开始学习」，保证说明被看到
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
                  top: math.max(
                      hole.bottom + 16, MediaQuery.of(context).padding.top + 8),
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
  Widget _buildCard(BuildContext context) {
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
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.text,
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
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onFinish,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '开始学习',
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
