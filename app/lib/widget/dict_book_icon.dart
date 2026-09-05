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

/// 统一自主绘制词书图标组件
///
/// 视觉原则：
/// 1. 100% 统一的书本基底：以经典的展开书卷形态（Open Book）为绝对核心视觉，
///    确保所有词书在列表中呈现完全一致的比例、视重与庄重感（“大家都是词书”）。
/// 2. 克制优雅的微差异印记：通过右下角微型手写笔、顶端垂落书签带或通关微勾，
///    在保证视觉和谐的同时清晰区分“只读系统词书”与“可编辑自建词书/生词本”。
class DictBookIcon extends StatelessWidget {
  final DictBookType type;
  final double size;
  final Color? color;
  final Color? badgeBackgroundColor;

  const DictBookIcon({
    super.key,
    required this.type,
    this.size = 22.0,
    this.color,
    this.badgeBackgroundColor,
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
    Color? badgeBackgroundColor,
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
      badgeBackgroundColor: badgeBackgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = badgeBackgroundColor ?? theme.cardColor;

    // 计算语义主色
    final Color effectiveColor = color ??
        switch (type) {
          DictBookType.rawBook => const Color(0xFFF59E0B), // 暖金色
          DictBookType.masteredBook => const Color(0xFF10B981), // 通关翡翠绿
          _ => theme.primaryColor,
        };

    // 核心基底：100% 统一展开书卷
    final baseBook = Icon(
      Icons.auto_stories_rounded,
      size: size,
      color: effectiveColor,
    );

    // 官方只读词书直接返回纯净书卷
    if (type == DictBookType.systemReadOnly) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: baseBook),
      );
    }

    final badgeSize = (size * 0.52).clamp(10.0, 16.0);
    final iconSize = badgeSize * 0.65;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          baseBook,

          // 生词本：正上方/中缝垂下一条优雅的燕尾书签带 (Bookmark Ribbon)
          if (type == DictBookType.rawBook)
            Positioned(
              top: -size * 0.05,
              right: size * 0.12,
              child: CustomPaint(
                size: Size(size * 0.32, size * 0.48),
                painter: _BookmarkRibbonPainter(
                  color: const Color(0xFFF59E0B),
                  borderColor: bgColor,
                ),
              ),
            ),

          // 用户自建/可编辑词书：右下角微型手写笔圆标 (圆润镂空背景 + 编辑笔)
          if (type == DictBookType.customEditable)
            Positioned(
              right: -size * 0.08,
              bottom: -size * 0.06,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.edit_rounded,
                    size: iconSize,
                    color: effectiveColor,
                  ),
                ),
              ),
            ),

          // 已掌握词书：右下角微型对勾圆标 (翡翠绿勾)
          if (type == DictBookType.masteredBook)
            Positioned(
              right: -size * 0.08,
              bottom: -size * 0.06,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.check_rounded,
                    size: iconSize,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 绘制垂落燕尾书签带
class _BookmarkRibbonPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _BookmarkRibbonPainter({
    required this.color,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h * 0.72)
      ..lineTo(0, h)
      ..close();

    // 填充底色
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 绘制微弱高光边框（使书签更立体精致）
    final borderPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.85)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _BookmarkRibbonPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderColor != borderColor;
  }
}
