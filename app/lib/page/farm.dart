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
        child: SizedBox.expand(
          child: PlantGrowthScene(),
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
  bool _seedPlanted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_seedPlanted) {
          setState(() {
            _seedPlanted = true;
          });
          _controller.repeat();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final double progress = _seedPlanted ? _controller.value : 0.0;
                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _TreeGrowthPainter(
                      progress: progress,
                      isDarkMode: isDarkMode,
                      accentColor: AppTheme.primaryColor,
                      seedPlanted: _seedPlanted,
                    ),
                  );
                },
              ),
              if (!_seedPlanted)
                Positioned(
                  bottom: 18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(isDarkMode ? 0.45 : 0.28),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      '轻点种子播种',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TreeGrowthPainter extends CustomPainter {
  final double progress;
  final bool isDarkMode;
  final Color accentColor;
  final bool seedPlanted;

  _TreeGrowthPainter({
    required this.progress,
    required this.isDarkMode,
    required this.accentColor,
    required this.seedPlanted,
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
    final double soilTop = size.height * 0.66;
    final Paint skyPaint = Paint()
      ..shader = LinearGradient(
        colors: isDarkMode
            ? [const Color(0xFF22354F), const Color(0xFF101D2C)]
            : [const Color(0xFF6BB7FF), const Color(0xFFCEE7FF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, soilTop));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, soilTop), skyPaint);

    final Rect soilRect = Rect.fromLTWH(0, soilTop, size.width, size.height - soilTop);
    final Paint soilPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFC88645), const Color(0xFF6E3816)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(soilRect);
    canvas.drawRect(soilRect, soilPaint);
    canvas.drawRect(
      Rect.fromLTWH(-1, soilTop - 6, size.width + 2, 6),
      Paint()..color = const Color(0xFF4F2E16),
    );

    final Paint stonePaint = Paint()..style = PaintingStyle.fill;
    final math.Random random = math.Random(11);
    for (int i = 0; i < 36; i++) {
      final double x = soilRect.left + random.nextDouble() * soilRect.width;
      final double y = soilRect.top + soilRect.height * (0.15 + random.nextDouble() * 0.8);
      final double r = 2.0 + random.nextDouble() * 3.0;
      stonePaint.color = Color.lerp(
        const Color(0xFF9B6A3D),
        const Color(0xFF6B4124),
        random.nextDouble(),
      )!;
      canvas.drawOval(Rect.fromCircle(center: Offset(x, y), radius: r), stonePaint);
    }

    final double stageSeed = _segmentProgress(0);
    final double stageSapling = _segmentProgress(2);
    final double stageBranch = _segmentProgress(3);

    final double centerX = size.width * 0.5;

    final Offset seedCenter = seedPlanted
        ? Offset(
            centerX,
            ui.lerpDouble(soilTop - 8, soilTop + 8, stageSeed) ?? soilTop - 8,
          )
        : Offset(centerX, soilTop - 12);
    final double seedRadius = seedPlanted
        ? ui.lerpDouble(5, 3.8, stageSeed)?.clamp(2.5, 5.0) ?? 5
        : 5;
    canvas.drawCircle(
      seedCenter,
      seedRadius,
      Paint()..color = const Color(0xFF9C6941),
    );

    if (seedPlanted && stageSapling > 0) {
      final double strength = stageSapling.clamp(0.0, 1.0);
      final double baseLength = (30 + 48 * strength) * strength;
      final double baseThickness = (4.2 + 3.6 * strength) * strength.clamp(0.35, 1.0);
      final int maxDepth = 3 + (stageSapling * 2.2).floor();

      Color rootColorFor(int depth) {
        final double t = depth / (maxDepth + 1);
        return Color.lerp(const Color(0xFFE6D3B2), const Color(0xFFB99863), t)!
            .withOpacity(0.92 - t * 0.2);
      }

      void drawRootBranch(
        Offset start,
        double length,
        double angleDeg,
        double thickness,
        int depth,
        double seed,
      ) {
        if (depth <= 0 || thickness < 0.6) return;
        final double angle = angleDeg * math.pi / 180;
        final double curveOffset = math.sin((seed + depth) * 1.2) * 18;
        final Offset control = start + Offset(
          math.cos((angleDeg + curveOffset * 0.2) * math.pi / 180) * length * 0.55,
          math.sin((angleDeg + curveOffset * 0.2) * math.pi / 180) * length * 0.55,
        );
        final Offset end = start + Offset(
          math.cos(angle) * length,
          math.sin(angle) * length,
        );

        final Path path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

        final Paint paint = Paint()
          ..color = rootColorFor(maxDepth - depth)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = thickness;
        canvas.drawPath(path, paint);

        final double nextLength = length * (0.62 + 0.18 * strength);
        final double nextThickness = thickness * 0.65;
        final double spread = 18 + 10 * (1 - strength);

        drawRootBranch(
          end,
          nextLength,
          angleDeg + spread,
          nextThickness,
          depth - 1,
          seed + 17.3,
        );
        drawRootBranch(
          end,
          nextLength,
          angleDeg - spread,
          nextThickness,
          depth - 1,
          seed + 31.1,
        );

        if (depth > 1) {
          drawRootBranch(
            end,
            nextLength * (0.75 + 0.15 * stageSapling),
            angleDeg + math.sin(seed) * 12,
            nextThickness * 0.8,
            depth - 2,
            seed + 9.6,
          );
        }
      }

      final Offset rootOrigin = Offset(centerX, soilTop + 4 * strength);
      drawRootBranch(rootOrigin, baseLength, 90, baseThickness, maxDepth, 11.0);
      drawRootBranch(rootOrigin, baseLength * 0.85, 115, baseThickness * 0.92, maxDepth - 1, 23.4);
      drawRootBranch(rootOrigin, baseLength * 0.85, 65, baseThickness * 0.92, maxDepth - 1, 37.8);
    }

    if (stageBranch > 0) {
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

      final double baseLength = ui.lerpDouble(54, 126, stageBranch) ?? 54;
      final double baseThickness = ui.lerpDouble(6.5, 11.0, stageBranch) ?? 6.5;
      final int maxDepth = 3 + (stageBranch * 2.5).floor();

      Color branchColor(int depth) {
        final double t = depth / (maxDepth + 1);
        return Color.lerp(const Color(0xFF704225), const Color(0xFF9B6B3A), t)!
            .withOpacity(0.95 - t * 0.25);
      }

      void growBranch(
        Offset start,
        double length,
        double angleDeg,
        double thickness,
        int depth,
        double seed,
      ) {
        if (depth <= 0 || thickness < 0.8) return;
        final double angle = angleDeg * math.pi / 180;
        final double bend = math.sin((seed + depth) * 1.4) * 8;
        final Offset control = start + Offset(
          math.cos((angleDeg + bend * 0.25) * math.pi / 180) * length * 0.5,
          math.sin((angleDeg + bend * 0.25) * math.pi / 180) * length * 0.5,
        );
        final Offset end = start + Offset(
          math.cos(angle) * length,
          math.sin(angle) * length,
        );

        final Path branchPath = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

        canvas.drawPath(
          branchPath,
          Paint()
            ..color = branchColor(maxDepth - depth)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = thickness,
        );

        final double nextLength = length * (0.74 + 0.12 * stageBranch);
        final double nextThickness = thickness * 0.62;
        final double spread = 14 + 8 * (1 - stageBranch);

        growBranch(
          end,
          nextLength,
          angleDeg + spread,
          nextThickness,
          depth - 1,
          seed + 14.6,
        );
        growBranch(
          end,
          nextLength,
          angleDeg - spread,
          nextThickness,
          depth - 1,
          seed + 27.3,
        );

        if (depth > 1) {
          growBranch(
            end,
            nextLength * (0.72 + 0.18 * stageBranch),
            angleDeg + math.sin(seed) * 6,
            nextThickness * 0.78,
            depth - 2,
            seed + 33.8,
          );
        }

        // 叶片暂不绘制，专注于枝干生长形态。
      }

      final Offset trunkTop = Offset(centerX, soilTop - stemHeight);
      growBranch(trunkTop, baseLength, -90, baseThickness, maxDepth, 12.4);
      growBranch(trunkTop + Offset(0, -stemHeight * 0.12), baseLength * 0.9, -78, baseThickness * 0.9, maxDepth - 1, 21.7);
      growBranch(trunkTop + Offset(0, -stemHeight * 0.12), baseLength * 0.9, -102, baseThickness * 0.9, maxDepth - 1, 32.1);
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.55),
        baseLength * 0.76,
        -72,
        baseThickness * 0.8,
        maxDepth - 2,
        44.9,
      );
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.55),
        baseLength * 0.76,
        -108,
        baseThickness * 0.8,
        maxDepth - 2,
        56.3,
      );
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.32),
        baseLength * 0.64,
        -65,
        baseThickness * 0.68,
        maxDepth - 3,
        68.7,
      );
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.32),
        baseLength * 0.64,
        -115,
        baseThickness * 0.68,
        maxDepth - 3,
        81.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TreeGrowthPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.seedPlanted != seedPlanted;
  }
}

