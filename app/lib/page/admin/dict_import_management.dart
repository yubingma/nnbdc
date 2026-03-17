import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/api/dto.dart';

class DictImportManagementWidget extends StatefulWidget {
  const DictImportManagementWidget({super.key});

  @override
  State<DictImportManagementWidget> createState() => _DictImportManagementWidgetState();
}

class _DictImportManagementWidgetState extends State<DictImportManagementWidget> {
  String? _taskId;
  Map<String, dynamic>? _taskDetails;
  Timer? _timer;
  bool _isSubmitting = false;
  String _strategy = 'RECREATE';

  void _submitTask() async {
    setState(() {
      _isSubmitting = true;
      _taskId = null;
      _taskDetails = null;
    });

    try {
      final request = JsonMap({
        "ownerId": Global.sysUserId,
        "fileName": "System Dict Import (dog, apple)",
        "config": jsonEncode({
          "isSystemImport": true,
          "dictId": "0",
          "words": ["dog", "apple"],
          "strategy": _strategy
        })
      });

      final res = await Api.client.submitDictImportTask(request);
      if (res.success && res.data != null) {
        setState(() {
          _taskId = res.data;
        });
        ToastUtil.success('任务提交成功：$_taskId');
        _startPolling();
      } else {
        ToastUtil.error('任务提交失败：${res.msg}');
      }
    } catch (e) {
      ToastUtil.error('请求出错：$e');
      Global.logger.e('submitDictImportTask failed', error: e);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_taskId == null) {
        timer.cancel();
        return;
      }
      try {
        final res = await Api.client.getDictImportTaskStatus(_taskId!);
        if (res.success && res.data != null) {
          if (mounted) {
            setState(() {
              _taskDetails = res.data!.data;
            });
            String status = _taskDetails!['status'] ?? '';
            if (status == 'COMPLETED' || status == 'FAILED') {
              timer.cancel();
              ToastUtil.info('任务完成 ($status)');
            }
          }
        }
      } catch (e) {
        Global.logger.e('getDictImportTaskStatus failed', error: e);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'COMPLETED':
        color = Colors.green;
        break;
      case 'FAILED':
        color = Colors.red;
        break;
      case 'RUNNING':
        color = Colors.blue;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatItem(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value.toString(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: 'AI 词书资源导入',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.science, color: AppTheme.primaryColor),
                        ),
                        const SizedBox(width: 12),
                        const Text('测试场景：系统级导入', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('将使用 AI 为以下字典生成音标、词性、例句及同义词：', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['dog', 'apple'].map((w) => Chip(
                        label: Text(w),
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.05),
                        side: const BorderSide(color: Colors.transparent),
                      )).toList(),
                    ),
                    const SizedBox(height: 16), 
                    const Text('导入目标词典：', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.library_books, color: AppTheme.primaryColor, size: 20),
                          SizedBox(width: 8),
                          Text('通用词典 (ID: 0)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('遇到相同单词时的导入覆盖策略：', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[800] : Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _strategy,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'SKIP', child: Text('SKIP (跳过已存在单词)')),
                            DropdownMenuItem(value: 'RECREATE', child: Text('RECREATE (重新生成全部资源并覆盖)')),
                            DropdownMenuItem(value: 'APPEND', child: Text('APPEND (保留现有的，并追加新内容)')),
                          ],
                          onChanged: _isSubmitting ? null : (val) {
                            if (val != null) {
                              setState(() => _strategy = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting || (_taskDetails != null && _taskDetails!['status'] == 'RUNNING') ? null : _submitTask,
                        icon: _isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.rocket_launch),
                        label: Text(_isSubmitting ? '正在提交请求...' : '开始执行导入'),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            if (_taskId != null) ...[
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: Text('执行状态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: _taskDetails != null ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('任务 ID: ${_taskId!.substring(0, 8)}...', style: const TextStyle(color: Colors.grey, fontFamily: 'monospace')),
                          _buildStatusBadge(_taskDetails!['status'] ?? 'UNKNOWN'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // 进度展示 (这里简单模拟：如果有 progress 字段就用，否则按状态)
                      if (_taskDetails!['status'] == 'RUNNING') ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Center(child: Text('AI 正在全力生成中，请耐心等待...', style: TextStyle(fontSize: 12, color: Colors.grey))),
                      ] else if (_taskDetails!['status'] == 'COMPLETED') ...[
                        LinearProgressIndicator(value: 1.0, color: Colors.green, backgroundColor: Colors.green.withValues(alpha: 0.2)),
                        const SizedBox(height: 8),
                        const Center(child: Text('任务已完成', style: TextStyle(fontSize: 12, color: Colors.green))),
                      ],

                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      
                      // 结果统计卡片
                      if (_taskDetails!['results'] != null) ...[
                        const Text('数据变动统计', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Builder(
                          builder: (context) {
                            try {
                              final stats = jsonDecode(_taskDetails!['results'] as String);
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _buildStatItem('新增单词', stats['addedWordCount'] ?? 0, Icons.add_circle_outline, Colors.blue),
                                  _buildStatItem('新增释义', stats['addedMeaningCount'] ?? 0, Icons.menu_book, Colors.purple),
                                  _buildStatItem('生成例句', stats['addedSentenceCount'] ?? 0, Icons.format_quote, Colors.orange),
                                  _buildStatItem('AI 音频资源', stats['addedAudioCount'] ?? 0, Icons.volume_up, Colors.teal),
                                  _buildStatItem('词频跳过', stats['skippedCount'] ?? 0, Icons.skip_next, Colors.grey),
                                  if ((stats['errorCount'] ?? 0) > 0)
                                    _buildStatItem('处理失败', stats['errorCount'], Icons.error_outline, Colors.red),
                                ],
                              );
                            } catch (e) {
                              return const Text('统计数据解析失败');
                            }
                          }
                        ),
                      ],
                      if (_taskDetails!['log'] != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                          child: Text(_taskDetails!['log'], style: const TextStyle(color: Colors.red, fontSize: 12)),
                        )
                      ]
                    ],
                  ) : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
