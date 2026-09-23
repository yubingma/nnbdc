import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';
import '../../../state.dart';
import '../../../theme/app_theme.dart';
import '../word_list_actions.dart';

/// 单词卡片在组内的位置（用于聚合岛设计：首项上圆角、中间直角、尾项下圆角，上下紧凑无缝）
enum GroupCardPosition {
  single, // 独立卡片（全圆角）
  top,    // 组首卡片（上圆角，无下边距）
  middle, // 组中卡片（全直角，无上下边距）
  bottom, // 组尾卡片（下圆角，无上边距）
}

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

  /// 整行自定义内容（如词根组头行）：非空时取代「序号 + 单词/释义」三段布局，
  /// 仍复用同一套卡片外观、分组圆角与组间分割线。
  final Widget? headerContent;

  /// 覆盖卡片外边距（null = 按 [groupPosition] 推导）。
  /// 用于「组头 + 族首词共处一张卡」：组头需要 bottom:0 才能与首词无缝相接。
  final EdgeInsets? cardMarginOverride;

  final List<Widget> slidableActions;
  final GroupCardPosition groupPosition;

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
    this.headerContent,
    this.cardMarginOverride,
    required this.slidableActions,
    this.groupPosition = GroupCardPosition.single,
  });

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final accentColor = themeConfig.primaryColor;

    // 选中时赋予 4%~5% 的极淡通透主题微光底色，未选中时保持纯白/卡片底色
    final cardBg = isDarkMode
        ? (isBookmarked
            ? Color.alphaBlend(accentColor.withValues(alpha: 0.12), context.cardBg)
            : context.cardBg)
        : (isBookmarked
            ? Color.alphaBlend(accentColor.withValues(alpha: 0.045), context.cardBg)
            : context.cardBg);

    // 选中时使用精致半透的主题微边框 (1.2px)，未选中时为极淡边框
    final borderColor = isBookmarked
        ? accentColor.withValues(alpha: isDarkMode ? 0.6 : 0.45)
        : themeConfig.cardBorder;

    // 组头（headerContent）与族首词共处一张卡，自身不投影 —— 否则两者接缝处
    // 两道阴影叠加，视觉上就是「两张卡被切开」，即使外边距已经相接。
    // 选中收藏：保留精致半透主题微光投影；未选中：统一卡片阴影(随透明度联动, 深色不拖黑影)
    final cardShadow = headerContent != null
        ? const <BoxShadow>[]
        : isBookmarked
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: isDarkMode ? 0.25 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 3),
                ),
                context.cardShadow,
              ]
            : [context.cardShadow];

    final borderRadius = switch (groupPosition) {
      GroupCardPosition.single => BorderRadius.circular(16),
      GroupCardPosition.top => const BorderRadius.vertical(top: Radius.circular(16)),
      GroupCardPosition.middle => BorderRadius.zero,
      GroupCardPosition.bottom => const BorderRadius.vertical(bottom: Radius.circular(16)),
    };

    final clipRadius = switch (groupPosition) {
      GroupCardPosition.single => BorderRadius.circular(15),
      GroupCardPosition.top => const BorderRadius.vertical(top: Radius.circular(15)),
      GroupCardPosition.middle => BorderRadius.zero,
      GroupCardPosition.bottom => const BorderRadius.vertical(bottom: Radius.circular(15)),
    };

    final cardMargin = cardMarginOverride ??
        switch (groupPosition) {
          GroupCardPosition.single => const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          GroupCardPosition.top => const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 0),
          GroupCardPosition.middle => const EdgeInsets.symmetric(horizontal: 10),
          GroupCardPosition.bottom => const EdgeInsets.only(left: 10, right: 10, top: 0, bottom: 4),
        };

    final borderSide = BorderSide(
      color: borderColor,
      width: isBookmarked ? 1.2 : 1.0,
    );

    final border = switch (groupPosition) {
      GroupCardPosition.single => Border.all(
          color: borderColor,
          width: isBookmarked ? 1.2 : 1.0,
        ),
      GroupCardPosition.top => Border(
          top: borderSide,
          left: borderSide,
          right: borderSide,
        ),
      GroupCardPosition.middle => Border(
          left: borderSide,
          right: borderSide,
        ),
      GroupCardPosition.bottom => Border(
          top: BorderSide.none,
          left: borderSide,
          right: borderSide,
          bottom: borderSide,
        ),
    };

    Widget itemContent = Container(
      margin: cardMargin,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: borderRadius,
        border: border,
        boxShadow: cardShadow,
      ),
      child: ClipRRect(
        borderRadius: clipRadius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headerContent != null)
              headerContent!
            else
              IntrinsicHeight(
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
            // 组内分隔线只画在「词与词之间」。
            // 组头（headerContent != null）传的正是 top 位置，若按位置画线会画在
            // 组头下缘，把「组头 + 族首词」这张卡切成两半。
            // 首词用 bottom 位置（紧随组头），它下面若还有词也不需要线。
            if (headerContent == null && groupPosition != GroupCardPosition.bottom)
              Container(
                height: 0.8,
                margin: const EdgeInsets.only(left: 44, right: 14),
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
          ],
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => actions.onWordTap(word, index),
      onLongPress: () => actions.onWordLongPress(word, index),
      child: Container(
        width: 44,
        color: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 环形熟练度微光环徽章（选中时实心高亮）
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

  /// 环形熟练度光环徽章（未选中为空心圆环，选中时为实心高亮微光圆盘）
  Widget _buildRingMasteryBadge(AppThemeConfig themeConfig) {
    final accentColor = themeConfig.primaryColor;

    // 选中态：实心主题色圆盘 + 白色加粗数字 + 精致微发光微投影（方案一核心）
    if (isBookmarked) {
      return Container(
        width: 25,
        height: 25,
        decoration: BoxDecoration(
          color: accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: isDarkMode ? 0.45 : 0.35),
              blurRadius: 6,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '${baseIndex + index + 1}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: (baseIndex + index + 1) >= 1000 ? 7.5 : ((baseIndex + index + 1) >= 100 ? 8.5 : 9.5),
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFamily: 'Roboto',
          ),
        ),
      );
    }

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

    final trackColor = isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.06);

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
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: (baseIndex + index + 1) >= 1000 ? 7.5 : ((baseIndex + index + 1) >= 100 ? 8.5 : 9.5),
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: themeConfig.textPrimary,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }
}

