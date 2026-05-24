import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/config.dart'; 

class AdminImageReviewPage extends StatefulWidget {
  const AdminImageReviewPage({super.key});

  @override 
  State<AdminImageReviewPage> createState() => _AdminImageReviewPageState();
}

class _AdminImageReviewPageState extends State<AdminImageReviewPage> {
  final TextEditingController _dictIdController = TextEditingController(text: '0');
  bool _autoDelete = false;

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
    _dictIdController.dispose();
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
      final response = await Api.dio.get('$_baseUrl/admin/image/batchReviewStatus.do');
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

  Future<void> _startScan() async {
    final dictId = _dictIdController.text.trim();
    if (dictId.isEmpty) {
      ToastUtil.info('请输入词典 ID');
      return;
    }

    try {
      final response = await Api.dio.post('$_baseUrl/admin/image/startBatchReview.do', queryParameters: {
        'dictId': dictId,
        'autoDelete': _autoDelete,
        'userId': Global.getLoggedInUser()?.id,
      });
      final res = response.data;
      if (res['success'] == true) {
        ToastUtil.success('成功启动后台审核任务');
        _fetchStatus();
      } else {
        ToastUtil.error('启动失败: ${res['msg']}');
      }
    } catch (e) {
      ToastUtil.error('请求异常: $e');
    }
  }

  Future<void> _stopScan() async {
    try {
      final response = await Api.dio.post('$_baseUrl/admin/image/stopBatchReview.do', queryParameters: {
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

  Future<void> _bulkDeleteMarked() async {
    if (_taskStatus == null || (_taskStatus!['markedImages'] as List).isEmpty) {
      ToastUtil.info('没有待删除的标记图片');
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('您确定要删除这 ${(_taskStatus!['markedImages'] as List).length} 张被确认为不合格的配图吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await Api.dio.post('$_baseUrl/admin/image/deleteMarked.do', queryParameters: {
          'userId': Global.getLoggedInUser()?.id,
        });
        final res = response.data;
        if (res['success'] == true) {
          ToastUtil.success('成功删除了 ${res['data']} 张图片');
          _fetchStatus();
        } else {
          ToastUtil.error('删除失败: ${res['msg']}');
        }
      } catch (e) {
        ToastUtil.error('请求异常: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    final bool isRunning = _taskStatus?['isRunning'] == true;
    final String statusMsg = _taskStatus?['statusMsg'] ?? '任务未启动';
    final int total = _taskStatus?['totalImages'] ?? 0;
    final int current = _taskStatus?['currentIndex'] ?? 0;
    final List marked = _taskStatus?['markedImages'] ?? [];
    final List deleted = _taskStatus?['deletedImages'] ?? [];

    return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppTheme.createGradientAppBar(
            title: 'AI 配图自动审核',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            actions: [
              if (marked.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.white),
                  tooltip: '一键删除建议删除项',
                  onPressed: _bulkDeleteMarked,
                )
            ]),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: isDarkMode ? Colors.grey[900] : Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                        controller: _dictIdController,
                        enabled: !isRunning,
                        decoration: const InputDecoration(
                          labelText: '目标词典ID (系统通常为0)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      )),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _autoDelete,
                            onChanged: isRunning ? null : (v) => setState(() => _autoDelete = v!),
                          ),
                          const Text('扫描时自动删除\n不合格配图', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (isRunning) {
                            _stopScan();
                          } else {
                            _startScan();
                          }
                        },
                        icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
                        label: Text(isRunning ? '停止后台审核' : '开启后台审核'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunning ? Colors.red : AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[850] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('状态: $statusMsg${isRunning ? ' ($current / $total)' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('已查出建议删除: ${marked.length}    本次已自动/手动删除: ${deleted.length}',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            ],
                          ),
                        ),
                        if (isRunning && total > 0) CircularProgressIndicator(value: current / total, backgroundColor: Colors.grey[300]),
                      ],
                    ),
                  )
                ],
              ),
            ),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: AppTheme.primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppTheme.primaryColor,
                      tabs: [
                        Tab(text: '建议删除 (${marked.length})'),
                        Tab(text: '已删除 (${deleted.length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildImageList(marked, false, isDarkMode),
                          _buildImageList(deleted, true, isDarkMode),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ));
  }

  Widget _buildImageList(List items, bool isAlreadyDeleted, bool isDarkMode) {
    if (items.isEmpty) {
      return const Center(child: Text('暂无数据', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      itemCount: items.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final img = items[index];
        final cardColor = isDarkMode ? Colors.grey[800]! : (isAlreadyDeleted ? Colors.grey[100]! : Colors.red.withValues(alpha: 0.05));
        final borderColor = isAlreadyDeleted ? Colors.transparent : Colors.red.withValues(alpha: 0.3);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          color: cardColor,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: isAlreadyDeleted ? 0.3 : 1.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Builder(
                      builder: (context) {
                        final imageUrl = Uri.encodeFull('${"${Config.imgBaseUrl}word/"}${img['imageFile']}');
                        Global.logger.d('加载单词图片 [审核页]: $imageUrl');
                        return Image.network(
                          imageUrl,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            Global.logger.e('图片加载失败 [审核页]: $imageUrl', error: error);
                            return const Center(child: Icon(Icons.broken_image, color: Colors.red));
                          },
                        );
                      }
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(img['spell'] ?? '未知单词',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: isAlreadyDeleted ? TextDecoration.lineThrough : null,
                        )),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isAlreadyDeleted ? '已删除' : '建议删除',
                            style: TextStyle(color: isAlreadyDeleted ? Colors.grey : Colors.red, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(img['reason'] ?? '', style: TextStyle(color: isAlreadyDeleted ? Colors.grey : Colors.red, fontSize: 13)),
                      ],
                    )
                  ],
                )),
              ],
            ),
          ),
        );
      },
    );
  }
}
