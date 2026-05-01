import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import '../word_list_actions.dart';

/// 单词列表项的通用布局外壳，处理 Slidable 和左侧边栏
class WordListItemLayout extends StatelessWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final WordListStudyMode studyMode;
  final bool isBookmarked;
  final bool isDarkMode;
  final bool? learningStatus;
  final bool showWordProgress;
  final WordListActionHandler actions;
  final Widget? centerContent;
  final Widget? rightContent;
  final Widget? audioIndicator;
  final List<SlidableAction> slidableActions;

  const WordListItemLayout({
    super.key,
    required this.word,
    required this.index,
    required this.baseIndex,
    required this.studyMode,
    required this.isBookmarked,
    required this.isDarkMode,
    required this.learningStatus,
    required this.showWordProgress,
    required this.actions,
    this.centerContent,
    this.rightContent,
    this.audioIndicator,
    required this.slidableActions,
  });

  @override
  Widget build(BuildContext context) {
    // 确定背景色
    final bgColor = isDarkMode
        ? (isBookmarked ? const Color(0xFF12353A) : const Color(0xFF1E1E1E))
        : (isBookmarked ? const Color(0xFFE0F2F1) : Colors.white);

    // 获取状态颜色
    Color? statusColor;
    if (learningStatus == true) {
      statusColor = const Color(0xFF4CAF50);
    } else if (learningStatus == false) {
      statusColor = Colors.orange;
    }

    Widget itemContent = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: bgColor,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /// 1. 左侧序号和点
              _buildLeftColumn(statusColor),

              /// 2. 中间和右侧内容
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (centerContent != null) Expanded(flex: 2, child: centerContent!),
                    if (rightContent != null) Expanded(flex: 3, child: rightContent!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (slidableActions.isEmpty) return itemContent;

    return Slidable(
      key: ValueKey('slidable_${word.word.id}'),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: (0.25 * slidableActions.length).clamp(0.0, 0.75),
        children: slidableActions,
      ),
      child: itemContent,
    );
  }

  Widget _buildLeftColumn(Color? statusColor) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => actions.onWordTap(word, index),
      onLongPress: () => actions.onWordLongPress(word, index),
      child: Container(
        width: 32,
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.15)
            : const Color(0xFFE2E8F0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${baseIndex + index + 1}',
                textScaler: const TextScaler.linear(1.0),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 3),
              if (statusColor != null)
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              if (showWordProgress)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildWordProgress(width: 22),
                ),
              if (audioIndicator != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: audioIndicator!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordProgress({required double width}) {
    // 进度计算逻辑修正
    final double current = word.currentProgress ?? 0;
    final double max = word.maxProgress ?? 100;
    final progress = (current / max).clamp(0.0, 1.0);
    
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(1),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF4DB6AC),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
