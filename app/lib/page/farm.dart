import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../global.dart';
import '../theme/app_theme.dart';

const List<double> _treeStageStops = [
  0.0,
  0.18,
  0.35,
  0.55,
  0.75,
  0.9,
  1.0,
];

const double _maxTreeHeightMeters = 6.0;
const double _secondsPerGrowthDay = 3.0; // 几秒一日的生长速度控制

double _segmentProgressFor(double progress, int segment) {
  final double start = _treeStageStops[segment];
  final double end = _treeStageStops[segment + 1];
  final double clamped = (progress - start) / (end - start);
  return clamped.clamp(0.0, 1.0);
}

double _branchFactorFor(double progress) {
  final double stageSapling = _segmentProgressFor(progress, 2);
  final double stageBranchProgress = _segmentProgressFor(progress, 3);
  return math.sqrt(math.max(stageSapling, stageBranchProgress));
}

double _rootProgressFor(double progress) {
  final double emergenceThreshold = _treeStageStops[2];
  if (emergenceThreshold <= 0) return 0;
  return (progress / emergenceThreshold).clamp(0.0, 1.0);
}

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
  late final int _branchSeed;
  static const int _totalDays = 30;
  static const int _maxDayInput = 365;
  late final TextEditingController _dayController;
  int _stopDay = _totalDays;
  double _displayProgress = 0.0;
  double _elapsedDays = 0.0;
  double _lastControllerValue = 0.0;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _branchSeed = _computeBranchSeed();
    _dayController = TextEditingController(text: '$_stopDay');
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _controller.addListener(_handleTick);
  }

  int _computeBranchSeed() {
    final user = Global.getLoggedInUser();
    final String source = (user?.id ?? 'guest').toString();
    int hash = 17;
    for (final unit in source.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    if (hash == 0) hash = 1;
    return hash;
  }

  void _handleTick() {
    if (!_seedPlanted) return;

    final double currentValue = _controller.value;
    double delta = currentValue - _lastControllerValue;
    if (delta < 0) {
      delta += 1.0;
    }
    _lastControllerValue = currentValue;

    if (delta <= 0) {
      return;
    }

    final double durationMs = (_controller.duration?.inMilliseconds ?? 0).toDouble();
    if (durationMs <= 0) {
      return;
    }
    final double deltaSeconds = delta * durationMs / 1000.0;
    _elapsedDays += deltaSeconds / _secondsPerGrowthDay; // 几秒钟流逝一天

    double newProgress;
    if (_stopDay > 0) {
      if (_elapsedDays >= _stopDay) {
        _elapsedDays = _stopDay.toDouble();
        _controller.stop();
      }
      final double normalized = (_elapsedDays / _stopDay).clamp(0.0, 1.0);
      newProgress = normalized;
    } else {
      const double characteristicDays = 45.0;
      final double normalized = (_elapsedDays / characteristicDays).clamp(0.0, 1.0);
      newProgress = normalized;
    }

    setState(() {
      _displayProgress = newProgress.clamp(0.0, 1.0);
    });
  }

  void _applyStopDay() {
    final String raw = _dayController.text.trim();
    final int? parsed = int.tryParse(raw);
    if (parsed == null) {
      setState(() {
        _inputError = '请输入有效的数字';
      });
      return;
    }

    final int clamped = parsed.clamp(0, _maxDayInput);
    final String normalized = clamped.toString();

    setState(() {
      _stopDay = clamped;
      _inputError = null;
      if (_dayController.text != normalized) {
        _dayController.value = TextEditingValue(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length),
        );
      }
      _elapsedDays = 0.0;
      _displayProgress = 0.0;
      _lastControllerValue = 0.0;
    });

    if (_seedPlanted) {
      _startGrowthFromSeed(restartOnly: true);
    }
  }

  void _startGrowthFromSeed({bool restartOnly = false}) {
    if (restartOnly) {
      setState(() {
        _displayProgress = 0.0;
        _elapsedDays = 0.0;
        _lastControllerValue = 0.0;
      });
    } else {
      setState(() {
        _seedPlanted = true;
        _displayProgress = 0.0;
        _elapsedDays = 0.0;
        _lastControllerValue = 0.0;
      });
    }

    _controller.stop();
    _controller.value = 0.0;
    _controller.repeat();
  }

  double _estimateTreeHeightMeters(double progress) {
    final double factor = _branchFactorFor(progress.clamp(0.0, 1.0));
    return factor * _maxTreeHeightMeters;
  }

  String _formatElapsedTime(double progress) {
    final int totalHours = (_elapsedDays * 24).floor();
    final int days = totalHours ~/ 24;
    final int hours = totalHours % 24;
    final double heightMeters = _estimateTreeHeightMeters(progress);
    return '生长时间：第${days}天${hours}小时 · 当前高度：${heightMeters.toStringAsFixed(2)}米';
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTick);
    _controller.dispose();
    _dayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dayController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '停止天数',
                    hintText: '0 - $_maxDayInput',
                    errorText: _inputError,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    helperText: '输入播放到第几天停止，填 0 表示不自动停止',
                    helperStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _applyStopDay,
                child: const Text('应用'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!_seedPlanted) {
                _startGrowthFromSeed();
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 使用 LayoutBuilder 获取父容器尺寸，便于自适应绘制大小
                final double progress = _seedPlanted ? _displayProgress : 0.0;
                final String elapsedLabel = _formatElapsedTime(progress);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _TreeGrowthPainter(
                        progress: progress,
                        isDarkMode: isDarkMode,
                        accentColor: AppTheme.primaryColor,
                        // 记录是否已播种，决定是否绘制树干
                        seedPlanted: _seedPlanted,
                        branchSeed: _branchSeed,
                      ),
                    ),
                    Positioned(
                      top: 18,
                      left: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              Colors.black.withValues(alpha: isDarkMode ? 0.48 : 0.32),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Text(
                            elapsedLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!_seedPlanted)
                      Positioned(
                        bottom: 18,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black
                                .withValues(alpha: isDarkMode ? 0.45 : 0.28),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            // 初始提示：轻点种子开始动画
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
          ),
        ),
      ],
    );
  }
}

class _TreeGrowthPainter extends CustomPainter {
  final double progress;
  final bool isDarkMode;
  final Color accentColor;
  final bool seedPlanted;
  final int branchSeed;
  // 整个动画按阶段划分，使用分段时间控制各部位的生长

  _TreeGrowthPainter({
    required this.progress,
    required this.isDarkMode,
    required this.accentColor,
    required this.seedPlanted,
    required this.branchSeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double soilTop = size.height * 0.65; // 土层位置：下方约三分之一
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

    final double stageBranch = _branchFactorFor(progress);
    final double stageRoot = _rootProgressFor(progress);

    final double centerX = size.width * 0.5;

    // 种子：播种瞬间埋入土壤，不再做缓慢下沉动画
    final Offset seedCenter = seedPlanted
        ? Offset(centerX, soilTop + 6)
        : Offset(centerX, soilTop - 12);
    final double seedRadius = seedPlanted ? 3.6 : 5;
    canvas.drawCircle(
      seedCenter,
      seedRadius,
      Paint()..color = const Color(0xFF9C6941),
    );

    // 播种后立刻生长根系，破土而出后隐藏
    if (seedPlanted && stageRoot > 0 && stageBranch < 0.02) {
      final double easedRoot = math.pow(stageRoot, 1.4).toDouble();
      final int rootDepth = 1 + (easedRoot * 4).floor();
      final double rootBaseLength = ui.lerpDouble(16, soilRect.height * 0.55, easedRoot) ?? 16;
      final double rootBaseThickness = ui.lerpDouble(1.2, 3.4, easedRoot) ?? 1.2;
      final Color rootBaseColor = const Color(0xFF8A532B);
      final Color rootTipColor = const Color(0xFF5B341B);

      double noise(String key) {
        int hash = branchSeed ^ 0x5f3759df;
        for (final code in key.codeUnits) {
          hash = (hash * 31 + code) & 0x7fffffff;
        }
        return (hash / 0x7fffffff) * 2 - 1;
      }

      void drawRootBranch(
        Offset start,
        double length,
        double angleDeg,
        double thickness,
        int depth,
        String key,
      ) {
        if (depth <= 0 || thickness < 0.6) {
          return;
        }
        final double angle = angleDeg * math.pi / 180;
        final double bend = noise('bend-$key-$depth') * (6 + easedRoot * 6);
        final double controlAngle = (angleDeg + bend * 0.35) * math.pi / 180;
        final Offset control = start + Offset(
          math.cos(controlAngle) * length * 0.46,
          math.sin(controlAngle) * length * 0.46,
        );
        final Offset end = start + Offset(
          math.cos(angle) * length,
          math.sin(angle) * length,
        );

        final double depthRatio = (rootDepth - depth) / rootDepth;
        final Paint rootPaint = Paint()
          ..color = Color.lerp(rootBaseColor, rootTipColor, depthRatio)!
          ..strokeWidth = thickness
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final Path rootPath = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        canvas.drawPath(rootPath, rootPaint);

        final double nextLength = length * (0.72 + 0.16 * easedRoot) * (0.96 + noise('len-$key-$depth') * 0.08);
        final double nextThickness = math.max(0.6, thickness * (0.64 + 0.18 * easedRoot));
        final double spread = 14 + easedRoot * 10 + noise('spread-$key-$depth') * 8;

        drawRootBranch(end, nextLength, angleDeg + spread, nextThickness, depth - 1, '${key}L');
        drawRootBranch(end, nextLength, angleDeg - spread, nextThickness, depth - 1, '${key}R');

        if (depth > 2 && easedRoot > 0.4) {
          final double extra = 0.48 + 0.16 * easedRoot;
          drawRootBranch(
            end,
            nextLength * extra,
            angleDeg + noise('mid-$key-$depth') * 16,
            nextThickness * 0.84,
            depth - 2,
            '${key}M',
          );
        }
      }

      final Offset rootStart = seedCenter + const Offset(0, 4);
      final double mainAngle = 90 + noise('root-main') * 6;
      drawRootBranch(rootStart, rootBaseLength, mainAngle + 12 + easedRoot * 24,
          rootBaseThickness, rootDepth, 'root-left');
      drawRootBranch(rootStart, rootBaseLength, mainAngle - (12 + easedRoot * 24),
          rootBaseThickness, rootDepth, 'root-right');
      if (easedRoot > 0.42) {
        drawRootBranch(
          rootStart,
          rootBaseLength * (0.74 + easedRoot * 0.22),
          mainAngle + noise('root-center') * 10,
          rootBaseThickness * 0.82,
          rootDepth - 1,
          'root-center',
        );
      }
    }

    if (stageBranch > 0) {
      final double stemHeight = ui.lerpDouble(18, size.height * 0.46, stageBranch * stageBranch) ?? 18;
      final double trunkBaseWidth = ui.lerpDouble(10, 26, stageBranch) ?? 10;
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

      // 树枝：递归生成向上分叉的枝干形态
      final double baseLength = ui.lerpDouble(54, 126, stageBranch) ?? 54;
      final double baseThickness = ui.lerpDouble(6.5, 11.0, stageBranch) ?? 6.5;
      final int maxDepth = 3 + (stageBranch * 2.5).floor();

      Color branchColor(int depth) {
        final double t = depth / (maxDepth + 1);
        return Color.lerp(const Color(0xFF704225), const Color(0xFF9B6B3A), t)!
            .withValues(alpha: 0.95 - t * 0.25);
      }

      double noise(String key) {
        int hash = branchSeed & 0x7fffffff;
        for (final code in key.codeUnits) {
          hash = (hash * 31 + code) & 0x7fffffff;
        }
        return (hash / 0x7fffffff) * 2 - 1;
      }

      double branchStageFor(String key, double parentStage) {
        final double delay = ((noise('$key-delay') + 1) / 2) * 0.25;
        return (parentStage - delay).clamp(0.0, 1.0);
      }

      void growBranch(
        Offset start,
        double length,
        double angleDeg,
        double thickness,
        int depth,
        String key,
        double parentStage,
      ) {
        if (depth <= 0 || thickness < 0.8) return;
        final double localStage = branchStageFor(key, parentStage);
        if (localStage <= 0) return;

        final double angle = angleDeg * math.pi / 180;
        final double bend = noise('$key-bend-$depth') * 10;
        final double controlAngle = (angleDeg + bend * 0.3) * math.pi / 180;
        final Offset control = start + Offset(
          math.cos(controlAngle) * length * 0.5,
          math.sin(controlAngle) * length * 0.5,
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

        final double lengthJitter = 1 + noise('$key-length-$depth') * 0.12;
        final double nextLength = length * (0.68 + 0.2 * localStage) * lengthJitter;
        final double taperBase = 0.52 + 0.2 * localStage;
        final double taperNoise = 1 + noise('$key-thickness-$depth') * 0.09;
        final double candidate = thickness * taperBase * taperNoise;
        final double guaranteedDecrease = thickness - 0.2 * (0.5 + 0.5 * localStage);
        final double nextThickness = math.max(0.18, math.min(candidate, guaranteedDecrease));
        final double spreadBase = 12 + 9 * (1 - localStage);
        final double spread = spreadBase + noise('$key-spread-$depth') * 9;

        growBranch(
          end,
          nextLength,
          angleDeg + spread,
          nextThickness,
          depth - 1,
          '$key-L$depth',
          localStage * 0.92,
        );
        growBranch(
          end,
          nextLength,
          angleDeg - spread,
          nextThickness,
          depth - 1,
          '$key-R$depth',
          localStage * 0.92,
        );

        if (depth > 1) {
          growBranch(
            end,
            nextLength * (0.62 + 0.15 * localStage),
            angleDeg + noise('$key-Mang-$depth') * 16,
            nextThickness * 0.76,
            depth - 2,
            '$key-M$depth',
            localStage * 0.85,
          );
        }

        // 叶片暂不绘制，专注于枝干生长形态。
      }

      final Offset trunkTop = Offset(centerX, soilTop - stemHeight);
      growBranch(trunkTop, baseLength, -90, baseThickness * 0.84, maxDepth, 'main', stageBranch);
      growBranch(trunkTop + Offset(0, -stemHeight * 0.08), baseLength * 0.9, -78,
          baseThickness * 0.78, maxDepth - 1, 'upperL', stageBranch);
      growBranch(trunkTop + Offset(0, -stemHeight * 0.08), baseLength * 0.9, -102,
          baseThickness * 0.78, maxDepth - 1, 'upperR', stageBranch);
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.52),
        baseLength * 0.76,
        -72,
        baseThickness * 0.7,
        maxDepth - 2,
        'midL',
        stageBranch,
      );
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.52),
        baseLength * 0.76,
        -108,
        baseThickness * 0.7,
        maxDepth - 2,
        'midR',
        stageBranch,
      );
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.3),
        baseLength * 0.64,
        -65,
        baseThickness * 0.6,
        maxDepth - 3,
        'lowL',
        stageBranch,
      );
      growBranch(
        Offset(centerX, soilTop - stemHeight * 0.3),
        baseLength * 0.64,
        -115,
        baseThickness * 0.6,
        maxDepth - 3,
        'lowR',
        stageBranch,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TreeGrowthPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.seedPlanted != seedPlanted ||
        oldDelegate.branchSeed != branchSeed;
  }
}


