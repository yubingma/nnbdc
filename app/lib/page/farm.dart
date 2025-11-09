import 'dart:math' as math;
import 'dart:typed_data';
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
const double _seedInitialDepth = 18.0; // 种子初始埋深，控制破土时间
const double _worldScaleMetersPerScreen = 10.0; // 当前屏幕宽度代表的米数
const double _targetWorldWidthMeters = 1000.0; // 世界总宽度（米）
const double _soilThicknessMeters = 5.0; // 土壤层厚度（米）

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
  late final TransformationController _viewController;
  Matrix4 _baseViewMatrix = Matrix4.identity();
  Size? _lastViewportSize;
  bool _viewMatrixInitialized = false;
  bool _userInteractingWithView = false;
  bool _isAdjustingViewMatrix = false;
  double _currentViewportHeight = 0;
  double _currentWorldHeight = 0;

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
    _viewController = TransformationController();
    _viewController.addListener(_handleViewMatrixChange);
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

  Matrix4 _computeBaseViewMatrix(
    double viewportWidth,
    double viewportHeight,
    double worldWidth,
    double worldHeight,
  ) {
    // 将用户小天地放在世界中央，同时保证世界底部贴齐屏幕底部
    // 用户小天地在世界中央，即 worldWidth / 2
    // 视口中央是 viewportWidth / 2
    // 所以 X 平移 = viewportWidth/2 - worldWidth/2
    final Matrix4 matrix = Matrix4.identity();
    matrix.translate(
      viewportWidth / 2 - worldWidth / 2,
      viewportHeight - worldHeight,
    );
    return matrix;
  }

  bool _matricesTranslationClose(Matrix4 a, Matrix4 b,
      [double tolerance = 0.5]) {
    final Float64List aStorage = a.storage;
    final Float64List bStorage = b.storage;
    return (aStorage[12] - bStorage[12]).abs() <= tolerance &&
        (aStorage[13] - bStorage[13]).abs() <= tolerance;
  }

  void _applyViewMatrix(Matrix4 matrix) {
    _isAdjustingViewMatrix = true;
    try {
      _viewController.value = Matrix4.copy(matrix);
    } finally {
      _isAdjustingViewMatrix = false;
    }
  }

  void _handleViewMatrixChange() {
    if (!_viewMatrixInitialized || _isAdjustingViewMatrix) {
      return;
    }
    if (_currentViewportHeight <= 0 || _currentWorldHeight <= 0) {
      return;
    }
    final Matrix4 value = _viewController.value;
    final double scaleY = value.getMaxScaleOnAxis();
    final double desiredTy =
        _currentViewportHeight - scaleY * _currentWorldHeight;
    final double currentTy = value.storage[13];
    if ((currentTy - desiredTy).abs() > 0.5) {
      final Matrix4 adjusted = Matrix4.copy(value);
      adjusted.setTranslationRaw(
        adjusted.storage[12],
        desiredTy,
        adjusted.storage[14],
      );
      _applyViewMatrix(adjusted);
    }
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

    const double characteristicDays = 45.0;
    if (_stopDay > 0 && _elapsedDays >= _stopDay) {
      _elapsedDays = _stopDay.toDouble();
      _controller.stop();
    }

    final double newProgress =
        (_elapsedDays / characteristicDays).clamp(0.0, 1.0);

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
    final double emergenceThreshold = _treeStageStops[2];
    if (progress < emergenceThreshold) {
      return 0.0;
    }
    final double post = ((progress - emergenceThreshold) / (1 - emergenceThreshold)).clamp(0.0, 1.0);
    final double factor = math.pow(post, 0.85).toDouble();
    return factor * _maxTreeHeightMeters;
  }

  String _formatElapsedTime(double progress) {
    final int totalHours = (_elapsedDays * 24).floor();
    final int days = totalHours ~/ 24;
    final int hours = totalHours % 24;
    final double heightMeters = _estimateTreeHeightMeters(progress);
    return '生长时间：第$days天$hours小时 · 当前高度：${heightMeters.toStringAsFixed(2)}米';
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTick);
    _controller.dispose();
    _dayController.dispose();
    _viewController.removeListener(_handleViewMatrixChange);
    _viewController.dispose();
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
            onDoubleTap: () {
              _userInteractingWithView = false;
              _applyViewMatrix(_baseViewMatrix);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 使用 LayoutBuilder 获取父容器尺寸，便于自适应绘制大小
                final double progress = _seedPlanted ? _displayProgress : 0.0;
                final String elapsedLabel = _formatElapsedTime(progress);
                final double worldWidth =
                    constraints.maxWidth * (_targetWorldWidthMeters / _worldScaleMetersPerScreen);
                final double aspectRatio = constraints.maxWidth == 0
                    ? 1.0
                    : constraints.maxHeight / constraints.maxWidth;
                final double worldHeight = worldWidth * aspectRatio;
                final double boundaryExtent =
                    math.max(worldWidth, worldHeight) * 0.25;
                final Size viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
                _currentViewportHeight = viewportSize.height;
                _currentWorldHeight = worldHeight;

                final Matrix4 desiredBaseMatrix = _computeBaseViewMatrix(
                  viewportSize.width,
                  viewportSize.height,
                  worldWidth,
                  worldHeight,
                );

                final bool viewportChanged = _lastViewportSize != viewportSize;

                if (!_viewMatrixInitialized || viewportChanged) {
                  _viewMatrixInitialized = true;
                  _lastViewportSize = viewportSize;
                  _baseViewMatrix = Matrix4.copy(desiredBaseMatrix);
                  _applyViewMatrix(_baseViewMatrix);
                } else if (!_userInteractingWithView &&
                    !_matricesTranslationClose(_baseViewMatrix, desiredBaseMatrix)) {
                  _lastViewportSize = viewportSize;
                  _baseViewMatrix = Matrix4.copy(desiredBaseMatrix);
                  _applyViewMatrix(_baseViewMatrix);
                }
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRect(
                      child: InteractiveViewer(
                        transformationController: _viewController,
                        constrained: false,
                        alignment: Alignment.topLeft,
                        minScale: 0.001,
                        maxScale: 2.6,
                        boundaryMargin: EdgeInsets.all(boundaryExtent),
                        clipBehavior: Clip.hardEdge,
                        onInteractionStart: (_) {
                          _userInteractingWithView = true;
                        },
                        onInteractionEnd: (_) {
                          _userInteractingWithView = false;
                        },
                        child: SizedBox(
                          width: worldWidth,
                          height: worldHeight,
                          child: CustomPaint(
                            painter: _TreeGrowthPainter(
                              progress: progress,
                              isDarkMode: isDarkMode,
                              accentColor: AppTheme.primaryColor,
                              // 记录是否已播种，决定是否绘制树干
                              seedPlanted: _seedPlanted,
                              branchSeed: _branchSeed,
                            ),
                          ),
                        ),
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

  // 绘制云朵
  void drawCloud(Canvas canvas, Offset center, double scale, double seed) {
    final Paint cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    
    final Paint cloudShadow = Paint()
      ..color = const Color(0xFFE0E0E0).withValues(alpha: 0.4);
    
    // 云朵由多个椭圆组成
    final List<Map<String, double>> bubbles = [
      {'x': 0, 'y': 0, 'w': 50 * scale, 'h': 30 * scale},
      {'x': 35 * scale, 'y': -5 * scale, 'w': 45 * scale, 'h': 35 * scale},
      {'x': 65 * scale, 'y': 2 * scale, 'w': 40 * scale, 'h': 28 * scale},
      {'x': 20 * scale, 'y': 8 * scale, 'w': 35 * scale, 'h': 25 * scale},
      {'x': 50 * scale, 'y': 10 * scale, 'w': 30 * scale, 'h': 22 * scale},
    ];
    
    // 绘制阴影
    for (final bubble in bubbles) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            center.dx + bubble['x']! + 2,
            center.dy + bubble['y']! + 2,
          ),
          width: bubble['w']!,
          height: bubble['h']!,
        ),
        cloudShadow,
      );
    }
    
    // 绘制云朵
    for (final bubble in bubbles) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            center.dx + bubble['x']!,
            center.dy + bubble['y']!,
          ),
          width: bubble['w']!,
          height: bubble['h']!,
        ),
        cloudPaint,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double pixelsPerMeter =
        _targetWorldWidthMeters == 0 ? 0 : size.width / _targetWorldWidthMeters;
    final double soilThicknessPx = pixelsPerMeter > 0
        ? math.min(size.height * 0.9, _soilThicknessMeters * pixelsPerMeter)
        : size.height * 0.35;
    final double soilTop = size.height - soilThicknessPx; // 土层位置，底部厚度固定为 5 米
    
    // 绘制蓝天 - 深邃的蔚蓝色
    final Paint skyPaint = Paint();
    if (isDarkMode) {
      skyPaint.shader = const LinearGradient(
        colors: [Color(0xFF22354F), Color(0xFF101D2C)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, soilTop));
    } else {
      skyPaint.color = const Color(0xFF1E88E5); // 深邃的蔚蓝色
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, soilTop), skyPaint);

    // 用户小天地在世界中央
    final double centerX = size.width * 0.5;
    
    // 使用已定义的pixelsPerMeter，计算视口尺寸（用于树木等对象的合理比例）
    final double viewportWidthMeters = _worldScaleMetersPerScreen; // 视口宽度对应10米
    final double viewportHeightMeters = viewportWidthMeters * (size.height / size.width);
    final double viewportHeightPx = viewportHeightMeters * pixelsPerMeter;
    
    final double horizonY = soilTop - viewportHeightPx * 0.35;
    
    // 绘制云朵和太阳（都在世界空间中，会随滚动变化）
    if (!isDarkMode) {
      final math.Random cloudRandom = math.Random(branchSeed ^ 0x1c7);
      
      // 太阳（在世界空间中，山峰上方10米）
      final double mountainHeight = viewportHeightPx * 0.32; // 山峰约高度
      final double sunX = size.width * 0.67; // 世界中的X位置
      final double sunY = horizonY - mountainHeight - 10 * pixelsPerMeter; // 山峰上方10米
      final double sunRadius = 75.0; // 直径150像素，半径75
      
      // 太阳光晕
      final Paint sunGlowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFEB3B).withValues(alpha: 0.5),
            const Color(0xFFFFEB3B).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: sunRadius * 2.5));
      canvas.drawCircle(Offset(sunX, sunY), sunRadius * 2.5, sunGlowPaint);
      
      // 太阳本体
      final Paint sunPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFACD),
            const Color(0xFFFFEB3B),
            const Color(0xFFFFC107),
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: sunRadius));
      canvas.drawCircle(Offset(sunX, sunY), sunRadius, sunPaint);
      
      // 云朵（覆盖整个天空）- 大20倍
      final int cloudCount = 15; // 增加数量覆盖整个天空
      final double skyHeight = soilTop; // 天空高度（从顶部到土壤）
      
      for (int i = 0; i < cloudCount; i++) {
        // 云朵在世界空间中均匀分布
        final double cloudX = (i / cloudCount) * size.width + cloudRandom.nextDouble() * 300 - 150;
        // 云朵分布在整个天空：从顶部5%到底部95%
        final double cloudY = skyHeight * 0.05 + cloudRandom.nextDouble() * skyHeight * 0.9;
        final double cloudScale = (0.6 + cloudRandom.nextDouble() * 0.8) * 20; // 放大20倍
        
        drawCloud(canvas, Offset(cloudX, cloudY), cloudScale, cloudRandom.nextDouble());
      }
    }
    
    // 绘制渐变的大气层，从天空平滑过渡到地平线
    final Paint atmospherePaint = Paint()
      ..shader = LinearGradient(
        colors: isDarkMode 
          ? [
              const Color(0xFF22354F).withValues(alpha: 0.0),
              const Color(0xFF3A4F72).withValues(alpha: 0.3),
              const Color(0xFF4A6088).withValues(alpha: 0.6),
            ]
          : [
              const Color(0xFF6BB7FF).withValues(alpha: 0.0),
              const Color(0xFF89C8FF).withValues(alpha: 0.4),
              const Color(0xFFB5DBFF).withValues(alpha: 0.7),
            ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, horizonY - viewportHeightPx * 0.25, size.width, viewportHeightPx * 0.25));
    canvas.drawRect(
      Rect.fromLTWH(0, horizonY - viewportHeightPx * 0.25, size.width, viewportHeightPx * 0.25),
      atmospherePaint,
    );

    Path distantRange(double baseY, double heightFactor, double skew, double peakDensity) {
      final Path path = Path()..moveTo(0, baseY);
      // 山峰数量基于视口宽度，确保在任何缩放级别都能看到起伏
      final double pixelsPerPeak = viewportWidthMeters * pixelsPerMeter / peakDensity;
      final int peakCount = math.max(3, (size.width / pixelsPerPeak).ceil());
      final double step = size.width / peakCount;
      
      // 生成所有山峰的高度数据
      final List<double> peakHeights = [];
      for (int i = 0; i <= peakCount; i++) {
        final double baseHeight = heightFactor * viewportHeightPx;
        final double majorVariation = math.sin(i * 0.9 + skew) * 0.8;
        final double minorVariation = math.sin(i * 2.5 + skew * 1.8) * 0.4;
        final double microVariation = math.sin(i * 5.2 + skew * 3.2) * 0.2;
        final double totalVariation = majorVariation + minorVariation + microVariation;
        peakHeights.add(baseY - baseHeight * (1.0 + totalVariation));
      }
      
      // 使用三次贝塞尔曲线创建非常圆润的山峰轮廓
      for (int i = 0; i <= peakCount; i++) {
        final double x = i * step;
        final double peak = peakHeights[i];
        
        if (i == 0) {
          path.lineTo(x, peak);
        } else {
          final double prevX = (i - 1) * step;
          final double prevPeak = peakHeights[i - 1];
          
          // 控制点位置非常接近端点，创造极其平缓的曲线
          final double segmentLength = x - prevX;
          final double control1X = prevX + segmentLength * 0.4;
          final double control2X = x - segmentLength * 0.4;
          
          // 控制点的Y坐标几乎贴近端点，让曲线在峰顶和谷底都非常平缓
          final double heightDiff = peak - prevPeak;
          final double control1Y = prevPeak + heightDiff * 0.1;
          final double control2Y = peak - heightDiff * 0.1;
          
          path.cubicTo(
            control1X, control1Y,
            control2X, control2Y,
            x, peak,
          );
        }
      }
      
      path
        ..lineTo(size.width, baseY)
        ..lineTo(size.width, soilTop)
        ..lineTo(0, soilTop)
        ..close();
      return path;
    }

    // 最远的山脉 - 深蓝色，低密度（约2个峰/视口）
    final double veryFarMountainBase = horizonY - viewportHeightPx * 0.05;
    final Paint veryFarRangePaint = Paint()
      ..shader = LinearGradient(
        colors: isDarkMode
          ? [
              const Color(0xFF4A5F8E),
              const Color(0xFF2F3D5E),
            ]
          : [
              const Color(0xFF7A9BC8),
              const Color(0xFF5A7BA8),
            ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, veryFarMountainBase - viewportHeightPx * 0.3, size.width, viewportHeightPx * 0.35));
    canvas.drawPath(
      distantRange(veryFarMountainBase, 0.25, 0.0, 2.0),
      veryFarRangePaint,
    );

    // 中远山脉 - 蓝紫色，中密度（约3个峰/视口）
    final double farMountainBase = horizonY;
    final Paint farRangePaint = Paint()
      ..shader = LinearGradient(
        colors: isDarkMode
          ? [
              const Color(0xFF5A6F9E),
              const Color(0xFF3A4F7E),
            ]
          : [
              const Color(0xFF8AAADF),
              const Color(0xFF6B8AAF),
            ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, farMountainBase - viewportHeightPx * 0.35, size.width, viewportHeightPx * 0.4));
    canvas.drawPath(
      distantRange(farMountainBase, 0.28, 1.5, 3.0),
      farRangePaint,
    );

    // 近山脉 - 绿色调，高密度（约4个峰/视口）
    final double nearMountainBase = horizonY + viewportHeightPx * 0.04;
    final Paint nearRangePaint = Paint()
      ..shader = LinearGradient(
        colors: isDarkMode
          ? [
              const Color(0xFF5A7F5A),
              const Color(0xFF3A5F3A),
            ]
          : [
              const Color(0xFF8AC87A),
              const Color(0xFF5A9850),
            ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, nearMountainBase - viewportHeightPx * 0.4, size.width, viewportHeightPx * 0.45));
    canvas.drawPath(
      distantRange(nearMountainBase, 0.32, 2.8, 4.0),
      nearRangePaint,
    );

    // 先绘制河流，让树木可以遮挡它
    final double riverTop = soilTop - viewportHeightPx * 0.18;
    final Paint riverPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF9CD0F3).withValues(alpha: 0.55),
          const Color(0xFF66A8D1).withValues(alpha: 0.8),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, riverTop - 14, size.width, 60));
    final Path riverPath = Path()
      ..moveTo(0, riverTop)
      ..cubicTo(
        size.width * 0.15,
        riverTop + 18,
        size.width * 0.35,
        riverTop - 28,
        size.width * 0.52,
        riverTop - 10,
      )
      ..cubicTo(
        size.width * 0.75,
        riverTop + 24,
        size.width * 0.92,
        riverTop - 6,
        size.width,
        riverTop + 14,
      )
      ..lineTo(size.width, riverTop + 60)
      ..lineTo(0, riverTop + 60)
      ..close();
    canvas.drawPath(riverPath, riverPaint);

    final Paint riverHighlight = Paint()
      ..color = Colors.white.withValues(alpha: isDarkMode ? 0.16 : 0.22)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      riverPath.shift(const Offset(0, -2)),
      riverHighlight,
    );

    // 计算河流上边缘的Y坐标函数（蜿蜒曲线）
    double getRiverEdgeY(double x) {
      // 复制河流路径的逻辑来计算指定X位置的河流上边缘Y坐标
      if (x <= size.width * 0.52) {
        // 第一段曲线
        final double t1 = x / (size.width * 0.52);
        final double y1 = riverTop;
        final double y2 = riverTop - 10;
        final double cy1 = riverTop + 18;
        final double cy2 = riverTop - 28;
        // 简化的三次贝塞尔曲线近似
        return y1 * math.pow(1 - t1, 3) + 
               cy1 * 3 * math.pow(1 - t1, 2) * t1 +
               cy2 * 3 * (1 - t1) * math.pow(t1, 2) +
               y2 * math.pow(t1, 3);
      } else {
        // 第二段曲线
        final double t2 = (x - size.width * 0.52) / (size.width - size.width * 0.52);
        final double y1 = riverTop - 10;
        final double y2 = riverTop + 14;
        final double cy1 = riverTop + 24;
        final double cy2 = riverTop - 6;
        return y1 * math.pow(1 - t2, 3) + 
               cy1 * 3 * math.pow(1 - t2, 2) * t2 +
               cy2 * 3 * (1 - t2) * math.pow(t2, 2) +
               y2 * math.pow(t2, 3);
      }
    }
    
    // 远景树林 - 深绿色，更明显，绘制在河流之后以遮挡河流
    // 树木分为两组：远景树林（沿河岸线分布）和近景树林（在土壤表面草地带）
    final math.Random treeRandom = math.Random(branchSeed ^ 0x7a9);
    final int groveCount = (size.width / 80).ceil();
    
    for (int i = 0; i < groveCount; i++) {
      final double t = i / groveCount;
      final double baseX = t * size.width + math.sin(i * 1.4) * 28;
      final double depthRandom = treeRandom.nextDouble();
      
      // 根据随机值决定树木在远处（河岸附近）还是近处（土壤表面）
      final bool isFar = depthRandom < 0.6; // 60%的树在远处
      
      double depthY;
      double depth;
      double treeHeight;
      
      if (isFar) {
        // 远景树林：沿着河流上边缘分布，树根紧贴河岸
        depth = depthRandom / 0.6; // 归一化到 0-1
        treeHeight = 40 + depth * 30;
        
        // 获取这个X位置的河流边缘Y坐标
        final double riverEdgeY = getRiverEdgeY(baseX.clamp(0.0, size.width));
        
        // 使用4次方分布让大部分树紧贴河岸
        final double distanceRandom = treeRandom.nextDouble();
        final double distanceFromRiver = math.pow(distanceRandom, 4.0).toDouble();
        
        // 树根距离河岸边缘 5-80px
        final double maxNearDistance = 80.0;
        final double rootY = riverEdgeY - 5 - distanceFromRiver * maxNearDistance;
        depthY = rootY - treeHeight;
        
        // 根据距离河岸的远近计算深度（用于透明度和尺寸）
        depth = (distanceFromRiver * 0.6 + 0.4).clamp(0.0, 1.0);
      } else {
        // 近景树林：在土壤表面的草地带（soilTop上方20-60px的绿色区域）
        depth = (depthRandom - 0.6) / 0.4; // 归一化到 0-1
        treeHeight = 50 + depth * 40;
        // 树根要固定在土壤表面附近
        final double grassZoneHeight = 50; // 草地带高度
        depthY = soilTop - grassZoneHeight + depth * grassZoneHeight * 0.6 - treeHeight;
      }
      
      final double treeWidth = 5 + depth * 5;
      final double crownWidth = 38 + depth * 24;
      final double crownHeight = 28 + depth * 18;
      
      // 树干 - 深褐色，更突出
      final Paint distantTreePaint = Paint()
        ..color = (isDarkMode 
            ? const Color(0xFF3A2F1A) 
            : const Color(0xFF5A4A2A)).withValues(alpha: 0.7 + depth * 0.2);
      
      // 树冠 - 深绿色，对比强烈
      final Paint distantCrownPaint = Paint()
        ..color = (isDarkMode
            ? const Color(0xFF2F4F2F)
            : const Color(0xFF3A7A3A)).withValues(alpha: 0.75 + depth * 0.2);
      
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(baseX, depthY + treeHeight * 0.5),
          width: treeWidth,
          height: treeHeight,
        ),
        distantTreePaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(baseX, depthY - treeHeight * 0.15),
          width: crownWidth,
          height: crownHeight,
        ),
        distantCrownPaint,
      );
    }

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
    final math.Random random = math.Random(branchSeed ^ 0x51f);
    final int stoneCount = (size.width / 20).round();
    for (int i = 0; i < stoneCount; i++) {
      final double x = soilRect.left + random.nextDouble() * soilRect.width;
      final double y = soilRect.top + soilRect.height * (0.15 + random.nextDouble() * 0.8);
      final double r = 1.6 + random.nextDouble() * 3.6;
      stonePaint.color = Color.lerp(
        const Color(0xFF9B6A3D),
        const Color(0xFF6B4124),
        random.nextDouble(),
      )!;
      canvas.drawOval(Rect.fromCircle(center: Offset(x, y), radius: r), stonePaint);
    }

    final Paint shrubPaint = Paint()
      ..color = const Color(0xFF4A7B37).withValues(alpha: 0.82);
    final Paint shrubShadow = Paint()
      ..color = const Color(0xFF2E4F27).withValues(alpha: 0.6);
    final int shrubCount = (size.width / 90).ceil();
    for (int i = 0; i < shrubCount; i++) {
      final double t = (i + 0.5) / shrubCount;
      final double baseX = soilRect.left + soilRect.width * t +
          math.sin(i * 1.6) * 32;
      final double baseY = soilRect.top + soilRect.height * 0.05 +
          math.sin(i * 0.9) * 12;
      final double radius = 18 + math.sin(i * 1.2) * 6;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(baseX, baseY + 8),
          width: radius * 1.6,
          height: radius * 0.7,
        ),
        shrubShadow,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(baseX, baseY),
          width: radius * 1.4,
          height: radius,
        ),
        shrubPaint,
      );
    }
    final double emergenceThreshold = _treeStageStops[2];
    final bool hasBrokenGround = seedPlanted && progress >= emergenceThreshold;
    final double stageRoot = _rootProgressFor(progress);
    final double stageBranch = hasBrokenGround
        ? math.pow(
              ((progress - emergenceThreshold) / (1 - emergenceThreshold)).clamp(0.0, 1.0),
              0.85,
            ).toDouble()
        : 0.0;
    final double foliageStart = _treeStageStops[3];
    final double stageFoliage = (hasBrokenGround && stageBranch > 0)
        ? math.pow(
              ((progress - foliageStart) / (1 - foliageStart)).clamp(0.0, 1.0),
              0.9,
            ).toDouble()
        : 0.0;

    // 种子：播种瞬间埋入土壤，不再做缓慢下沉动画
    final double sproutRatio = seedPlanted
        ? (emergenceThreshold > 0
            ? (progress / emergenceThreshold).clamp(0.0, 1.0)
            : progress.clamp(0.0, 1.0))
        : 0.0;

    final double seedLift = seedPlanted ? sproutRatio.clamp(0.0, 1.0) : 0.0;
    final double rootPush = seedPlanted
        ? ui.lerpDouble(
              0,
              _seedInitialDepth + 12,
              math.pow(stageRoot, 1.18).toDouble(),
            ) ??
            0
        : 0.0;
    final double emergenceOvershoot = hasBrokenGround
        ? ((progress - emergenceThreshold) / 0.12).clamp(0.0, 1.0)
        : 0.0;
    final double combinedLift = math.max(
      ui.lerpDouble(0, _seedInitialDepth + 8, seedLift) ?? 0,
      rootPush,
    );
    final double seedDepthOffset =
        (_seedInitialDepth - combinedLift).clamp(-12.0, _seedInitialDepth) -
            emergenceOvershoot * 12;
    final Offset seedCenter = seedPlanted
        ? Offset(centerX, soilTop + seedDepthOffset)
        : Offset(centerX, soilTop - 12);
    final double seedRadius = seedPlanted
        ? ui.lerpDouble(3.6, 2.2, (seedLift * 1.2).clamp(0.0, 1.0)) ?? 3.0
        : 5;
    canvas.drawCircle(
      seedCenter,
      seedRadius,
      Paint()..color = const Color(0xFF9C6941),
    );
    if (seedPlanted) {
      final double shellAlpha = (1 - seedLift).clamp(0.0, 1.0);
      if (shellAlpha > 0) {
        final Paint shellPaint = Paint()
          ..color = const Color(0xFFB27A47).withValues(alpha: 0.38 * shellAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ui.lerpDouble(1.4, 0.4, seedLift) ?? 1.0;
        canvas.drawCircle(seedCenter, seedRadius + 2.6, shellPaint);
      }
    }

    if (seedPlanted && sproutRatio > 0 && !hasBrokenGround) {
      final double maxRise = _seedInitialDepth + 14;
      final double sproutLength = sproutRatio * maxRise;
      final Offset sproutEnd = Offset(
        centerX,
        math.max(soilTop - 4, seedCenter.dy - sproutLength),
      );

      final Paint sproutPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF6A3A1E),
            const Color(0xFF8B5A2F),
          ],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ).createShader(
          Rect.fromPoints(seedCenter, sproutEnd),
        )
        ..strokeWidth = ui.lerpDouble(1.1, 2.2, sproutRatio)!
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final Path sproutPath = Path()
        ..moveTo(seedCenter.dx, seedCenter.dy)
        ..quadraticBezierTo(
          centerX + math.sin(sproutRatio * math.pi) * 6,
          (seedCenter.dy + sproutEnd.dy) / 2,
          sproutEnd.dx,
          sproutEnd.dy,
        );
      canvas.drawPath(sproutPath, sproutPaint);

      if (sproutRatio > 0.32) {
        final double budRadius = ui.lerpDouble(1.4, 2.6, sproutRatio)!;
        canvas.drawOval(
          Rect.fromCenter(
            center: sproutEnd + const Offset(0, -2),
            width: budRadius * 1.4,
            height: budRadius * 2.4,
          ),
          Paint()
            ..shader = LinearGradient(
              colors: [const Color(0xFF8B5F39), const Color(0xFFB57A47)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ).createShader(
              Rect.fromCenter(
                center: sproutEnd + const Offset(0, -2),
                width: budRadius * 1.4,
                height: budRadius * 2.4,
              ),
            ),
        );
      }
    }

    // 播种后立刻生长根系，破土而出后隐藏
    if (seedPlanted && stageRoot > 0 && !hasBrokenGround) {
      final double easedRoot = math.pow(stageRoot, 1.35).toDouble();
      final Offset rootStart = seedCenter + const Offset(0, 4);
      final Color rootBaseColor = const Color(0xFF8A532B);
      final Color rootTipColor = const Color(0xFF5B341B);

      if (stageRoot > 0.18) {
        final Paint pushPaint = Paint()
          ..color = Color.lerp(
            rootBaseColor,
            const Color(0xFF4B2A13),
            math.pow(stageRoot, 1.08).toDouble(),
          )!
          ..strokeWidth = ui.lerpDouble(2.2, 4.4, stageRoot) ?? 2.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          rootStart + const Offset(0, 2),
          seedCenter + Offset(0, -seedRadius * 0.3),
          pushPaint,
        );
      }

      if (easedRoot < 0.58) {
        final double rootLength = ui.lerpDouble(28, soilRect.height * 0.45, easedRoot) ?? 28;
        final double sway = ui.lerpDouble(4, 18, easedRoot) ?? 6;
        final Offset control = rootStart + Offset(sway, rootLength * 0.45);
        final Offset end = rootStart + Offset(0, rootLength);
        final Paint rootPaint = Paint()
          ..color = Color.lerp(rootBaseColor, rootTipColor, easedRoot)!
          ..strokeWidth = ui.lerpDouble(1.2, 2.6, easedRoot) ?? 1.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final Path rootPath = Path()
          ..moveTo(rootStart.dx, rootStart.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        canvas.drawPath(rootPath, rootPaint);
      } else {
        final int rootDepth = 1 + (easedRoot * 4).floor();
        final double rootBaseLength = ui.lerpDouble(20, soilRect.height * 0.55, easedRoot) ?? 20;
        final double rootBaseThickness = ui.lerpDouble(1.4, 3.6, easedRoot) ?? 1.4;

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
          final double bend = noise('bend-$key-$depth') * (5 + easedRoot * 6);
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

          final double nextLength =
              length * (0.72 + 0.16 * easedRoot) * (0.96 + noise('len-$key-$depth') * 0.08);
          final double nextThickness = math.max(0.6, thickness * (0.64 + 0.18 * easedRoot));
          final double spread = 14 + easedRoot * 10 + noise('spread-$key-$depth') * 8;

          drawRootBranch(end, nextLength, angleDeg + spread, nextThickness, depth - 1, '${key}L');
          drawRootBranch(end, nextLength, angleDeg - spread, nextThickness, depth - 1, '${key}R');

          if (depth > 2) {
            final double extra = 0.48 + 0.16 * easedRoot;
            drawRootBranch(
              end,
              nextLength * extra,
              angleDeg + noise('mid-$key-$depth') * 14,
              nextThickness * 0.84,
              depth - 2,
              '${key}M',
            );
          }
        }

        final double mainAngle = 90 + noise('root-main') * 6;
        drawRootBranch(rootStart, rootBaseLength, mainAngle + 12 + easedRoot * 24,
            rootBaseThickness, rootDepth, 'root-left');
        drawRootBranch(rootStart, rootBaseLength, mainAngle - (12 + easedRoot * 24),
            rootBaseThickness, rootDepth, 'root-right');
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

    if (hasBrokenGround && stageBranch > 0) {
      final double stemHeight = ui.lerpDouble(14, viewportHeightPx * 0.46, stageBranch) ?? 14;
      final double trunkBaseWidth = ui.lerpDouble(8, 26, stageBranch) ?? 8;
      final double trunkTopWidth = ui.lerpDouble(1.6, 10, stageBranch) ?? 1.6;
      final double trunkLeftBase = centerX - trunkBaseWidth;
      final double trunkRightBase = centerX + trunkBaseWidth;
      final double trunkLeftTop = centerX - trunkTopWidth;
      final double trunkRightTop = centerX + trunkTopWidth;

      final double woodStage = math.pow(stageBranch, 0.78).toDouble();
      final Color trunkHighlight = Color.lerp(
        const Color(0xFFAF7C48),
        const Color(0xFF885932),
        woodStage,
      )!;
      final Color trunkShadow = Color.lerp(
        const Color(0xFF6B4525),
        const Color(0xFF3F2412),
        woodStage * 0.6,
      )!;
      final Paint trunkPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            trunkHighlight,
            trunkShadow,
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
          centerX + trunkBaseWidth * 0.45,
          soilTop - stemHeight * 0.48,
          trunkRightTop,
          soilTop - stemHeight,
        )
        ..lineTo(trunkLeftTop, soilTop - stemHeight)
        ..quadraticBezierTo(
          centerX - trunkBaseWidth * 0.45,
          soilTop - stemHeight * 0.44,
          trunkLeftBase,
          soilTop,
        )
        ..close();
      canvas.drawPath(trunkPath, trunkPaint);

      double noise(String key) {
        int hash = branchSeed & 0x7fffffff;
        for (final code in key.codeUnits) {
          hash = (hash * 31 + code) & 0x7fffffff;
        }
        return (hash / 0x7fffffff) * 2 - 1;
      }

      void drawLeafCluster({
        required Offset origin,
        required double directionDeg,
        required double scale,
        required double growth,
        required String seedKey,
      }) {
        final double normalizedScale = scale.clamp(0.12, 1.0);
        final double stageEased = math.pow(growth.clamp(0.0, 1.0), 0.86).toDouble();
        final double clusterRadius = ui.lerpDouble(8, 28, normalizedScale) ?? 12;
        final Color baseColor = Color.lerp(
          const Color(0xFF6FB257),
          const Color(0xFF37692A),
          0.35 * (1 - stageEased),
        )!;
        final Color highlightColor = Color.lerp(
          const Color(0xFFB1F08C),
          const Color(0xFF7AD463),
          stageEased * 0.6 + 0.2,
        )!;
        final Color shadowColor = Color.lerp(
          const Color(0xFF3E6125),
          const Color(0xFF1E3B16),
          normalizedScale * 0.28 + 0.12,
        )!;

        final Paint bubblePaint = Paint()..style = PaintingStyle.fill;
        final Paint highlightPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.06 + stageEased * 0.06);
        final Paint shadowPaint = Paint()
          ..color = shadowColor.withValues(alpha: 0.16 + stageEased * 0.14)
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, clusterRadius * 0.18);
        final Paint stemPaint = Paint()
          ..color = Color.lerp(
            const Color(0xFF3F5E27),
            const Color(0xFF6E9E3D),
            stageEased,
          )!
          ..strokeWidth = math.max(1.1, clusterRadius * 0.12)
          ..strokeCap = StrokeCap.round;

        canvas.save();
        canvas.translate(origin.dx, origin.dy);
        canvas.rotate(directionDeg * math.pi / 180);

        canvas.drawLine(
          Offset(-clusterRadius * 0.12, 0),
          Offset(clusterRadius * 0.4, 0),
          stemPaint,
        );
        final double cloudWidth = clusterRadius * (2.0 + normalizedScale * 0.5);
        final double cloudHeight = clusterRadius * (1.28 + normalizedScale * 0.34);

        Offset lobeCenter(String axis, double dx, double dy) {
          return Offset(
            dx * cloudWidth + noise('cloud-$axis-x-$seedKey') * clusterRadius * 0.12,
            dy * cloudHeight + noise('cloud-$axis-y-$seedKey') * clusterRadius * 0.1,
          );
        }

        final List<Offset> centers = [
          lobeCenter('a', -0.38, -0.18),
          lobeCenter('b', -0.06, -0.46),
          lobeCenter('c', 0.32, -0.22),
          lobeCenter('d', 0.18, 0.08),
        ];
        final List<double> radii = [
          clusterRadius * (1.08 + normalizedScale * 0.24),
          clusterRadius * (1.26 + normalizedScale * 0.2),
          clusterRadius * (1.02 + normalizedScale * 0.22),
          clusterRadius * (0.88 + normalizedScale * 0.18),
        ];
        final List<double> verticalStretch = [1.42, 1.48, 1.36, 1.44];

        Path cloudPath = Path();
        for (int i = 0; i < centers.length; i++) {
          final Rect oval = Rect.fromCenter(
            center: centers[i],
            width: radii[i] * 2,
            height: radii[i] * verticalStretch[i],
          );
          final Path lobe = Path()..addOval(oval);
          cloudPath = i == 0 ? lobe : Path.combine(PathOperation.union, cloudPath, lobe);
        }

        final Path basePad = Path()
          ..addOval(
            Rect.fromCenter(
              center: Offset(
                noise('cloud-base-x-$seedKey') * clusterRadius * 0.08,
                clusterRadius * (0.32 + stageEased * 0.24),
              ),
              width: cloudWidth * 1.05,
              height: clusterRadius * (0.92 + stageEased * 0.3),
            ),
          );
        cloudPath = Path.combine(PathOperation.union, cloudPath, basePad);

        final Rect bounds = cloudPath.getBounds();

        canvas.drawPath(
          cloudPath.shift(const Offset(0.12, 0.16)),
          shadowPaint,
        );

        bubblePaint.shader = LinearGradient(
          colors: [shadowColor, baseColor, highlightColor],
          stops: const [0.0, 0.58, 1.0],
          begin: Alignment.bottomCenter,
          end: Alignment.topLeft,
        ).createShader(bounds);
        canvas.drawPath(cloudPath, bubblePaint);

        final Path highlightPath = Path.combine(
          PathOperation.intersect,
          cloudPath,
          Path()
            ..addOval(
              Rect.fromCenter(
                center: bounds.center +
                    Offset(
                      -bounds.width * 0.08,
                      -bounds.height * (0.24 + stageEased * 0.12),
                    ),
                width: bounds.width * 0.82,
                height: bounds.height * (0.66 + stageEased * 0.08),
              ),
            ),
        );
        canvas.drawPath(highlightPath, highlightPaint);

        final Paint rimPaint = Paint()
          ..color = highlightColor.withValues(alpha: 0.12 + stageEased * 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, clusterRadius * 0.12);
        canvas.drawPath(
          cloudPath.shift(Offset(0, -clusterRadius * 0.04)),
          rimPaint,
        );

        canvas.restore();
      }

      if (stageBranch > 0 && stageBranch < 0.28) {
        final double cotyledonStage = (stageBranch / 0.28).clamp(0.0, 1.0);
        final double cotyledonGrowth = math.pow(cotyledonStage, 0.82).toDouble();
        final Offset cotyledonAnchor =
            Offset(centerX, soilTop - stemHeight * (0.98 - 0.12 * cotyledonGrowth));
        final double cotyledonScale =
            ui.lerpDouble(0.32, 0.58, cotyledonGrowth) ?? 0.4;
        final double cotyledonSpread =
            ui.lerpDouble(42, 28, cotyledonGrowth) ?? 36;

        drawLeafCluster(
          origin: cotyledonAnchor + const Offset(-6, -2),
          directionDeg: -cotyledonSpread,
          scale: cotyledonScale,
          growth: cotyledonGrowth.clamp(0.0, 0.9),
          seedKey: 'cotyledon-left',
        );
        drawLeafCluster(
          origin: cotyledonAnchor + const Offset(6, -2),
          directionDeg: cotyledonSpread,
          scale: cotyledonScale,
          growth: cotyledonGrowth.clamp(0.0, 0.9),
          seedKey: 'cotyledon-right',
        );
      }

      // 树枝：递归生成向上分叉的枝干形态（与根系算法一致）
      final double branchBaseLength = ui.lerpDouble(22, 126, stageBranch) ?? 22;
      final double branchBaseThickness = ui.lerpDouble(3.6, 11.0, stageBranch) ?? 3.6;
      final double branchingFactor = stageBranch.clamp(0.0, 1.0);
      final double easedBranch = math.pow(stageBranch, 1.35).toDouble();
      final int branchDepth = math.max(1, 1 + (easedBranch * 4).floor());

      Color branchColor(int generation) {
        final double t = generation / (branchDepth + 1);
        return Color.lerp(const Color(0xFF704225), const Color(0xFF9B6B3A), t)!
            .withValues(alpha: 0.95 - t * 0.25);
      }

      void drawTreeBranch(
        Offset start,
        double length,
        double angleDeg,
        double thickness,
        int depth,
        String key,
      ) {
        if (depth <= 0 || thickness < 0.6) return;
        final double angle = angleDeg * math.pi / 180;
        final double bend = noise('branch-bend-$key-$depth') * (5 + easedBranch * 6);
        final double controlAngle = (angleDeg + bend * 0.35) * math.pi / 180;
        final Offset control = start + Offset(
          math.cos(controlAngle) * length * 0.46,
          math.sin(controlAngle) * length * 0.46,
        );
        final Offset end = start + Offset(
          math.cos(angle) * length,
          math.sin(angle) * length,
        );

        final Path branchPath = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

        final int generation = branchDepth - depth;

        canvas.drawPath(
          branchPath,
          Paint()
            ..color = branchColor(generation)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = thickness,
        );

        final double generationRatio = (generation + 1) / (branchDepth + 1);
        final double foliageStrength =
            (stageFoliage * (0.6 + generationRatio * 0.6) + 0.12).clamp(0.12, 1.0);
        final double tipScale = ui.lerpDouble(0.34, 0.96, foliageStrength) ?? 0.52;
        drawLeafCluster(
          origin: end,
          directionDeg: angleDeg + noise('branch-tip-$key-$depth') * 5,
          scale: tipScale,
          growth: foliageStrength,
          seedKey: '$key-tip-$depth',
        );

        if (foliageStrength > 0.24 && depth > 1) {
          final double budT = ui.lerpDouble(0.26, 0.48, generationRatio)!;
          final double invT = 1 - budT;
          final Offset budPoint = Offset(
            invT * invT * start.dx + 2 * invT * budT * control.dx + budT * budT * end.dx,
            invT * invT * start.dy + 2 * invT * budT * control.dy + budT * budT * end.dy,
          );
          final double budScale =
              (tipScale * (0.72 + noise('branch-bud-$key-$depth') * 0.12)).clamp(0.22, 0.82);
          drawLeafCluster(
            origin: budPoint,
            directionDeg: angleDeg + noise('branch-bud-ang-$key-$depth') * 6,
            scale: budScale,
            growth: (foliageStrength * 0.8).clamp(0.24, 1.0),
            seedKey: '$key-bud-$depth',
          );
        }

        final double nextLength =
            length * (0.72 + 0.16 * easedBranch) *
                (0.96 + noise('branch-len-$key-$depth') * 0.08);
        final double nextThickness =
            math.max(0.6, thickness * (0.64 + 0.18 * easedBranch));
        final double spread =
            14 + easedBranch * 10 + noise('branch-spread-$key-$depth') * 8;

        drawTreeBranch(
          end,
          nextLength,
          angleDeg + spread,
          nextThickness,
          depth - 1,
          '${key}L',
        );
        drawTreeBranch(
          end,
          nextLength,
          angleDeg - spread,
          nextThickness,
          depth - 1,
          '${key}R',
        );

        if (depth > 2) {
          final double extra = 0.48 + 0.16 * easedBranch;
          drawTreeBranch(
            end,
            nextLength * extra,
            angleDeg + noise('branch-mid-$key-$depth') * 14,
            nextThickness * 0.84,
            depth - 2,
            '${key}M',
          );
        }
      }

      final Offset trunkTop = Offset(centerX, soilTop - stemHeight);
      drawTreeBranch(
        trunkTop,
        branchBaseLength,
        -90,
        branchBaseThickness * 0.84,
        branchDepth,
        'main',
      );
      if (branchingFactor > 0.2) {
        final int upperDepth = math.max(1, branchDepth - 1);
        final int midDepth = math.max(1, branchDepth - 2);
        final int lowDepth = math.max(1, branchDepth - 3);

        drawTreeBranch(
          trunkTop + Offset(0, -stemHeight * 0.08),
          branchBaseLength * 0.9,
          -78,
          branchBaseThickness * 0.78,
          upperDepth,
          'upperL',
        );
        drawTreeBranch(
          trunkTop + Offset(0, -stemHeight * 0.08),
          branchBaseLength * 0.9,
          -102,
          branchBaseThickness * 0.78,
          upperDepth,
          'upperR',
        );
        final double midOffset = ui.lerpDouble(0.58, 0.42, branchingFactor) ?? 0.5;
        final double lowOffset = ui.lerpDouble(0.36, 0.26, branchingFactor) ?? 0.32;
        final double midLengthFactor = ui.lerpDouble(0.6, 0.82, branchingFactor) ?? 0.7;
        final double lowLengthFactor = ui.lerpDouble(0.42, 0.7, branchingFactor) ?? 0.6;
        final double midThicknessFactor = ui.lerpDouble(0.48, 0.72, branchingFactor) ?? 0.6;
        final double lowThicknessFactor = ui.lerpDouble(0.38, 0.66, branchingFactor) ?? 0.55;
        final double midLength = branchBaseLength * midLengthFactor;
        final double lowLength = branchBaseLength * lowLengthFactor;
        final double midThickness = branchBaseThickness * midThicknessFactor;
        final double lowThickness = branchBaseThickness * lowThicknessFactor;

        drawTreeBranch(
          Offset(centerX, soilTop - stemHeight * midOffset),
          midLength,
          -72,
          midThickness,
          midDepth,
          'midL',
        );
        drawTreeBranch(
          Offset(centerX, soilTop - stemHeight * midOffset),
          midLength,
          -108,
          midThickness,
          midDepth,
          'midR',
        );
        drawTreeBranch(
          Offset(centerX, soilTop - stemHeight * lowOffset),
          lowLength,
          -65,
          lowThickness,
          lowDepth,
          'lowL',
        );
        drawTreeBranch(
          Offset(centerX, soilTop - stemHeight * lowOffset),
          lowLength,
          -115,
          lowThickness,
          lowDepth,
          'lowR',
        );
      }
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


