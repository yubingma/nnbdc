import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/config.dart';

class AdminCigenOptimizePage extends StatefulWidget {
  const AdminCigenOptimizePage({super.key});

  @override
  State<AdminCigenOptimizePage> createState() => _AdminCigenOptimizePageState();
}

class _AdminCigenOptimizePageState extends State<AdminCigenOptimizePage> {
  Map<String, dynamic>? _taskStatus;
  Timer? _pollingTimer;

  String get _baseUrl => Api.useProdUrl ? Config.profiles["prod"]["service_url"] : Config.serviceUrl;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _fetchStatus();
      }
    });
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await Api.dio.get('$_baseUrl/admin/cigen/batchOptimizeStatus.do');
      final res = response.data;
      if (res['success'] == true && mounted) {
        setState(() {
          _taskStatus = res['data'];
        });
      }
    } catch (e) {
      // debugPrint('Failed to poll status: $e');
    }
  }

  Future<void> _startFullOptimize() async {
    try {
      final response = await Api.dio.post('$_baseUrl/admin/cigen/startFullOptimize.do', queryParameters: {
        'userId': Global.getLoggedInUser()?.id,
      });
      final res = response.data;
      if (res['success'] == true) {
        ToastUtil.success('成功启动全量优化任务');
        _fetchStatus();
      } else {
        ToastUtil.error('启动失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('请求异常: $e');
    }
  }

  Future<void> _stopOptimize() async {
    try {
      final response = await Api.dio.post('$_baseUrl/admin/cigen/stopBatchOptimize.do', queryParameters: {
        'userId': Global.getLoggedInUser()?.id,
      });
      final res = response.data;
      if (res['success'] == true) {
        ToastUtil.success('已发送停止指令');
        _fetchStatus();
      } else {
        ToastUtil.error('停止失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('请求异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    final bool isRunning = _taskStatus?['isRunning'] == true;
    final String statusMsg = _taskStatus?['statusMsg'] ?? '任务未启动';
    final int total = _taskStatus?['totalIndices'] ?? 0;
    final int current = _taskStatus?['currentIndex'] ?? 0;
    final List optimizedLogs = _taskStatus?['optimizedLogs'] ?? [];

    return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppTheme.createGradientAppBar(
          title: 'AI 词根解析清洗优化',
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: isDarkMode ? Colors.grey[900] : Colors.white,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '点击按钮开始自动化调用 AI (Qwen-Max) 清洗并优化现有的词根解析数据。该过程会在后台异步执行。',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (isRunning) {
                            _stopOptimize();
                          } else {
                            _startFullOptimize();
                          }
                        },
                        icon: Icon(isRunning ? Icons.stop : Icons.auto_awesome),
                        label: Text(isRunning ? '中止任务' : '开始全量自动优化'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunning ? Colors.red : AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[850] : Colors.blue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insights, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('状态: $statusMsg${isRunning ? ' ($current / $total)' : ''}', 
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('本次已成功优化条目: ${optimizedLogs.length}',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            ],
                          ),
                        ),
                        if (isRunning && total > 0) 
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              value: current / total, 
                              backgroundColor: Colors.grey[300]
                            )
                          ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            Expanded(
              child: _buildLogList(optimizedLogs, isDarkMode),
            )
          ],
        ));
  }

  Widget _buildLogList(List logs, bool isDarkMode) {
    if (logs.isEmpty) {
      return const Center(child: Text('暂无优化记录', style: TextStyle(color: Colors.grey)));
    }

    final reversedLogs = logs.reversed.toList();

    return ListView.builder(
      itemCount: reversedLogs.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final log = reversedLogs[index];
        final bool isStructured = log['type'] == 'STRUCTURED';
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          color: isDarkMode ? Colors.grey[800]! : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isStructured ? Colors.teal : AppTheme.primaryColor).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log['spell'] ?? '未知',
                        style: TextStyle(color: isStructured ? Colors.teal : AppTheme.primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isStructured ? '词根结构化' : '词源解析优化',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (log['before'] != null && log['after'] != null)
                  _buildExplainDiff(log['before'], log['after'], isDarkMode, type: log['type'])
                else
                  Text('处理详情: ${log['desc'] ?? '-'} -> ${log['status'] ?? '-'}', 
                       style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExplainDiff(String before, String after, bool isDarkMode, {String? type}) {
    final bool isStructured = type == 'STRUCTURED';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _diffItem(isStructured ? '原始描述' : '修改前', before, isStructured ? Colors.blueGrey : Colors.red, isDarkMode),
        const SizedBox(height: 8),
        _diffItem(isStructured ? '结构化全字段' : '通过 AI 优化后', after, isStructured ? Colors.teal : Colors.green, isDarkMode),
      ],
    );
  }

  Widget _diffItem(String label, String text, Color color, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
        ),
      ],
    );
  }
}
