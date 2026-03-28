import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';

enum XAxisMode {
  stability,
  popularity,
  difficulty,
  category,
}

class MemoryCloudPage extends StatefulWidget {
  const MemoryCloudPage({super.key});

  @override
  State<MemoryCloudPage> createState() => _MemoryCloudPageState();
}

class _MemoryCloudPageState extends State<MemoryCloudPage> with TickerProviderStateMixin {
  List<CloudPoint> _points = [];
  bool _isLoading = true;
  XAxisMode _currentMode = XAxisMode.stability;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = MyDatabase.instance;
    final userId = Global.currentUserId;
    if (userId == null) return;

    final data = await db.learningWordsDao.getLearningWordsForCloud(userId);
    final now = AppClock.now();

    setState(() {
      _points = data.map((item) {
        final lastDate = item['lastLearningDate'] as DateTime? ?? now;
        final scheduledDays = item['scheduledDays'] as int? ?? 0;
        final nextDate = lastDate.add(Duration(days: scheduledDays));
        final daysDiff = nextDate.difference(now).inDays;

        return CloudPoint(
          word: item['word'] as String,
          stability: (item['stability'] as double?) ?? 0.0,
          difficulty: (item['difficulty'] as double?) ?? 5.0,
          popularity: (item['popularity'] as int?) ?? 0,
          reps: (item['reps'] as int?) ?? 0,
          state: (item['state'] as int?) ?? 0,
          category: item['category'] as String,
          yValue: daysDiff.toDouble(),
        );
      }).toList();
      _isLoading = false;
    });
    _animationController.forward(from: 0);
  }

  void _switchMode(XAxisMode mode) {
    if (_currentMode == mode) return;
    setState(() {
      _currentMode = mode;
    });
    _animationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('记忆云图', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildModeSelector(isDarkMode),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SingleChildScrollView(
                      child: Stack(
                        children: [
                          AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              const double canvasHeight = 15.0 * 205; // 205 days * 15px/day
                              return CustomPaint(
                                painter: CloudPainter(
                                  points: _points,
                                  mode: _currentMode,
                                  progress: _animationController.value,
                                  isDarkMode: isDarkMode,
                                ),
                                size: const Size(double.infinity, canvasHeight),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                _buildLegend(isDarkMode),
              ],
            ),
    );
  }


  Widget _buildModeSelector(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: XAxisMode.values.map((mode) {
            final isSelected = _currentMode == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_getModeName(mode)),
                selected: isSelected,
                onSelected: (val) => _switchMode(mode),
                selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                labelStyle: TextStyle(
                  color: isSelected ? AppTheme.primaryColor : (isDarkMode ? Colors.white70 : Colors.black54),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _getModeName(XAxisMode mode) {
    switch (mode) {
      case XAxisMode.stability:
        return '牢固度';
      case XAxisMode.popularity:
        return '常用度';
      case XAxisMode.difficulty:
        return '难度';
      case XAxisMode.category:
        return '分类';
    }
  }

  Widget _buildLegend(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem('新词', Colors.blue, isDarkMode),
          const SizedBox(width: 12),
          _legendItem('学习', Colors.green, isDarkMode),
          const SizedBox(width: 12),
          _legendItem('复习', Colors.orange, isDarkMode),
          const SizedBox(width: 12),
          _legendItem('超期', Colors.red, isDarkMode),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, bool isDarkMode) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white60 : Colors.black54)),
      ],
    );
  }
}

class CloudPoint {
  final String word;
  final double stability;
  final double difficulty;
  final int popularity;
  final int reps;
  final int state;
  final String category;
  final double yValue;
  Offset? currentPos;

  CloudPoint({
    required this.word,
    required this.stability,
    required this.difficulty,
    required this.popularity,
    required this.reps,
    required this.state,
    required this.category,
    required this.yValue,
  });

  double getX(XAxisMode mode) {
    switch (mode) {
      case XAxisMode.stability:
        return min(stability / 50.0, 1.0); // 0 to 50+
      case XAxisMode.popularity:
        return min(popularity / 2000.0, 1.0); // 0 to 2000+
      case XAxisMode.difficulty:
        return (difficulty - 1.0) / 9.0; // 1 to 10
      case XAxisMode.category:
        return (category.hashCode % 1000) / 1000.0;
    }
  }
}

class CloudPainter extends CustomPainter {
  final List<CloudPoint> points;
  final XAxisMode mode;
  final double progress;
  final bool isDarkMode;

  CloudPainter({
    required this.points,
    required this.mode,
    required this.progress,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackgroundBands(canvas, size);

    if (points.isEmpty) return;

    // Fixed Y range: 0 to 200 days (to see mastered words)
    const double maxY = 200.0;
    const double minY = -5.0; // Overdue

    final paint = Paint()..strokeWidth = 1.0;

    for (var point in points) {
      double targetX = point.getX(mode) * size.width;
      // Y-axis: Top (urgent/overdue) to Bottom (future)
      double normalizedY = (point.yValue - minY) / (maxY - minY);
      double targetY = size.height * normalizedY.clamp(0.0, 1.0);

      final color = _getColor(point);
      final radius = 3.0 + (point.reps.clamp(0, 20) / 4.0);

      canvas.drawCircle(Offset(targetX, targetY), radius * progress, paint..color = color.withOpacity(0.6 * progress));

      // 仅为学习次数较多且动画接近完成的点绘制文本
      if (point.reps > 15 && progress > 0.9) {
        final textSpan = TextSpan(
          text: point.word,
          style: TextStyle(
            color: color.withOpacity(0.9),
            fontSize: 9,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(color: isDarkMode ? Colors.black : Colors.white, blurRadius: 2)],
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(targetX + 6, targetY - 6));
      }
    }
  }

  void _drawBackgroundBands(Canvas canvas, Size size) {
    final List<Map<String, dynamic>> bands;

    switch (mode) {
      case XAxisMode.stability:
        bands = [
          {'label': '不牢固', 'color': Colors.red, 'end': 0.15},
          {'label': '起步中', 'color': Colors.orange, 'end': 0.4},
          {'label': '已入门', 'color': Colors.amber, 'end': 0.7},
          {'label': '很稳固', 'color': Colors.green, 'end': 1.0},
        ];
        break;
      case XAxisMode.difficulty:
        bands = [
          {'label': '送分题', 'color': Colors.green, 'end': 0.3},
          {'label': '普通', 'color': Colors.blue, 'end': 0.7},
          {'label': '硬骨头', 'color': Colors.red, 'end': 1.0},
        ];
        break;
      case XAxisMode.popularity:
        bands = [
          {'label': '极罕见', 'color': Colors.blueGrey, 'end': 0.25},
          {'label': '常用词', 'color': Colors.blue, 'end': 0.65},
          {'label': '高频词', 'color': Colors.teal, 'end': 1.0},
        ];
        break;
      case XAxisMode.category:
        bands = []; // 不画条带
        break;
    }

    double startX = 0;
    for (var band in bands) {
      double endX = (band['end'] as double) * size.width;
      final paint = Paint()
        ..color = (band['color'] as Color).withOpacity(isDarkMode ? 0.15 : 0.08)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(Rect.fromLTRB(startX, 0, endX, size.height), paint);

      // Draw band label at the top with higher visibility
      final textSpan = TextSpan(
        text: band['label'],
        style: TextStyle(
          color: (band['color'] as Color).withOpacity(isDarkMode ? 0.7 : 0.8),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          fontFamily: 'NotoSansSC',
        ),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(startX + 12, 12));

      startX = endX;
    }

    // --- Y轴时间刻度系统 ---
    const double maxY = 200.0;
    const double minY = -5.0;
    final tickDays = [-5, 0, 7, 15, 30, 45, 60, 90, 120, 150, 180, 200];
    
    final tickPaint = Paint()
      ..color = isDarkMode ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.12)
      ..strokeWidth = 0.8;
    
    for (var day in tickDays) {
      double normalizedY = (day - minY) / (maxY - minY);
      double y = size.height * normalizedY.clamp(0.0, 1.0);
      
      // 画虚线/细线
      canvas.drawLine(Offset(0, y), Offset(size.width, y), tickPaint);
      
      // 画刻度文本
      String label = day == 0 ? '今天' : (day < 0 ? '超期' : '$day天');
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: isDarkMode ? Colors.white54 : Colors.black45,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y - 12));
    }
  }




  Color _getColor(CloudPoint p) {
    if (p.yValue < 0) return Colors.red;
    switch (p.state) {
      case 0: return Colors.blue;
      case 1: return Colors.green;
      case 2: return Colors.orange;
      case 3: return Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  bool shouldRepaint(covariant CloudPainter oldDelegate) => true;
}
