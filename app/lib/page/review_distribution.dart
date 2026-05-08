import 'package:flutter/material.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/page/word_list/bucket_words.dart';

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

    Map<int, int> dayToTotalCounts = {};
    Map<int, int> dayToNewCounts = {};
    _totalWords = data.length;

    for (var item in data) {
      final isNew = (item['learnedTimes'] ?? 0) == 0;
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

      dayToTotalCounts[key] = (dayToTotalCounts[key] ?? 0) + 1;
      if (isNew) {
        dayToNewCounts[key] = (dayToNewCounts[key] ?? 0) + 1;
      }
    }

    var sortedKeys = dayToTotalCounts.keys.toList()..sort();

    _maxCount = 0;
    _barDataList = sortedKeys.map((key) {
      final totalCount = dayToTotalCounts[key]!;
      final newCount = dayToNewCounts[key] ?? 0;
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
        newCount: newCount,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                '复习分布图',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!_isLoading) ...[
              const SizedBox(width: 4),
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

  void _onBarTap(BarChartData data) {
    toBucketWordsListPage(data.sortKey, data.label)?.then((_) => _loadData());
  }

  Widget _buildBarRow(BarChartData data, bool isDarkMode) {
    return InkWell(
      onTap: () => _onBarTap(data),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
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
                  final maxWidth = constraints.maxWidth - 80; 
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
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'NotoSansSC',
                            color: isDarkMode ? Colors.white60 : Colors.black54,
                          ),
                          children: [
                            TextSpan(text: "${data.totalCount - data.newCount}"),
                            if (data.newCount > 0) ...[
                              TextSpan(
                                text: " | ",
                                style: TextStyle(
                                  fontWeight: FontWeight.normal,
                                  color: isDarkMode ? Colors.white24 : Colors.black12,
                                ),
                              ),
                              TextSpan(
                                text: "${data.newCount}",
                                style: const TextStyle(color: Color(0xFF8B5CF6)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleBar(BarChartData data, double totalBarWidth) {
    if (totalBarWidth <= 0) return const SizedBox.shrink();

    final reviewCount = data.totalCount - data.newCount;
    final double reviewWidth = (reviewCount / data.totalCount) * totalBarWidth;
    final double newWidth = (data.newCount / data.totalCount) * totalBarWidth;

    return Row(
      children: [
        if (reviewWidth > 0)
          Container(
            height: 30,
            width: reviewWidth < 1 && reviewWidth > 0 ? 1 : reviewWidth, // 确保极短的条也能看见
            decoration: BoxDecoration(
              color: data.isToday 
                  ? AppTheme.primaryColor 
                  : (data.isOverdue ? Colors.redAccent : AppTheme.primaryColor.withValues(alpha: 0.5)),
            ),
          ),
        if (newWidth > 0)
          Container(
            height: 30,
            width: newWidth < 1 && newWidth > 0 ? 1 : newWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6),
            ),
          ),
      ],
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
            _dialogDescItem(
              Icons.color_lens_outlined, 
              '颜色含义', 
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 13, color: Colors.grey, fontFamily: 'NotoSansSC'),
                  children: [
                    const TextSpan(text: '红色', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    const TextSpan(text: '代表逾期待复习，'),
                    TextSpan(text: '深蓝色', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                    const TextSpan(text: '代表今日待复习，'),
                    TextSpan(text: '浅蓝色', style: TextStyle(color: AppTheme.primaryColor.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
                    const TextSpan(text: '代表未来待复习，'),
                    const TextSpan(text: '紫色', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                    const TextSpan(text: '代表新词（从未开始背诵）。'),
                  ],
                ),
              ),
            ),
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

  Widget _dialogDescItem(IconData icon, String title, dynamic desc) {
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
              if (desc is Widget) desc else Text(desc.toString(), style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}
