import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/select_book.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

enum DownloadStatus { pending, downloading, success, failure }

class DictDownloadDialog extends StatefulWidget {
  final List<DictVo> dicts;
  final VoidCallback onComplete;

  const DictDownloadDialog({
    super.key,
    required this.dicts,
    required this.onComplete,
  });

  @override
  State<DictDownloadDialog> createState() => _DictDownloadDialogState();
}

class _DictDownloadDialogState extends State<DictDownloadDialog> {
  final Map<String, double> _downloadProgress = {};
  final Map<String, DownloadStatus> _downloadStatus = {};
  final Map<String, String> _dictNames = {};
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadDictNames();
  }

  Future<void> _loadDictNames() async {
    for (var dict in widget.dicts) {
      _downloadProgress[dict.id] = 0;
      _downloadStatus[dict.id] = DownloadStatus.pending;
      var dictInfo = await MyDatabase.instance.dictsDao.findById(dict.id);
      if (dictInfo != null) {
        _dictNames[dict.id] = dictInfo.name;
      }
    }
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
    });

    // 串行下载所有词书，避免内存压力过大
    for (var dict in widget.dicts) {
      if (!mounted) break;
      setState(() {
        _downloadStatus[dict.id] = DownloadStatus.downloading;
      });
      try {
        Global.logger.i('开始下载词书, ID: ${dict.id}, 名称: ${dict.name}');
        await SelectBookPageState.downloadADict(
          dict,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _downloadProgress[dict.id] = progress;
              });
            }
          },
        );
        if (mounted) {
          setState(() {
            _downloadStatus[dict.id] = DownloadStatus.success;
            _downloadProgress[dict.id] = 1;
          });
          // 下载并处理成功后，本地库中应该已经有 Metadata (name)，尝试重新加载一次
          if (_dictNames[dict.id] == null) {
            MyDatabase.instance.dictsDao.findById(dict.id).then((info) {
              if (info != null && mounted) {
                setState(() => _dictNames[dict.id] = info.name);
              }
            });
          }
        }
        Global.logger.i('词书下载完成, ID: ${dict.id}, 名称: ${dict.name}');
      } catch (e, stackTrace) {
        // 记录下载失败的详细错误信息
        Global.logger.e('下载词书失败: ${dict.id}', error: e, stackTrace: stackTrace);
        if (mounted) {
          setState(() {
            _downloadStatus[dict.id] = DownloadStatus.failure;
            _downloadProgress[dict.id] = 0; // 失败时重置进度
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
    }

    // 不再自动调用 widget.onComplete()，让用户点击“完成”按钮，避免失败时无限循环
  }

  String _getProgressText(double progress, DownloadStatus status) {
    if (status == DownloadStatus.failure) return '下载失败';
    if (status == DownloadStatus.success) return '导入完成';

    // 将进度转换为百分比显示
    if (progress < 0.2) {
      final int percent = (progress * 100).round();
      return '下载中... $percent%';
    }
    if (progress <= 0.25) {
      final String percent = (progress * 100).toStringAsFixed(1);
      return '解析中... $percent%';
    }
    final int percent = (progress * 100).round();
    return '导入中... $percent%';
  }

  @override
  Widget build(BuildContext context) {
    final int completedCount = _downloadStatus.values.where((v) => v == DownloadStatus.success || v == DownloadStatus.failure).length;
    final bool allFinished = completedCount == widget.dicts.length;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      title: Text('导入词书 ($completedCount/${widget.dicts.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: widget.dicts.isEmpty ? 0 : _downloadProgress.values.fold(0.0, (a, b) => a + b) / widget.dicts.length,
                backgroundColor: Colors.blue.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 16),
            ],
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: widget.dicts.map((dict) {
                    final status = _downloadStatus[dict.id] ?? DownloadStatus.pending;
                    final progress = _downloadProgress[dict.id] ?? 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildStatusIcon(status),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _dictNames[dict.id] ?? dict.name?.replaceAll('.dict', '') ?? dict.id.replaceAll('.dict', ''),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: status == DownloadStatus.success ? 1.0 : (status == DownloadStatus.failure ? 0.0 : progress),
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      status == DownloadStatus.failure ? Colors.red : Colors.blue,
                                    ),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getProgressText(progress, status),
                                style: TextStyle(fontSize: 10, color: status == DownloadStatus.failure ? Colors.red : Colors.grey[600]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (allFinished)
          TextButton(
            onPressed: () {
              widget.onComplete();
            },
            child: const Text('完成', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  Widget _buildStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: 18);
      case DownloadStatus.failure:
        return const Icon(Icons.error, color: Colors.red, size: 18);
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.pending:
        return const Icon(Icons.hourglass_empty, color: Colors.grey, size: 18);
    }
  }
}
