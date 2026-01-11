import 'package:flutter/material.dart';
import 'package:nnbdc/util/level_util.dart';


class LevelPathPage extends StatelessWidget {
  final int currentLevel;

  const LevelPathPage({super.key, required this.currentLevel});

  @override
  Widget build(BuildContext context) {
    final levels = LevelUtil.allLevels;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FBF8),
      appBar: AppBar(
        title: const Text('成长之路'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // 背景路径装饰 (简单的曲线效果)
          CustomPaint(
            size: Size(MediaQuery.of(context).size.width, double.infinity),
            painter: PathPainter(),
          ),
          ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            itemCount: levels.length,
            itemBuilder: (context, index) {
              final level = levels[index];
              final isReached = level.level <= currentLevel;
              final isCurrent = level.level == currentLevel;
              
              // 左右交替布局
              final isLeft = index % 2 == 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
                  children: [
                    if (!isLeft) const Spacer(),
                    _LevelNode(
                      level: level,
                      isReached: isReached,
                      isCurrent: isCurrent,
                    ),
                    if (isLeft) const Spacer(),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LevelNode extends StatelessWidget {
  final Level level;
  final bool isReached;
  final bool isCurrent;

  const _LevelNode({
    required this.level,
    required this.isReached,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isReached ? level.color : Colors.grey.shade300,
          width: isCurrent ? 3 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isReached ? level.color : Colors.grey).withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: (isReached ? level.color : Colors.grey.shade100).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  level.icon,
                  style: TextStyle(
                    fontSize: 28,
                    color: isReached ? null : Colors.grey.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isReached ? Colors.black87 : Colors.grey,
                      ),
                    ),
                    Text(
                      'LV.${level.level} | ${level.minScore} 积分',
                      style: TextStyle(
                        fontSize: 12,
                        color: isReached ? Colors.grey.shade600 : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: level.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '当前',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            decoration: BoxDecoration(
              color: (isReached ? level.color : Colors.grey.shade50).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '“${level.quotes[0]}”',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: isReached ? Colors.black54 : Colors.grey.shade400,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    final path = Path();
    double y = 80; // 起始高度偏移
    const double stepY = 135; // 节点垂直间距 ( Padding(10)+Row(node_height)+Padding(10) )
    
    path.moveTo(size.width * 0.5, 0);
    path.lineTo(size.width * 0.5, y);

    for (int i = 0; i < LevelUtil.allLevels.length; i++) {
      final isLeft = i % 2 == 0;
      final nextY = y + stepY;
      
      if (isLeft) {
        // 当前在左，下一个在右（或者第一个就在左）
        path.quadraticBezierTo(
          size.width * 0.2, y + stepY * 0.5,
          size.width * 0.5, nextY,
        );
      } else {
        // 当前在右，下一个在左
        path.quadraticBezierTo(
          size.width * 0.8, y + stepY * 0.5,
          size.width * 0.5, nextY,
        );
      }
      y = nextY;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
