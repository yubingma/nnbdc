import 'dart:async';
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

const double _baseMetersPerGrowthDay = 0.1; // 基础生长速度：每天生长0.1米
const double _growthPlaybackMultiplier = 1000000.0; // 生长播放快进倍数（调试用，影响时间流逝）
const double _seedInitialDepthMeters = 0.18; // 种子初始埋深（米），控制破土时间
const double _seedRadiusMeters = 0.036; // 种子平均半径（米）
const double _seedGrowthMetersPerDay = 0.32; // 种子破土阶段的日生长速度（米/天）
const double _branchFullMaturityDays = 180.0; // 树枝达到完全成熟所需天数
const double _foliageFullMaturityDays = 220.0; // 树冠达到完全茂密所需天数
const double _worldScaleMetersPerScreen = 10.0; // 当前屏幕宽度代表的米数
const double _targetWorldWidthMeters = 1000.0; // 世界总宽度（米）
const double _soilThicknessMeters = 5.0; // 土壤层厚度（米）
const Duration _growthTickInterval = Duration(seconds: 1);

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

class _PlantGrowthSceneState extends State<PlantGrowthScene> {
  
  Timer? _growthTimer;
  bool _seedPlanted = false;
  late final int _branchSeed;
  static const int _totalDays = 3000;
  static const int _maxDayInput = 3650;
  late final TextEditingController _dayController;
  int _stopDay = _totalDays;
  double _displayProgress = 0.0;
  double _elapsedDays = 0.0;
  DateTime? _lastGrowthUpdateTime;
  String? _inputError;
  late final TransformationController _viewController;
  Matrix4 _baseViewMatrix = Matrix4.identity();
  Size? _lastViewportSize;
  bool _viewMatrixInitialized = false;
  bool _userInteractingWithView = false;
  bool _isAdjustingViewMatrix = false;
  DateTime? _lastUserInteractionTime;
  double _currentViewportHeight = 0;
  double _currentViewportWidth = 0;
  double _currentWorldHeight = 0;
  double _currentWorldWidth = 0;

  void _ensureGrowthTimer() {
    _growthTimer ??= Timer.periodic(
      _growthTickInterval,
      (_) => _handleTick(),
    );
  }

  @override
  void initState() {
    super.initState();
    _branchSeed = _computeBranchSeed();
    _dayController = TextEditingController(text: '$_stopDay');
    _ensureGrowthTimer();
    _lastGrowthUpdateTime = DateTime.now();
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
    if (_stopDay > 0 && _elapsedDays >= _stopDay) {
      _elapsedDays = _stopDay.toDouble();
      _lastGrowthUpdateTime = DateTime.now();
      return;
    }

    final DateTime now = DateTime.now();
    _lastGrowthUpdateTime ??= now;
    final Duration interval = now.difference(_lastGrowthUpdateTime!);
    _lastGrowthUpdateTime = now;

    final double deltaSeconds = interval.inMicroseconds / 1e6;
    if (deltaSeconds <= 0) {
      return;
    }

    final double deltaDays =
        (deltaSeconds / Duration.secondsPerDay) * _growthPlaybackMultiplier;
    if (deltaDays <= 0) {
      return;
    }
    _elapsedDays += deltaDays;

    const double characteristicDays = 45.0;
    if (_stopDay > 0 && _elapsedDays >= _stopDay) {
      _elapsedDays = _stopDay.toDouble();
    }

    final double newProgress =
        (_elapsedDays / characteristicDays).clamp(0.0, 1.0);

    setState(() {
      _displayProgress = newProgress.clamp(0.0, 1.0);
    });
    
    // 自动缩放以保持树木完整可见
    _autoAdjustZoomForTree();
  }
  
  void _autoAdjustZoomForTree() {
    // 只在用户没有手动交互时自动调整
    if (_userInteractingWithView || !_viewMatrixInitialized) {
      return;
    }
    
    // 如果用户最近交互过（3秒内），不自动调整
    if (_lastUserInteractionTime != null) {
      final Duration timeSinceInteraction = DateTime.now().difference(_lastUserInteractionTime!);
      if (timeSinceInteraction.inSeconds < 3) {
        return;
      }
    }
    
    // 计算当前树木高度（米）
    final double treeHeightMeters = _estimateTreeHeightMeters(_displayProgress);
    if (treeHeightMeters <= 0) return;
    
    // 获取当前视口尺寸
    if (_currentViewportHeight <= 0 || _currentWorldHeight <= 0) {
      return;
    }
    
    // 计算树木在世界中的像素高度
    final double pixelsPerMeter = (_currentWorldWidth > 0) 
        ? _currentWorldWidth / _targetWorldWidthMeters 
        : 1.0;
    final double treeHeightPx = treeHeightMeters * pixelsPerMeter;
    
    // 土壤层高度（固定5米）
    final double soilHeightPx = _soilThicknessMeters * pixelsPerMeter;
    
    // 计算总需要显示的高度：
    // 底部：土壤层（始终贴着屏幕底部）
    // 中部：树高 + 树冠空间（树高的0.5倍，包含枝叶）
    // 顶部：至少 1/4 屏幕高度的空白空间
    final double treeWithCrownHeight = treeHeightPx * 1.5;
    final double requiredTopSpace = _currentViewportHeight * 0.25; // 至少1/4屏幕高度
    final double totalRequiredHeight = soilHeightPx + treeWithCrownHeight + requiredTopSpace;
    
    // 计算需要的最小缩放比例
    double requiredScale = 1.0;
    if (totalRequiredHeight > 0) {
      requiredScale = _currentViewportHeight / totalRequiredHeight;
    }
    
    // 限制树木（不含顶部额外留白）在屏幕中的占比不超过 60%
    final double maxTreeScreenHeight = _currentViewportHeight * 0.6;
    if (treeHeightPx > 0) {
      final double scaleForTreeRatio = maxTreeScreenHeight / treeHeightPx;
      requiredScale = math.min(requiredScale, scaleForTreeRatio);
    }
    
    // 只在需要缩小时才自动调整（不自动放大）
    final Matrix4 currentMatrix = _viewController.value;
    final double currentScale = currentMatrix.getMaxScaleOnAxis();
    
    if (requiredScale < currentScale && requiredScale >= 0.001) {
      // 平滑过渡到新的缩放比例
      final double newScale = math.max(requiredScale, 0.001);
      
      // 创建新的变换矩阵
      final Matrix4 newMatrix = Matrix4.identity();
      
      // 保持世界水平居中
      final double translateX = _currentViewportWidth / 2 - newScale * _currentWorldWidth / 2;
      // 保持底部对齐
      final double translateY = _currentViewportHeight - newScale * _currentWorldHeight;
      
      newMatrix.translate(translateX, translateY);
      newMatrix.scale(newScale);
      
      // 应用新的变换
      _applyViewMatrix(newMatrix);
    }
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
      _lastGrowthUpdateTime = DateTime.now();
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
        _lastGrowthUpdateTime = DateTime.now();
      });
    } else {
      setState(() {
        _seedPlanted = true;
        _displayProgress = 0.0;
        _elapsedDays = 0.0;
        _lastGrowthUpdateTime = DateTime.now();
      });
    }

    _ensureGrowthTimer();
  }

  double _estimateTreeHeightMeters(double progress) {
    final double emergenceThreshold = _treeStageStops[2];
    if (progress < emergenceThreshold) {
      return 0.0;
    }
    // 树木持续生长，不再有高度限制
    // 使用经过的天数计算实际高度，保持线性生长速度
    final double daysGrown = _elapsedDays;
    if (daysGrown <= 0) return 0.0;
    
    // 线性增长模型：保持每天固定的生长米数
    const double offset = 0.5; // 初期微小高度，避免破土瞬间为0
    return offset + _baseMetersPerGrowthDay * daysGrown;
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
    _growthTimer?.cancel();
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
                _currentViewportWidth = viewportSize.width;
                _currentWorldHeight = worldHeight;
                _currentWorldWidth = worldWidth;

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
                          _lastUserInteractionTime = DateTime.now();
                        },
                        onInteractionEnd: (_) {
                          _userInteractingWithView = false;
                          _lastUserInteractionTime = DateTime.now();
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
                              treeHeightMeters: _estimateTreeHeightMeters(progress),
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
  final double treeHeightMeters; // 树木高度（米）
  // 整个动画按阶段划分，使用分段时间控制各部位的生长

  _TreeGrowthPainter({
    required this.progress,
    required this.isDarkMode,
    required this.accentColor,
    required this.seedPlanted,
    required this.branchSeed,
    required this.treeHeightMeters,
  });

  // 绘制云朵
  void drawCloud(Canvas canvas, Offset center, double scale, double seed) {
    final Paint cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    
    final Paint cloudShadow = Paint()
      ..color = const Color(0xFFD0D0D0).withValues(alpha: 0.3);
    
    // 使用随机种子创建更自然的棉花状云朵
    final math.Random cloudRand = math.Random((seed * 10000).toInt());
    
    // 云朵由更多小椭圆组成，形成蓬松的棉花效果
    final List<Map<String, double>> bubbles = [];
    
    // 中心大团
    bubbles.add({'x': 0, 'y': 0, 'w': 30 * scale, 'h': 20 * scale});
    
    // 周围添加8-12个小棉花团，形成不规则的蓬松外形
    final int smallBubbles = 8 + cloudRand.nextInt(5);
    for (int i = 0; i < smallBubbles; i++) {
      final double angle = (i / smallBubbles) * 2 * math.pi + cloudRand.nextDouble() * 0.5;
      final double distance = (15 + cloudRand.nextDouble() * 12) * scale;
      final double bubbleSize = (12 + cloudRand.nextDouble() * 12) * scale;
      
      bubbles.add({
        'x': math.cos(angle) * distance,
        'y': math.sin(angle) * distance * 0.6, // Y轴压缩，更像云
        'w': bubbleSize,
        'h': bubbleSize * (0.7 + cloudRand.nextDouble() * 0.3),
      });
    }
    
    // 绘制轻微阴影
    for (final bubble in bubbles) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            center.dx + bubble['x']! + 1,
            center.dy + bubble['y']! + 1.5,
          ),
          width: bubble['w']!,
          height: bubble['h']!,
        ),
        cloudShadow,
      );
    }
    
    // 绘制云朵本体
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
    double toPixels(double meters) => meters * pixelsPerMeter;
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

    // 使用已定义的pixelsPerMeter，计算视口尺寸（用于树木等对象的合理比例）
    final double viewportWidthMeters = _worldScaleMetersPerScreen; // 视口宽度对应10米
    final double viewportWidthPx = viewportWidthMeters * pixelsPerMeter;
    final double viewportHeightMeters = viewportWidthMeters * (size.height / size.width);
    final double viewportHeightPx = viewportHeightMeters * pixelsPerMeter;
    
    final double horizonY = soilTop - viewportHeightPx * 0.35;
    
    // 用户小天地在世界中央
    final double centerX = size.width * 0.5;
    
    // 绘制云朵和太阳（都在世界空间中，会随滚动变化）
    if (!isDarkMode) {
      final math.Random cloudRandom = math.Random(branchSeed ^ 0x1c7);
      
      // 太阳（在用户小天地上方偏右，完全露出不被山峰遮挡）
      final double mountainHeight = viewportHeightPx * 0.32; // 山峰约高度
      final double sunX = centerX + viewportWidthPx * 0.3; // 用户小天地中心偏右
      final double sunRadius = 75.0; // 直径150像素，半径75
      // 太阳位置：山峰顶部上方非常高的位置，确保不被云朵遮挡
      final double sunY = horizonY - mountainHeight - viewportHeightPx * 0.65; // 山峰上方很高
      
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
      
      // 云朵（主要集中在山峰上方，像棉花一样）
      final int cloudCount = 30; // 增加数量，但缩小单个云朵
      
      // 山峰上方区域（重点分布区域）
      final double mountainTopY = horizonY - mountainHeight;
      
      for (int i = 0; i < cloudCount; i++) {
        // 云朵在世界空间中均匀分布
        final double cloudX = (i / cloudCount) * size.width + cloudRandom.nextDouble() * 400 - 200;
        
        // 云朵集中在山峰上方附近，但不要太高（避免遮挡太阳）
        // 从山峰顶部开始，向上延伸0.45个视口高度（太阳在0.65处）
        final double cloudY = mountainTopY - (cloudRandom.nextDouble() * viewportHeightPx * 0.45);
        
        final double cloudScale = (0.5 + cloudRandom.nextDouble() * 0.6) * 4; // 进一步缩小到4倍
        
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
    final double stageRoot = _rootProgressFor(progress);
    double stageBranch = 0.0;
    double stageFoliage = 0.0;

    // 种子：播种瞬间埋入土壤，不再做缓慢下沉动画
    final double sproutRatio = seedPlanted
        ? (emergenceThreshold > 0
            ? (progress / emergenceThreshold).clamp(0.0, 1.0)
            : progress.clamp(0.0, 1.0))
        : 0.0;

    final double seedLift = seedPlanted ? sproutRatio.clamp(0.0, 1.0) : 0.0;
    final double seedInitialDepthMeters = _seedInitialDepthMeters;
    final double maxRootPushMeters = math.min(
      seedInitialDepthMeters + _seedGrowthMetersPerDay * 0.6,
      seedInitialDepthMeters * 2.0,
    );
    final double rootPushMeters = seedPlanted
        ? ui.lerpDouble(
              0,
              maxRootPushMeters,
              math.pow(stageRoot, 1.18).toDouble(),
            ) ??
            0
        : 0.0;
    final double liftTargetMeters = math.min(
      seedInitialDepthMeters + _seedGrowthMetersPerDay * 0.35,
      maxRootPushMeters,
    );
    final double combinedLiftMeters = math.max(
      ui.lerpDouble(
            0,
            liftTargetMeters,
            seedLift,
          ) ??
          0,
      rootPushMeters,
    );
    final double sproutLengthMeters =
        sproutRatio * _seedGrowthMetersPerDay;
    final double sproutTipAboveSoilMeters = seedPlanted
        ? sproutLengthMeters + combinedLiftMeters - seedInitialDepthMeters
        : 0.0;
    final bool sproutAboveSoil =
        seedPlanted && sproutTipAboveSoilMeters >= 0;
    final bool hasBrokenGround =
        seedPlanted && (sproutAboveSoil || progress >= emergenceThreshold);
    final double emergenceOvershoot = hasBrokenGround
        ? ((progress - emergenceThreshold) / 0.12).clamp(0.0, 1.0)
        : 0.0;
    final double depthClamp = math.min(
      seedInitialDepthMeters,
      _seedGrowthMetersPerDay * 0.4,
    );
    final double seedDepthOffsetMeters =
        (seedInitialDepthMeters - combinedLiftMeters)
            .clamp(-depthClamp, seedInitialDepthMeters) -
        emergenceOvershoot * depthClamp;
    final double seedDepthOffsetPx = toPixels(seedDepthOffsetMeters);
    final Offset seedCenter = seedPlanted
        ? Offset(centerX, soilTop + seedDepthOffsetPx)
        : Offset(
            centerX,
            soilTop - toPixels(depthClamp),
          );
    final double seedRadiusMeters = seedPlanted
        ? ui.lerpDouble(
              _seedRadiusMeters,
              _seedRadiusMeters * 0.65,
              (seedLift * 1.2).clamp(0.0, 1.0),
            ) ??
            _seedRadiusMeters
        : _seedRadiusMeters * 1.2;
    final double seedRadiusPx = toPixels(seedRadiusMeters);
    canvas.drawCircle(
      seedCenter,
      seedRadiusPx,
      Paint()..color = const Color(0xFF9C6941),
    );
    if (seedPlanted) {
      final double shellAlpha = (1 - seedLift).clamp(0.0, 1.0);
      if (shellAlpha > 0) {
        final Paint shellPaint = Paint()
          ..color = const Color(0xFFB27A47).withValues(alpha: 0.38 * shellAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = toPixels(
            ui.lerpDouble(
                  _seedRadiusMeters * 0.42,
                  _seedRadiusMeters * 0.16,
                  seedLift,
                ) ??
                _seedRadiusMeters * 0.42,
          );
        canvas.drawCircle(
          seedCenter,
          seedRadiusPx +
              toPixels(
                _seedRadiusMeters * 0.72,
              ),
          shellPaint,
        );
      }
    }

    if (hasBrokenGround) {
      final double growthDays = math.max(
        0.0,
        (treeHeightMeters - 0.5) / _baseMetersPerGrowthDay,
      );

      stageBranch = (growthDays / _branchFullMaturityDays).clamp(0.0, 1.0);
      if (sproutAboveSoil && stageBranch < 0.15) {
        final double normalizedExposure =
            (sproutTipAboveSoilMeters / (_seedGrowthMetersPerDay * 0.6))
                .clamp(0.0, 1.0);
        final double exposureBoost = normalizedExposure * 0.15;
        if (exposureBoost > stageBranch) {
          stageBranch = exposureBoost;
        }
      }

      if (stageBranch > 0) {
        final double foliageByTime =
            (growthDays / _foliageFullMaturityDays).clamp(0.0, 1.0);
        final double foliageByBranch =
            math.pow(stageBranch, 0.9).toDouble();
        stageFoliage =
            foliageByTime >= foliageByBranch ? foliageByTime : foliageByBranch;
      }
    }

    final double sproutLengthPx = toPixels(sproutLengthMeters);
    final Offset sproutEnd = Offset(
      centerX,
      math.max(
        soilTop - toPixels(_seedRadiusMeters * 1.2),
        seedCenter.dy - sproutLengthPx,
      ),
    );
    final bool shouldDrawSprout =
        seedPlanted && sproutRatio > 0 && stageBranch < 0.35;

    if (shouldDrawSprout) {
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
        ..strokeWidth = toPixels(
          ui.lerpDouble(
                _seedRadiusMeters * 0.32,
                _seedRadiusMeters * 0.64,
                sproutRatio,
              ) ??
              _seedRadiusMeters * 0.32,
        )
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
          seedCenter + Offset(0, -seedRadiusPx * 0.3),
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
      // 树木持续生长，高度不再受限
      // 使用实际米数转换为像素，基于对数增长模型
      final double pixelsPerMeter = size.width / _targetWorldWidthMeters;
      final double stemHeight = math.max(14.0, treeHeightMeters * pixelsPerMeter);
      // 树干粗度随高度持续增长，但速度放缓
      final double baseWidth = 8 + math.log(treeHeightMeters + 1) * 6;
      final double topWidth = 1.6 + math.log(treeHeightMeters + 1) * 2.5;
      final double trunkBaseWidth = baseWidth.clamp(8.0, 80.0);
      final double trunkTopWidth = topWidth.clamp(1.6, 30.0);
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
        required double canopyHeightPx,
      }) {
        final double normalizedScale = scale.clamp(0.08, 1.0);
        final double stageEased = math.pow(growth.clamp(0.0, 1.0), 0.86).toDouble();
        final double desiredHeight =
            canopyHeightPx.clamp(8.0, size.height * 0.5);
        final double baseStretch = 1.4 + normalizedScale * 0.4;
        const double averageVerticalStretch = 1.42;
        final double targetRadius =
            desiredHeight / (baseStretch * averageVerticalStretch);
        final double clusterRadius = (ui.lerpDouble(
                  targetRadius * 0.55,
                  targetRadius,
                  normalizedScale,
                ) ??
                targetRadius)
            .clamp(6.0, desiredHeight);
        
        // 更丰富的颜色层次，从深绿到亮绿
        final Color deepGreen = Color.lerp(
          const Color(0xFF2D5016),
          const Color(0xFF37692A),
          stageEased * 0.4,
        )!;
        final Color baseColor = Color.lerp(
          const Color(0xFF5FA84B),
          const Color(0xFF6FB257),
          stageEased * 0.5 + 0.3,
        )!;
        final Color brightGreen = Color.lerp(
          const Color(0xFF8BC879),
          const Color(0xFFB1F08C),
          stageEased * 0.6,
        )!;
        final Color highlightColor = Color.lerp(
          const Color(0xFFCEF5B8),
          const Color(0xFFE8FFDA),
          stageEased * 0.4 + 0.3,
        )!;
        final Color shadowColor = Color.lerp(
          const Color(0xFF1E3B16),
          const Color(0xFF2A4A1D),
          normalizedScale * 0.3,
        )!;

        final Paint bubblePaint = Paint()..style = PaintingStyle.fill;
        final Paint highlightPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.08 + stageEased * 0.08);
        final Paint shadowPaint = Paint()
          ..color = shadowColor.withValues(alpha: 0.2 + stageEased * 0.18)
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, clusterRadius * 0.22);
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

        // 绘制叶柄
        canvas.drawLine(
          Offset(-clusterRadius * 0.12, 0),
          Offset(clusterRadius * 0.4, 0),
          stemPaint,
        );
        
        final double cloudWidth = clusterRadius * (2.2 + normalizedScale * 0.6);
        final double cloudHeight = clusterRadius * (1.4 + normalizedScale * 0.4);

        // 使用更多随机变化创建更自然的叶团
        Offset lobeCenter(String axis, double dx, double dy) {
          return Offset(
            dx * cloudWidth + noise('cloud-$axis-x-$seedKey') * clusterRadius * 0.18,
            dy * cloudHeight + noise('cloud-$axis-y-$seedKey') * clusterRadius * 0.15,
          );
        }

        // 增加叶团数量和变化，形成更蓬松的效果
        final List<Offset> centers = [
          lobeCenter('a', -0.42, -0.22),
          lobeCenter('b', -0.15, -0.52),
          lobeCenter('c', 0.28, -0.48),
          lobeCenter('d', 0.38, -0.12),
          lobeCenter('e', 0.22, 0.15),
          lobeCenter('f', -0.08, 0.12),
          lobeCenter('g', -0.28, 0.05),
        ];
        final List<double> radii = [
          clusterRadius * (1.05 + normalizedScale * 0.25 + noise('r-a-$seedKey') * 0.15),
          clusterRadius * (1.28 + normalizedScale * 0.22 + noise('r-b-$seedKey') * 0.12),
          clusterRadius * (1.12 + normalizedScale * 0.24 + noise('r-c-$seedKey') * 0.14),
          clusterRadius * (0.95 + normalizedScale * 0.2 + noise('r-d-$seedKey') * 0.12),
          clusterRadius * (0.88 + normalizedScale * 0.18 + noise('r-e-$seedKey') * 0.1),
          clusterRadius * (0.92 + normalizedScale * 0.19 + noise('r-f-$seedKey') * 0.11),
          clusterRadius * (0.82 + normalizedScale * 0.16 + noise('r-g-$seedKey') * 0.1),
        ];
        // 垂直拉伸，形成更自然的椭圆形叶团
        final List<double> verticalStretch = [
          1.35 + noise('v-a-$seedKey') * 0.15,
          1.50 + noise('v-b-$seedKey') * 0.12,
          1.42 + noise('v-c-$seedKey') * 0.14,
          1.38 + noise('v-d-$seedKey') * 0.13,
          1.45 + noise('v-e-$seedKey') * 0.11,
          1.40 + noise('v-f-$seedKey') * 0.12,
          1.36 + noise('v-g-$seedKey') * 0.10,
        ];

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

        // 底部基础垫，连接枝干
        final Path basePad = Path()
          ..addOval(
            Rect.fromCenter(
              center: Offset(
                noise('cloud-base-x-$seedKey') * clusterRadius * 0.1,
                clusterRadius * (0.35 + stageEased * 0.28),
              ),
              width: cloudWidth * 1.08,
              height: clusterRadius * (1.0 + stageEased * 0.35),
            ),
          );
        cloudPath = Path.combine(PathOperation.union, cloudPath, basePad);

        final Rect bounds = cloudPath.getBounds();

        // 绘制阴影，增加深度感
        canvas.drawPath(
          cloudPath.shift(Offset(clusterRadius * 0.03, clusterRadius * 0.05)),
          shadowPaint,
        );

        // 使用多色渐变创建更丰富的层次感
        bubblePaint.shader = LinearGradient(
          colors: [shadowColor, deepGreen, baseColor, brightGreen, highlightColor],
          stops: const [0.0, 0.25, 0.52, 0.78, 1.0],
          begin: Alignment.bottomCenter,
          end: Alignment.topLeft,
        ).createShader(bounds);
        canvas.drawPath(cloudPath, bubblePaint);

        // 绘制高光，模拟阳光照射
        final Path highlightPath = Path.combine(
          PathOperation.intersect,
          cloudPath,
          Path()
            ..addOval(
              Rect.fromCenter(
                center: bounds.center +
                    Offset(
                      -bounds.width * 0.12,
                      -bounds.height * (0.28 + stageEased * 0.15),
                    ),
                width: bounds.width * 0.75,
                height: bounds.height * (0.62 + stageEased * 0.1),
              ),
            ),
        );
        canvas.drawPath(highlightPath, highlightPaint);

        // 添加细微的边缘高光，增加立体感
        final Paint rimPaint = Paint()
          ..color = brightGreen.withValues(alpha: 0.15 + stageEased * 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.3, clusterRadius * 0.14);
        canvas.drawPath(
          cloudPath.shift(Offset(0, -clusterRadius * 0.05)),
          rimPaint,
        );
        
        // 添加一些细小的亮点，模拟叶片反光
        final Paint sparkPaint = Paint()
          ..color = highlightColor.withValues(alpha: 0.4 + stageEased * 0.2);
        for (int i = 0; i < 3; i++) {
          final double sparkX = noise('spark-x-$i-$seedKey') * bounds.width * 0.4;
          final double sparkY = noise('spark-y-$i-$seedKey') * bounds.height * 0.3 - bounds.height * 0.2;
          final double sparkSize = clusterRadius * (0.08 + noise('spark-s-$i-$seedKey') * 0.06);
          canvas.drawCircle(Offset(sparkX, sparkY), sparkSize, sparkPaint);
        }

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
      final double maxCanopyHeight = stemHeight * 0.32;
      final double cotyledonCanopyHeight =
          (stemHeight * 0.24 * cotyledonGrowth).clamp(
        math.min(12.0, maxCanopyHeight),
        math.max(12.0, maxCanopyHeight),
      );

        drawLeafCluster(
          origin: cotyledonAnchor + const Offset(-6, -2),
          directionDeg: -cotyledonSpread,
          scale: cotyledonScale,
          growth: cotyledonGrowth.clamp(0.0, 0.9),
          seedKey: 'cotyledon-left',
          canopyHeightPx: cotyledonCanopyHeight,
        );
        drawLeafCluster(
          origin: cotyledonAnchor + const Offset(6, -2),
          directionDeg: cotyledonSpread,
          scale: cotyledonScale,
          growth: cotyledonGrowth.clamp(0.0, 0.9),
          seedKey: 'cotyledon-right',
          canopyHeightPx: cotyledonCanopyHeight,
        );
      }

      // 树枝：递归生成向上分叉的枝干形态（与根系算法一致）
      // 树枝随树木高度持续生长
      final double branchBaseLength = 26 + math.log(treeHeightMeters + 1) * 35;
      final double branchBaseThickness = 4.2 + math.log(treeHeightMeters + 1) * 2.8;
      final double branchingFactor = stageBranch.clamp(0.0, 1.0);
      final double easedBranch = math.pow(stageBranch, 1.35).toDouble();
      // 增加分支深度，形成茂密的树冠
      final int branchDepth = math.max(1, 2 + (easedBranch * 4.5).floor());

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

        bool shouldCullBranch() {
          if (generation <= 0) {
            return false;
          }
          if (depth > 1) {
            return false;
          }
          final double maturity = stageBranch.clamp(0.0, 1.0);
          if (maturity <= 0.35) {
            return false;
          }
          final double exposure = (generation + 1) / (branchDepth + 1);
          final double baseChance = (maturity - 0.35) * 0.22;
          final double generationBonus = exposure * 0.25;
          final double deathChance = (baseChance + generationBonus).clamp(0.0, 0.42);
          final double randomValue =
              (noise('branch-death-$key-$depth') + 1.0) * 0.5; // 0-1
          return randomValue < deathChance;
        }

        if (shouldCullBranch()) {
          return;
        }

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
        final double canopyHeightForTip =
            math.max(10.0, length / 3 * (0.8 + generationRatio * 0.2));
        drawLeafCluster(
          origin: end,
          directionDeg: angleDeg + noise('branch-tip-$key-$depth') * 5,
          scale: tipScale,
          growth: foliageStrength,
          seedKey: '$key-tip-$depth',
          canopyHeightPx: canopyHeightForTip,
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
          final double budCanopyHeight =
              math.max(8.0, canopyHeightForTip * 0.7);
          drawLeafCluster(
            origin: budPoint,
            directionDeg: angleDeg + noise('branch-bud-ang-$key-$depth') * 6,
            scale: budScale,
            growth: (foliageStrength * 0.8).clamp(0.24, 1.0),
            seedKey: '$key-bud-$depth',
            canopyHeightPx: budCanopyHeight,
          );
        }

        // 自然的衰减参数，让树枝逐渐变细，树冠更茂密
        final double nextLength =
            length * (0.73 + 0.17 * easedBranch) *
                (0.96 + noise('branch-len-$key-$depth') * 0.08);
        final double nextThickness =
            math.max(0.6, thickness * (0.65 + 0.19 * easedBranch));
        final double spread =
            15 + easedBranch * 11 + noise('branch-spread-$key-$depth') * 9;

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

        final double sproutChanceBase = (stageBranch - 0.35).clamp(0.0, 0.65);
        if (depth > 1 && sproutChanceBase > 0) {
          final double sproutProbability = (sproutChanceBase *
                  (0.28 + generationRatio * 0.5) *
                  (0.6 + easedBranch * 0.4))
              .clamp(0.0, 0.85);
          final double sproutRoll =
              (noise('branch-sprout-$key-$depth') + 1.0) * 0.5;
          if (sproutRoll < sproutProbability) {
            final double sproutT =
                ((noise('branch-sprout-t-$key-$depth') + 1.0) * 0.5)
                    .clamp(0.18, 0.82);
            final double invT = 1 - sproutT;
            final Offset sproutOrigin = Offset(
              invT * invT * start.dx +
                  2 * invT * sproutT * control.dx +
                  sproutT * sproutT * end.dx,
              invT * invT * start.dy +
                  2 * invT * sproutT * control.dy +
                  sproutT * sproutT * end.dy,
            );

            final double sproutLengthFactor =
                (0.3 + stageBranch * 0.45) *
                (0.88 + noise('branch-sprout-len-$key-$depth') * 0.08);
            final double sproutThicknessFactor =
                (0.36 + stageBranch * 0.32) *
                (0.9 + noise('branch-sprout-thick-$key-$depth') * 0.05);
            final double sproutLength = nextLength * sproutLengthFactor;
            final double sproutThickness =
                math.max(0.6, nextThickness * sproutThicknessFactor);
            final double sproutAngle = angleDeg +
                noise('branch-sprout-ang-$key-$depth') *
                    (16 + 6 * (1 - generationRatio)) +
                (sproutRoll - sproutProbability * 0.5) * spread * 0.2;

            drawTreeBranch(
              sproutOrigin,
              sproutLength,
              sproutAngle,
              sproutThickness,
              depth - 1,
              '${key}S',
            );
          }
        }
      }

      final Offset trunkTop = Offset(centerX, soilTop - stemHeight);
      // 主干顶部的中央枝
      drawTreeBranch(
        trunkTop,
        branchBaseLength,
        -90,
        branchBaseThickness * 0.85,
        branchDepth,
        'main',
      );
      if (branchingFactor > 0.18) {
        final int baseLateralLevels = 3;
        final int heightDrivenLevels =
            math.max(0, (treeHeightMeters / 2.2).floor());
        final int lateralLevels =
            (baseLateralLevels + heightDrivenLevels).clamp(3, 14);

        for (int i = 0; i < lateralLevels; i++) {
          final double levelT = (i + 1) / (lateralLevels + 1);
          final double anchorFactor =
              (ui.lerpDouble(0.22, 0.92, levelT) ?? 0.5).clamp(0.18, 0.94);
          final Offset anchor =
              Offset(centerX, soilTop - stemHeight * anchorFactor);

          final double strengthNoise = noise('lvl-strength-$i') * 0.08;
          final double levelStrength =
              (branchingFactor * (0.52 + levelT * 0.68) + strengthNoise)
                  .clamp(0.2, 1.0);

          final double lengthFactor =
              (ui.lerpDouble(0.42, 0.9, levelStrength) ?? 0.66) *
                  (0.9 + noise('lvl-len-$i') * 0.08);
          final double thicknessFactor =
              (ui.lerpDouble(0.32, 0.78, levelStrength) ?? 0.54) *
                  (0.92 + noise('lvl-thick-$i') * 0.06);

          final double levelLength = branchBaseLength * lengthFactor;
          final double levelThickness =
              branchBaseThickness * thicknessFactor;

          final int levelDepth =
              math.max(1, branchDepth - (i ~/ 2) - 1);
          final double baseAngle =
              ui.lerpDouble(84, 72, levelStrength) ?? 78;
          final double spreadAngle =
              (ui.lerpDouble(18, 32, levelStrength) ?? 22) *
                  (0.9 + noise('lvl-spread-$i') * 0.05);
          final double upwardBias =
              ui.lerpDouble(6, 14, levelStrength) ?? 10;

          drawTreeBranch(
            anchor,
            levelLength,
            -(baseAngle - spreadAngle + upwardBias) +
                noise('lvl-angL-$i') * 4,
            levelThickness,
            levelDepth,
            'lvlL-$i',
          );
          drawTreeBranch(
            anchor,
            levelLength,
            -(baseAngle + spreadAngle + upwardBias) -
                noise('lvl-angR-$i') * 4,
            levelThickness,
            levelDepth,
            'lvlR-$i',
          );
        }
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


