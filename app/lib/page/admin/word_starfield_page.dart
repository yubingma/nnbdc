import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nnbdc/util/pca_projection_service.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/api/api.dart';

/// 3D 星空粒子实体模型
class StarfieldPoint {
  final String id;
  final String spell;
  final double x; // 归一化后的3D坐标
  final double y;
  final double z;
  final double popularity;

  // 临时存储每帧投影计算结果
  double rotatedX = 0;
  double rotatedY = 0;
  double rotatedZ = 0;
  double screenX = 0;
  double screenY = 0;
  double scale = 0;

  StarfieldPoint({
    required this.id,
    required this.spell,
    required this.x,
    required this.y,
    required this.z,
    required this.popularity,
  });
}

/// 纯背景星空粒子（无单词），增加星云深邃感
class BackgroundStar {
  final double x;
  final double y;
  final double z;
  final double size;

  double rotatedX = 0;
  double rotatedY = 0;
  double rotatedZ = 0;
  double screenX = 0;
  double screenY = 0;
  double scale = 0;

  BackgroundStar({
    required this.x,
    required this.y,
    required this.z,
    required this.size,
  });
}

class WordStarfieldPage extends StatefulWidget {
  const WordStarfieldPage({super.key});

  @override
  State<WordStarfieldPage> createState() => _WordStarfieldPageState();
}

class _WordStarfieldPageState extends State<WordStarfieldPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isAdmin = false;
  List<StarfieldPoint> _points = [];
  List<BackgroundStar> _bgStars = [];

  // 视角控制参数
  double _rotateX = 0.3; // 绕X轴偏转角
  double _rotateY = 0.5; // 绕Y轴旋转角
  double _zoom = 1.0;
  final double _cameraDistance = 400.0;

  // 交互控制
  bool _isUserInteracting = false;
  Timer? _resumeTimer;
  late AnimationController _autoRotateController;
  StarfieldPoint? _selectedPoint;
  List<StarfieldPoint> _neighbors = [];
  List<MeaningItem> _selectedWordMeanings = [];
  bool _isLoadingMeanings = false;

  // 设置面板选项
  bool _showRelations = true;
  int _densityLimit = 3000;

  // 一键重构相关状态
  bool _hasReconstructWarning = false;
  String _reconstructStatus = 'IDLE';
  String _reconstructMsg = '';
  double _reconstructProgress = 0.0;
  int _totalWords = 0;
  int _fittedWords = 0;
  double _unreconstructedPercent = 0.0;
  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    _checkAdminPermission();

    // 自动慢旋转控制器
    _autoRotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 360),
    )..addListener(() {
        if (!_isUserInteracting) {
          setState(() {
            _rotateY += 0.0015; // 每帧慢速自转
          });
        }
      });
    _autoRotateController.repeat();
  }

  @override
  void dispose() {
    _autoRotateController.dispose();
    _resumeTimer?.cancel();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  void _checkAdminPermission() {
    final user = Global.getLoggedInUser();
    if (user == null || !(user.isAdmin ?? false)) {
      setState(() {
        _isAdmin = false;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
        ToastUtil.error('非管理员账号，无权访问3D词星空！');
      });
      return;
    }
    setState(() {
      _isAdmin = true;
    });
    _loadData();
    _loadStatusQuietly();
  }

  Future<void> _loadStatusQuietly() async {
    try {
      final res = await Api.client.getEmbeddingStatus();
      if (res.success && res.data != null) {
        final data = res.data!.data;
        if (mounted) {
          setState(() {
            _hasReconstructWarning = data['warning'] == true;
            _reconstructStatus = data['reconstructStatus'] ?? 'IDLE';
            _reconstructMsg = data['reconstructMsg'] ?? '';
            _reconstructProgress = (data['reconstructProgress'] as num?)?.toDouble() ?? 0.0;
            _totalWords = (data['totalWords'] as num?)?.toInt() ?? 0;
            _fittedWords = (data['fittedWords'] as num?)?.toInt() ?? 0;
            _unreconstructedPercent = (data['unreconstructedPercent'] as num?)?.toDouble() ?? 0.0;
          });
        }
      }
    } catch (_) {}
  }

  void _showReconstructDialog() {
    _loadStatusQuietly();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isRunning = _reconstructStatus == 'RUNNING';
            
            if (isRunning && (_statusPollTimer == null || !_statusPollTimer!.isActive)) {
              _startStatusPolling(setDialogState);
            }

            final percentText = (_unreconstructedPercent * 100).toStringAsFixed(1);

            return AlertDialog(
              backgroundColor: const Color(0xFF141829),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.rocket_launch, color: Colors.amberAccent, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '词嵌入一键重构控制台',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '提示：当词库中新增了大量词汇，或者词典同步后 3D 降维出现偏移时，需要执行词嵌入一键重构。这会触发在后台向 AI 大模型获取单词的语义特征（词向量），并更新全局 PCA（主成分分析）降维投影矩阵，重新计算所有单词在 3D 空间中的分布位置。重构在后台执行，不影响正常学习。',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildStatusRow('全库单词数', '$_totalWords 个'),
                          const Divider(color: Colors.white10),
                          _buildStatusRow('参与 3D 拟合词数', '$_fittedWords 个'),
                          const Divider(color: Colors.white10),
                          _buildStatusRow(
                            '新增未重构单词占比', 
                            '$percentText%',
                            valueColor: _hasReconstructWarning ? Colors.redAccent : Colors.greenAccent
                          ),
                          const Divider(color: Colors.white10),
                          _buildStatusRow('重构状态', _reconstructStatus, valueColor: isRunning ? Colors.amberAccent : Colors.cyanAccent),
                        ],
                      ),
                    ),
                    if (isRunning) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: _reconstructProgress,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _reconstructMsg.isEmpty ? '正在重构，请稍候...' : _reconstructMsg,
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                      ),
                    ] else if (_reconstructStatus == 'FAILED') ...[
                      const SizedBox(height: 12),
                      Text(
                        '重构失败: $_reconstructMsg',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isRunning ? null : () => Navigator.pop(context),
                  child: const Text('关闭', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: isRunning ? null : () => _triggerReconstructTask(setDialogState),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(isRunning ? '重构中...' : '触发词嵌入一键重构'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _statusPollTimer?.cancel();
    });
  }

  Widget _buildStatusRow(String label, String value, {Color valueColor = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _startStatusPolling(StateSetter setDialogState) {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final res = await Api.client.getEmbeddingStatus();
        if (res.success && res.data != null) {
          final data = res.data!.data;
          if (mounted) {
            setDialogState(() {
              _hasReconstructWarning = data['warning'] == true;
              _reconstructStatus = data['reconstructStatus'] ?? 'IDLE';
              _reconstructMsg = data['reconstructMsg'] ?? '';
              _reconstructProgress = (data['reconstructProgress'] as num?)?.toDouble() ?? 0.0;
              _totalWords = (data['totalWords'] as num?)?.toInt() ?? 0;
              _fittedWords = (data['fittedWords'] as num?)?.toInt() ?? 0;
              _unreconstructedPercent = (data['unreconstructedPercent'] as num?)?.toDouble() ?? 0.0;
            });
            setState(() {});

            if (_reconstructStatus != 'RUNNING') {
              _statusPollTimer?.cancel();
              if (_reconstructStatus == 'COMPLETED') {
                ToastUtil.success('词嵌入一键重构成功！');
                _loadData();
              } else if (_reconstructStatus == 'FAILED') {
                ToastUtil.error('词嵌入重构失败：$_reconstructMsg');
              }
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _triggerReconstructTask(StateSetter setDialogState) async {
    try {
      final res = await Api.client.triggerReconstruct();
      if (res.success) {
        setDialogState(() {
          _reconstructStatus = 'RUNNING';
          _reconstructMsg = '重构任务已成功触发，正在建立连接...';
          _reconstructProgress = 0.0;
        });
        setState(() {});
        _startStatusPolling(setDialogState);
      } else {
        ToastUtil.error('触发重构失败: ${res.msg}');
      }
    } catch (e) {
      ToastUtil.error('发生网络错误: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = MyDatabase.instance;
      // 从本地数据库读取所有带 1bit 词嵌入的单词，最大限制 5000 确保平滑度
      final words = await db.wordsDao.getWordsWithCoordinates(limit: _densityLimit);

      if (words.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        ToastUtil.info('本地暂无词嵌入数据，请先执行“词嵌入一键重构”！');
        return;
      }

      await PcaProjectionService().ensureInitialized();

      // 先动态计算好这批词的 3D 坐标
      final List<Map<String, dynamic>> calculatedWords = [];
      for (var w in words) {
        if (w.embedding1bit != null) {
          final coords = PcaProjectionService().projectTo3D(w.embedding1bit!);
          calculatedWords.add({
            'word': w,
            'x': coords[0],
            'y': coords[1],
            'z': coords[2],
          });
        }
      }

      if (calculatedWords.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        ToastUtil.info('本地暂无有效词嵌入坐标的单词数据！');
        return;
      }

      // 1. 进行坐标自适应归一化与归中
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      double minZ = double.infinity, maxZ = -double.infinity;

      for (var item in calculatedWords) {
        final x = item['x'] as double;
        final y = item['y'] as double;
        final z = item['z'] as double;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }

      final double offsetX = (minX + maxX) / 2;
      final double offsetY = (minY + maxY) / 2;
      final double offsetZ = (minZ + maxZ) / 2;

      double deltaX = maxX - minX;
      double deltaY = maxY - minY;
      double deltaZ = maxZ - minZ;
      double maxDelta = max(deltaX, max(deltaY, deltaZ));
      if (maxDelta == 0) maxDelta = 1.0;

      // 缩放边界设定在 [-200, 200] 空间内
      const double targetBound = 200.0;

      _points = calculatedWords.map((item) {
        final Word w = item['word'] as Word;
        final nx = ((item['x'] as double) - offsetX) / maxDelta * (targetBound * 2);
        final ny = ((item['y'] as double) - offsetY) / maxDelta * (targetBound * 2);
        final nz = ((item['z'] as double) - offsetZ) / maxDelta * (targetBound * 2);
        return StarfieldPoint(
          id: w.id,
          spell: w.spell,
          x: nx,
          y: ny,
          z: nz,
          popularity: (w.popularity).toDouble(),
        );
      }).toList();

      // 2. 随机生成 250 个静态背景星，做远景衬托
      final random = Random();
      _bgStars = List.generate(250, (index) {
        // 分布在 [-350, 350] 范围的立方体或球体内
        final r = 250.0 + random.nextDouble() * 200.0;
        final theta = random.nextDouble() * 2.0 * pi;
        final phi = acos(2.0 * random.nextDouble() - 1.0);
        
        final x = r * sin(phi) * cos(theta);
        final y = r * sin(phi) * sin(theta);
        final z = r * cos(phi);

        return BackgroundStar(
          x: x,
          y: y,
          z: z,
          size: 0.8 + random.nextDouble() * 1.5,
        );
      });

      setState(() {
        _isLoading = false;
        _selectedPoint = null;
        _neighbors = [];
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ToastUtil.error('数据加载失败: $e');
    }
  }

  void _onInteractionStart() {
    _isUserInteracting = true;
    _resumeTimer?.cancel();
  }

  void _onInteractionEnd() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _isUserInteracting = false;
        });
      }
    });
  }

  // 点击检测：把屏幕点击坐标与粒子投影坐标匹配，射线求最近距离点
  void _handleTap(TapDownDetails details, Size viewSize) {
    if (_points.isEmpty) return;
    
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    final tapX = localPosition.dx;
    final tapY = localPosition.dy;

    StarfieldPoint? bestMatch;
    double bestDistance = double.infinity;

    for (var pt in _points) {
      // 计算到屏幕投影点的二维距离
      final dx = pt.screenX - tapX;
      final dy = pt.screenY - tapY;
      final dist = sqrt(dx * dx + dy * dy);

      // 24像素为点击感应半径，并且距离更近或深度更靠前
      if (dist < 24.0) {
        // 在多个点都处于点击感应内时，优先挑选深度靠近屏幕的点（rotatedZ越小越近）
        if (dist < bestDistance) {
          bestMatch = pt;
          bestDistance = dist;
        }
      }
    }

    if (bestMatch != null) {
      _selectPoint(bestMatch);
    } else {
      setState(() {
        _selectedPoint = null;
        _neighbors = [];
        _selectedWordMeanings = [];
      });
    }
  }

  void _selectPoint(StarfieldPoint point) {
    setState(() {
      _selectedPoint = point;
      _isLoadingMeanings = true;
    });

    // 1. 寻找 3D 归一化空间中与该词最近的 3 个邻接词作为关联语义词
    final sortedList = List<StarfieldPoint>.from(_points)..remove(point);
    sortedList.sort((a, b) {
      final distA = _euclideanDistance(point, a);
      final distB = _euclideanDistance(point, b);
      return distA.compareTo(distB);
    });

    _neighbors = sortedList.take(3).toList();

    // 2. 异步拉取词意数据
    final db = MyDatabase.instance;
    db.meaningItemsDao.getMeaningsByWordId(point.id).then((meanings) {
      if (mounted && _selectedPoint?.id == point.id) {
        setState(() {
          _selectedWordMeanings = meanings;
          _isLoadingMeanings = false;
        });
      }
    }).catchError((err) {
      if (mounted) {
        setState(() {
          _isLoadingMeanings = false;
        });
      }
    });
  }

  double _euclideanDistance(StarfieldPoint a, StarfieldPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Scaffold(
        backgroundColor: Color(0xFF050814),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF03050F), // 深邃宇宙黑蓝
              Color(0xFF0B0E1B),
              Color(0xFF13172E), // 极光暗紫蓝
            ],
          ),
        ),
        child: Stack(
          children: [
            // 1. 3D Canvas 星空交互区域
            GestureDetector(
              onScaleStart: (_) => _onInteractionStart(),
              onScaleUpdate: (details) {
                setState(() {
                  // 双指缩放，限制倍率在 0.4 到 4.0 之间
                  if (details.scale != 1.0) {
                    _zoom = (_zoom * (details.scale > 1.0 ? 1.03 : 0.97)).clamp(0.4, 4.0);
                  }
                  // 单指拖拽旋转
                  if (details.pointerCount == 1) {
                    _rotateY += details.focalPointDelta.dx * 0.005;
                    _rotateX -= details.focalPointDelta.dy * 0.005;
                    // 限制垂直旋转角度，防止星空颠倒错觉
                    _rotateX = _rotateX.clamp(-pi / 2.2, pi / 2.2);
                  }
                });
              },
              onScaleEnd: (_) => _onInteractionEnd(),
              onTapDown: (details) {
                final Size viewSize = MediaQuery.of(context).size;
                _handleTap(details, viewSize);
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: StarfieldPainter(
                  points: _points,
                  bgStars: _bgStars,
                  rotateX: _rotateX,
                  rotateY: _rotateY,
                  zoom: _zoom,
                  cameraDistance: _cameraDistance,
                  selectedPoint: _selectedPoint,
                  neighbors: _neighbors,
                  showRelations: _showRelations,
                ),
              ),
            ),

            // 2. 顶部毛玻璃导航栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 8,
                      bottom: 12,
                      left: 16,
                      right: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                        ),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '3D 词汇语义星空',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'NotoSansSC',
                                  letterSpacing: 0.8,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '基于 AI 词嵌入空间投影 PCA 降维拟合',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                  fontFamily: 'NotoSansSC',
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  onPressed: () => _showReconstructDialog(),
                                  icon: const Icon(Icons.rocket_launch, color: Colors.amberAccent, size: 22),
                                  tooltip: '词嵌入一键重构',
                                ),
                                if (_hasReconstructWarning)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 8,
                                        minHeight: 8,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            IconButton(
                              onPressed: () => _showSettingsDialog(),
                              icon: const Icon(Icons.tune, color: Colors.white, size: 22),
                              tooltip: '渲染设置',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. 加载进度指示
            if (_isLoading)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '正在构建 3D 三维星空地图...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 4. 底部毛玻璃词义卡片
            if (_selectedPoint != null)
              Positioned(
                bottom: 24,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF141829).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedPoint!.spell,
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '词频: ${_selectedPoint!.popularity.toInt()}',
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isLoadingMeanings)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LinearProgressIndicator(
                                backgroundColor: Colors.white10,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                              ),
                            )
                          else if (_selectedWordMeanings.isEmpty)
                            const Text(
                              '暂未同步到本地释义项',
                              style: TextStyle(color: Colors.white54, fontSize: 14),
                            )
                          else
                            ..._selectedWordMeanings.map(
                              (mi) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        mi.ciXing,
                                        style: const TextStyle(
                                          color: Colors.cyanAccent,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        mi.meaning,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white10, height: 1),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.bubble_chart, color: Colors.white54, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '语义临近词：${_neighbors.map((n) => n.spell).join(', ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141829),
              title: const Text('星空渲染配置', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('绘制语义关系连线', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    value: _showRelations,
                    onChanged: (val) {
                      setDialogState(() {
                        _showRelations = val;
                      });
                      setState(() {
                        _showRelations = val;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('粒子最大数量限制:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _densityLimit.toDouble(),
                          min: 500,
                          max: 6000,
                          divisions: 11,
                          label: '$_densityLimit',
                          onChanged: (val) {
                            setDialogState(() {
                              _densityLimit = val.toInt();
                            });
                          },
                        ),
                      ),
                      Text('$_densityLimit', style: const TextStyle(color: Colors.cyanAccent)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadData(); // 重新加载数据应用新的密度设置
                  },
                  child: const Text('确认更新', style: TextStyle(color: Colors.amberAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 3D 渲染星空核心绘制器
class StarfieldPainter extends CustomPainter {
  final List<StarfieldPoint> points;
  final List<BackgroundStar> bgStars;
  final double rotateX;
  final double rotateY;
  final double zoom;
  final double cameraDistance;
  final StarfieldPoint? selectedPoint;
  final List<StarfieldPoint> neighbors;
  final bool showRelations;

  StarfieldPainter({
    required this.points,
    required this.bgStars,
    required this.rotateX,
    required this.rotateY,
    required this.zoom,
    required this.cameraDistance,
    required this.selectedPoint,
    required this.neighbors,
    required this.showRelations,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    final double cosY = cos(rotateY);
    final double sinY = sin(rotateY);
    final double cosX = cos(rotateX);
    final double sinX = sin(rotateX);

    // 1. 对背景星背景粒子应用 3D 变换并投影
    for (var star in bgStars) {
      final double x1 = star.x * cosY - star.z * sinY;
      final double z1 = star.x * sinY + star.z * cosY;

      final double y2 = star.y * cosX - z1 * sinX;
      final double z2 = star.y * sinX + z1 * cosX;

      star.rotatedX = x1;
      star.rotatedY = y2;
      star.rotatedZ = z2;

      final double scale = cameraDistance / (cameraDistance + z2);
      star.scale = scale;
      star.screenX = centerX + x1 * scale * zoom;
      star.screenY = centerY + y2 * scale * zoom;
    }

    // 2. 对单词粒子应用 3D 变换与旋转投影
    for (var pt in points) {
      final double x1 = pt.x * cosY - pt.z * sinY;
      final double z1 = pt.x * sinY + pt.z * cosY;

      final double y2 = pt.y * cosX - z1 * sinX;
      final double z2 = pt.y * sinX + z1 * cosX;

      pt.rotatedX = x1;
      pt.rotatedY = y2;
      pt.rotatedZ = z2;

      final double scale = cameraDistance / (cameraDistance + z2);
      pt.scale = scale;
      pt.screenX = centerX + x1 * scale * zoom;
      pt.screenY = centerY + y2 * scale * zoom;
    }

    // 3. 绘制远景背景微星 (无重叠排序要求，直接全部画，透明度低)
    final bgPaint = Paint()..style = PaintingStyle.fill;
    for (var star in bgStars) {
      // 抛弃屏幕外的背景点
      if (star.screenX < 0 || star.screenX > size.width || star.screenY < 0 || star.screenY > size.height) continue;
      
      // 景深衰减
      final alpha = (0.35 * star.scale).clamp(0.05, 0.6);
      bgPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(star.screenX, star.screenY), star.size * star.scale, bgPaint);
    }

    // 4. 对单词点依照 rotatedZ (深度坐标) 进行升序或降序排序 (Painter算法：从远到近画)
    final List<StarfieldPoint> sortedPoints = List.from(points);
    // rotatedZ 越大越靠后（越远），越小越靠前。所以我们要按 rotatedZ 降序排序，先画大值（远点），后画小值（近点）
    sortedPoints.sort((a, b) => b.rotatedZ.compareTo(a.rotatedZ));

    // 5. 绘制选中的邻近连接线 (在画点的前面或者点之后)
    if (showRelations && selectedPoint != null && neighbors.isNotEmpty) {
      final linePaint = Paint()
        ..color = Colors.amberAccent.withValues(alpha: 0.45)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      
      // 绘制流光连线效果，可以用微调的光晕表现
      for (var nb in neighbors) {
        canvas.drawLine(
          Offset(selectedPoint!.screenX, selectedPoint!.screenY),
          Offset(nb.screenX, nb.screenY),
          linePaint,
        );
      }
    }

    // 6. 依次绘制星空粒子点和拼写文本
    final pointPaint = Paint()..style = PaintingStyle.fill;

    for (var pt in sortedPoints) {
      // 过滤掉视口外部的点以优化图形吞吐量
      if (pt.screenX < -50 || pt.screenX > size.width + 50 || pt.screenY < -50 || pt.screenY > size.height + 50) {
        continue;
      }

      final isSelected = selectedPoint?.id == pt.id;
      final isNeighbor = neighbors.any((nb) => nb.id == pt.id);

      // 点的色彩分布 (依据深度以及被选中的状态渐变)
      double alpha = (0.75 * pt.scale).clamp(0.1, 1.0);
      double radius = (2.2 * pt.scale).clamp(0.6, 6.0);

      if (isSelected) {
        // 选中的点：闪耀的黄金色，光环扩大
        pointPaint.color = Colors.amberAccent;
        canvas.drawCircle(Offset(pt.screenX, pt.screenY), 8.0, pointPaint..color = Colors.amberAccent.withValues(alpha: 0.3));
        canvas.drawCircle(Offset(pt.screenX, pt.screenY), 4.0, pointPaint..color = Colors.amberAccent);
      } else if (isNeighbor) {
        // 临近点：明亮的浅绿色
        pointPaint.color = Colors.cyanAccent;
        canvas.drawCircle(Offset(pt.screenX, pt.screenY), radius * 1.5, pointPaint);
      } else {
        // 普通点：星系渐变蓝紫色 (z轴越小，越靠近屏幕，颜色越亮)
        final double ratio = (pt.rotatedZ + 200.0) / 400.0; // 0.0 到 1.0
        pointPaint.color = Color.lerp(
          const Color(0xFF6E85FF), // 近处亮蓝
          const Color(0xFFC582FF).withValues(alpha: alpha), // 远处暗紫
          ratio.clamp(0.0, 1.0),
        )!;
        canvas.drawCircle(Offset(pt.screenX, pt.screenY), radius, pointPaint);
      }

      // 7. 绘制拼写文本：
      // 为防止界面文字爆炸，只有三种粒子显示拼写：
      // - 被选中粒子
      // - 邻近粒子
      // - 非常靠近屏幕（scale > 1.3）且是深度靠前（rotatedZ 属于前 40 靠近屏幕）的词汇
      final isCloseToScreen = pt.scale > 1.3;
      final showText = isSelected || isNeighbor || (isCloseToScreen && sortedPoints.indexOf(pt) >= sortedPoints.length - 40);

      if (showText) {
        double textOpacity = isSelected ? 1.0 : (isNeighbor ? 0.8 : (pt.scale - 1.0).clamp(0.0, 0.75));
        
        final textSpan = TextSpan(
          text: pt.spell,
          style: TextStyle(
            color: isSelected
                ? Colors.amberAccent
                : (isNeighbor ? Colors.cyanAccent : Colors.white.withValues(alpha: textOpacity)),
            fontSize: isSelected ? 16.0 : (10.0 * pt.scale).clamp(8.0, 13.0),
            fontWeight: isSelected || isNeighbor ? FontWeight.bold : FontWeight.normal,
            shadows: isSelected
                ? [
                    const Shadow(
                      color: Colors.black54,
                      offset: Offset(0, 1),
                      blurRadius: 4,
                    )
                  ]
                : null,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        // 略微偏置以避免盖住粒子圆点
        textPainter.paint(
          canvas,
          Offset(pt.screenX + 8, pt.screenY - textPainter.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) {
    return oldDelegate.rotateX != rotateX ||
        oldDelegate.rotateY != rotateY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.selectedPoint != selectedPoint ||
        oldDelegate.showRelations != showRelations;
  }
}
