import 'package:flutter/material.dart';
import '../../services/dialog_service.dart';
import '../../api/bo/word_bo.dart';
import '../../api/vo.dart';
import '../../db/db.dart';
import '../../global.dart';
import '../../util/toast_util.dart';
import '../../util/utils.dart';
import '../../widget/app_scaffold.dart';
import '../select_book.dart';
import 'word_list.dart';

class ImportFromBookPage extends StatefulWidget {
  final WordModifier wordModifier;

  const ImportFromBookPage({super.key, required this.wordModifier});

  @override
  ImportFromBookPageState createState() => ImportFromBookPageState();
}

class ImportFromBookPageState extends State<ImportFromBookPage> {
  List<Dict> _availableDicts = [];
  Dict? _selectedDict;
  List<DictWordVo> _words = [];
  Set<String> _selectedWordIds = {};
  bool _isLoadingDicts = false;
  bool _isLoadingWords = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  Set<String> _targetWordIds = {}; // 目标词书中已有的单词ID

  @override
  void initState() {
    super.initState();
    _loadTargetWordIds();
    _loadDicts().then((_) {
      if (mounted && _availableDicts.isNotEmpty) {
        _showDictPicker();
      }
    });
  }

  Future<void> _loadTargetWordIds() async {
    final targetDictId = widget.wordModifier.targetDictId;
    if (targetDictId == null) return;

    try {
      final db = MyDatabase.instance;
      final dictWords = await (db.select(db.dictWords)..where((tbl) => tbl.dictId.equals(targetDictId))).get();
      if (mounted) {
        setState(() {
          _targetWordIds = dictWords.map((dw) => dw.wordId).toSet();
        });
      }
    } catch (e) {
      Global.logger.e('加载目标词书单词失败: $e');
    }
  }

  Future<void> _loadDicts() async {
    setState(() => _isLoadingDicts = true);
    try {
      final db = MyDatabase.instance;
      // 加载所有本地词书（包括已下载和未下载的）
      final dicts = await db.select(db.dicts).get();
      if (mounted) {
        setState(() {
          _availableDicts = dicts;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDicts = false);
      }
    }
  }

  Future<void> _loadWords(Dict dict) async {
    setState(() {
      _selectedDict = dict;
      _isLoadingWords = true;
      _selectedWordIds.clear();
      _words.clear();
    });
    try {
      // 检查词书是否有单词（可能还未下载资源）
      final db = MyDatabase.instance;
      final hasWords = await db.dictWordsDao.hasDictWords(dict.id);

      if (!hasWords) {
        // 词书尚未下载，自动触发下载
        await _downloadDict(dict);
      }

      final results = await WordBo().getDictWordsForAPage(dict.id, 0, 10000);
      if (mounted) {
        setState(() {
          _words = results.rows;
          // 预选已经在目标词书中的单词
          for (var row in _words) {
            if (_targetWordIds.contains(row.word.id)) {
              _selectedWordIds.add(row.word.id!);
            }
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingWords = false);
      }
    }
  }

  /// 下载词书资源
  Future<void> _downloadDict(Dict dict) async {
    if (!mounted) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final dictVo = DictVo.c2(dict.id);
      dictVo.name = dict.name;

      // 用 ownerId 构建 owner 信息
      final ownerVo = UserVo.c2(dict.ownerId);
      dictVo.owner = ownerVo;

      await SelectBookPageState.downloadADict(
        dictVo,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      // 下载完成后重新加载词书列表（wordCount 可能已更新）
      await _loadDicts();
    } catch (e) {
      Global.logger.e('从词书导入-下载失败: $e');
      if (mounted) {
        ToastUtil.error('词书下载失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _importSelected() async {
    if (_selectedWordIds.isEmpty) {
      ToastUtil.info('请先选择单词');
      return;
    }

    // 过滤掉已经在目标词书中的单词，避免触发“已在词典中”报错
    final toImportIds = _selectedWordIds.where((id) => !_targetWordIds.contains(id)).toList();
    final alreadyInCount = _selectedWordIds.length - toImportIds.length;

    if (toImportIds.isEmpty && alreadyInCount > 0) {
      ToastUtil.info('所选单词均已在词书中');
      return;
    }

    int successCount = 0;
    DialogService.showDialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      for (String wordId in toImportIds) {
        bool success = await widget.wordModifier.addWord(wordId);
        if (success) successCount++;
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }

    if (alreadyInCount > 0) {
      ToastUtil.info('导入完毕：新增 $successCount 个，跳过 $alreadyInCount 个 (已存在)');
    } else {
      ToastUtil.info('成功导入 $successCount 个单词');
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// 打开带搜索功能的词书选择弹窗
  void _showDictPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _DictSearchSheet(
          dicts: _availableDicts,
          onSelected: (dict) {
            Navigator.of(sheetContext).pop();
            _loadWords(dict);
          },
        );
      },
    );
  }

  String _getDownloadProgressText() {
    if (_downloadProgress < 0.2) {
      return '下载中... ${(_downloadProgress * 100).round()}%';
    } else if (_downloadProgress <= 0.25) {
      return '解析中... ${(_downloadProgress * 100).toStringAsFixed(1)}%';
    } else {
      return '导入中... ${(_downloadProgress * 100).round()}%';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: '从词书导入',
        actions: [
          if (_words.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedWordIds.length == _words.length) {
                    _selectedWordIds.clear();
                  } else {
                    _selectedWordIds = _words.map((w) => w.word.id!).toSet();
                  }
                });
              },
              child: Text(
                _selectedWordIds.length == _words.length ? '全不选' : '全选',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 词书选择器 — 紧贴顶部，无额外间距
          if (_isLoadingDicts)
            const LinearProgressIndicator()
          else
            InkWell(
              onTap: _showDictPicker,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedDict != null
                          ? Util.getDictIcon(
                              editable: _selectedDict!.editable,
                              ownerId: _selectedDict!.ownerId,
                              name: _selectedDict!.name,
                            )
                          : Icons.auto_stories_rounded,
                      size: 20,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedDict?.name ?? '请选择要导入的词书',
                        style: TextStyle(
                          fontSize: 16,
                          color: _selectedDict != null ? Colors.black87 : Colors.grey,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),

          // 下载进度条
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _downloadProgress),
                  const SizedBox(height: 4),
                  Text(
                    _getDownloadProgressText(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),

          // 单词列表 — 占满剩余空间
          Expanded(
            child: _isLoadingWords
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (_isDownloading) ...[
                          const SizedBox(height: 12),
                          Text(
                            '正在下载词书资源...',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  )
                : (_selectedDict == null
                    ? const Center(child: Text('请先选择词书'))
                    : _words.isEmpty
                        ? const Center(child: Text('该词书暂无单词'))
                        : ListView.builder(
                            itemCount: _words.length,
                            itemBuilder: (context, index) {
                              final word = _words[index];
                              final isSelected = _selectedWordIds.contains(word.word.id);
                              final isAlreadyInTarget = _targetWordIds.contains(word.word.id);
                              return CheckboxListTile(
                                value: isSelected,
                                title: Row(
                                  children: [
                                    Text(word.word.spell),
                                    if (isAlreadyInTarget) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                                        ),
                                        child: const Text('已在词书中', style: TextStyle(fontSize: 10, color: Colors.green)),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(word.word.getMeaningStr()),
                                tileColor: isAlreadyInTarget ? Colors.green.withValues(alpha: 0.05) : null,
                                onChanged: (bool? value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedWordIds.add(word.word.id!);
                                    } else {
                                      _selectedWordIds.remove(word.word.id!);
                                    }
                                  });
                                },
                              );
                            },
                          )),
          ),

          // 底部按钮 — 取消 + 导入
          if (_selectedDict != null && _words.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.import_contacts),
                        label: Text('导入选中 (${_selectedWordIds.length})'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                        ),
                        onPressed: _selectedWordIds.isEmpty ? null : _importSelected,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 带搜索功能的词书选择弹窗
class _DictSearchSheet extends StatefulWidget {
  final List<Dict> dicts;
  final ValueChanged<Dict> onSelected;

  const _DictSearchSheet({required this.dicts, required this.onSelected});

  @override
  _DictSearchSheetState createState() => _DictSearchSheetState();
}

class _DictSearchSheetState extends State<_DictSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Dict> _filteredDicts = [];

  @override
  void initState() {
    super.initState();
    _filteredDicts = widget.dicts;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredDicts = widget.dicts;
      } else {
        _filteredDicts = widget.dicts.where((d) => d.name.toLowerCase().contains(query)).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.7;
    return SizedBox(
      height: sheetHeight,
      child: Column(
        children: [
          // 拖拽手柄
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('选择词书', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              decoration: InputDecoration(
                hintText: '搜索词书名称...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 列表
          Expanded(
            child: _filteredDicts.isEmpty
                ? const Center(child: Text('没有匹配的词书'))
                : ListView.separated(
                    itemCount: _filteredDicts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final dict = _filteredDicts[index];
                      return ListTile(
                        leading: Icon(Util.getDictIcon(
                          editable: dict.editable,
                          ownerId: dict.ownerId,
                          name: dict.name,
                        )),
                        title: Text(dict.name),
                        subtitle: Text('${dict.wordCount} 词'),
                        onTap: () => widget.onSelected(dict),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
