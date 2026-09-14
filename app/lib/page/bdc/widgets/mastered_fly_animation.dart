import 'dart:math';
import 'package:flutter/material.dart';
import '../../../global.dart';

/// 单词掌握飞行动画管理器
class MasteredFlyAnimation {
  /// 启动飞行动画
  static void play({
    required BuildContext context,
    required String spell,
    required GlobalKey? startKey,
    required GlobalKey? targetKey,
    VoidCallback? onArrived,
  }) {
    if (spell.isEmpty) return;

    try {
      final overlay = Overlay.of(context, rootOverlay: true);

      // 获取起点坐标（当前单词中心）
      Offset startOffset;
      final startBox = startKey?.currentContext?.findRenderObject() as RenderBox?;
      if (startBox != null && startBox.hasSize) {
        startOffset = startBox.localToGlobal(
          Offset(startBox.size.width / 2, startBox.size.height / 2),
        );
      } else {
        final screenSize = MediaQuery.of(context).size;
        startOffset = Offset(screenSize.width / 2, screenSize.height * 0.35);
      }

      // 获取终点坐标（右上角掌握按钮中心）
      Offset targetOffset;
      final targetBox = targetKey?.currentContext?.findRenderObject() as RenderBox?;
      if (targetBox != null && targetBox.hasSize) {
        targetOffset = targetBox.localToGlobal(
          Offset(targetBox.size.width / 2, targetBox.size.height / 2),
        );
      } else {
        final screenSize = MediaQuery.of(context).size;
        final statusBarHeight = MediaQuery.of(context).padding.top;
        targetOffset = Offset(screenSize.width - 118, statusBarHeight + 24);
      }

      Global.logger.i('🕊️ [Mastered-Fly] 触发掌握飞行动效: word=$spell, start=$startOffset -> target=$targetOffset');

      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) => IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            child: _FlyTrajectory(
              spell: spell,
              startOffset: startOffset,
              targetOffset: targetOffset,
              onComplete: () {
                entry.remove();
                onArrived?.call();
              },
            ),
          ),
        ),
      );

      overlay.insert(entry);
    } catch (e, stack) {
      Global.logger.e('🕊️ [Mastered-Fly] 播放飞行动效失败: $e', error: e, stackTrace: stack);
    }
  }
}

/// 轨迹曲线与胶囊动画组件
class _FlyTrajectory extends StatefulWidget {
  final String spell;
  final Offset startOffset;
  final Offset targetOffset;
  final VoidCallback onComplete;

  const _FlyTrajectory({
    required this.spell,
    required this.startOffset,
    required this.targetOffset,
    required this.onComplete,
  });

  @override
  State<_FlyTrajectory> createState() => _FlyTrajectoryState();
}

class _FlyTrajectoryState extends State<_FlyTrajectory> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 620),
      vsync: this,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 计算给定进度 t [0.0, 1.0] 下的抛物线绝对坐标
  static Offset computePoint(Offset start, Offset target, double t) {
    final double x = start.dx + (target.dx - start.dx) * t;
    // Y 轴带一段优雅的拱起弧线，最高点出现在飞行前半程
    final double arcHeight = min(75.0, (target.dx - start.dx).abs() * 0.45 + 30.0);
    final double parabolaY = -arcHeight * sin(pi * t);
    final double y = start.dy + (target.dy - start.dy) * t + parabolaY;
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        final currentPos = computePoint(widget.startOffset, widget.targetOffset, t);

        // 缩放：初始略有弹出 (1.05)，然后向目标按钮渐进聚敛 (0.35)
        final double scale = t < 0.15
            ? 1.0 + 0.1 * (t / 0.15)
            : 1.1 - 0.72 * ((t - 0.15) / 0.85);

        // 透明度：最后 15% 融入掌握按钮
        final double opacity = t > 0.85 ? (1.0 - (t - 0.85) / 0.15).clamp(0.0, 1.0) : 1.0;

        // 微倾斜动态角度
        final double angle = -0.08 + 0.16 * t;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. 轨迹光弧与尾迹粒子
            CustomPaint(
              painter: _TrajectoryPainter(
                start: widget.startOffset,
                target: widget.targetOffset,
                progress: t,
              ),
            ),

            // 2. 飞行的单词胶囊（使用 Align + Transform.translate 确保不受任何 Stack 约束影响）
            Align(
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: Offset(currentPos.dx - 85, currentPos.dy - 20),
                child: SizedBox(
                  width: 170,
                  height: 40,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.rotate(
                      angle: angle,
                      child: Transform.scale(
                        scale: scale,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF22C55E), // 掌握翡翠绿
                                  Color(0xFF15803D), // 饱满深绿
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.55),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 3),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.75),
                                width: 1.4,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.spell,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Roboto',
                                      decoration: TextDecoration.none,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 绘制流光弧线与尾迹的 Painter
class _TrajectoryPainter extends CustomPainter {
  final Offset start;
  final Offset target;
  final double progress;

  _TrajectoryPainter({
    required this.start,
    required this.target,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.02) return;

    // 绘制流光轨迹曲线（采样 24 个点拟合平滑路径）
    final path = Path();
    final int sampleCount = (28 * progress).ceil().clamp(3, 28);
    final firstPoint = _FlyTrajectoryState.computePoint(start, target, 0.0);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    for (int i = 1; i <= sampleCount; i++) {
      final double t = (i / 28) * progress;
      final p = _FlyTrajectoryState.computePoint(start, target, t);
      path.lineTo(p.dx, p.dy);
    }

    // 外层弥散光晕
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4ADE80).withValues(alpha: (0.35 * (1.0 - progress * 0.4)).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, glowPaint);

    // 内层流光亮线
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF22C55E).withValues(alpha: 0.1),
          const Color(0xFF4ADE80).withValues(alpha: 0.85),
          Colors.white,
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromPoints(start, target));
    canvas.drawPath(path, linePaint);

    // 头部引导微星芒
    final currentPos = _FlyTrajectoryState.computePoint(start, target, progress);
    final starPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(currentPos, 3.5, starPaint);

    final starHaloPaint = Paint()
      ..color = const Color(0xFF4ADE80).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(currentPos, 7.0, starHaloPaint);
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
