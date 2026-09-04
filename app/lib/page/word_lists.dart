import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/confusable_words.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';
import 'package:nnbdc/page/word_list/learning_words.dart';
import 'package:nnbdc/page/word_list/mastered_words.dart';
import 'package:nnbdc/page/word_list/today_new_words.dart';
import 'package:nnbdc/page/word_list/today_old_words.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/page/word_list/wrong_words.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../api/vo.dart';
import '../state.dart';
import 'package:nnbdc/event/events.dart';
import '../global.dart';

class WordListsPage extends StatefulWidget {
  const WordListsPage({super.key});

  @override
  State<StatefulWidget> createState() => WordListsPageState();
}

class WordListsPageState extends State<WordListsPage> implements RefreshableTab {
  static WordListsPageState? instance;
  bool dataLoaded = false;
  List<WordList> wordLists = [];
  List<Dict> deskDicts = [];
  Map<String, int> deskDictMasteredCounts = {};
  Map<String, int> deskDictLearningCounts = {};
  bool _isDirty = false;
  StreamSubscription? _subscription;
  StreamSubscription? _dictDownloadSub;
  StreamSubscription? _learningDictChangedSub;

  @override
  bool get isDirty => _isDirty;

  @override
  void refreshData() {
    Global.logger.d('[RefreshableTab] 词表页收到 refreshData() 指令，开始刷新');
    loadData();
    _isDirty = false;
  }

  @override
  void initState() {
    super.initState();
    instance = this;
    Global.logger.d('[EventBus Debug] WordListsPage initState()');
    loadData();

    // 页面内部自行监听底层错词广播，维护内聚的数据状态
    _subscription = EventBus.onNewWrongWord().listen((event) {
      Global.logger.d('[EventBus Debug] 词表页内部监听到 NewWrongWordEvent, _isDirty = true');
      _isDirty = true;
    });

    // 监听词书下载完成事件，自动刷新书桌
    _dictDownloadSub = EventBus.onDictDownloadCompleted().listen((_) {
      Global.logger.d('[WordLists] 词书下载完成，刷新书桌');
      loadData();
    });

    // 监听书桌词书变化事件（停学/选书），自动刷新书桌
    _learningDictChangedSub = EventBus.onLearningDictChanged().listen((_) {
      Global.logger.d('[WordLists] 书桌词书发生变化，刷新书桌');
      loadData();
    });
  }

  @override
  void dispose() {
    if (instance == this) {
      instance = null;
    }
    _subscription?.cancel();
    _dictDownloadSub?.cancel();
    _learningDictChangedSub?.cancel();
    super.dispose();
  }

  Future<void> loadData() async {
    Global.logger.d('[EventBus Debug] === loadData 开始异步加载数据 ===');
    try {
      final listsResult = await WordBo().getWordLists();
      final lists = listsResult.data ?? [];

      // 加载用户书桌上的词书与已掌握/已取词数
      final user = Global.getLoggedInUser();
      final loadedDeskDicts = <Dict>[];
      final loadedMasteredCounts = <String, int>{};
      final loadedLearningCounts = <String, int>{};
      if (user != null) {
        final db = MyDatabase.instance;
        final learningDicts = await db.learningDictsDao.getLearningDictsOfUser(user.id);
        for (final ld in learningDicts) {
          final d = await db.dictsDao.findById(ld.dictId);
          if (d != null) {
            loadedDeskDicts.add(d);
            try {
              final mCount = await db.masteredWordsDao.getMasteredWordsCountInDicts(user.id, [d.id]);
              loadedMasteredCounts[d.id] = mCount;
            } catch (e, st) {
              Global.logger.w('获取词书 ${d.id} 已掌握词数失败: $e', stackTrace: st);
              loadedMasteredCounts[d.id] = 0;
            }
            try {
              final lCount = await db.learningWordsDao.getLearningWordsCountInDicts(user.id, [d.id]);
              loadedLearningCounts[d.id] = lCount;
            } catch (e, st) {
              Global.logger.w('获取词书 ${d.id} 学习中词数失败: $e', stackTrace: st);
              loadedLearningCounts[d.id] = 0;
            }
          }
        }
        // 最新选的词书排在首位（书桌主卡片高亮展示）
        loadedDeskDicts.sort((a, b) => b.updateTime.compareTo(a.updateTime));
      }

      if (mounted) {
        setState(() {
          wordLists = lists;
          deskDicts = loadedDeskDicts;
          deskDictMasteredCounts = loadedMasteredCounts;
          deskDictLearningCounts = loadedLearningCounts;
          dataLoaded = true;
        });
        Global.logger.d('[EventBus Debug] loadData() 已触发 UI 刷新 (setState)');
      }
    } catch (e, st) {
      Global.logger.e('词表页 loadData 失败: $e', stackTrace: st);
      if (mounted) {
        setState(() {
          dataLoaded = true;
        });
      }
    }
  }

  String _cleanDictName(String name) {
    if (name.endsWith('.dict')) {
      return name.substring(0, name.lastIndexOf('.'));
    }
    return name;
  }

  WordList? _findListByName(String name) {
    for (final l in wordLists) {
      if (l.name == name) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final darkModeState = context.watch<DarkMode>();
    final themeStyle = darkModeState.themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    final textColor = themeConfig.textPrimary;
    final textSubColor = themeConfig.textSecondary;
    final isDarkMode = themeStyle.isDark;

    return AppScaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // 1. 顶部大标题栏
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '词表总览',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '预习新词 · 及时复习 · 深度巩固',
                          style: TextStyle(
                            color: textSubColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 2. 主体内容区
            SliverToBoxAdapter(
              child: !dataLoaded
                  ? SizedBox(
                      height: 320,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                themeConfig.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '正在加载词表...',
                              style: TextStyle(
                                color: textSubColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. 我的书桌板块
                          _buildDeskBooksSection(isDarkMode),
                          const SizedBox(height: 20),

                          // 2. 今日学习板块 (2x2 网格)
                          _buildTodayStudySection(isDarkMode),
                          const SizedBox(height: 20),

                          // 3. 核心词库板块 (纵向普通词表卡片)
                          _buildCoreDictsSection(isDarkMode),
                          const SizedBox(height: 20),

                          // 4. 专项突破板块 (易混淆单词)
                          _buildSpecialSection(isDarkMode),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 通用板块小节标题（极简现代，无生硬竖条）
  Widget _buildSectionHeader(String title, Color textColor, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: -0.2,
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// 1. 我的书桌板块 (用户正在背的词书)
  Widget _buildDeskBooksSection(bool isDarkMode) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    final textColor = themeConfig.textPrimary;
    final accentColor = themeConfig.primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题与选词书操作
        _buildSectionHeader(
          '我的书桌',
          textColor,
          trailing: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              context.push('/select_book').then((_) => loadData());
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '选词书',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 10,
                    color: accentColor.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 词书列表（聚合一体化现代大卡片，收拢多本词书）
        if (deskDicts.isEmpty)
          _buildEmptyDeskCard(isDarkMode)
        else
          Container(
            decoration: BoxDecoration(
              color: isDarkMode ? themeConfig.cardBg : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: themeConfig.cardBorder, width: 1.0),
              boxShadow: themeConfig.cardShadows,
            ),
            child: Column(
              children: [
                for (int i = 0; i < deskDicts.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 48, right: 14),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.055),
                      ),
                    ),
                  () {
                    final dict = deskDicts[i];
                    final total = dict.wordCount;
                    final mastered = deskDictMasteredCounts[dict.id] ?? 0;
                    final learning = deskDictLearningCounts[dict.id] ?? 0;
                    final fetched = mastered + learning;
                    final masteryProgress = total > 0 ? (mastered / total).clamp(0.0, 1.0) : 0.0;
                    final fetchProgress = total > 0 ? (fetched / total).clamp(0.0, 1.0) : 0.0;
                    final percent = (masteryProgress * 100).toInt();
                    return _buildGroupedItemRow(
                      icon: Icons.auto_stories_rounded,
                      iconColor: accentColor,
                      title: _cleanDictName(dict.name),
                      subtitle: '已掌握 $mastered · 已取 $fetched · $percent%',
                      countText: '$total 词',
                      progress: masteryProgress,
                      fetchProgress: fetchProgress,
                      isFirst: i == 0,
                      isLast: i == deskDicts.length - 1,
                      onTap: () async {
                        await toDictWordsListPage(dict.id, true);
                        loadData();
                      },
                    );
                  }(),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// 空书桌引导卡片
  Widget _buildEmptyDeskCard(bool isDarkMode) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final cardBg = themeConfig.cardBg;
    final cardBorder = themeConfig.cardBorder;
    final textSub = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        context.push('/select_book').then((_) => loadData());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder, width: 1),
          boxShadow: themeConfig.cardShadows,
        ),
        child: Row(
          children: [
            Icon(Icons.bookmark_add_outlined, size: 22, color: accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '书桌暂无词书，点击挑选一本加入学习',
                style: TextStyle(fontSize: 13, color: textSub, fontWeight: FontWeight.w400),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: textSub.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  /// 2. 今日学习板块 (2x2 网格)
  Widget _buildTodayStudySection(bool isDarkMode) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final textColor = themeConfig.textPrimary;
    final accentColor = themeConfig.primaryColor;

    final todayList = _findListByName('今日单词');
    final todayNewList = _findListByName('今日新词');
    final todayOldList = _findListByName('今日旧词');
    final wrongList = _findListByName('今日错词');

    final todayCount = todayList?.wordCount ?? 0;
    final newCount = todayNewList?.wordCount ?? 0;
    final oldCount = todayOldList?.wordCount ?? 0;
    final wrongCount = wrongList?.wordCount ?? 0;

    final wrongAlert = wrongCount > 0;
    final wrongColor = wrongAlert
        ? (isDarkMode ? const Color(0xFFFF7E6C) : const Color(0xFFE54D3B))
        : themeConfig.textSecondary.withValues(alpha: 0.45);
    final wrongIcon = wrongAlert ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('今日学习', textColor),

        // 2x2 网格
        Row(
          children: [
            Expanded(
              child: _buildGridWordListCard(
                isDarkMode: isDarkMode,
                title: '今日单词',
                count: todayCount,
                icon: Icons.calendar_today_rounded,
                iconColor: accentColor,
                onTap: () {
                  toTodayWordsListPage(true)?.then((_) => loadData());
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridWordListCard(
                isDarkMode: isDarkMode,
                title: '今日新词',
                count: newCount,
                icon: Icons.auto_awesome_rounded,
                iconColor: accentColor,
                onTap: () {
                  toTodayNewWordsListPage(true)?.then((_) => loadData());
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildGridWordListCard(
                isDarkMode: isDarkMode,
                title: '今日旧词',
                count: oldCount,
                icon: Icons.replay_rounded,
                iconColor: accentColor,
                onTap: () {
                  toTodayOldWordsListPage(true)?.then((_) => loadData());
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildGridWordListCard(
                isDarkMode: isDarkMode,
                title: '今日错词',
                count: wrongCount,
                icon: wrongIcon,
                iconColor: wrongColor,
                isAlert: wrongAlert,
                onTap: () {
                  toWrongWordsListPage()?.then((_) => loadData());
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 3. 核心词库板块 (聚合一体化现代大卡片)
  Widget _buildCoreDictsSection(bool isDarkMode) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final textColor = themeConfig.textPrimary;
    final cardBg = isDarkMode ? themeConfig.cardBg : Colors.white;
    final cardBorder = themeConfig.cardBorder;
    final dividerColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.055);

    final learningList = _findListByName('学习中');
    final masteredList = _findListByName('已掌握');
    final rawDictList = _findListByName('生词本');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('核心词库', textColor),

        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorder, width: 1.0),
            boxShadow: themeConfig.cardShadows,
          ),
          child: Column(
            children: [
              _buildGroupedItemRow(
                icon: Icons.school_rounded,
                iconColor: themeConfig.primaryColor,
                title: '学习中',
                subtitle: '正在记忆与巩固中的词汇',
                countText: '${learningList?.wordCount ?? 0} 词',
                onTap: () {
                  toLearningWordsListPage(true)?.then((_) => loadData());
                },
                isFirst: true,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 14),
                child: Divider(height: 1, thickness: 0.5, color: dividerColor),
              ),
              _buildGroupedItemRow(
                icon: Icons.check_circle_rounded,
                iconColor: const Color(0xFF10B981),
                title: '已掌握',
                subtitle: '已完全牢固掌握的高频词',
                countText: '${masteredList?.wordCount ?? 0} 词',
                onTap: () {
                  toMasteredWordsListPage(true)?.then((_) => loadData());
                },
              ),
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 14),
                child: Divider(height: 1, thickness: 0.5, color: dividerColor),
              ),
              _buildGroupedItemRow(
                icon: Icons.bookmark_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: '生词本',
                subtitle: '阅读与查词中标记的高难词',
                countText: '${rawDictList?.wordCount ?? 0} 词',
                onTap: () async {
                  final dict = await WordBo().getRawWordDict();
                  await toDictWordsListPage(dict, true);
                  loadData();
                },
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 4. 专项突破板块 (易混淆单词)
  Widget _buildSpecialSection(bool isDarkMode) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final textColor = themeConfig.textPrimary;
    final confusableList = _findListByName('易混淆单词');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('专项突破', textColor),

        _buildHorizontalWordListCard(
          isDarkMode: isDarkMode,
          icon: Icons.compare_arrows_rounded,
          iconColor: const Color(0xFF6366F1),
          title: '易混淆单词',
          subtitle: '形近词、同义辨析强化攻坚',
          countText: '${confusableList?.wordCount ?? 0} 组',
          onTap: () {
            toConfusableWordsListPage()?.then((_) => loadData());
          },
        ),
      ],
    );
  }

  /// 通用横向词表微卡片
  Widget _buildHorizontalWordListCard({
    required bool isDarkMode,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String countText,
    required VoidCallback onTap,
    bool isHighlighted = false,
    double? progress,
    double? fetchProgress,
  }) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final accentColor = themeConfig.primaryColor;

    // 选中/主线高亮时赋予 4.5% 极淡主题微光底色与精致边框，非高亮时保持纯白与常规边框
    final cardBg = isDarkMode
        ? (isHighlighted
            ? Color.alphaBlend(accentColor.withValues(alpha: 0.12), themeConfig.cardBg)
            : themeConfig.cardBg)
        : (isHighlighted
            ? Color.alphaBlend(accentColor.withValues(alpha: 0.045), Colors.white)
            : Colors.white);

    final cardBorder = isHighlighted
        ? accentColor.withValues(alpha: isDarkMode ? 0.55 : 0.45)
        : themeConfig.cardBorder;

    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;

    final cardShadow = isHighlighted
        ? [
            BoxShadow(
              color: accentColor.withValues(alpha: isDarkMode ? 0.25 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ]
        : themeConfig.cardShadows;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: isHighlighted ? 1.2 : 1.0),
        boxShadow: cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 左侧图标（精致通透，无多余色块）
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: 12),

                // 中间文字
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: textMain,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                          color: textSub,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (progress != null || fetchProgress != null) ...[
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 3.5,
                            child: Stack(
                              children: [
                                Container(
                                  color: isDarkMode
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.055),
                                ),
                                if (fetchProgress != null && fetchProgress > 0)
                                  FractionallySizedBox(
                                    widthFactor: fetchProgress.clamp(0.0, 1.0),
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      color: accentColor.withValues(alpha: isDarkMode ? 0.45 : 0.35),
                                    ),
                                  ),
                                if (progress != null && progress > 0)
                                  FractionallySizedBox(
                                    widthFactor: progress.clamp(0.0, 1.0),
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      color: accentColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 右侧数量 + 箭头（纯粹通透排版，无多余药丸底色）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      countText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                        color: isHighlighted ? accentColor : textSub,
                        fontFamily: 'Roboto',
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: textSub.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 聚合大卡片内部行项
  Widget _buildGroupedItemRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String countText,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
    double? progress,
    double? fetchProgress,
  }) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final accentColor = themeConfig.primaryColor;
    final textMain = themeConfig.textPrimary;
    final textSub = themeConfig.textSecondary;
    final isDarkMode = themeStyle.isDark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(16) : Radius.zero,
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textMain,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        color: textSub,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (progress != null || fetchProgress != null) ...[
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          height: 3.5,
                          child: Stack(
                            children: [
                              Container(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.055),
                              ),
                              if (fetchProgress != null && fetchProgress > 0)
                                FractionallySizedBox(
                                  widthFactor: fetchProgress.clamp(0.0, 1.0),
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    color: accentColor.withValues(alpha: isDarkMode ? 0.45 : 0.35),
                                  ),
                                ),
                              if (progress != null && progress > 0)
                                FractionallySizedBox(
                                  widthFactor: progress.clamp(0.0, 1.0),
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    color: accentColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    countText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: textSub,
                      fontFamily: 'Roboto',
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: textSub.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 通用 2x2 网格词表微卡片
  Widget _buildGridWordListCard({
    required bool isDarkMode,
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    bool isAlert = false,
  }) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final cardBg = isDarkMode ? themeConfig.cardBg : Colors.white;
    final cardBorder = themeConfig.cardBorder;
    final textMain = themeConfig.textPrimary;
    final alertColor = isDarkMode ? const Color(0xFFFF7E6C) : const Color(0xFFE54D3B);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: themeConfig.cardShadows,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 顶部行：纯粹轻灵的图标 + 右侧轻箭头
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: 20, color: iconColor),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: themeConfig.textSecondary.withValues(alpha: 0.35),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 底部行：标题 + 醒目大数字（基线对齐）
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: themeConfig.textSecondary,
                      ),
                    ),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: (isAlert && count > 0) ? alertColor : textMain,
                        fontFamily: 'Roboto',
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
