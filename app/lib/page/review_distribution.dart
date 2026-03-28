import 'package:flutter/material.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';

class ReviewDistributionPage extends StatefulWidget {
  const ReviewDistributionPage({super.key});

  @override
  State<ReviewDistributionPage> createState() => _ReviewDistributionPageState();
}

class BarChartData {
  final String label;
  final int totalCount;
  final bool isToday;
  final bool isOverdue;
  final int sortKey;

  BarChartData({
    required this.label,
    required this.totalCount,
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final db = MyDatabase.instance;
    final userId = Global.currentUserId;
    if (userId == null) return;

    final data = await db.learningWordsDao.getLearningWordsForCloud(userId);
    final now = AppClock.now();
    final nowDate = DateTime(now.year, now.month, now.day);

    Map<int, int> dayToCounts = {};
    _totalWords = data.length;

    for (var item in data) {
      final lastDateRaw = item['lastLearningDate'] as DateTime? ?? now;
      final scheduledDays = item['scheduledDays'] as int? ?? 0;
      final nextDateRaw = lastDateRaw.add(Duration(days: scheduledDays));
      
      final nextDate = DateTime(nextDateRaw.year, nextDateRaw.month, nextDateRaw.day);
      final daysDiff = nextDate.difference(nowDate).inDays;

      int key;
      if (daysDiff >= 0) {
        key = daysDiff;
      } else {
        int overdueDays = -daysDiff;
        key = -((overdueDays + 9) ~/ 10 * 10);
      }

      dayToCounts[key] = (dayToCounts[key] ?? 0) + 1;
    }

    var sortedKeys = dayToCounts.keys.toList()..sort();

    _maxCount = 0;
    _barDataList = sortedKeys.map((key) {
      final count = dayToCounts[key]!;
      if (count > _maxCount) _maxCount = count;

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
        totalCount: count,
        isToday: isToday,
        isOverdue: isOverdue,
        sortKey: key,
      );
    }).toList();

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            const Text('复习分布图', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            if (!_isLoading) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$_totalWords 词', style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
            ]
          ],
        ),
        elevation: 0,
        backgroundColor: AppTheme.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
            onPressed: () => _showExplainDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadData(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _barDataList.isEmpty
              ? const Center(child: Text("暂无数据"))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  itemCount: _barDataList.length,
                  itemBuilder: (context, index) {
                    return _buildBarRow(_barDataList[index], isDarkMode);
                  },
                ),
    );
  }

  Widget _buildBarRow(BarChartData data, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              data.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: data.isToday ? FontWeight.bold : FontWeight.normal,
                color: data.isToday 
                  ? AppTheme.primaryColor 
                  : (data.isOverdue ? Colors.redAccent : (isDarkMode ? Colors.white70 : Colors.black54)),
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
                    Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 30,
                          width: maxWidth,
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
                          ),
                        ),
                        _buildSimpleBar(data, barWidth),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "${data.totalCount}",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: data.isToday ? AppTheme.primaryColor : (isDarkMode ? Colors.white60 : Colors.black54),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleBar(BarChartData data, double totalBarWidth) {
    if (totalBarWidth <= 0) return const SizedBox.shrink();

    return Container(
      height: 30,
      width: totalBarWidth,
      decoration: BoxDecoration(
        color: data.isToday 
            ? AppTheme.primaryColor 
            : (data.isOverdue ? Colors.redAccent : AppTheme.primaryColor.withValues(alpha: 0.5)),
      ),
    );
  }

  void _showExplainDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('复习分布说明', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogDescItem(Icons.height, '纵轴 (Y轴)', '代表时间维度。上方为已逾期的任务，下方为未来的复习安排。'),
            const SizedBox(height: 12),
            _dialogDescItem(Icons.bar_chart, '横轴 (X轴)', '代表单词数量。柱状条越长表示该时段复习任务越重。'),
            const SizedBox(height: 12),
            _dialogDescItem(Icons.color_lens_outlined, '颜色含义', '红色代表逾期，深蓝色代表今天，浅蓝色代表未来。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _dialogDescItem(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(desc, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}
