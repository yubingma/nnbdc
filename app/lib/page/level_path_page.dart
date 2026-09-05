import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/level_util.dart';

class LevelPathPage extends StatefulWidget {
  final int currentLevel;
  final int? masteredWords;

  const LevelPathPage({
    super.key,
    required this.currentLevel,
    this.masteredWords,
  });

  @override
  State<LevelPathPage> createState() => _LevelPathPageState();
}

class _LevelPathPageState extends State<LevelPathPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 自动滚动到当前等级位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetIndex = widget.currentLevel.clamp(0, LevelUtil.allLevels.length - 1);
      if (targetIndex > 1) {
        final offset = (targetIndex - 1) * 115.0;
        _scrollController.animateTo(
          offset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;
    final textColor = themeConfig.textPrimary;
    final subTextColor = themeConfig.textSecondary;
    final primaryColor = themeConfig.primaryColor;
    final cardBg = themeConfig.cardBg;
    final levels = LevelUtil.allLevels;

    final currentLevelObj = LevelUtil.getTitle(widget.currentLevel);
    final nextLevelIndex = widget.currentLevel + 1;
    final nextLevelObj = nextLevelIndex < levels.length ? levels[nextLevelIndex] : null;

    return AppScaffold(
      appBar: AppBar(
        title: Text(
          '成长之路',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // 顶部当前段位概览卡片
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _buildHeaderCard(
                themeConfig: themeConfig,
                isDarkMode: isDarkMode,
                textColor: textColor,
                subTextColor: subTextColor,
                primaryColor: primaryColor,
                cardBg: cardBg,
                currentLevelObj: currentLevelObj,
                nextLevelObj: nextLevelObj,
                totalLevels: levels.length,
              ),
            ),
          ),
          // 时间轴路径列表
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final level = levels[index];
                  final isReached = level.level <= widget.currentLevel;
                  final isCurrent = level.level == widget.currentLevel;
                  final isFirst = index == 0;
                  final isLast = index == levels.length - 1;

                  return _TimelineNodeItem(
                    level: level,
                    isReached: isReached,
                    isCurrent: isCurrent,
                    isFirst: isFirst,
                    isLast: isLast,
                    themeConfig: themeConfig,
                    isDarkMode: isDarkMode,
                    textColor: textColor,
                    subTextColor: subTextColor,
                    primaryColor: primaryColor,
                    cardBg: cardBg,
                  );
                },
                childCount: levels.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard({
    required AppThemeConfig themeConfig,
    required bool isDarkMode,
    required Color textColor,
    required Color subTextColor,
    required Color primaryColor,
    required Color cardBg,
    required Level currentLevelObj,
    required Level? nextLevelObj,
    required int totalLevels,
  }) {
    // 计算升至下一级所需词数进度
    double? progress;
    int? wordsToNext;
    if (widget.masteredWords != null && nextLevelObj != null) {
      final currentBase = currentLevelObj.minWords;
      final target = nextLevelObj.minWords;
      final range = target - currentBase;
      if (range > 0) {
        final currentInLevel = widget.masteredWords! - currentBase;
        progress = (currentInLevel / range).clamp(0.0, 1.0);
        wordsToNext = (target - widget.masteredWords!).clamp(0, target);
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: isDarkMode ? Border.all(color: themeConfig.cardBorder, width: 0.8) : null,
        boxShadow: themeConfig.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                currentLevelObj.icon,
                style: const TextStyle(fontSize: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          currentLevelObj.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'LV.${currentLevelObj.level}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已达成 ${(widget.currentLevel + 1)} / $totalLevels 个段位',
                      style: TextStyle(
                        fontSize: 12,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.masteredWords != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${widget.masteredWords}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      '已掌握词汇',
                      style: TextStyle(
                        fontSize: 11,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (progress != null && nextLevelObj != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: primaryColor.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '距下一级「${nextLevelObj.name}」',
                  style: TextStyle(fontSize: 11, color: subTextColor),
                ),
                Text(
                  wordsToNext == 0 ? '即将晋升' : '还需掌握 $wordsToNext 词',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineNodeItem extends StatelessWidget {
  final Level level;
  final bool isReached;
  final bool isCurrent;
  final bool isFirst;
  final bool isLast;
  final AppThemeConfig themeConfig;
  final bool isDarkMode;
  final Color textColor;
  final Color subTextColor;
  final Color primaryColor;
  final Color cardBg;

  const _TimelineNodeItem({
    required this.level,
    required this.isReached,
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
    required this.themeConfig,
    required this.isDarkMode,
    required this.textColor,
    required this.subTextColor,
    required this.primaryColor,
    required this.cardBg,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor = isReached
        ? primaryColor.withValues(alpha: 0.28)
        : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧轨道线与指示器
          SizedBox(
            width: 28,
            child: Column(
              children: [
                // 上半截线
                Expanded(
                  child: isFirst
                      ? const SizedBox.shrink()
                      : Center(
                          child: Container(
                            width: 2,
                            color: lineColor,
                          ),
                        ),
                ),
                // 节点指示器
                _buildIndicator(),
                // 下半截线
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Center(
                          child: Container(
                            width: 2,
                            color: lineColor,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 右侧等级卡片
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _buildCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator() {
    if (isCurrent) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: primaryColor,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    if (isReached) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.75),
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard() {
    final border = isCurrent
        ? Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1.2)
        : (isDarkMode ? Border.all(color: themeConfig.cardBorder, width: 0.8) : null);

    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: border,
        boxShadow: themeConfig.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                level.icon,
                style: const TextStyle(fontSize: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          level.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LV.${level.level}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isReached ? primaryColor : subTextColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.maxWords > 1000000
                          ? '≥ ${level.minWords} 词'
                          : '${level.minWords} - ${level.maxWords} 词',
                      style: TextStyle(
                        fontSize: 12,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '当前段位',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (!isReached)
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: subTextColor.withValues(alpha: 0.5),
                ),
            ],
          ),
          if (level.quotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '“${level.quotes[0]}”',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isReached ? textColor.withValues(alpha: 0.72) : subTextColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );

    if (!isReached) {
      return Opacity(
        opacity: 0.55,
        child: cardContent,
      );
    }

    return cardContent;
  }
}
