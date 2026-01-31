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

// 新增自然生长参数
const double _growthCurveExponent = 0.7; // 生长曲线指数，使生长更自然
const double _seasonalGrowthFactor = 0.2; // 季节性生长因子，使生长有波动

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
    _viewController = TransformationController(Matrix4.identity());
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

    // 添加安全检查，防止极端值导致矩阵错误
    final double safeTranslateX = (viewportWidth.isFinite && worldWidth.isFinite) ? viewportWidth / 2 - worldWidth / 2 : 0.0;
    final double safeTranslateY = (viewportHeight.isFinite && worldHeight.isFinite) ? viewportHeight - worldHeight : 0.0;

    matrix.translateByDouble(
      safeTranslateX,
      safeTranslateY,
      0.0,
      0.0,
    );
    return matrix;
  }

  bool _matricesTranslationClose(Matrix4 a, Matrix4 b, [double tolerance = 0.5]) {
    final Float64List aStorage = a.storage;
    final Float64List bStorage = b.storage;
    return (aStorage[12] - bStorage[12]).abs() <= tolerance && (aStorage[13] - bStorage[13]).abs() <= tolerance;
  }

  void _applyViewMatrix(Matrix4 matrix) {
    _isAdjustingViewMatrix = true;
    try {
      // 检查矩阵是否有效且可逆，避免 InteractiveViewer 崩溃
      final double determinant = matrix.determinant();
      final bool isValuesFinite = matrix.storage.every((v) => v.isFinite);

      if (isValuesFinite && determinant.abs() > 1e-10) {
        _viewController.value = Matrix4.copy(matrix);
      } else {
        // 如果矩阵无效，不进行更新，或者在必要时恢复到基础矩阵
        Global.logger.w('尝试应用无效或不可逆的矩阵: determinant=$determinant, finite=$isValuesFinite');
        // 如果当前值已经是无效的，恢复到单位矩阵
        if (!_viewController.value.storage.every((v) => v.isFinite) || _viewController.value.determinant().abs() <= 1e-10) {
          _viewController.value = Matrix4.identity();
        }
      }
    } catch (e) {
      Global.logger.e('应用矩阵时出错: $e');
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
    final double determinant = value.determinant();

    // 添加安全检查，防止无效的矩阵进入后续计算甚至崩溃
    if (!determinant.isFinite || determinant.abs() < 1e-10) {
      return; // 如果矩阵不可逆，直接返回，避免 InteractionViewer 调用 toScene 时崩溃
    }

    final double scaleY = value.getMaxScaleOnAxis();

    // 确保数值都是有限的，避免矩阵错误
    if (!_currentViewportHeight.isFinite || !_currentWorldHeight.isFinite || !scaleY.isFinite) {
      return;
    }

    final double desiredTy = _currentViewportHeight - scaleY * _currentWorldHeight;
    final double currentTy = value.storage[13];

    if (!desiredTy.isFinite) return;

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

    final double deltaDays = (deltaSeconds / Duration.secondsPerDay) * _growthPlaybackMultiplier;
    if (deltaDays <= 0) {
      return;
    }
    _elapsedDays += deltaDays;

    // 使用更自然的生长曲线，带有季节性波动
    const double characteristicDays = 45.0;
    double baseProgress = (_elapsedDays / characteristicDays).clamp(0.0, 1.0);

    // 添加季节性波动
    double seasonalVariation = math.sin(_elapsedDays * 0.1) * _seasonalGrowthFactor;
    double adjustedProgress = (baseProgress + seasonalVariation).clamp(0.0, 1.0);

    // 使用幂函数创建非线性生长曲线（初期快，后期慢）
    final double newProgress = math.pow(adjustedProgress, _growthCurveExponent).toDouble();

    if (_stopDay > 0 && _elapsedDays >= _stopDay) {
      _elapsedDays = _stopDay.toDouble();
    }

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
    final double pixelsPerMeter = (_currentWorldWidth > 0) ? _currentWorldWidth / _targetWorldWidthMeters : 1.0;
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

      // 保持世界水平居中，添加安全检查
      final double safeNewScale = newScale.isFinite ? newScale : 1.0;
      final double translateX =
          _currentViewportWidth.isFinite && _currentWorldWidth.isFinite ? _currentViewportWidth / 2 - safeNewScale * _currentWorldWidth / 2 : 0.0;
      // 保持底部对齐，添加安全检查
      final double translateY =
          _currentViewportHeight.isFinite && _currentWorldHeight.isFinite ? _currentViewportHeight - safeNewScale * _currentWorldHeight : 0.0;

      newMatrix.translateByDouble(translateX, translateY, 0.0, 0.0);
      newMatrix.scaleByDouble(safeNewScale, safeNewScale, safeNewScale, 1.0);

      // 应用新的变换，使用安全的矩阵应用方法
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
                final double worldWidth = constraints.maxWidth * (_targetWorldWidthMeters / _worldScaleMetersPerScreen);
                final double aspectRatio = constraints.maxWidth == 0 ? 1.0 : constraints.maxHeight / constraints.maxWidth;
                final double worldHeight = worldWidth * aspectRatio;
                final double boundaryExtent = math.max(worldWidth, worldHeight) * 0.25;
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

                  // 安全地设置基础视图矩阵
                  try {
                    _baseViewMatrix = Matrix4.copy(desiredBaseMatrix);
                    _applyViewMatrix(_baseViewMatrix);
                  } catch (e) {
                    // 如果出现矩阵错误，使用单位矩阵作为安全默认值
                    _baseViewMatrix = Matrix4.identity();
                    _applyViewMatrix(_baseViewMatrix);
                  }
                } else if (!_userInteractingWithView && !_matricesTranslationClose(_baseViewMatrix, desiredBaseMatrix)) {
                  _lastViewportSize = viewportSize;

                  // 安全地更新基础视图矩阵
                  try {
                    _baseViewMatrix = Matrix4.copy(desiredBaseMatrix);
                    _applyViewMatrix(_baseViewMatrix);
                  } catch (e) {
                    // 如果出现矩阵错误，使用单位矩阵作为安全默认值
                    _baseViewMatrix = Matrix4.identity();
                    _applyViewMatrix(_baseViewMatrix);
                  }
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
                              elapsedDays: _elapsedDays,
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
                          color: Colors.black.withValues(alpha: isDarkMode ? 0.48 : 0.32),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.28),
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
    this.elapsedDays = 0.0, // 添加时间参数
  });

  final double elapsedDays; // 添加已用天数参数

  // 绘制云朵
  void drawCloud(Canvas canvas, Offset center, double scale, double seed) {
    final Paint cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final Paint cloudShadow = Paint()..color = const Color(0xFFD0D0D0).withValues(alpha: 0.3);

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
    final double pixelsPerMeter = _targetWorldWidthMeters == 0 ? 0 : size.width / _targetWorldWidthMeters;
    double toPixels(double meters) => meters * pixelsPerMeter;
    final double soilThicknessPx = pixelsPerMeter > 0 ? math.min(size.height * 0.9, _soilThicknessMeters * pixelsPerMeter) : size.height * 0.35;
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
            control1X,
            control1Y,
            control2X,
            control2Y,
            x,
            peak,
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
        return y1 * math.pow(1 - t1, 3) + cy1 * 3 * math.pow(1 - t1, 2) * t1 + cy2 * 3 * (1 - t1) * math.pow(t1, 2) + y2 * math.pow(t1, 3);
      } else {
        // 第二段曲线
        final double t2 = (x - size.width * 0.52) / (size.width - size.width * 0.52);
        final double y1 = riverTop - 10;
        final double y2 = riverTop + 14;
        final double cy1 = riverTop + 24;
        final double cy2 = riverTop - 6;
        return y1 * math.pow(1 - t2, 3) + cy1 * 3 * math.pow(1 - t2, 2) * t2 + cy2 * 3 * (1 - t2) * math.pow(t2, 2) + y2 * math.pow(t2, 3);
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
        ..color = (isDarkMode ? const Color(0xFF3A2F1A) : const Color(0xFF5A4A2A)).withValues(alpha: 0.7 + depth * 0.2);

      // 树冠 - 深绿色，对比强烈
      final Paint distantCrownPaint = Paint()
        ..color = (isDarkMode ? const Color(0xFF2F4F2F) : const Color(0xFF3A7A3A)).withValues(alpha: 0.75 + depth * 0.2);

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

    final Paint shrubPaint = Paint()..color = const Color(0xFF4A7B37).withValues(alpha: 0.82);
    final Paint shrubShadow = Paint()..color = const Color(0xFF2E4F27).withValues(alpha: 0.6);
    final int shrubCount = (size.width / 90).ceil();
    for (int i = 0; i < shrubCount; i++) {
      final double t = (i + 0.5) / shrubCount;
      final double baseX = soilRect.left + soilRect.width * t + math.sin(i * 1.6) * 32;
      final double baseY = soilRect.top + soilRect.height * 0.05 + math.sin(i * 0.9) * 12;
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
    final double sproutRatio =
        seedPlanted ? (emergenceThreshold > 0 ? (progress / emergenceThreshold).clamp(0.0, 1.0) : progress.clamp(0.0, 1.0)) : 0.0;

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
    final double sproutLengthMeters = sproutRatio * _seedGrowthMetersPerDay;
    final double sproutTipAboveSoilMeters = seedPlanted ? sproutLengthMeters + combinedLiftMeters - seedInitialDepthMeters : 0.0;
    final bool sproutAboveSoil = seedPlanted && sproutTipAboveSoilMeters >= 0;
    final bool hasBrokenGround = seedPlanted && (sproutAboveSoil || progress >= emergenceThreshold);
    final double emergenceOvershoot = hasBrokenGround ? ((progress - emergenceThreshold) / 0.12).clamp(0.0, 1.0) : 0.0;
    final double depthClamp = math.min(
      seedInitialDepthMeters,
      _seedGrowthMetersPerDay * 0.4,
    );
    final double seedDepthOffsetMeters =
        (seedInitialDepthMeters - combinedLiftMeters).clamp(-depthClamp, seedInitialDepthMeters) - emergenceOvershoot * depthClamp;
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
        final double normalizedExposure = (sproutTipAboveSoilMeters / (_seedGrowthMetersPerDay * 0.6)).clamp(0.0, 1.0);
        final double exposureBoost = normalizedExposure * 0.15;
        if (exposureBoost > stageBranch) {
          stageBranch = exposureBoost;
        }
      }

      if (stageBranch > 0) {
        final double foliageByTime = (growthDays / _foliageFullMaturityDays).clamp(0.0, 1.0);
        final double foliageByBranch = math.pow(stageBranch, 0.9).toDouble();
        stageFoliage = foliageByTime >= foliageByBranch ? foliageByTime : foliageByBranch;
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
    final bool shouldDrawSprout = seedPlanted && sproutRatio > 0 && stageBranch < 0.35;

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

        double fastNoise(int hash) {
          return ((hash & 0x7fffffff) / 0x7fffffff) * 2 - 1;
        }

        int mix(int hash, int val) {
          return (hash * 31 + val) & 0x7fffffff;
        }

        void drawRootBranch(
          Offset start,
          double length,
          double angleDeg,
          double thickness,
          int depth,
          int seed,
        ) {
          if (depth <= 0 || thickness < 0.6) {
            return;
          }
          final double angle = angleDeg * math.pi / 180;
          final double bend = fastNoise(mix(seed, depth * 10 + 1)) * (5 + easedRoot * 6);
          final double controlAngle = (angleDeg + bend * 0.35) * math.pi / 180;
          final Offset control = start +
              Offset(
                math.cos(controlAngle) * length * 0.46,
                math.sin(controlAngle) * length * 0.46,
              );
          final Offset end = start +
              Offset(
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

          final double nextLength = length * (0.72 + 0.16 * easedRoot) * (0.96 + fastNoise(mix(seed, depth * 10 + 2)) * 0.08);
          final double nextThickness = math.max(0.6, thickness * (0.64 + 0.18 * easedRoot));
          final double spread = 14 + easedRoot * 10 + fastNoise(mix(seed, depth * 10 + 3)) * 8;

          drawRootBranch(end, nextLength, angleDeg + spread, nextThickness, depth - 1, mix(seed, 1));
          drawRootBranch(end, nextLength, angleDeg - spread, nextThickness, depth - 1, mix(seed, 2));

          if (depth > 2) {
            final double extra = 0.48 + 0.16 * easedRoot;
            drawRootBranch(
              end,
              nextLength * extra,
              angleDeg + fastNoise(mix(seed, depth * 10 + 4)) * 14,
              nextThickness * 0.84,
              depth - 2,
              mix(seed, 3),
            );
          }
        }

        final double mainAngle = 90 + fastNoise(mix(branchSeed, 100)) * 6;
        drawRootBranch(rootStart, rootBaseLength, mainAngle + 12 + easedRoot * 24, rootBaseThickness, rootDepth, mix(branchSeed, 101));
        drawRootBranch(rootStart, rootBaseLength, mainAngle - (12 + easedRoot * 24), rootBaseThickness, rootDepth, mix(branchSeed, 102));
        drawRootBranch(
          rootStart,
          rootBaseLength * (0.74 + easedRoot * 0.22),
          mainAngle + fastNoise(mix(branchSeed, 103)) * 10,
          rootBaseThickness * 0.82,
          rootDepth - 1,
          mix(branchSeed, 104),
        );
      }
    }

    if (hasBrokenGround && stageBranch > 0) {
      // 树木持续生长，高度不再受限
      // 使用实际米数转换为像素，基于对数增长模型
      final double pixelsPerMeter = size.width / _targetWorldWidthMeters;

      // 添加生长不均匀性，使树木在不同阶段生长速度略有差异
      final double growthVariation = 1.0 + math.sin(treeHeightMeters * 0.5) * 0.1; // 每隔一定高度会有生长速度变化
      final double stemHeight = math.max(14.0, treeHeightMeters * pixelsPerMeter * growthVariation);

      // 树干粗度随高度持续增长，但速度放缓
      // 移除不再使用的旧变量以清理代码
      // 移除旧的渐变树干绘制，以解决变量名称重复和视觉冲突的问题

      double fastNoise(int hash) {
        return ((hash & 0x7fffffff) / 0x7fffffff) * 2 - 1;
      }

      int mix(int hash, int val) {
        return (hash * 31 + val) & 0x7fffffff;
      }

      void drawLeafCluster({
        required Offset origin,
        required double directionDeg,
        required double scale,
        required double growth,
        required int seed,
        required double canopyHeightPx,
      }) {
        final double normalizedScale = scale.clamp(0.08, 1.0);
        final double stageEased = math.pow(growth.clamp(0.0, 1.0), 0.86).toDouble();

        // 卡通风格颜色：更饱和，更分明
        final Color baseColor = Color.lerp(
          const Color(0xFF81C784), // 更亮，更卡通的绿
          const Color(0xFF4CAF50),
          stageEased * 0.3,
        )!;
        final Color shadowColor = Color.lerp(
          const Color(0xFF388E3C),
          const Color(0xFF2E7D32),
          normalizedScale * 0.3,
        )!;
        final Color outlineColor = const Color(0xFF1B5E20); // 深绿色轮廓

        // 增加基础半径倍率，并放宽最大限制 (从 80 增加到 250)
        final double clusterRadius = (canopyHeightPx * 0.85 * scale).clamp(8.0, 250.0);

        final Paint fillPaint = Paint()
          ..color = baseColor
          ..style = PaintingStyle.fill;

        final Paint shadowPaint = Paint()
          ..color = shadowColor
          ..style = PaintingStyle.fill;

        final Paint outlinePaint = Paint()
          ..color = outlineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, clusterRadius * 0.08)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.save();
        canvas.translate(origin.dx, origin.dy);
        // 树叶不需要跟随树枝完全旋转，保持相对竖直的蓬松感，稍微跟随一点点
        canvas.rotate(directionDeg * 0.3 * math.pi / 180);

        // 极简云朵造型：一个大球 + 两个小球
        final double w = clusterRadius * 2.0;
        final double h = clusterRadius * 1.6;

        final Path cloudPath = Path();

        // 主球
        cloudPath.addOval(Rect.fromCenter(center: const Offset(0, 0), width: w, height: h));

        // 随机添加 1-2 个子球，增加不对称性
        if (fastNoise(mix(seed, 900)) > 0) {
          cloudPath.addOval(Rect.fromCenter(center: Offset(w * 0.35, -h * 0.2), width: w * 0.6, height: h * 0.6));
        } else {
          cloudPath.addOval(Rect.fromCenter(center: Offset(-w * 0.35, -h * 0.2), width: w * 0.6, height: h * 0.6));
        }

        // 简单的底部阴影（新月形）
        final Path shadowPath = Path.combine(
            PathOperation.intersect, cloudPath, Path()..addOval(Rect.fromCenter(center: Offset(w * 0.1, h * 0.3), width: w * 0.9, height: h * 0.8)));

        canvas.drawPath(cloudPath, fillPaint);
        canvas.drawPath(shadowPath, shadowPaint);
        canvas.drawPath(cloudPath, outlinePaint);

        // 可爱的圆点高光
        canvas.drawCircle(Offset(-w * 0.25, -h * 0.25), w * 0.1, Paint()..color = Colors.white.withValues(alpha: 0.4));

        canvas.restore();
      }

      if (stageBranch > 0 && stageBranch < 0.28) {
        final double cotyledonStage = (stageBranch / 0.28).clamp(0.0, 1.0);

        // 使用更自然的生长曲线，早期生长快，后期变慢
        final double cotyledonGrowth = math.pow(cotyledonStage, 0.65).toDouble();

        // 添加生长不规则性，使两片子叶略有差异
        final double leftWingGrowth = cotyledonGrowth * (0.95 + fastNoise(mix(branchSeed, 301)) * 0.1);
        final double rightWingGrowth = cotyledonGrowth * (0.95 + fastNoise(mix(branchSeed, 302)) * 0.1);

        final Offset cotyledonAnchor = Offset(centerX, soilTop - stemHeight * (0.98 - 0.12 * cotyledonGrowth));
        final double cotyledonScale = ui.lerpDouble(0.32, 0.58, cotyledonGrowth) ?? 0.4;
        final double cotyledonSpread = ui.lerpDouble(42, 28, cotyledonGrowth) ?? 36;
        final double maxCanopyHeight = stemHeight * 0.32;
        final double cotyledonCanopyHeight = (stemHeight * 0.24 * cotyledonGrowth).clamp(
          math.min(12.0, maxCanopyHeight),
          math.max(12.0, maxCanopyHeight),
        );

        drawLeafCluster(
          origin: cotyledonAnchor + const Offset(-6, -2),
          directionDeg: -cotyledonSpread,
          scale: cotyledonScale * leftWingGrowth, // 应用左翼生长差异
          growth: cotyledonGrowth.clamp(0.0, 0.9),
          seed: mix(branchSeed, 201),
          canopyHeightPx: cotyledonCanopyHeight * leftWingGrowth, // 应用左翼高度差异
        );
        drawLeafCluster(
          origin: cotyledonAnchor + const Offset(6, -2),
          directionDeg: cotyledonSpread,
          scale: cotyledonScale * rightWingGrowth, // 应用右翼生长差异
          growth: cotyledonGrowth.clamp(0.0, 0.9),
          seed: mix(branchSeed, 202),
          canopyHeightPx: cotyledonCanopyHeight * rightWingGrowth, // 应用右翼高度差异
        );
      }

      // 树枝：完全重写为"棒棒糖/橡树"风格的生成算法
      // 不再依赖高度生成细长的树，而是由粗干+大树冠组成

      // 基础参数配置

      // 树干颜色
      final Paint trunkPaint = Paint()
        ..color = const Color(0xFF8D6E63) // 较浅的棕色
        ..style = PaintingStyle.fill;
      final Paint trunkOutlinePaint = Paint()
        ..color = const Color(0xFF3E2723) // 深棕色轮廓
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      // 根部位置
      final Offset roots = Offset(centerX, soilTop);

      // 主干高度由 stemHeight 决定，它是根据 treeHeightMeters 计算出来的
      // 我们将主干分配为总高度的一部分（例如 45%），其余为树冠分叉
      final double trunkHeight = stemHeight * 0.45;
      final Offset trunkEnd = roots + Offset(0, -trunkHeight);

      // 树干粗度也随高度增加
      // 增加树干粗度随高度增加的强度
      final double baseTrunkThickness = (18.0 + math.pow(treeHeightMeters, 0.72) * 18.0).clamp(18.0, 360.0);

      // 添加树干粗度的自然变化，底部更粗，顶部更细
      final double trunkBottomThickness = baseTrunkThickness * (1.0 + fastNoise(mix(branchSeed, 500)) * 0.1);
      final double trunkTopThickness = baseTrunkThickness * 0.35 * (1.0 + fastNoise(mix(branchSeed, 501)) * 0.05);

      final Path trunkPath = Path();
      // 使用更自然的曲线连接树干底部和顶部
      trunkPath.moveTo(roots.dx - trunkBottomThickness * 0.5, roots.dy);
      trunkPath.lineTo(roots.dx + trunkBottomThickness * 0.5, roots.dy);

      // 使用二次贝塞尔曲线创建更自然的树干形状，避免可能导致矩阵错误的复杂路径
      final double controlY = trunkEnd.dy + trunkHeight * 0.3; // 控制点在树干中下部
      trunkPath.quadraticBezierTo(
        roots.dx - trunkTopThickness * 0.2, // 轻微的不对称
        controlY,
        trunkEnd.dx + trunkTopThickness * 0.35,
        trunkEnd.dy,
      );
      trunkPath.lineTo(trunkEnd.dx - trunkTopThickness * 0.35, trunkEnd.dy);
      trunkPath.quadraticBezierTo(
        roots.dx + trunkTopThickness * 0.2, // 轻微的不对称
        controlY,
        roots.dx - trunkBottomThickness * 0.5,
        roots.dy,
      );
      trunkPath.close();

      canvas.drawPath(trunkPath, trunkPaint);
      canvas.drawPath(trunkPath, trunkOutlinePaint);

      // 递归绘制树枝（调整为基于主干高度的比例）
      void drawSimpleBranch(
        Offset start,
        double length,
        double angleDeg,
        double thickness,
        int depth,
        int seed,
        double elapsedTime, // 添加时间参数用于风力效果
      ) {
        if (depth <= 0) {
          // 添加随风摆动效果
          final double windEffect = math.sin(elapsedTime * 0.5 + start.dx * 0.01) * 5;
          final Offset windOffset = Offset(windEffect * 0.3, 0);

          drawLeafCluster(
            origin: start + windOffset,
            directionDeg: windEffect,
            // 将树叶大小直接与生长阶段挂钩 (0.5 -> 1.5倍)
            scale: (0.6 + stageFoliage * 1.0) * (1.0 + fastNoise(mix(seed, 99)) * 0.2),
            growth: stageFoliage,
            seed: mix(seed, 100),
            canopyHeightPx: length * 1.8, // 进一步增大比例
          );
          return;
        }

        final double angle = angleDeg * math.pi / 180;

        // 添加树枝摆动效果
        final double branchFlexibility = 0.3;
        final double windStrength = math.sin(elapsedTime * 0.3 + start.dx * 0.02) * branchFlexibility;

        final Offset end = start +
            Offset(
              math.cos(angle + windStrength * 0.1) * length,
              math.sin(angle + windStrength * 0.1) * length,
            );

        final Path limbPath = Path();
        limbPath.moveTo(
          start.dx + math.cos(angle + math.pi / 2) * thickness * 0.5,
          start.dy + math.sin(angle + math.pi / 2) * thickness * 0.5,
        );
        limbPath.lineTo(
          end.dx + math.cos(angle + math.pi / 2) * thickness * 0.4,
          end.dy + math.sin(angle + math.pi / 2) * thickness * 0.4,
        );
        limbPath.lineTo(
          end.dx - math.cos(angle + math.pi / 2) * thickness * 0.4,
          end.dy - math.sin(angle + math.pi / 2) * thickness * 0.4,
        );
        limbPath.lineTo(
          start.dx - math.cos(angle + math.pi / 2) * thickness * 0.5,
          start.dy - math.sin(angle + math.pi / 2) * thickness * 0.5,
        );
        limbPath.close();

        canvas.drawPath(limbPath, trunkPaint);
        canvas.drawPath(limbPath, trunkOutlinePaint);

        final int splitCount = 2 + (fastNoise(mix(seed, 10)) > 0 ? 1 : 0);

        for (int i = 0; i < splitCount; i++) {
          final double spread = 45.0 + fastNoise(mix(seed, 20 + i)) * 15.0;
          final double newAngle = angleDeg - (spread * (splitCount - 1) / 2) + spread * i;
          final double jitter = fastNoise(mix(seed, 30 + i)) * 10;

          drawSimpleBranch(
              end,
              length * 0.72,
              newAngle + jitter,
              thickness * 0.82, // 再次提高子分支粗度保留比例 (从 0.75 提高到 0.82)
              depth - 1,
              mix(seed, 40 + i),
              elapsedTime); // 传递时间参数
        }

        if ((fastNoise(mix(seed, 50)) > 0.4)) {
          // 侧枝也添加摆动效果
          final double lateralWind = math.sin(elapsedTime * 0.4 + end.dx * 0.015) * 4;
          final Offset lateralWindOffset = Offset(lateralWind * 0.2, 0);

          drawLeafCluster(
            origin: end + lateralWindOffset,
            directionDeg: lateralWind,
            // 侧边叶团也随生长缩放
            scale: (0.4 + stageFoliage * 0.5),
            growth: stageFoliage,
            seed: mix(seed, 51),
            canopyHeightPx: length * 1.3,
          );
        }
      }

      // 从主干顶部开始爆发式生长
      if (stageBranch > 0.2) {
        final int depth = 2 + (stageBranch * 1.5).floor(); // 保持卡通感，不宜太深

        const int mainBranches = 3;
        // 树枝的基础长度随高度增长
        final double baseBranchLength = stemHeight * (0.35 + stageBranch * 0.1);

        for (int i = 0; i < mainBranches; i++) {
          // 添加生长不均匀性，让每根树枝的生长速度略有差异
          final double growthVariation = 0.8 + fastNoise(mix(branchSeed, 100 + i)) * 0.4;
          final double adjustedLength = baseBranchLength * growthVariation;
          final double angle = -90.0 + (i - 1) * 45.0 + fastNoise(mix(branchSeed, i)) * 10;

          drawSimpleBranch(
              trunkEnd,
              adjustedLength,
              angle,
              baseTrunkThickness * 0.65, // 再次提高主分支与主干的比例 (从 0.55 提高到 0.65)
              depth,
              mix(branchSeed, 1000 + i),
              elapsedDays); // 使用传递的时间参数
        }
      }

      // 添加随机落叶效果，模拟自然现象
      if (stageFoliage > 0.3) {
        final math.Random leafFallRandom = math.Random((elapsedDays * 1000).floor());
        final int leafCount = (stageFoliage * 15).floor();

        for (int i = 0; i < leafCount; i++) {
          final double randX = centerX + (leafFallRandom.nextDouble() - 0.5) * baseTrunkThickness * 3;
          final double randY = soilTop - (leafFallRandom.nextDouble()) * stemHeight * 0.7;
          final double leafSize = 2 + leafFallRandom.nextDouble() * 3;

          // 只绘制少量飘落的叶子，增加自然感
          if (i % 5 == 0) {
            // 每5片叶子画一片
            final double fallOffset = math.sin(elapsedDays * 2 + i) * 5; // 飘落动画
            canvas.drawOval(
              Rect.fromCenter(
                center: Offset(randX + fallOffset, randY),
                width: leafSize,
                height: leafSize * 1.2,
              ),
              Paint()..color = const Color(0xFF81C784).withValues(alpha: 0.6),
            );
          }
        }
      }

      // 根部叶子装饰也随缩放
      final double shrubSize = (baseTrunkThickness * 1.5).clamp(15.0, 50.0);
      drawLeafCluster(
          origin: roots + Offset(-baseTrunkThickness * 0.8, -5), directionDeg: -45, scale: 0.5, growth: 1.0, seed: 1, canopyHeightPx: shrubSize);
      drawLeafCluster(
          origin: roots + Offset(baseTrunkThickness * 0.8, -5), directionDeg: 45, scale: 0.5, growth: 1.0, seed: 2, canopyHeightPx: shrubSize);
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
