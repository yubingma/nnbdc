import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:provider/provider.dart';

class StudyStatsPage extends StatefulWidget {
  const StudyStatsPage({super.key});

  @override
  State<StudyStatsPage> createState() => _StudyStatsPageState();
}

class _StudyStatsPageState extends State<StudyStatsPage> {
  bool _isLoading = true;
  List<String> _last30DaysDakaStatus = [];
  List<Map<String, dynamic>> _dailyReviewCounts = [];
  int _totalReviews = 0;
  int _maxDailyReviews = 0;
  int _continuousDakaDays = 0;

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

      // 1. 获取打卡状态
      final result = await UserBo().getDayStatuses(30);
      if (result.success) {
        _last30DaysDakaStatus = result.data!;
      }

      // 2. 获取每日复习数
      _dailyReviewCounts = await MyDatabase.instance.learningLogsDao.getDailyReviewCounts(userId, 30);
      
      _totalReviews = 0;
      _maxDailyReviews = 0;
      for (var item in _dailyReviewCounts) {
        final count = item['count'] as int;
        _totalReviews += count;
        if (count > _maxDailyReviews) _maxDailyReviews = count;
      }

      // 3. 获取连续打卡天数
      _continuousDakaDays = await UserBo().calculateContinuousDakaDays(userId);

    } catch (e) {
      Global.logger.e('加载学习统计失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final accentColor = isDarkMode ? const Color(0xFF22D3EE) : const Color(0xFF0EA5E9);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('学习统计', style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'NotoSansSC')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeatmapSection(isDarkMode, cardColor, textColor, subtitleColor),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSummarySection(Color accentColor, Color cardColor, Color textColor, Color subtitleColor) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            '累计复习',
            _totalReviews.toString(),
            '词',
            Icons.auto_awesome_rounded,
            accentColor,
            cardColor,
            textColor,
            subtitleColor,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryCard(
            '连续打卡',
            _continuousDakaDays.toString(),
            '天',
            Icons.local_fire_department_rounded,
            Colors.orangeAccent,
            cardColor,
            textColor,
            subtitleColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, String unit, IconData icon, Color color, Color cardColor, Color textColor, Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  color: subtitleColor,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: subtitleColor,
              fontWeight: FontWeight.w500,
              fontFamily: 'NotoSansSC',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapSection(bool isDarkMode, Color cardColor, Color textColor, Color subtitleColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '打卡热力图',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textColor,
              fontFamily: 'NotoSansSC',
            ),
          ),
          const SizedBox(height: 20),
          _buildHeatmapGrid(isDarkMode),
          const SizedBox(height: 16),
          _buildLegend(isDarkMode, subtitleColor),
        ],
      ),
    );
  }

  Widget _buildHeatmapGrid(bool isDarkMode) {
    final now = AppClock.now();
    final startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = (constraints.maxWidth - 30) / 7;
        
        return Wrap(
          spacing: 5,
          runSpacing: 5,
          children: List.generate(30, (index) {
            final date = startDate.add(Duration(days: index));
            final status = _last30DaysDakaStatus[index];
            final color = _dakaStatus2Color(status);
            
            return Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  date.day.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: color == Colors.transparent || color == Colors.grey.withValues(alpha: 0.1) 
                        ? Colors.grey 
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

  Widget _buildLegend(bool isDarkMode, Color subtitleColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildLegendItem('已打卡', _dakaStatus2Color(UserDayStatus.dakaed.json), subtitleColor),
        const SizedBox(width: 12),
        _buildLegendItem('仅学习', _dakaStatus2Color(UserDayStatus.studied.json), subtitleColor),
        const SizedBox(width: 12),
        _buildLegendItem('无记录', _dakaStatus2Color(UserDayStatus.notLogin.json), subtitleColor),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, Color subtitleColor) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: subtitleColor, fontFamily: 'NotoSansSC'),
        ),
      ],
    );
  }

  Widget _buildReviewChartSection(Color accentColor, Color cardColor, Color textColor, Color subtitleColor, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近30天复习量',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textColor,
              fontFamily: 'NotoSansSC',
            ),
          ),
          const SizedBox(height: 24),
          _buildBarChart(accentColor, isDarkMode, subtitleColor),
        ],
      ),
    );
  }

  Widget _buildBarChart(Color accentColor, bool isDarkMode, Color subtitleColor) {
    if (_dailyReviewCounts.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text('暂无数据')));
    }

    final now = AppClock.now();
    
    // 映射数据，确保有30天的数据点
    final Map<String, int> dataMap = {
      for (var item in _dailyReviewCounts) item['day'] as String: item['count'] as int
    };
    
    final List<int> counts = [];
    final List<String> days = [];
    for (int i = 29; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      counts.add(dataMap[dateStr] ?? 0);
      days.add(DateFormat('MM/dd').format(date));
    }

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(counts.length, (index) {
          final count = counts[index];
          final ratio = _maxDailyReviews == 0 ? 0.0 : count / _maxDailyReviews;
          
          return Expanded(
            child: Tooltip(
              message: '${days[index]}: $count词',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: ratio * 150 + 2, // 最小高度 2
                    decoration: BoxDecoration(
                      color: index == counts.length - 1 ? accentColor : accentColor.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (index % 5 == 0 || index == counts.length - 1)
                    Text(
                      days[index],
                      style: TextStyle(fontSize: 8, color: subtitleColor),
                    )
                  else
                    const SizedBox(height: 10),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Color _dakaStatus2Color(String status) {
    if (status == UserDayStatus.dakaed.json) {
      return const Color(0xFF10B981); // Emerald Green
    } else if (status == UserDayStatus.studied.json) {
      return const Color(0xFFFACC15); // Amber/Yellow
    } else {
      return const Color(0xFF94A3B8).withValues(alpha: 0.3); // Slate Grey
    }
  }
}
