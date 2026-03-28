import 'package:flutter/material.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';

class MemoryCloudPage extends StatefulWidget {
  const MemoryCloudPage({super.key});

  @override
  State<MemoryCloudPage> createState() => _MemoryCloudPageState();
}

class BarChartData {
  final String label;
  final int totalCount;
  final Map<int, int> stateCounts; // state -> count
  final bool isToday;
  final bool isOverdue;
  final int sortKey;

  BarChartData({
    required this.label,
    required this.totalCount,
    required this.stateCounts,
    this.isToday = false,
    this.isOverdue = false,
    required this.sortKey,
  });
}

class _MemoryCloudPageState extends State<MemoryCloudPage> {
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

    Map<int, Map<int, int>> dayToStateCounts = {};
    _totalWords = data.length;

    for (var item in data) {
      final lastDate = item['lastLearningDate'] as DateTime? ?? now;
      final scheduledDays = item['scheduledDays'] as int? ?? 0;
      final nextDate = lastDate.add(Duration(days: scheduledDays));
      final daysDiff = nextDate.difference(now).inDays;
      final state = (item['state'] as int?) ?? 0;

      int key;
      if (daysDiff >= 0) {
        key = daysDiff;
      } else {
        // Overdue bucket: group by 10 days
        int overdueDays = -daysDiff;
        key = -((overdueDays + 9) ~/ 10 * 10); // -10, -20, -30...
      }

      dayToStateCounts.putIfAbsent(key, () => {});
      dayToStateCounts[key]![state] = (dayToStateCounts[key]![state] ?? 0) + 1;
    }

    // Sort keys: oldest overdue (most negative) to furthest future
    var sortedKeys = dayToStateCounts.keys.toList()..sort();

    _maxCount = 0;
    _barDataList = sortedKeys.map((key) {
      final counts = dayToStateCounts[key]!;
      final total = counts.values.fold(0, (a, b) => a + b);
      if (total > _maxCount) _maxCount = total;

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
        totalCount: total,
        stateCounts: counts,
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
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        itemCount: _barDataList.length,
                        itemBuilder: (context, index) {
                          return _buildBarRow(_barDataList[index], isDarkMode);
                        },
                      ),
                    ),
                    _buildLegend(isDarkMode),
                  ],
                ),
    );
  }

  Widget _buildBarRow(BarChartData data, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          // Y轴标签 (时间)
          SizedBox(
            width: 80,
            child: Text(
              data.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: data.isToday ? FontWeight.bold : FontWeight.normal,
                color: data.isToday 
                  ? AppTheme.primaryColor 
                  : (data.isOverdue ? Colors.redAccent : (isDarkMode ? Colors.white70 : Colors.black54)),
              ),
            ),
          ),
          // X轴柱状图
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth - 50; // 为数字留出空间
                final barWidth = _maxCount == 0 ? 0.0 : (data.totalCount / _maxCount) * maxWidth;
                
                return Row(
                  children: [
                    Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // 背景条
                        Container(
                          height: 24,
                          width: maxWidth,
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
                          ),
                        ),
                        // 实际分段条
                        _buildStackedBar(data, barWidth),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // 单词数标注
                    Text(
                      "${data.totalCount}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: data.isToday ? AppTheme.primaryColor : (isDarkMode ? Colors.white38 : Colors.black38),
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

  Widget _buildStackedBar(BarChartData data, double totalBarWidth) {
    if (totalBarWidth <= 0) return const SizedBox.shrink();

    // 如果是逾期，主色调设为红色
    if (data.isOverdue) {
      return Container(
        height: 24,
        width: totalBarWidth,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.redAccent.withValues(alpha: 0.8), Colors.red.withValues(alpha: 0.6)],
          ),
          boxShadow: [
            BoxShadow(color: Colors.red.withValues(alpha: 0.1), blurRadius: 4, spreadRadius: 0)
          ]
        ),
      );
    }

    // 非逾期，展示分段 (New, Learning, Review)
    List<Widget> segments = [];
    final states = [0, 1, 2, 3]; 
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple];
    
    for (int i = 0; i < states.length; i++) {
      int count = data.stateCounts[states[i]] ?? 0;
      if (count > 0) {
        double segmentWidth = (count / data.totalCount) * totalBarWidth;
        segments.add(
          Container(
            height: 24,
            width: segmentWidth,
            color: colors[i].withValues(alpha: 0.7),
          ),
        );
      }
    }

    return Row(children: segments);
  }

  Widget _buildLegend(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        border: Border(top: BorderSide(color: isDarkMode ? Colors.white12 : Colors.black.withValues(alpha: 0.05))),
        boxShadow: [
          if (!isDarkMode) BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, -5))
        ]
      ),
      child: SafeArea(
        top: false,
        child: Wrap(
          spacing: 20,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            _legendItem('新词', Colors.blue),
            _legendItem('学习中', Colors.green),
            _legendItem('复习中', Colors.orange),
            _legendItem('已逾期', Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
            _dialogDescItem(Icons.color_lens_outlined, '颜色含义', '红色代表逾期，蓝色为新词，绿色为初次学习，橙色为长期复习。'),
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
