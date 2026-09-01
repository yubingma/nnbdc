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
  bool _isDirty = false;
  StreamSubscription? _subscription;

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
  }

  @override
  void dispose() {
    if (instance == this) {
      instance = null;
    }
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> loadData() async {
    Global.logger.d('[EventBus Debug] === loadData 开始异步加载数据 ===');
    try {
      final listsResult = await WordBo().getWordLists();
      final lists = listsResult.data ?? [];

      // 加载用户书桌上的词书
      final user = Global.getLoggedInUser();
      final loadedDeskDicts = <Dict>[];
      if (user != null) {
        final db = MyDatabase.instance;
        final learningDicts = await db.learningDictsDao.getLearningDictsOfUser(user.id);
        for (final ld in learningDicts) {
          final d = await db.dictsDao.findById(ld.dictId);
          if (d != null) {
            loadedDeskDicts.add(d);
          }
        }
      }

      if (mounted) {
        setState(() {
          wordLists = lists;
          deskDicts = loadedDeskDicts;
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
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF0C1312) : const Color(0xFFF6F9F8);
    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSubColor = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691);

    return Scaffold(
      backgroundColor: backgroundColor,
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
                          '词表',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '查漏补缺 · 专项巩固',
                          style: TextStyle(
                            color: textSubColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
                                isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '正在加载词表...',
                              style: TextStyle(
                                color: textSubColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
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

  /// 1. 我的书桌板块 (用户正在背的词书)
  Widget _buildDeskBooksSection(bool isDarkMode) {
    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final accentGreen = isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor;
    final primarySoft = isDarkMode ? const Color(0x262CD88F) : const Color(0xFFEDF8F3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标头部
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accentGreen,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '我的书桌',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                context.push('/select_book').then((_) => loadData());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '+ 选词书',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: accentGreen,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 词书列表
        if (deskDicts.isEmpty)
          _buildEmptyDeskCard(isDarkMode)
        else
          Column(
            children: [
              for (int i = 0; i < deskDicts.length; i++) ...[
                if (i > 0) const SizedBox(height: 9),
                _buildHorizontalWordListCard(
                  isDarkMode: isDarkMode,
                  icon: Icons.auto_stories_rounded,
                  iconBgColor: isDarkMode ? const Color(0x262CD88F) : const Color(0xFFEDF8F3),
                  iconColor: accentGreen,
                  title: _cleanDictName(deskDicts[i].name),
                  subtitle: i == 0 ? '正在学习的主线词书' : '书桌备选词书',
                  countText: '${deskDicts[i].wordCount} 词',
                  onTap: () async {
                    await toDictWordsListPage(deskDicts[i].id, true);
                    loadData();
                  },
                ),
              ],
            ],
          ),
      ],
    );
  }

  /// 空书桌引导卡片
  Widget _buildEmptyDeskCard(bool isDarkMode) {
    final cardBg = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
    final cardBorder = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);
    final textSub = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691);
    final accentGreen = isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        context.push('/select_book').then((_) => loadData());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cardBorder, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0x262CD88F) : const Color(0xFFEDF8F3),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.bookmark_add_outlined, size: 18, color: accentGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '书桌暂无词书，点击挑选一本加入学习',
                style: TextStyle(fontSize: 13, color: textSub, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textSub.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  /// 2. 今日学习板块 (2x2 网格)
  Widget _buildTodayStudySection(bool isDarkMode) {
    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final amberColor = isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

    final todayList = _findListByName('今日单词');
    final todayNewList = _findListByName('今日新词');
    final todayOldList = _findListByName('今日旧词');
    final wrongList = _findListByName('今日错词');

    final todayCount = todayList?.wordCount ?? 0;
    final newCount = todayNewList?.wordCount ?? 0;
    final oldCount = todayOldList?.wordCount ?? 0;
    final wrongCount = wrongList?.wordCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 12,
              decoration: BoxDecoration(
                color: amberColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '今日学习',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2x2 网格
        Row(
          children: [
            Expanded(
              child: _buildGridWordListCard(
                isDarkMode: isDarkMode,
                title: '今日单词',
                count: todayCount,
                icon: Icons.calendar_today_rounded,
                iconBgColor: isDarkMode ? const Color(0x262CD88F) : const Color(0xFFEDF8F3),
                iconColor: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
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
                iconBgColor: isDarkMode ? const Color(0x26FBBF24) : const Color(0xFFFFF8E6),
                iconColor: amberColor,
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
                iconBgColor: isDarkMode ? const Color(0x2660A5FA) : const Color(0xFFEFF6FF),
                iconColor: isDarkMode ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
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
                icon: Icons.error_outline_rounded,
                iconBgColor: isDarkMode ? const Color(0x26FF7E6C) : const Color(0xFFFEF3F2),
                iconColor: isDarkMode ? const Color(0xFFFF7E6C) : const Color(0xFFE54D3B),
                isAlert: wrongCount > 0,
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

  /// 3. 核心词库板块 (纵向普通词表卡片)
  Widget _buildCoreDictsSection(bool isDarkMode) {
    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final blueColor = isDarkMode ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);

    final learningList = _findListByName('学习中');
    final masteredList = _findListByName('已掌握');
    final rawDictList = _findListByName('生词本');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 12,
              decoration: BoxDecoration(
                color: blueColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '核心词库',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Column(
          children: [
            _buildHorizontalWordListCard(
              isDarkMode: isDarkMode,
              icon: Icons.school_rounded,
              iconBgColor: isDarkMode ? const Color(0x262CD88F) : const Color(0xFFEDF8F3),
              iconColor: isDarkMode ? const Color(0xFF2CD88F) : AppTheme.primaryColor,
              title: '学习中',
              subtitle: '正在记忆与巩固中的词汇',
              countText: '${learningList?.wordCount ?? 0} 词',
              onTap: () {
                toLearningWordsListPage(true)?.then((_) => loadData());
              },
            ),
            const SizedBox(height: 9),
            _buildHorizontalWordListCard(
              isDarkMode: isDarkMode,
              icon: Icons.check_circle_rounded,
              iconBgColor: isDarkMode ? const Color(0x2660A5FA) : const Color(0xFFEFF6FF),
              iconColor: blueColor,
              title: '已掌握',
              subtitle: '已完全牢固掌握的高频词',
              countText: '${masteredList?.wordCount ?? 0} 词',
              onTap: () {
                toMasteredWordsListPage(true)?.then((_) => loadData());
              },
            ),
            const SizedBox(height: 9),
            _buildHorizontalWordListCard(
              isDarkMode: isDarkMode,
              icon: Icons.bookmark_rounded,
              iconBgColor: isDarkMode ? const Color(0x26FBBF24) : const Color(0xFFFFF8E6),
              iconColor: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
              title: '生词本',
              subtitle: '自主收藏与重点标记单词',
              countText: '${rawDictList?.wordCount ?? 0} 词',
              onTap: () async {
                final dict = await WordBo().getRawWordDict();
                await toDictWordsListPage(dict, true);
                loadData();
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 4. 专项突破板块 (易混淆单词)
  Widget _buildSpecialSection(bool isDarkMode) {
    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final purpleColor = isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
    final confusableList = _findListByName('易混淆单词');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 12,
              decoration: BoxDecoration(
                color: purpleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '专项突破',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        _buildHorizontalWordListCard(
          isDarkMode: isDarkMode,
          icon: Icons.compare_arrows_rounded,
          iconBgColor: isDarkMode ? const Color(0x26A78BFA) : const Color(0xFFF5F3FF),
          iconColor: purpleColor,
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
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String countText,
    required VoidCallback onTap,
  }) {
    final cardBg = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
    final cardBorder = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);
    final textMain = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSub = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF789691);
    final pillBg = isDarkMode ? const Color(0xFF192C27) : const Color(0xFFF0F6F3);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.025),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 左侧图标容器
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
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
                          fontWeight: FontWeight.w700,
                          color: textMain,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textSub,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 右侧数量胶囊 + 箭头
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cardBorder, width: 0.8),
                      ),
                      child: Text(
                        countText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: textSub,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: textSub.withValues(alpha: 0.6),
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

  /// 通用 2x2 网格词表微卡片
  Widget _buildGridWordListCard({
    required bool isDarkMode,
    required String title,
    required int count,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required VoidCallback onTap,
    bool isAlert = false,
  }) {
    final cardBg = isDarkMode ? const Color(0xFF131E1C) : Colors.white;
    final cardBorder = isDarkMode ? Colors.white10 : const Color(0xFFE1EFEA);
    final textMain = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final textSecondary = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF425B57);
    final alertColor = isDarkMode ? const Color(0xFFFF7E6C) : const Color(0xFFE54D3B);

    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.025),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 顶部行：图标 + 箭头
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 15, color: iconColor),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: isDarkMode ? Colors.white24 : Colors.black26,
                    ),
                  ],
                ),

                // 底部行：标题 + 数量
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: textMain,
                      ),
                    ),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: isAlert ? alertColor : textSecondary,
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
