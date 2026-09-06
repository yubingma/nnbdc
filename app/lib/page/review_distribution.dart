import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/date_utils.dart' as app_date;
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/page/word_list/bucket_words.dart';
import '../theme/app_theme.dart';

class ReviewDistributionPage extends StatefulWidget {
  const ReviewDistributionPage({super.key});

  @override
  State<ReviewDistributionPage> createState() => _ReviewDistributionPageState();
}

class BarChartData {
  final String label;
  final int totalCount;
  final int newCount;
  final bool isToday;
  final bool isOverdue;
  final int sortKey;

  BarChartData({
    required this.label,
    required this.totalCount,
    required this.newCount,
    this.isToday = false,
    this.isOverdue = false,
    required this.sortKey,
  });
}

class _ReviewDistributionPageState extends State<ReviewDistributionPage> {
  List<BarChartData> _barDataList = [];
  bool _isLoading = true;
  int _maxCount = 0;
  int _totalWords = 0;
  int _totalNewWords = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int get _todayReviewCount {
    for (final item in _barDataList) {
      if (item.isToday) return item.totalCount;
    }
    return 0;
  }

  int get _overdueReviewCount {
    int sum = 0;
    for (final item in _barDataList) {
      if (item.isOverdue) sum += item.totalCount;
    }
    return sum;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final db = MyDatabase.instance;
    final userId = Global.currentUserId;
    if (userId == null) return;

    final data = await db.learningWordsDao.getLearningWordsForCloud(userId);

    // 排除已掌握的单词（防御：防止已掌握单词的学习记录残留导致在复习分布图中反复出现）
    final masteredWordIds = await db.masteredWordsDao.getMasteredWordIdSet(userId);
    final filteredData = masteredWordIds.isEmpty
        ? data
        : data.where((item) => !masteredWordIds.contains(item['wordId'] as String?)).toList();
    if (data.length > filteredData.length) {
      Global.logger.w('review_distribution: 排除了 ${data.length - filteredData.length} 个已在"已掌握"中的单词');
    }

    final now = AppClock.now();
    final nowDate = AppClock.today();

    Map<int, int> dayToTotalCounts = {};
    _totalNewWords = 0;
    final Set<String> seenWordIds = {}; // 去重：JOIN 可能导致同一 wordId 出现多次（多词根）

    for (var item in filteredData) {
      final wordId = item['wordId'] as String?;
      if (wordId == null || !seenWordIds.add(wordId)) continue; // 已见过 → 跳过重复行

      final isNew = (item['learnedTimes'] ?? 0) == 0;
      if (isNew) {
        _totalNewWords++;
        continue;
      }

      final lastDateRaw = item['lastLearningDate'] as DateTime? ?? now;
      final scheduledDays = item['scheduledDays'] as int? ?? 0;
      final nextDateRaw = app_date.DateUtils.businessDate(lastDateRaw).add(Duration(days: scheduledDays));

      final nextDate = app_date.DateUtils.businessDate(nextDateRaw);
      final daysDiff = nextDate.difference(nowDate).inDays;

      int key;
      if (daysDiff >= 0) {
        key = daysDiff;
      } else {
        int overdueDays = -daysDiff;
        key = -((overdueDays + 9) ~/ 10 * 10);
      }

      dayToTotalCounts[key] = (dayToTotalCounts[key] ?? 0) + 1;
    }
    _totalWords = seenWordIds.length; // 基于去重后的唯一单词数

    dayToTotalCounts[0] = dayToTotalCounts[0] ?? 0;
    var sortedKeys = dayToTotalCounts.keys.toList()..sort();

    _maxCount = _totalNewWords; // 初始最大值设为新词数，确保缩放一致
    _barDataList = sortedKeys.map((key) {
      final totalCount = dayToTotalCounts[key]!;
      if (totalCount > _maxCount) _maxCount = totalCount;

      String label;
      bool isToday = key == 0;
      bool isOverdue = key < 0;

      if (isToday) {
        label = "今天";
      } else if (isOverdue) {
        label = "已逾期${-key}天";
      } else {
        label = "$key天后";
      }

      return BarChartData(
        label: label,
        totalCount: totalCount,
        newCount: 0, // 分布图中不再混入新词
        isToday: isToday,
        isOverdue: isOverdue,
        sortKey: key,
      );
    }).toList();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;

    final cardBg = themeConfig.cardBg;
    final subtleBg = themeConfig.subtleBg;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final borderColor = themeConfig.cardBorder;

    return AppScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '复习分布图',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: textColor,
            fontSize: 17.5,
            fontFamily: 'NotoSansSC',
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: subtleBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_totalWords 词',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.help_outline_rounded, color: subtitleColor, size: 22),
            onPressed: () => _showExplainDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: accentColor,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 1. 顶部 Hero 统计态势展台
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: themeConfig.appBarGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: isDarkMode ? 0.25 : 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('📊 ', style: TextStyle(fontSize: 11)),
                                    Text(
                                      'FSRS 记忆曲线调度',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () => _showExplainDialog(context),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '图表说明',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: Colors.white.withValues(alpha: 0.85),
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // 四维态势小方块
                          Row(
                            children: [
                              _buildHeroStatBox('学习池总词', '$_totalWords', Colors.white, null),
                              const SizedBox(width: 8),
                              _buildHeroStatBox('今日待复习', '$_todayReviewCount', Colors.white, Colors.white.withValues(alpha: 0.22)),
                              const SizedBox(width: 8),
                              _buildHeroStatBox('逾期未复习', '$_overdueReviewCount', const Color(0xFFFECDD3), null),
                              const SizedBox(width: 8),
                              _buildHeroStatBox('新词待学习', '$_totalNewWords', const Color(0xFFDDD6FE), null),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. 图例说明栏
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildLegendItem('今日复习', accentColor, subtitleColor),
                          _buildLegendItem('已逾期', isDarkMode ? const Color(0xFFFB7185) : const Color(0xFFF43F5E), subtitleColor),
                          _buildLegendItem('未来复习', isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0284C7), subtitleColor),
                          _buildLegendItem('新词储备', isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF8B5CF6), subtitleColor),
                        ],
                      ),
                    ),
                  ),

                  // 3. 待学习新词储备池卡片
                  if (_totalNewWords > 0)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('📦 ', style: TextStyle(fontSize: 13)),
                                    Text(
                                      '待学习 (新词储备池)',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: textColor,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '未开始初记',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subtitleColor,
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildNewWordsBar(isDarkMode, subtleBg),
                          ],
                        ),
                      ),
                    ),

                  // 4. 待复习时间分布卡片
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '⏳ ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: accentColor,
                                    ),
                                  ),
                                  Text(
                                    '待复习时间分布',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: textColor,
                                      fontFamily: 'NotoSansSC',
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '点击查看单词列表',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: subtitleColor,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_barDataList.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  '暂无待复习任务',
                                  style: TextStyle(color: subtitleColor, fontSize: 13),
                                ),
                              ),
                            )
                          else
                            ..._barDataList.map((data) => _buildBarRow(data, isDarkMode, subtleBg, textColor, subtitleColor, accentColor)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroStatBox(String label, String value, Color valColor, Color? bgHighlight) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: bgHighlight ?? Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: valColor,
                fontFamily: 'Roboto',
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, Color textCol) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: textCol,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ],
    );
  }

  Widget _buildNewWordsBar(bool isDarkMode, Color subtleBg) {
    final purpleColor = isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF8B5CF6);

    return InkWell(
      onTap: () {
        toBucketWordsListPage(9999, "新词库")?.then((_) => _loadData());
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                "新词储备",
                style: TextStyle(
                  fontSize: 12.5,
                  color: purpleColor,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth - 50;
                  final barWidth = _maxCount == 0 ? 0.0 : (_totalNewWords / _maxCount) * maxWidth;

                  return Row(
                    children: [
                      Container(
                        height: 20,
                        width: maxWidth,
                        decoration: BoxDecoration(
                          color: subtleBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 20,
                          width: barWidth < 6 && _totalNewWords > 0 ? 6 : barWidth,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [purpleColor, purpleColor.withValues(alpha: 0.7)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 38,
                        child: Text(
                          "$_totalNewWords",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: purpleColor,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: purpleColor.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  void _onBarTap(BarChartData data) {
    toBucketWordsListPage(data.sortKey, data.label)?.then((_) => _loadData());
  }

  Widget _buildBarRow(
    BarChartData data,
    bool isDarkMode,
    Color subtleBg,
    Color textColor,
    Color subtitleColor,
    Color accentColor,
  ) {
    final overdueColor = isDarkMode ? const Color(0xFFFB7185) : const Color(0xFFF43F5E);
    final futureColor = isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    Color labelColor;
    if (data.isToday) {
      labelColor = isDarkMode ? accentColor : textColor;
    } else if (data.isOverdue) {
      labelColor = overdueColor;
    } else {
      labelColor = textColor;
    }

    return InkWell(
      onTap: () => _onBarTap(data),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: data.isToday ? accentColor.withValues(alpha: isDarkMode ? 0.15 : 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                data.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: data.isToday ? FontWeight.w900 : FontWeight.w700,
                  color: labelColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth - 50;
                  final barWidth = _maxCount == 0 ? 0.0 : (data.totalCount / _maxCount) * maxWidth;

                  return Row(
                    children: [
                      Container(
                        height: 20,
                        width: maxWidth,
                        decoration: BoxDecoration(
                          color: subtleBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 20,
                          width: barWidth < 6 && data.totalCount > 0 ? 6 : barWidth,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: data.isToday
                                  ? [accentColor, accentColor.withValues(alpha: 0.7)]
                                  : (data.isOverdue
                                      ? [overdueColor, overdueColor.withValues(alpha: 0.7)]
                                      : [futureColor.withValues(alpha: 0.9), futureColor.withValues(alpha: 0.6)]),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: data.isToday
                                ? [
                                    BoxShadow(
                                      color: accentColor.withValues(alpha: 0.35),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 38,
                        child: Text(
                          "${data.totalCount}",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: labelColor,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: data.isToday ? accentColor : subtitleColor.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  void _showExplainDialog(BuildContext context) {
    final themeStyle = Provider.of<DarkMode>(context, listen: false).themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;

    final cardBg = themeConfig.cardBg;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Text('🧠 ', style: TextStyle(fontSize: 18)),
            Text(
              'FSRS 自适应记忆算法',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textColor,
                fontSize: 17,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogDescItem(
              Icons.psychology_rounded,
              '科学动态调度',
              'FSRS（自由间隔重复算法）基于现代认知模型，根据每个单词的掌握反馈自适应预测最佳复习临界点。',
              accentColor,
              textColor,
              subtitleColor,
            ),
            const SizedBox(height: 14),
            _dialogDescItem(
              Icons.auto_graph_rounded,
              'D-S-R 记忆模型',
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 12.5, color: subtitleColor, fontFamily: 'NotoSansSC', height: 1.45),
                  children: [
                    TextSpan(text: '• 稳定性 (S)：', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                    const TextSpan(text: '每次成功回忆，记忆稳固度成倍提升，复习间隔自动延长；\n'),
                    TextSpan(text: '• 难度 (D)：', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                    const TextSpan(text: '难词高频巩固，熟词快速通关；\n'),
                    TextSpan(text: '• 可提取性 (R)：', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                    const TextSpan(text: '始终在记忆即将遗忘的黄金临界点精准唤醒。'),
                  ],
                ),
              ),
              accentColor,
              textColor,
              subtitleColor,
            ),
            const SizedBox(height: 14),
            _dialogDescItem(
              Icons.access_time_rounded,
              '分布调度逻辑',
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 12.5, color: subtitleColor, fontFamily: 'NotoSansSC', height: 1.45),
                  children: [
                    TextSpan(text: '• 今日必复习：', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                    const TextSpan(text: '到达最佳复习窗口，效率最高；\n'),
                    TextSpan(text: '• 已逾期：', style: TextStyle(color: isDarkMode ? const Color(0xFFFB7185) : const Color(0xFFF43F5E), fontWeight: FontWeight.bold)),
                    const TextSpan(text: '错过黄金复习点，建议优先消灭；\n'),
                    TextSpan(text: '• 未来分布：', style: TextStyle(color: isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                    const TextSpan(text: '科学平滑分散复习量，避免堆积。'),
                  ],
                ),
              ),
              accentColor,
              textColor,
              subtitleColor,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '我知道了',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: accentColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogDescItem(IconData icon, String title, dynamic desc, Color accentColor, Color textColor, Color subtitleColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: accentColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 2),
              if (desc is Widget)
                desc
              else
                Text(
                  desc.toString(),
                  style: TextStyle(fontSize: 12.5, color: subtitleColor, fontFamily: 'NotoSansSC', height: 1.4),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

