import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';
import '../../../state.dart';
import '../../../theme/app_theme.dart';
import '../word_list_actions.dart';

/// 单词列表项的通用布局外壳，处理 Slidable、卡片与环形熟练度微光环
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
  final List<Widget> slidableActions;

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
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final accentColor = themeConfig.primaryColor;

    final cardBg = isDarkMode
        ? (isBookmarked ? accentColor.withValues(alpha: 0.18) : themeConfig.cardBg)
        : (isBookmarked ? accentColor.withValues(alpha: 0.08) : Colors.white);

    final borderColor = isBookmarked ? accentColor : themeConfig.cardBorder;

    final cardShadow = isBookmarked
        ? [
            BoxShadow(
              color: accentColor.withValues(alpha: isDarkMode ? 0.25 : 0.16),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ]
        : themeConfig.cardShadows;

    Widget itemContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: isBookmarked ? 1.6 : 1.0,
        ),
        boxShadow: cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /// 1. 左侧序号与环形掌握度光环徽章
              _buildLeftColumn(themeConfig),

              /// 2. 中间和右侧单词释义与交互内容
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (centerContent != null && rightContent != null) ...[
                      Expanded(flex: 2, child: centerContent!),
                      Expanded(flex: 3, child: rightContent!),
                    ] else if (centerContent != null) ...[
                      Expanded(child: centerContent!),
                    ] else if (rightContent != null) ...[
                      Expanded(child: rightContent!),
                    ],
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

  Widget _buildLeftColumn(AppThemeConfig themeConfig) {
    final accentColor = themeConfig.primaryColor;
    final sidebarBg = isDarkMode
        ? (isBookmarked ? accentColor.withValues(alpha: 0.22) : themeConfig.subtleBg)
        : (isBookmarked ? accentColor.withValues(alpha: 0.12) : const Color(0xFFF7FBF9));

    final dividerColor = themeConfig.cardBorder;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => actions.onWordTap(word, index),
      onLongPress: () => actions.onWordLongPress(word, index),
      child: Container(
        width: 44,
        decoration: BoxDecoration(
          color: sidebarBg,
          border: Border(
            right: BorderSide(color: dividerColor, width: 1),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 环形熟练度微光环徽章（序号 + 熟练度光环二合一）
              _buildRingMasteryBadge(themeConfig),
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

  /// 环形熟练度光环徽章
  Widget _buildRingMasteryBadge(AppThemeConfig themeConfig) {
    final double current = word.currentProgress ?? 0;
    final double max = word.maxProgress ?? 100;
    double progressRatio = 0.0;

    if (showWordProgress && max > 0) {
      progressRatio = (current / max).clamp(0.0, 1.0);
    } else if (learningStatus == true) {
      progressRatio = 1.0;
    } else if (learningStatus == false) {
      progressRatio = 0.5;
    }

    final accentColor = themeConfig.primaryColor;
    final trackColor = isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06);

    final numColor = isBookmarked
        ? accentColor
        : themeConfig.textPrimary;

    return SizedBox(
      width: 25,
      height: 25,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 环形外弧
          if (progressRatio > 0)
            CircularProgressIndicator(
              value: progressRatio,
              strokeWidth: 2.2,
              backgroundColor: trackColor,
              valueColor: AlwaysStoppedAnimation(
                progressRatio >= 1.0
                    ? accentColor
                    : accentColor.withValues(alpha: 0.7),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: trackColor, width: 1.5),
              ),
            ),

          // 中心序号
          Text(
            '${baseIndex + index + 1}',
            textScaler: const TextScaler.linear(1.0),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: (baseIndex + index + 1) >= 1000 ? 7.5 : ((baseIndex + index + 1) >= 100 ? 8.5 : 9.5),
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: numColor,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }
}

