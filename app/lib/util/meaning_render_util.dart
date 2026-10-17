import 'package:flutter/material.dart';
import '../api/vo.dart';

/// 单词释义与常用度圆点渲染工具
class MeaningRenderUtil {
  /// 阶梯默认百分比（当数据中 popularityPercent 缺失时根据排序名次平滑兜底）
  static int defaultPercentForRank(int rank, int total) {
    if (total <= 1) return 100;
    if (rank == 0) return 65;
    if (rank == 1) return 25;
    if (rank == 2) return 10;
    return 5;
  }

  /// 根据常用度百分比计算小圆点的规格（直径与不透明度）
  /// - 核心高频（>=60%）：直径 6.0px，高对比
  /// - 常用（25%~59%）：直径 4.5px
  /// - 次要（5%~24%）：直径 3.2px，浅灰
  /// - 生僻（<5%）：直径 2.2px，微弱透显
  static ({double size, double opacity}) getDotSpec(int? percent) {
    final pct = percent ?? 0;
    if (pct >= 60) {
      return (size: 6.0, opacity: 0.88);
    } else if (pct >= 25) {
      return (size: 4.5, opacity: 0.65);
    } else if (pct >= 5) {
      return (size: 3.2, opacity: 0.45);
    } else {
      return (size: 2.2, opacity: 0.28);
    }
  }

  /// 构建单行或流式行内的小圆点 InlineSpan
  static InlineSpan buildDotSpan({
    required int? percent,
    required Color color,
    bool isLastInLine = false,
  }) {
    final spec = getDotSpec(percent);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.only(
          left: 4.0,
          right: isLastInLine ? 0.0 : 7.0,
        ),
        child: Container(
          width: spec.size,
          height: spec.size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: spec.opacity),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  /// 判断该单词所有释义项是否构成多释义（总义项数 >= 2）
  static bool hasMultipleMeanings(List<MeaningItemVo> items) {
    int totalCount = 0;
    for (final item in items) {
      if (item.parts != null && item.parts!.isNotEmpty) {
        totalCount += item.parts!.length;
      } else if ((item.meaning ?? '').trim().isNotEmpty) {
        final count = item.meaning!
            .split(RegExp(r'[;；]'))
            .where((s) => s.trim().isNotEmpty)
            .length;
        totalCount += (count > 0 ? count : 1);
      }
      if (totalCount >= 2) return true;
    }
    return false;
  }

  /// 为一个 MeaningItemVo 构建其释义文本及小圆点的 InlineSpan 列表
  /// [showDots]: 是否展示小圆点（单释义时传 false，多释义时传 true）
  static List<InlineSpan> buildMeaningSpans({
    required MeaningItemVo item,
    required TextStyle meaningStyle,
    required Color dotColor,
    required bool showDots,
  }) {
    List<MeaningPartVo> parts = item.parts != null ? List.from(item.parts!) : [];
    if (parts.isEmpty && (item.meaning ?? '').isNotEmpty) {
      final rawTokens = item.meaning!.split(RegExp(r'[;；]'));
      int rank = 0;
      for (final raw in rawTokens) {
        var trimmed = raw.trim();
        while (trimmed.endsWith(';') ||
            trimmed.endsWith('；') ||
            trimmed.endsWith(',') ||
            trimmed.endsWith('，') ||
            trimmed.endsWith('。')) {
          trimmed = trimmed.substring(0, trimmed.length - 1).trim();
        }
        if (trimmed.isNotEmpty) {
          final pct = item.popularityPercent ??
              defaultPercentForRank(rank, rawTokens.length);
          parts.add(MeaningPartVo(trimmed, pct));
          rank++;
        }
      }
    }

    if (parts.isEmpty) {
      return [TextSpan(text: '', style: meaningStyle)];
    }

    final spans = <InlineSpan>[];
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;

      // 清理释义文本内部尾部标点
      var cleanText = part.text.trim();
      while (cleanText.endsWith(';') ||
          cleanText.endsWith('；') ||
          cleanText.endsWith(',') ||
          cleanText.endsWith('，') ||
          cleanText.endsWith('。')) {
        cleanText = cleanText.substring(0, cleanText.length - 1).trim();
      }

      spans.add(TextSpan(
        text: cleanText,
        style: meaningStyle,
      ));

      if (showDots) {
        spans.add(buildDotSpan(
          percent: part.popularityPercent,
          color: dotColor,
          isLastInLine: isLast,
        ));
      } else if (!isLast) {
        spans.add(TextSpan(
          text: '；',
          style: meaningStyle,
        ));
      }
    }

    return spans;
  }

  /// 为一行流式展示（如单词列表卡片、随身听等）构建包含词性与常用度圆点的 InlineSpan 列表
  static List<InlineSpan> buildInlineMeaningSpans({
    required WordVo word,
    required TextStyle meaningStyle,
    required TextStyle posStyle,
    required Color dotColor,
  }) {
    final mergedItems = word.getMergedMeaningItems();
    if (mergedItems.isEmpty) {
      final meaningStr = word.getMeaningStr();
      return [
        TextSpan(
          text: meaningStr.isNotEmpty ? meaningStr : "（暂无释义）",
          style: meaningStyle,
        )
      ];
    }

    final showDots = hasMultipleMeanings(mergedItems);
    final spans = <InlineSpan>[];

    for (int i = 0; i < mergedItems.length; i++) {
      final item = mergedItems[i];
      final ciXing = (item.ciXing ?? '').trim();
      if (ciXing.isNotEmpty) {
        spans.add(TextSpan(
          text: '$ciXing ',
          style: posStyle,
        ));
      }

      final itemSpans = buildMeaningSpans(
        item: item,
        meaningStyle: meaningStyle,
        dotColor: dotColor,
        showDots: showDots,
      );
      spans.addAll(itemSpans);

      if (i < mergedItems.length - 1) {
        spans.add(const TextSpan(text: '  '));
      }
    }

    return spans;
  }
}
