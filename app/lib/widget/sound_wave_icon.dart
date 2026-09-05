import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nnbdc/theme/app_theme.dart';

/// 现代极简声波发音图标组件（对标 Apple SF Symbols / 高端词典极简质感）
/// - 支持外部传入 [animationController] 联动全局状态
/// - 未传入控制器时，若 [isPlaying] 为 true 则内部自驱动平滑呼吸律动
/// - 纯展示模式下呈现极简双弧声波微圆角喇叭
class ModernSoundWaveIcon extends StatefulWidget {
  final bool isPlaying;
  final AnimationController? animationController;
  final double size;
  final Color? color;
  final Color? activeColor;

  const ModernSoundWaveIcon({
    super.key,
    this.isPlaying = false,
    this.animationController,
    this.size = 18.0,
    this.color,
    this.activeColor,
  });

  @override
  State<ModernSoundWaveIcon> createState() => _ModernSoundWaveIconState();
}

class _ModernSoundWaveIconState extends State<ModernSoundWaveIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _internalController;

  AnimationController get _effectiveController =>
      widget.animationController ??
      (_internalController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      ));

  @override
  void initState() {
    super.initState();
    if (widget.animationController == null && widget.isPlaying) {
      _effectiveController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ModernSoundWaveIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationController == null) {
      if (widget.isPlaying && !oldWidget.isPlaying) {
        _effectiveController.repeat();
      } else if (!widget.isPlaying && oldWidget.isPlaying) {
        _effectiveController.stop();
        _effectiveController.reset();
      }
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultNormalColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final defaultActiveColor = context.primaryColor;

    final normalColor = widget.color ?? defaultNormalColor;
    final activeColor = widget.activeColor ?? defaultActiveColor;

    final controller = _effectiveController;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final active = widget.isPlaying || controller.isAnimating;
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: ModernSoundWavePainter(
            color: active ? activeColor : normalColor,
            isPlaying: active,
            animationValue: controller.value,
          ),
        );
      },
    );
  }
}

/// 现代声波发音图标绘制器：
/// 造型采用微圆角 Solid Cone 喇叭，并带双重同心弧形声波，支持向外推涌的声浪流动动效
class ModernSoundWavePainter extends CustomPainter {
  final Color color;
  final bool isPlaying;
  final double animationValue;

  ModernSoundWavePainter({
    required this.color,
    required this.isPlaying,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. 绘制喇叭主体（Solid Cone with Smooth Rounded Corners）
    final paintFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final conePath = Path();
    final baseLeft = w * 0.08;
    final baseRight = w * 0.26;
    final baseTop = h * 0.35;
    final baseBottom = h * 0.65;

    final coneRight = w * 0.46;
    final coneTop = h * 0.18;
    final coneBottom = h * 0.82;

    conePath.moveTo(baseLeft + 1.2, baseTop);
    conePath.lineTo(baseRight, baseTop);
    conePath.lineTo(coneRight - 1.2, coneTop);
    conePath.arcToPoint(
      Offset(coneRight, coneTop + 1.6),
      radius: const Radius.circular(1.6),
    );
    conePath.lineTo(coneRight, coneBottom - 1.6);
    conePath.arcToPoint(
      Offset(coneRight - 1.2, coneBottom),
      radius: const Radius.circular(1.6),
    );
    conePath.lineTo(baseRight, baseBottom);
    conePath.lineTo(baseLeft + 1.2, baseBottom);
    conePath.arcToPoint(
      Offset(baseLeft, baseBottom - 1.2),
      radius: const Radius.circular(1.2),
    );
    conePath.lineTo(baseLeft, baseTop + 1.2);
    conePath.arcToPoint(
      Offset(baseLeft + 1.2, baseTop),
      radius: const Radius.circular(1.2),
    );
    conePath.close();

    canvas.drawPath(conePath, paintFill);

    // 2. 绘制右侧两条精巧的弧形声波（Sound Waves）
    final waveCenter = Offset(w * 0.35, h * 0.50);
    const sweepAngle = 76 * (pi / 180);
    const startAngle = -38 * (pi / 180);

    double wave1Opacity = 0.90;
    double wave2Opacity = 0.50;
    double wave1Scale = 1.0;
    double wave2Scale = 1.0;

    if (isPlaying) {
      final t = animationValue;
      // 声波 1：第一道声波，随周期呈现明暗呼吸与微幅涟漪律动
      wave1Scale = 0.95 + 0.12 * sin(t * pi * 2);
      wave1Opacity = (0.35 + 0.65 * (0.5 + 0.5 * sin(t * pi * 2))).clamp(0.0, 1.0);

      // 声波 2：第二道声波，相位差 90 度，自内向外推涌声浪
      wave2Scale = 0.94 + 0.14 * sin((t - 0.25) * pi * 2);
      wave2Opacity = (0.20 + 0.80 * (0.5 + 0.5 * sin((t - 0.25) * pi * 2))).clamp(0.0, 1.0);
    }

    final strokeW = (w * 0.095).clamp(1.4, 2.2);

    final wavePaint1 = Paint()
      ..color = color.withValues(alpha: wave1Opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    final wave1Radius = w * 0.29 * wave1Scale;
    canvas.drawArc(
      Rect.fromCircle(center: waveCenter, radius: wave1Radius),
      startAngle,
      sweepAngle,
      false,
      wavePaint1,
    );

    final wavePaint2 = Paint()
      ..color = color.withValues(alpha: wave2Opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    final wave2Radius = w * 0.49 * wave2Scale;
    canvas.drawArc(
      Rect.fromCircle(center: waveCenter, radius: wave2Radius),
      startAngle,
      sweepAngle,
      false,
      wavePaint2,
    );
  }

  @override
  bool shouldRepaint(covariant ModernSoundWavePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.animationValue != animationValue;
  }
}
