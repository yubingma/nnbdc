import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/select_book.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

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
  final Map<String, bool> _downloadStatus = {};
  final Map<String, String> _dictNames = {};
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadDictNames();
  }

  Future<void> _loadDictNames() async {
    for (var dict in widget.dicts) {
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
      // 初始化所有词书的状态
      for (var dict in widget.dicts) {
        _downloadProgress[dict.id] = 0;
        _downloadStatus[dict.id] = false;
      }
    });

    // 串行下载所有词书，避免内存压力过大
    for (var dict in widget.dicts) {
      try {
        Global.logger.i('开始下载词书, ID: ${dict.id}, 名称: ${dict.name}');
        await SelectBookPageState.downloadADict(
          dict.id,
          onProgress: (progress) {
            setState(() {
              _downloadProgress[dict.id] = progress;
            });
          },
        );
        setState(() {
          _downloadStatus[dict.id] = true;
          _downloadProgress[dict.id] = 1;
        });
        Global.logger.i('词书下载完成, ID: ${dict.id}, 名称: ${dict.name}');
      } catch (e, stackTrace) {
        // 记录下载失败的详细错误信息
        Global.logger.e('下载词书失败: ${dict.id}', error: e, stackTrace: stackTrace);
        // 下载失败也标记为完成
        setState(() {
          _downloadStatus[dict.id] = true;
        });
      }
    }

    setState(() {
      _isDownloading = false;
    });

    widget.onComplete();
  }

  String _getProgressText(double progress) {
    if (progress <= 0.2) {
      return '下载中...';
    } else {
      return '导入中...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      title: Text('导入词书 (已导入 ${_downloadStatus.values.where((v) => v).length}/${widget.dicts.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isDownloading) ...[
            LinearProgressIndicator(
              value: widget.dicts.isEmpty ? 0 : _downloadProgress.values.reduce((a, b) => a + b) / widget.dicts.length,
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 8),
            ...widget.dicts.map((dict) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _downloadStatus[dict.id] == true ? Icons.check_circle : Icons.hourglass_empty,
                            color: _downloadStatus[dict.id] == true ? Colors.green : Colors.grey,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dict.name?.replaceAll('.dict', '') ?? dict.id.replaceAll('.dict', ''),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      if (!_downloadStatus[dict.id]!) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: _downloadProgress[dict.id] ?? 0,
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getProgressText(_downloadProgress[dict.id] ?? 0),
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
