import 'package:flutter/material.dart';
import 'package:nnbdc/util/utils.dart';

/// 词书类型语义定义
enum DictBookType {
  /// 官方系统词书（不可编辑，只读权威教材）
  systemReadOnly,

  /// 用户自建词书（可编辑，支持单词与释义增删改）
  customEditable,

  /// 生词本（可编辑，阅读查词标记，专属暖金带签）
  rawBook,

  /// 已掌握（可编辑，完全掌握高频词，专属翡翠绿带勾）
  masteredBook,
}

/// 统一自主绘制精装立式小册词书图标组件 (Classic Book Series)
///
/// 视觉原则：
/// 1. 100% 统一的精装口袋书基底：以经典的立式圆角精装书壳（Classic Pocket Book）为核心视觉，
///    左侧带有暗影书脊压痕，保证列表中每本词书拥有完全一致的比例、体量与稳重感（“大家都是词书”）。
/// 2. 克制优雅的微差异印记：
///    - 官方只读词书：双白色排版横线，典雅工整；
///    - 用户自建词书：单横线 + 右下角斜插精致手写铅笔，传达“自建手记”；
///    - 生词本：顶端垂挂暖金燕尾书签带（Bookmark Ribbon）；
///    - 已掌握：通关翡翠绿硬壳 + 白色微对勾。
class DictBookIcon extends StatelessWidget {
  final DictBookType type;
  final double size;
  final Color? color;

  const DictBookIcon({
    super.key,
    required this.type,
    this.size = 22.0,
    this.color,
  });

  /// 解析词书对应的语义类型
  static DictBookType resolveType({
    bool? editable,
    required String? ownerId,
    required String name,
  }) {
    if (name == '生词本') {
      return DictBookType.rawBook;
    }
    if (name == '已掌握') {
      return DictBookType.masteredBook;
    }
    if (Util.isEditableDict(editable: editable, ownerId: ownerId, name: name)) {
      return DictBookType.customEditable;
    }
    return DictBookType.systemReadOnly;
  }

  /// 根据词书属性自适应构建
  factory DictBookIcon.fromDict({
    Key? key,
    bool? editable,
    required String? ownerId,
    required String name,
    double size = 22.0,
    Color? color,
  }) {
    final type = resolveType(
      editable: editable,
      ownerId: ownerId,
      name: name,
    );
    return DictBookIcon(
      key: key,
      type: type,
      size: size,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 计算语义主色
    final Color effectiveColor = color ??
        switch (type) {
          DictBookType.masteredBook => const Color(0xFF10B981), // 通关翡翠绿
          _ => theme.primaryColor,
        };

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _ClassicBookPainter(
          type: type,
          color: effectiveColor,
        ),
      ),
    );
  }
}

/// 纯矢量自主绘制精装立式小册
class _ClassicBookPainter extends CustomPainter {
  final DictBookType type;
  final Color color;

  _ClassicBookPainter({
    required this.type,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;

    // 1. 书本封面 (圆角矩形精装硬壳)
    final coverRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4.5 * scale, 3.5 * scale, 15.0 * scale, 17.0 * scale),
      Radius.circular(3.0 * scale),
    );
    final coverPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(coverRRect, coverPaint);

    // 2. 左侧书脊暗影压痕 (左侧带同比例圆角，右侧直角)
    final spineRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(4.5 * scale, 3.5 * scale, 3.0 * scale, 17.0 * scale),
      topLeft: Radius.circular(3.0 * scale),
      bottomLeft: Radius.circular(3.0 * scale),
    );
    final spinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(spineRRect, spinePaint);

    // 3. 生词本：顶端垂挂暖金燕尾书签带 (Bookmark Ribbon)
    if (type == DictBookType.rawBook) {
      final ribbonPath = Path()
        ..moveTo(13.0 * scale, 2.0 * scale)
        ..lineTo(16.5 * scale, 2.0 * scale)
        ..lineTo(16.5 * scale, 10.5 * scale)
        ..lineTo(14.75 * scale, 9.0 * scale)
        ..lineTo(13.0 * scale, 10.5 * scale)
        ..close();
      final ribbonPaint = Paint()
        ..color = const Color(0xFFF59E0B) // 暖金书签
        ..style = PaintingStyle.fill;
      canvas.drawPath(ribbonPath, ribbonPaint);
    }

    // 4. 白色封面排版线 (Ruled Lines)
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (type == DictBookType.systemReadOnly) {
      // 官方系统词书：双排版横线
      canvas.drawLine(
        Offset(11.0 * scale, 8.0 * scale),
        Offset(16.5 * scale, 8.0 * scale),
        linePaint,
      );
      canvas.drawLine(
        Offset(11.0 * scale, 12.0 * scale),
        Offset(14.5 * scale, 12.0 * scale),
        linePaint,
      );
    } else if (type == DictBookType.rawBook) {
      // 生词本：避开上方书签，下方一条横线
      canvas.drawLine(
        Offset(10.5 * scale, 14.0 * scale),
        Offset(14.5 * scale, 14.0 * scale),
        linePaint,
      );
    } else if (type == DictBookType.customEditable) {
      // 自建可编辑词书：上方一条短横线
      canvas.drawLine(
        Offset(11.0 * scale, 8.0 * scale),
        Offset(15.0 * scale, 8.0 * scale),
        linePaint,
      );

      // 右下角斜插 45° 手写笔 (白底笔身 + 亮蓝笔帽)
      final penBodyPath = Path()
        ..moveTo(18.8 * scale, 14.2 * scale)
        ..lineTo(14.2 * scale, 18.8 * scale)
        ..lineTo(14.2 * scale, 20.5 * scale)
        ..lineTo(15.9 * scale, 20.5 * scale)
        ..lineTo(20.5 * scale, 15.9 * scale)
        ..close();
      final penBodyPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawPath(penBodyPath, penBodyPaint);

      final penCapPath = Path()
        ..moveTo(21.2 * scale, 15.2 * scale)
        ..lineTo(20.5 * scale, 15.9 * scale)
        ..lineTo(18.8 * scale, 14.2 * scale)
        ..lineTo(19.5 * scale, 13.5 * scale)
        ..arcToPoint(
          Offset(21.2 * scale, 15.2 * scale),
          radius: Radius.circular(1.2 * scale),
          clockwise: true,
        )
        ..close();
      final penCapPaint = Paint()
        ..color = const Color(0xFF38BDF8) // 亮天蓝笔头
        ..style = PaintingStyle.fill;
      canvas.drawPath(penCapPath, penCapPaint);
    } else if (type == DictBookType.masteredBook) {
      // 已掌握词书：上方一条横线 + 右下角白色微对勾
      canvas.drawLine(
        Offset(11.0 * scale, 8.0 * scale),
        Offset(15.0 * scale, 8.0 * scale),
        linePaint,
      );

      final checkPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.8 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final checkPath = Path()
        ..moveTo(14.0 * scale, 15.5 * scale)
        ..lineTo(16.0 * scale, 17.5 * scale)
        ..lineTo(20.0 * scale, 13.0 * scale);
      canvas.drawPath(checkPath, checkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClassicBookPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
