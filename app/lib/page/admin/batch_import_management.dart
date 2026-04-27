import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nnbdc/api/api.dart';

import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';

import 'package:nnbdc/util/toast_util.dart';

class BatchImportManagementPage extends StatefulWidget {
  const BatchImportManagementPage({super.key});

  @override
  State<BatchImportManagementPage> createState() => _BatchImportManagementPageState();
}

class _BatchImportManagementPageState extends State<BatchImportManagementPage> {
  final TextEditingController _dirPathCtrl = TextEditingController(
    text: "/Volumes/ssd/ppdc/tools/book/大学/toimport"
  );
  bool _isSubmitting = false;
  Map<String, dynamic> _batches = {};
  Timer? _timer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBatches();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadBatches(silent: true);
    });
  }

  @override
  void dispose() {
    _dirPathCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadBatches({bool silent = false}) async {
    if (_isLoading) return;
    if (!silent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() { _isLoading = true; });
      });
    }
    try {
      final res = await Api.client.getAllBatches();
      if (res.success && res.data != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _batches = res.data!.data;
            });
          }
        });
      }
    } catch (e, stack) {
      Global.logger.e('获取批次异常', error: e, stackTrace: stack);
      if (!silent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ToastUtil.error('获取批次失败: $e');
        });
      }
    } finally {
      if (!silent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() { _isLoading = false; });
        });
      }
    }
  }


  Future<void> _submitBatch() async {
    final dirPath = _dirPathCtrl.text.trim();
    if (dirPath.isEmpty) {
      ToastUtil.info('请输入词书绝对路径');
      return;
    }

    setState(() { _isSubmitting = true; });
    try {
      final res = await Api.client.submitBatchImportTask(dirPath);
      if (res.success) {
        ToastUtil.success(res.data ?? '任务提交成功');
        _loadBatches();
      } else {
        ToastUtil.error(res.msg ?? '未知错误');
      }
    } catch (e, stack) {
      Global.logger.e('批量导入提交异常', error: e, stackTrace: stack);
      ToastUtil.error('提交失败: $e');
    }
 finally {
      if (mounted) {
        setState(() { _isSubmitting = false; });
      }
    }
  }

  Future<void> _pickDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory != null) {
        setState(() {
          _dirPathCtrl.text = selectedDirectory;
        });
      }
    } catch (e) {
      Global.logger.e('选取文件夹失败', error: e);
      ToastUtil.error('选取文件夹异常: $e');
    }
  }


  Future<void> _cancelBatch(String batchId) async {
    if (batchId == 'UNBATCHED') {
      ToastUtil.info('无法操作未批次任务');
      return;
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    bool confirm = await showDialog(


      context: context,
      builder: (context) => AlertDialog(
        title: const Text('中止批次任务', style: TextStyle(color: Colors.orange)),
        content: Text('您确定要强行中止批次【$batchId】中所有待执行与运行中的词书导入任务吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('确定终止'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final res = await Api.client.cancelBatch(batchId);
      if (res.success) {
        ToastUtil.success(res.data ?? '终止指令下发成功');
      } else {
        ToastUtil.error(res.msg ?? '未知错误');
      }
    } catch (e, stack) {
      Global.logger.e('终止批次任务异常', error: e, stackTrace: stack);
      ToastUtil.error('操作失败: $e');
    }
  }

  Future<void> _deleteBatch(String batchId, List tasks) async {
    if (batchId == 'UNBATCHED') {
      ToastUtil.info('无法删除未批次任务');
      return;
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    bool confirm = await showDialog(


      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理批次', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('您确定要彻底删除批次【$batchId】导入的所有词书吗？此操作不可撤销！'),
            const SizedBox(height: 16),
            const Text(
              '将要被清理的词书列表:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.maxFinite,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: tasks.map<Widget>((task) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '• ${task['dictName'] ?? task['fileName'] ?? '未命名词书'}',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    );
                  }).toList(),
                ),
              ),

            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('彻底清除'),
          ),
        ],
      ),
    ) ?? false;


    if (!confirm) return;

    try {
      final res = await Api.client.deleteBatch(batchId);
      if (res.success) {
        ToastUtil.success(res.data ?? '删除成功');
        _loadBatches();
      } else {
        ToastUtil.error(res.msg ?? '未知错误');
      }
    } catch (e, stack) {
      Global.logger.e('删除批次异常', error: e, stackTrace: stack);
      ToastUtil.error('删除异常: $e');
    }


  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.createGradientAppBar(
        title: '批量导入管理',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white)
        ),
      ),
      body: _isLoading && _batches.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBatches,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSubmitCard(),
                  const SizedBox(height: 16),
                  _buildBatchList(),
                ],
              ),
            ),
    );
  }

  Widget _buildSubmitCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '启动批量导入',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dirPathCtrl,
              decoration: InputDecoration(
                labelText: '词书存放绝对路径',
                hintText: '例: /Volumes/ssd/ppdc/tools/book/大学/toimport',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickDirectory,
                  tooltip: '浏览选择文件夹',
                ),
              ),
            ),

            const SizedBox(height: 12),
            _isSubmitting
                ? const Center(child: CircularProgressIndicator())
                : FilledButton.icon(
                    onPressed: _submitBatch,
                    icon: const Icon(Icons.rocket_launch),
                    label: const Text('提交批量导入任务'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchList() {
    if (_batches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 40.0),
          child: Text('暂无历史批次数据', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '历史导入批次',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '总批次数: ${_batches.length}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._batches.entries.map((entry) {
          final batchId = entry.key;
          final List tasks = entry.value as List;
          return _buildBatchCard(batchId, tasks);
        }),
      ],
    );
  }

  Widget _buildBatchCard(String batchId, List tasks) {
    int completed = tasks.where((t) => t['status'] == 'COMPLETED').length;
    int running = tasks.where((t) => t['status'] == 'RUNNING').length;
    int failed = tasks.where((t) => t['status'] == 'FAILED').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          batchId,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
        ),
        subtitle: Text(
          '总计 ${tasks.length} 本 (成功: $completed, 运行: $running, 失败: $failed)',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: batchId == 'UNBATCHED'
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (running > 0 || tasks.where((t) => t['status'] == 'PENDING').isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.stop_circle_outlined, color: Colors.orange),
                      onPressed: () {
                        Future.microtask(() => _cancelBatch(batchId));
                      },
                      tooltip: '中止该批次所有未完成任务',
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_forever, 
                      color: (running > 0 || tasks.where((t) => t['status'] == 'PENDING').isNotEmpty) 
                        ? Colors.grey 
                        : Colors.red),
                    onPressed: (running > 0 || tasks.where((t) => t['status'] == 'PENDING').isNotEmpty)
                      ? () { 
                          Future.microtask(() {
                            ToastUtil.info('该批次内仍有进行中的任务，请先中止任务后再执行粉碎操作。');
                          });
                        }
                      : () {
                          Future.microtask(() => _deleteBatch(batchId, tasks));
                        },



                    tooltip: (running > 0 || tasks.where((t) => t['status'] == 'PENDING').isNotEmpty)
                      ? '任务进行中，无法粉碎'
                      : '彻底粉碎该批次所有词书',
                  ),

                ],
              ),

        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final task = tasks[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Future.microtask(() => _showTaskDetail(task));
                  },
                  title: Text(
                    task['dictName'] ?? task['fileName'] ?? '未命名词库',

                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '${task['processedWords'] ?? 0} / ${task['totalWords'] ?? 0} 词 | ${task['fileName']}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: _buildStatusTag(task['status'] ?? 'PENDING'),
                );

              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusTag(String status) {
    Color color;
    switch (status) {
      case 'COMPLETED': color = Colors.green; break;
      case 'RUNNING': color = Colors.blue; break;
      case 'FAILED': color = Colors.red; break;
      default: color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _showTaskDetail(dynamic task) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;


    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          task['dictName'] ?? task['fileName'] ?? '词库详情',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SizedBox(
          width: 500, // 给定一个较大的宽度
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('物理文件名', task['fileName'] ?? '无'),
                _buildDetailRow('任务状态', task['status'] ?? 'PENDING'),
                _buildDetailRow('处理进度', '${task['processedWords'] ?? 0} / ${task['totalWords'] ?? 0} 词'),
                _buildDetailRow('创建时间', _formatTime(task['createTime'])),
                const Divider(height: 24),
                const Text(
                  '执行日志:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.maxFinite,
                  constraints: const BoxConstraints(maxHeight: 200), // 限制日志区高度
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      (task['log'] == null || task['log'].toString().trim().isEmpty)
                          ? '暂无日志记录'
                          : task['log'].toString(),
                      style: const TextStyle(fontFamily: 'Courier', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic timeObj) {
    if (timeObj == null) return '未知时间';
    if (timeObj is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(timeObj);
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
    }
    // 可能是格式良好的字符串
    if (timeObj is String) {
      try {
        final dt = DateTime.parse(timeObj);
        return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
      } catch (_) {
        return timeObj;
      }
    }
    return timeObj.toString();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');


}
