import 'package:flutter/material.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../theme/page_vibrancy.dart';
import '../widget/frosted_glass_card.dart';

enum HeatmapDisplayMode { date, time, count }

enum TimeDimension {
  today('今日'),
  week('近7天'),
  month('近30天'),
  year('近1年'),
  allTime('累计');

  final String label;
  const TimeDimension(this.label);
}

class ChartBarItem {
  final String label;
  final String fullDateStr;
  final int seconds;
  final bool isHighlight;

  ChartBarItem({
    required this.label,
    required this.fullDateStr,
    required this.seconds,
    this.isHighlight = false,
  });
}

class StudyStatsPage extends StatefulWidget {
  const StudyStatsPage({super.key});

  @override
  State<StudyStatsPage> createState() => _StudyStatsPageState();
}

class _StudyStatsPageState extends State<StudyStatsPage> {
  bool _isLoading = true;
  User? _currentUser;
  List<UserStudyDailyStat> _recentYearDailyStats = [];
  List<String> _last30DaysDakaStatus = [];
  List<Map<String, dynamic>> _dailyReviewCounts = [];
  List<Map<String, dynamic>> _dailyWordCounts = [];

  // 当前选中的时长统计维度
  TimeDimension _selectedDimension = TimeDimension.week;
  int? _selectedBarIndex;

  // 热力图显示模式
  HeatmapDisplayMode _displayMode = HeatmapDisplayMode.date;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = Global.currentUserId;
      if (userId == null) return;

      // 1. 获取用户信息（提取 totalLearningSeconds 与 todayLearningSeconds）
      _currentUser = await MyDatabase.instance.usersDao.getUserById(userId);

      // 2. 获取近 365 天每日学习统计数据（用于日/周/月/年多维时长计算与柱状图）
      _recentYearDailyStats = await MyDatabase.instance.userStudyDailyStatsDao.getRecentStats(userId, 365);

      // 3. 获取最近 30 天打卡状态
      final result = await UserBo().getDayStatuses(30);
      if (result.success) {
        _last30DaysDakaStatus = result.data!;
      }

      // 4. 获取每日复习数与秒数（供热力图读取）
      _dailyReviewCounts = await MyDatabase.instance.learningLogsDao.getDailyReviewCounts(userId, 30);

      // 5. 获取每日去重单词数（供热力图“单词”模式展示）
      _dailyWordCounts = await MyDatabase.instance.learningLogsDao.getDailyWordCounts(userId, 30);
    } catch (e) {
      Global.logger.e('加载学习统计失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- 辅助计算与格式化方法 ---

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '0m';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) {
      return '${minutes}m';
    } else if (minutes == 0) {
      return '${hours}h';
    } else {
      return '${hours}h ${minutes}m';
    }
  }

  static String _formatMinutes(int seconds) {
    if (seconds <= 0) return '0 分钟';
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes 分钟';
    }
    final hours = (minutes / 60).toStringAsFixed(1);
    return '$hours 小时';
  }

  static String _getAchievementMetaphor(int seconds) {
    final hours = seconds / 3600;
    if (seconds < 300) {
      return '🌱 专注种下一颗语言幼苗';
    } else if (seconds < 1800) {
      return '🍅 完成了 1 个高质量深度番茄钟';
    } else if (hours < 2) {
      return '📰 相当于精读了 1 篇外刊深度长文';
    } else if (hours < 5) {
      return '🎧 相当于精听了 2 期原版英文播客';
    } else if (hours < 15) {
      return '📖 相当于通读了 1 本中篇英文原版书';
    } else if (hours < 50) {
      return '🎬 相当于刷完了 2 季原声美剧核心对话';
    } else if (hours < 100) {
      return '📚 相当于学完 1 门大学进阶英语课程';
    } else if (hours < 300) {
      return '⛰️ 相当于攀登了 1 座 CEFR 欧标语言高峰';
    } else {
      return '🏆 时间沉淀非凡，已步入终身学者殿堂';
    }
  }

  Map<String, int> _buildDailySecondsMap() {
    final map = <String, int>{};
    for (final stat in _recentYearDailyStats) {
      final key = DateFormat('yyyy-MM-dd').format(stat.date);
      map[key] = (map[key] ?? 0) + stat.studySeconds;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final isDarkMode = themeStyle.isDark;
    final cardColor = context.cardBg;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    return AppScaffold(
      vibrancy: PageVibrancy.studyStats,
      appBar: AppBar(
        title: Text(
          '学习统计与时光馆',
          style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontFamily: 'NotoSansSC'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 核心专注时光看板（支持 日/周/月/年/累计 切换）
                  _buildTimeStatsSection(isDarkMode, cardColor, textColor, subtitleColor, accentColor, themeConfig),
                  const SizedBox(height: 20),

                  // 2. 学习热力图（30天色块与精确秒数）
                  _buildHeatmapSection(isDarkMode, cardColor, textColor, subtitleColor, accentColor, themeConfig),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ==========================================
  // 模块 1: 核心专注时光面板 (Hero Dashboard)
  // ==========================================

  Widget _buildTimeStatsSection(
    bool isDarkMode,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    Color accentColor,
    AppThemeConfig themeConfig,
  ) {
    final dailyMap = _buildDailySecondsMap();
    final today = AppClock.today();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    // 计算当前所选维度的总时长、日均、天数及柱状图数据
    int totalSecs = 0;
    int activeDays = 0;
    int periodDays = 1;
    double? growthPercent;
    List<ChartBarItem> bars = [];

    switch (_selectedDimension) {
      case TimeDimension.today:
        periodDays = 1;
        final dbTodaySecs = dailyMap[todayStr] ?? 0;
        final userTodaySecs = _currentUser?.todayLearningSeconds ?? 0;
        totalSecs = dbTodaySecs > userTodaySecs ? dbTodaySecs : userTodaySecs;
        activeDays = totalSecs > 0 ? 1 : 0;

        // 对比昨日
        final yesterdayStr = DateFormat('yyyy-MM-dd').format(today.subtract(const Duration(days: 1)));
        final yesterdaySecs = dailyMap[yesterdayStr] ?? 0;
        if (yesterdaySecs > 0) {
          growthPercent = ((totalSecs - yesterdaySecs) / yesterdaySecs) * 100;
        }

        // 柱状图展示最近 7 天，标出今天在这一周的位次
        for (int i = 6; i >= 0; i--) {
          final date = today.subtract(Duration(days: i));
          final dStr = DateFormat('yyyy-MM-dd').format(date);
          final secs = i == 0 ? totalSecs : (dailyMap[dStr] ?? 0);
          final label = i == 0 ? '今日' : DateFormat('M/d').format(date);
          bars.add(ChartBarItem(
            label: label,
            fullDateStr: dStr,
            seconds: secs,
            isHighlight: i == 0,
          ));
        }
        break;

      case TimeDimension.week:
        periodDays = 7;
        int prevWeekSecs = 0;
        // 近 7 天
        for (int i = 6; i >= 0; i--) {
          final date = today.subtract(Duration(days: i));
          final dStr = DateFormat('yyyy-MM-dd').format(date);
          int secs = dailyMap[dStr] ?? 0;
          if (i == 0) {
            final userToday = _currentUser?.todayLearningSeconds ?? 0;
            if (userToday > secs) secs = userToday;
          }
          totalSecs += secs;
          if (secs > 0) activeDays++;

          const weekDayNames = ['一', '二', '三', '四', '五', '六', '日'];
          final dayName = '周${weekDayNames[date.weekday - 1]}';
          bars.add(ChartBarItem(
            label: i == 0 ? '今日' : dayName,
            fullDateStr: dStr,
            seconds: secs,
            isHighlight: i == 0,
          ));
        }
        // 前 7 天（用于环比）
        for (int i = 13; i >= 7; i--) {
          final date = today.subtract(Duration(days: i));
          final dStr = DateFormat('yyyy-MM-dd').format(date);
          prevWeekSecs += (dailyMap[dStr] ?? 0);
        }
        if (prevWeekSecs > 0) {
          growthPercent = ((totalSecs - prevWeekSecs) / prevWeekSecs) * 100;
        }
        break;

      case TimeDimension.month:
        periodDays = 30;
        int prevMonthSecs = 0;
        // 近 30 天
        for (int i = 29; i >= 0; i--) {
          final date = today.subtract(Duration(days: i));
          final dStr = DateFormat('yyyy-MM-dd').format(date);
          int secs = dailyMap[dStr] ?? 0;
          if (i == 0) {
            final userToday = _currentUser?.todayLearningSeconds ?? 0;
            if (userToday > secs) secs = userToday;
          }
          totalSecs += secs;
          if (secs > 0) activeDays++;

          bars.add(ChartBarItem(
            label: (i % 5 == 0 || i == 0) ? DateFormat('M/d').format(date) : '',
            fullDateStr: dStr,
            seconds: secs,
            isHighlight: i == 0,
          ));
        }
        // 前 30 天（用于环比）
        for (int i = 59; i >= 30; i--) {
          final date = today.subtract(Duration(days: i));
          final dStr = DateFormat('yyyy-MM-dd').format(date);
          prevMonthSecs += (dailyMap[dStr] ?? 0);
        }
        if (prevMonthSecs > 0) {
          growthPercent = ((totalSecs - prevMonthSecs) / prevMonthSecs) * 100;
        }
        break;

      case TimeDimension.year:
        periodDays = 365;
        // 近 12 个月聚合
        final now = AppClock.now();
        final Map<String, int> monthSecsMap = {};
        final Map<String, String> monthLabels = {};

        for (int i = 11; i >= 0; i--) {
          final mDate = DateTime(now.year, now.month - i, 1);
          final mKey = DateFormat('yyyy-MM').format(mDate);
          monthSecsMap[mKey] = 0;
          monthLabels[mKey] = '${mDate.month}月';
        }

        for (final stat in _recentYearDailyStats) {
          final mKey = DateFormat('yyyy-MM').format(stat.date);
          if (monthSecsMap.containsKey(mKey)) {
            monthSecsMap[mKey] = (monthSecsMap[mKey] ?? 0) + stat.studySeconds;
          }
          totalSecs += stat.studySeconds;
          if (stat.studySeconds > 0) activeDays++;
        }

        // 加上今日可能的未写入秒数
        final userTotal = _currentUser?.totalLearningSeconds ?? 0;
        if (userTotal > totalSecs) {
          totalSecs = userTotal;
        }

        monthSecsMap.forEach((mKey, secs) {
          bars.add(ChartBarItem(
            label: monthLabels[mKey] ?? '',
            fullDateStr: mKey,
            seconds: secs,
            isHighlight: mKey == DateFormat('yyyy-MM').format(now),
          ));
        });
        break;

      case TimeDimension.allTime:
        final allTimeSecsFromUser = _currentUser?.totalLearningSeconds ?? 0;
        int sumDaily = 0;
        for (final stat in _recentYearDailyStats) {
          sumDaily += stat.studySeconds;
          if (stat.studySeconds > 0) activeDays++;
        }
        totalSecs = allTimeSecsFromUser > sumDaily ? allTimeSecsFromUser : sumDaily;
        periodDays = _currentUser?.learnedDays ?? (activeDays > 0 ? activeDays : 1);

        // 累计也展示近 12 个月的月度分布
        final now = AppClock.now();
        final Map<String, int> monthSecsMap = {};
        final Map<String, String> monthLabels = {};
        for (int i = 11; i >= 0; i--) {
          final mDate = DateTime(now.year, now.month - i, 1);
          final mKey = DateFormat('yyyy-MM').format(mDate);
          monthSecsMap[mKey] = 0;
          monthLabels[mKey] = '${mDate.month}月';
        }
        for (final stat in _recentYearDailyStats) {
          final mKey = DateFormat('yyyy-MM').format(stat.date);
          if (monthSecsMap.containsKey(mKey)) {
            monthSecsMap[mKey] = (monthSecsMap[mKey] ?? 0) + stat.studySeconds;
          }
        }
        monthSecsMap.forEach((mKey, secs) {
          bars.add(ChartBarItem(
            label: monthLabels[mKey] ?? '',
            fullDateStr: mKey,
            seconds: secs,
            isHighlight: mKey == DateFormat('yyyy-MM').format(now),
          ));
        });
        break;
    }

    final avgSecsPerDay = periodDays > 0 ? (totalSecs / periodDays).round() : 0;
    final metaphorText = _getAchievementMetaphor(totalSecs);

    // 处理选中的柱子信息
    String? selectedInfo;
    if (_selectedBarIndex != null && _selectedBarIndex! >= 0 && _selectedBarIndex! < bars.length) {
      final bar = bars[_selectedBarIndex!];
      selectedInfo = '${bar.fullDateStr} · 专注 ${_formatMinutes(bar.seconds)}';
    }

    return FrostedGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 周期选择器 Segment
          _buildDimensionSelector(accentColor, subtitleColor),
          const SizedBox(height: 18),

          // 主时长展示
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formatDuration(totalSecs),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '总专注时长',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subtitleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 具象化成就感标签（精神锚点）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 0.8),
            ),
            child: Text(
              metaphorText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accentColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 三项辅助统计指标（日均、天数、环比）
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _buildSubStatCol('日均专注', _formatMinutes(avgSecsPerDay), textColor, subtitleColor),
                _buildDivider(isDarkMode),
                _buildSubStatCol('专注天数', '$activeDays 天', textColor, subtitleColor),
                _buildDivider(isDarkMode),
                _buildSubStatCol(
                  '环比波动',
                  growthPercent == null
                      ? '-'
                      : '${growthPercent >= 0 ? '+' : ''}${growthPercent.toStringAsFixed(0)}%',
                  growthPercent != null && growthPercent > 0
                      ? accentColor
                      : (growthPercent != null && growthPercent < 0 ? const Color(0xFFEF4444) : textColor),
                  subtitleColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 柱状走势图标头
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedDimension == TimeDimension.today
                    ? '近 7 天对比（标明今日）'
                    : (_selectedDimension == TimeDimension.year || _selectedDimension == TimeDimension.allTime
                        ? '月度专注分布'
                        : '每日专注走势'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              if (selectedInfo != null)
                Text(
                  selectedInfo,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 柱状图组件
          _buildBarChart(bars, accentColor, subtitleColor, isDarkMode),
        ],
      ),
    );
  }

  Widget _buildDimensionSelector(Color accentColor, Color subtitleColor) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: subtitleColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: TimeDimension.values.map((dim) {
          final isSelected = _selectedDimension == dim;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDimension = dim;
                  _selectedBarIndex = null;
                });
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  dim.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? Colors.white : subtitleColor,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubStatCol(String label, String value, Color valueColor, Color subtitleColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: valueColor,
              fontFamily: 'NotoSansSC',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: subtitleColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDarkMode) {
    return Container(
      width: 0.6,
      height: 22,
      color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
    );
  }

  Widget _buildBarChart(
    List<ChartBarItem> bars,
    Color accentColor,
    Color subtitleColor,
    bool isDarkMode,
  ) {
    if (bars.isEmpty) return const SizedBox.shrink();

    // 寻找最大时长秒数
    int maxSecs = 0;
    for (final b in bars) {
      if (b.seconds > maxSecs) maxSecs = b.seconds;
    }
    if (maxSecs == 0) maxSecs = 1;

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bars.length, (index) {
          final item = bars[index];
          final heightFactor = (item.seconds / maxSecs).clamp(0.06, 1.0);
          final isSelected = _selectedBarIndex == index;

          Color barColor;
          if (isSelected) {
            barColor = accentColor;
          } else if (item.isHighlight) {
            barColor = accentColor.withValues(alpha: 0.85);
          } else if (item.seconds > 0) {
            barColor = isDarkMode ? Colors.white.withValues(alpha: 0.28) : Colors.black.withValues(alpha: 0.22);
          } else {
            barColor = isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05);
          }

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedBarIndex = _selectedBarIndex == index ? null : index;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: heightFactor,
                          child: Container(
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: (isSelected || item.isHighlight)
                                  ? [
                                      BoxShadow(
                                        color: accentColor.withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: (isSelected || item.isHighlight) ? FontWeight.w800 : FontWeight.w500,
                        color: (isSelected || item.isHighlight) ? accentColor : subtitleColor,
                        fontFamily: 'NotoSansSC',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ==========================================
  // 模块 2: 30 天学习热力图 (Heatmap)
  // ==========================================

  Widget _buildHeatmapSection(
    bool isDarkMode,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    Color accentColor,
    AppThemeConfig themeConfig,
  ) {
    return FrostedGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '30 天习惯热力图',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              _buildDisplayToggle(accentColor, subtitleColor),
            ],
          ),
          const SizedBox(height: 20),
          _buildHeatmapGrid(isDarkMode, themeConfig),
          const SizedBox(height: 16),
          _buildLegend(isDarkMode, subtitleColor, themeConfig),
        ],
      ),
    );
  }

  Widget _buildDisplayToggle(Color accentColor, Color subtitleColor) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: subtitleColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(HeatmapDisplayMode.date, '日期', accentColor, subtitleColor),
          _buildToggleButton(HeatmapDisplayMode.time, '时长', accentColor, subtitleColor),
          _buildToggleButton(HeatmapDisplayMode.count, '单词', accentColor, subtitleColor),
        ],
      ),
    );
  }

  Widget _buildToggleButton(HeatmapDisplayMode mode, String label, Color accentColor, Color subtitleColor) {
    final isSelected = _displayMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _displayMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? Colors.white : subtitleColor,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ),
    );
  }

  Widget _buildHeatmapGrid(bool isDarkMode, AppThemeConfig themeConfig) {
    final startDate = AppClock.today().subtract(const Duration(days: 29));

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = (constraints.maxWidth - 30) / 7;

        // 映射每日秒数与复习数
        final Map<String, int> secondsMap = {
          for (var item in _dailyReviewCounts)
            item['day'] as String: (item['seconds'] as int? ?? 0)
        };
        final Map<String, int> reviewCountMap = {
          for (var item in _dailyReviewCounts)
            item['day'] as String: (item['count'] as int? ?? 0)
        };

        // 映射去重单词数
        final Map<String, int> wordCountMap = {
          for (var item in _dailyWordCounts)
            item['day'] as String: (item['count'] as int? ?? 0)
        };

        return Wrap(
          spacing: 5,
          runSpacing: 5,
          children: List.generate(30, (index) {
            final date = startDate.add(Duration(days: index));
            final dateStr = DateFormat('yyyy-MM-dd').format(date);
            final status = _last30DaysDakaStatus.length > index
                ? _last30DaysDakaStatus[index]
                : UserDayStatus.notLogin.json;
            final isNotLearned = status != UserDayStatus.dakaed.json && status != UserDayStatus.studied.json;
            final color = _dakaStatus2Color(status, isDarkMode, themeConfig);
            final wordCount = wordCountMap[dateStr] ?? 0;
            final exactSeconds = secondsMap[dateStr] ?? 0;
            final reviewCount = reviewCountMap[dateStr] ?? 0;

            String displayText = '';
            if (_displayMode == HeatmapDisplayMode.date) {
              displayText = '${date.month}/${date.day}';
            } else if (_displayMode == HeatmapDisplayMode.count) {
              displayText = wordCount > 0 ? wordCount.toString() : '';
            } else {
              // 优先使用真实精确学习秒数，没有时才按复习数兜底
              int minutes = (exactSeconds / 60).round();
              if (minutes == 0 && reviewCount > 0) {
                minutes = (reviewCount * 15 / 60).ceil();
              }
              displayText = minutes > 0 ? '${minutes}m' : '';
            }

            return Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: isNotLearned
                    ? Border.all(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
                        width: 1,
                      )
                    : null,
              ),
              child: Center(
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 8,
                    color: isNotLearned
                        ? (isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5A7570))
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildLegend(bool isDarkMode, Color subtitleColor, AppThemeConfig themeConfig) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildLegendItem('已打卡', _dakaStatus2Color(UserDayStatus.dakaed.json, isDarkMode, themeConfig), subtitleColor),
        const SizedBox(width: 12),
        _buildLegendItem('未打卡', _dakaStatus2Color(UserDayStatus.studied.json, isDarkMode, themeConfig), subtitleColor),
        const SizedBox(width: 12),
        _buildLegendItem('未学习', _dakaStatus2Color(UserDayStatus.notLogin.json, isDarkMode, themeConfig), subtitleColor),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, Color subtitleColor) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: subtitleColor,
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ],
    );
  }

  Color _dakaStatus2Color(String status, bool isDarkMode, AppThemeConfig themeConfig) {
    if (status == UserDayStatus.dakaed.json) {
      return themeConfig.primaryColor;
    } else if (status == UserDayStatus.studied.json) {
      return themeConfig.dakaStudiedColor;
    } else {
      return isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9);
    }
  }
}

