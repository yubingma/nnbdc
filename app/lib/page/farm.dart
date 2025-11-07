import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FarmPage extends StatefulWidget {
  const FarmPage({super.key});

  @override
  State<FarmPage> createState() => _FarmPageState();
}

class _FarmPageState extends State<FarmPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8),
      appBar: AppBar(
        title: const Text('我的小天地'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: const SafeArea(
        child: Center(
          child: SizedBox(
            width: 420,
            height: 320,
            child: PlantGrowthScene(),
          ),
        ),
      ),
    );
  }
}

class PlantGrowthScene extends StatefulWidget {
  const PlantGrowthScene({super.key});

  @override
  State<PlantGrowthScene> createState() => _PlantGrowthSceneState();
}

class _PlantGrowthSceneState extends State<PlantGrowthScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _TreeGrowthPainter(
            progress: _controller.value,
            isDarkMode: isDarkMode,
            accentColor: AppTheme.primaryColor,
          ),
        );
      },
    );
  }
}

class _TreeGrowthPainter extends CustomPainter {
  final double progress;
  final bool isDarkMode;
  final Color accentColor;

  _TreeGrowthPainter({
    required this.progress,
    required this.isDarkMode,
    required this.accentColor,
  });

  static const List<double> _stageStops = [
    0.0,
    0.18,
    0.35,
    0.55,
    0.75,
    0.9,
    1.0,
  ];

  double _segmentProgress(int segment) {
    final double start = _stageStops[segment];
    final double end = _stageStops[segment + 1];
    final double clamped = (progress - start) / (end - start);
    return clamped.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double soilTop = size.height * 0.68;
    final Paint bgPaint = Paint()
      ..shader = LinearGradient(
        colors: isDarkMode
            ? [const Color(0xFF26303F), const Color(0xFF10151F)]
            : [const Color(0xFFDFF3FF), const Color(0xFFF6FBFF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final Paint soilPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFC58B5B), const Color(0xFF8B572A)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, soilTop, size.width, size.height - soilTop));
    canvas.drawRect(
      Rect.fromLTWH(0, soilTop, size.width, size.height - soilTop),
      soilPaint,
    );

    final Paint stonePaint = Paint()..style = PaintingStyle.fill;
    final math.Random random = math.Random(7);
    for (int i = 0; i < 28; i++) {
      final double x = (i + 1) * (size.width / 30) + random.nextDouble() * 12 - 6;
      final double y = soilTop + random.nextDouble() * (size.height - soilTop - 20);
      final double r = 3 + random.nextDouble() * 4;
      stonePaint.color = Color.lerp(
        const Color(0xFF7A4A25),
        const Color(0xFF5E381A),
        random.nextDouble(),
      )!;
      canvas.drawOval(Rect.fromCircle(center: Offset(x, y), radius: r), stonePaint);
    }

    final double stageSeed = _segmentProgress(0);
    final double stageSprout = _segmentProgress(1);
    final double stageSapling = _segmentProgress(2);
    final double stageBranch = _segmentProgress(3);
    final double stageCanopy = _segmentProgress(4);
    final double stageMature = _segmentProgress(5);

    final double centerX = size.width * 0.5;

    final Paint seedPaint = Paint()..color = const Color(0xFF5D4037);
    final double seedScale = ui.lerpDouble(0.2, 1.0, stageSeed) ?? 0.2;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - 40 * (1 - stageSeed), soilTop - 6 * stageSeed),
        width: 16 * seedScale,
        height: 10 * seedScale,
      ),
      seedPaint,
    );

    final Paint primaryRootPaint = Paint()
      ..color = const Color(0xFFE6D3B2)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = ui.lerpDouble(2.0, 4.0, stageSapling) ?? 2.0;
    final double rootDepth = ui.lerpDouble(18, 68, stageSapling) ?? 18;

    Path buildRootPath({
      required double angleDeg,
      required double lengthFactor,
      required double curvature,
    }) {
      final double angle = angleDeg * math.pi / 180;
      final double dx = math.cos(angle);
      final double dyFactor = math.sin(angle).abs();
      final double depth = rootDepth * lengthFactor;
      final Path path = Path()
        ..moveTo(centerX, soilTop)
        ..cubicTo(
          centerX + dx * 16 * stageSapling,
          soilTop + depth * (0.18 + 0.12 * dyFactor),
          centerX + dx * 32 * stageSapling + curvature * 12,
          soilTop + depth * (0.48 + 0.15 * dyFactor),
          centerX + dx * 52 * stageSapling,
          soilTop + depth,
        );
      return path;
    }

    canvas.drawPath(
      buildRootPath(angleDeg: 200, lengthFactor: 1.0, curvature: -1),
      primaryRootPaint,
    );
    canvas.drawPath(
      buildRootPath(angleDeg: -200, lengthFactor: 1.0, curvature: 1),
      primaryRootPaint,
    );

    if (stageSapling > 0.25) {
      final Paint sideRootPaint = Paint()
        ..color = const Color(0xFFEBDAC0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ui.lerpDouble(1.2, 2.6, stageSapling) ?? 1.2;

      void drawSideRoot(double startOffset, double angleDeg, double lengthFactor) {
        final double startY = soilTop + rootDepth * startOffset;
        final double angle = angleDeg * math.pi / 180;
        final Path path = Path()
          ..moveTo(centerX, startY)
          ..quadraticBezierTo(
            centerX + math.cos(angle) * 18 * stageSapling,
            startY + math.sin(angle) * 18 * stageSapling,
            centerX + math.cos(angle) * 36 * stageSapling,
            startY + math.sin(angle) * 36 * stageSapling * lengthFactor,
          );
        canvas.drawPath(path, sideRootPaint);
      }

      drawSideRoot(0.35, 215, 1.0);
      drawSideRoot(0.32, -215, 1.0);
      if (stageSapling > 0.6) {
        drawSideRoot(0.55, 245, 0.85);
        drawSideRoot(0.55, -245, 0.85);
      }
    }

    final double stemHeight = ui.lerpDouble(18, size.height * 0.46, stageBranch) ?? 18;
    final double trunkBaseWidth = ui.lerpDouble(6, 22, stageBranch) ?? 6;
    final double trunkTopWidth = ui.lerpDouble(2, 10, stageBranch) ?? 2;
    final double trunkLeftBase = centerX - trunkBaseWidth;
    final double trunkRightBase = centerX + trunkBaseWidth;
    final double trunkLeftTop = centerX - trunkTopWidth;
    final double trunkRightTop = centerX + trunkTopWidth;

    final Paint trunkPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF8D5A2F),
          const Color(0xFF6B4525),
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      ).createShader(
        Rect.fromLTRB(trunkLeftBase, soilTop - stemHeight, trunkRightBase, soilTop),
      );

    final Path trunkPath = Path()
      ..moveTo(trunkLeftBase, soilTop)
      ..lineTo(trunkRightBase, soilTop)
      ..quadraticBezierTo(
        centerX + trunkBaseWidth * 0.5,
        soilTop - stemHeight * 0.45,
        trunkRightTop,
        soilTop - stemHeight,
      )
      ..lineTo(trunkLeftTop, soilTop - stemHeight)
      ..quadraticBezierTo(
        centerX - trunkBaseWidth * 0.5,
        soilTop - stemHeight * 0.38,
        trunkLeftBase,
        soilTop,
      )
      ..close();
    canvas.drawPath(trunkPath, trunkPaint);

    final Paint branchPaint = Paint()
      ..color = const Color(0xFF704225)
      ..strokeWidth = ui.lerpDouble(2.0, 4.0, stageBranch) ?? 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawBranch(double heightFactor, double direction, double lengthFactor) {
      if (stageBranch <= 0) return;
      final double branchOriginY = soilTop - stemHeight * heightFactor;
      final Path branchPath = Path()
        ..moveTo(centerX, branchOriginY)
        ..quadraticBezierTo(
          centerX + direction * 40 * stageBranch,
          branchOriginY - 10 * stageBranch,
          centerX + direction * 80 * stageBranch * lengthFactor,
          branchOriginY - 20 * stageBranch,
        );
      canvas.drawPath(branchPath, branchPaint);
    }

    drawBranch(0.32, -1, 0.65);
    drawBranch(0.32, 1, 0.65);
    drawBranch(0.55, -1.1, 0.7);
    drawBranch(0.55, 1.1, 0.7);
    drawBranch(0.72, -0.8, 0.5);
    drawBranch(0.72, 0.8, 0.5);

    final List<Offset> canopyOffsets = [
      const Offset(-60, -10),
      const Offset(-42, -6),
      const Offset(-24, -24),
      const Offset(-8, -12),
      const Offset(8, -18),
      const Offset(22, -6),
      const Offset(40, -28),
      const Offset(58, -12),
      const Offset(-30, -44),
      const Offset(-4, -36),
      const Offset(24, -42),
      const Offset(52, -46),
    ];

    double canopyRadius(double base, double variance) {
      return ui.lerpDouble(0, base, stageCanopy)! + variance * stageMature;
    }

    final Paint canopyPaint = Paint();
    for (final offset in canopyOffsets) {
      final double radius = canopyRadius(26, 10 * math.sin(offset.dx / 18));
      if (radius <= 0) continue;
      final Offset center = Offset(
        centerX + offset.dx * stageCanopy,
        soilTop - stemHeight - 18 * stageCanopy + offset.dy * (0.6 + 0.4 * stageCanopy),
      );
      canopyPaint.shader = RadialGradient(
        colors: [
          const Color(0xFF7BC67D).withOpacity(0.85),
          const Color(0xFF2E7D32).withOpacity(0.9),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, canopyPaint);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withOpacity(0.08),
      );
    }

    void drawLeaf(Offset position, double rotation, double scale, double opacity) {
      if (opacity <= 0 || scale <= 0) return;
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(rotation);
      final Rect leafRect = Rect.fromCenter(center: Offset.zero, width: 20 * scale, height: 38 * scale);
      final Paint leafPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF7BC67D).withOpacity(0.6 + 0.3 * opacity),
            const Color(0xFF2E7D32).withOpacity(0.7 + 0.3 * opacity),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(leafRect);
      final Path leafPath = Path()
        ..moveTo(0, -leafRect.height / 2)
        ..quadraticBezierTo(leafRect.width * 0.55, -leafRect.height * 0.15, 0, leafRect.height / 2)
        ..quadraticBezierTo(-leafRect.width * 0.55, -leafRect.height * 0.15, 0, -leafRect.height / 2);
      canvas.drawPath(leafPath, leafPaint);
      canvas.restore();
    }

    final double trunkTopY = soilTop - stemHeight;

    final double earlyLeafOpacity = stageSprout.clamp(0.0, 1.0);
    if (earlyLeafOpacity > 0) {
      final double sproutOffset = 18 * (1 - stageSprout * 0.5);
      drawLeaf(
        Offset(centerX - 12 * (0.4 + stageSprout * 0.6), trunkTopY + sproutOffset),
        -math.pi * 0.22,
        0.35 + 0.25 * stageSprout,
        earlyLeafOpacity,
      );
      drawLeaf(
        Offset(centerX + 12 * (0.4 + stageSprout * 0.6), trunkTopY + sproutOffset),
        math.pi * 0.22,
        0.35 + 0.25 * stageSprout,
        earlyLeafOpacity,
      );
    }

    final double leafOpacity = math.max(stageBranch, stageSprout);
    if (leafOpacity > 0) {
      drawLeaf(
        Offset(centerX - 26 * stageBranch, soilTop - stemHeight * 0.55),
        -math.pi * 0.18,
        0.75 * leafOpacity,
        leafOpacity,
      );
      drawLeaf(
        Offset(centerX + 22 * stageBranch, soilTop - stemHeight * 0.5),
        math.pi * 0.2,
        0.7 * leafOpacity,
        leafOpacity,
      );
      drawLeaf(
        Offset(centerX - 38 * stageBranch, soilTop - stemHeight * 0.32),
        -math.pi * 0.25,
        (leafOpacity - 0.2).clamp(0.0, 1.0),
        (leafOpacity - 0.2).clamp(0.0, 1.0),
      );
      drawLeaf(
        Offset(centerX + 34 * stageBranch, soilTop - stemHeight * 0.35),
        math.pi * 0.27,
        (leafOpacity - 0.2).clamp(0.0, 1.0),
        (leafOpacity - 0.2).clamp(0.0, 1.0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TreeGrowthPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.accentColor != accentColor;
  }
}

