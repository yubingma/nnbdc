import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. 获取打卡状态
      final result = await UserBo().getDayStatuses(30);
      if (result.success) {
        _last30DaysDakaStatus = result.data!;
      }
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
