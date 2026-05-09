import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

enum HeatmapDisplayMode { date, time, count }

class StudyStatsPage extends StatefulWidget {
  const StudyStatsPage({super.key});

  @override
  State<StudyStatsPage> createState() => _StudyStatsPageState();
}

class _StudyStatsPageState extends State<StudyStatsPage> {
  bool _isLoading = true;
  List<String> _last30DaysDakaStatus = [];
  List<Map<String, dynamic>> _dailyReviewCounts = [];
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

      // 1. 获取打卡状态
      final result = await UserBo().getDayStatuses(30);
      if (result.success) {
        _last30DaysDakaStatus = result.data!;
      }

      // 2. 获取每日复习数
      _dailyReviewCounts = await MyDatabase.instance.learningLogsDao.getDailyReviewCounts(userId, 30);
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
                  _buildHeatmapSection(isDarkMode, cardColor, textColor, subtitleColor, accentColor),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildHeatmapSection(bool isDarkMode, Color cardColor, Color textColor, Color subtitleColor, Color accentColor) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '学习热力图',
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
          _buildHeatmapGrid(isDarkMode),
          const SizedBox(height: 16),
          _buildLegend(isDarkMode, subtitleColor),
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
          _buildToggleButton(HeatmapDisplayMode.date, '日期', accentColor),
          _buildToggleButton(HeatmapDisplayMode.time, '时长', accentColor),
          _buildToggleButton(HeatmapDisplayMode.count, '单词', accentColor),
        ],
      ),
    );
  }

  Widget _buildToggleButton(HeatmapDisplayMode mode, String label, Color accentColor) {
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
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildHeatmapGrid(bool isDarkMode) {
    final startDate = AppClock.today().subtract(const Duration(days: 29));
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = (constraints.maxWidth - 30) / 7;
        
        // 映射复习数
        final Map<String, int> countMap = {
          for (var item in _dailyReviewCounts) item['day'] as String: item['count'] as int
        };

        return Wrap(
          spacing: 5,
          runSpacing: 5,
          children: List.generate(30, (index) {
            final date = startDate.add(Duration(days: index));
            final dateStr = DateFormat('yyyy-MM-dd').format(date);
            final status = _last30DaysDakaStatus[index];
            final color = _dakaStatus2Color(status);
            final count = countMap[dateStr] ?? 0;
            
            String displayText = '';
            if (_displayMode == HeatmapDisplayMode.date) {
              displayText = '${date.month}/${date.day}';
            } else if (_displayMode == HeatmapDisplayMode.count) {
              displayText = count > 0 ? count.toString() : '';
            } else {
              // 估算时长：每个词 15 秒 (0.25 分钟)
              final minutes = (count * 15 / 60).ceil();
              displayText = minutes > 0 ? '${minutes}m' : '';
            }
            
            return Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontSize: 8,
                    color: color == Colors.transparent || color == Colors.grey.withValues(alpha: 0.3) 
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
        _buildLegendItem('未打卡', _dakaStatus2Color(UserDayStatus.studied.json), subtitleColor),
        const SizedBox(width: 12),
        _buildLegendItem('未学习', _dakaStatus2Color(UserDayStatus.notLogin.json), subtitleColor),
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
