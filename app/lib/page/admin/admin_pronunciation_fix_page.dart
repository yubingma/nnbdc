import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/config.dart';

class AdminPronunciationFixPage extends StatefulWidget {
  const AdminPronunciationFixPage({super.key});

  @override
  State<AdminPronunciationFixPage> createState() => _AdminPronunciationFixPageState();
}

class _AdminPronunciationFixPageState extends State<AdminPronunciationFixPage> {
  Map<String, dynamic>? _taskStatus;
  Timer? _pollingTimer;
  bool _fixUk = true;
  bool _fixUs = true;

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
      final response = await Api.dio.get('$_baseUrl/admin/pronunciation/fixStatus.do');
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

  Future<void> _startFix() async {
    try {
      final response = await Api.dio.post('$_baseUrl/admin/pronunciation/startFix.do', queryParameters: {
        'userId': Global.getLoggedInUser()?.id,
        'fixUk': _fixUk,
        'fixUs': _fixUs,
      });
      final res = response.data;
      if (res['success'] == true) {
        ToastUtil.success('发音补齐任务已启动');
        _fetchStatus();
      } else {
        ToastUtil.error('启动失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('请求异常: $e');
    }
  }

  Future<void> _stopFix() async {
    try {
      final response = await Api.dio.post('$_baseUrl/admin/pronunciation/stopFix.do', queryParameters: {
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
    final int ukOk = _taskStatus?['ukOk'] ?? 0;
    final int ukFail = _taskStatus?['ukFail'] ?? 0;
    final int usOk = _taskStatus?['usOk'] ?? 0;
    final int usFail = _taskStatus?['usFail'] ?? 0;
    final List failedLogs = _taskStatus?['failedLogs'] ?? [];

    return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppTheme.createGradientAppBar(
          title: '发音补齐',
          context: context,
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
                          '逐词检查英音(_uk)、美音(_us)发音文件,缺失的自动从有道下载,失败回退 AI 合成。该过程会在后台异步执行。',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (isRunning) {
                            _stopFix();
                          } else {
                            _startFix();
                          }
                        },
                        icon: Icon(isRunning ? Icons.stop : Icons.record_voice_over),
                        label: Text(isRunning ? '中止任务' : '开始补齐'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunning ? Colors.red : Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('美音 (_us)'),
                        selected: _fixUs,
                        onSelected: isRunning ? null : (v) => setState(() => _fixUs = v),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('英音 (_uk)'),
                        selected: _fixUk,
                        onSelected: isRunning ? null : (v) => setState(() => _fixUk = v),
                      ),
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
                              Text('美音: OK $usOk / 失败 $usFail   英音: OK $ukOk / 失败 $ukFail',
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
                              backgroundColor: Colors.grey[300],
                            ),
                          ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            Expanded(
              child: _buildFailedList(failedLogs, isDarkMode),
            )
          ],
        ));
  }

  Widget _buildFailedList(List logs, bool isDarkMode) {
    if (logs.isEmpty) {
      return const Center(child: Text('暂无失败记录', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      itemCount: logs.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final log = logs[index];
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
                        color: const Color(0xFFE91E63).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log['spell'] ?? '未知',
                        style: const TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (log['error'] != null)
                      Flexible(
                        child: Text(
                          log['error'],
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      )
                    else
                      Text(
                        '美音: ${log['us'] ?? '-'}   英音: ${log['uk'] ?? '-'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}