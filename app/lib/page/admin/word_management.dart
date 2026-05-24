import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/config.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/local_word_cache.dart';
import 'package:just_audio/just_audio.dart';

class WordManagementWidget extends StatefulWidget {
  const WordManagementWidget({super.key});

  @override
  State<WordManagementWidget> createState() => _WordManagementWidgetState();
}

class _WordManagementWidgetState extends State<WordManagementWidget> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  bool _isRegenerating = false;
  WordVo? _currentWord;
  List<WordImage> _wordImages = [];
  List<SentenceVo> _sentences = [];
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<WordVo> _candidates = [];
  bool _isSearchingCandidates = false;
  String _lastCandidateQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onSearchTextChanged(String value) async {
    final query = value.trim();
    if (query == _lastCandidateQuery) return;
    _lastCandidateQuery = query;

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _candidates = [];
          _currentWord = null;
        });
      }
      return;
    }

    if (_isSearchingCandidates) return;
    _isSearchingCandidates = true;

    try {
      final words = await LocalWordCache.instance.fuzzySearchWord(query);
      if (mounted) {
        setState(() {
          _candidates = words;
          // 如果搜索框内容发生了变化，且当前显示的单词拼写与之不符，则清空当前单词显示，转而显示候选词
          if (_currentWord != null && _currentWord!.spell.toLowerCase() != query.toLowerCase()) {
            _currentWord = null;
          }
        });
      }
    } catch (e) {
      Global.logger.e("Failed to search candidates: $e");
    } finally {
      _isSearchingCandidates = false;
      // 结束后检查一下，若在查询期间query变了，可以再次触发同步（这里简化处理，下次输入会触发）
    }
  }

  Future<void> _searchWord({String? spell}) async {
    final searchSpell = spell ?? _searchController.text.trim();
    if (searchSpell.isEmpty) return;

    if (spell != null) {
      _searchController.text = spell;
      _lastCandidateQuery = spell; // 同步最后的查询字符串
    }

    setState(() {
      _isLoading = true;
      _currentWord = null;
      _candidates = []; // 选中后清空候选列表
      _wordImages = [];
      _sentences = [];
    });

    try {
      final searchResult = await WordBo().searchWordLocalOnly(searchSpell);
      _currentWord = searchResult.word;

      if (_currentWord != null && _currentWord!.id != null) {
        // 1. 获取本地配图
        final db = MyDatabase.instance;
        final imagesQuery = db.select(db.wordImages)..where((tbl) => tbl.wordId.equals(_currentWord!.id!));
        _wordImages = await imagesQuery.get();

        // 2. 从服务器获取最全例句列表
        await _loadSentences();
      }
    } catch (e) {
      Global.logger.e("Failed to search word: $searchSpell, error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSentences() async {
    if (_currentWord == null || _currentWord!.id == null) return;
    try {
      final result = await Api.client.getWordSentences(_currentWord!.id!);
      if (result.success) {
        setState(() {
          _sentences = result.data ?? [];
        });
      }
    } catch (e) {
      Global.logger.e("Failed to load sentences: $e");
    }
  }

  Future<void> _playPronunciation() async {
    if (_currentWord == null) return;
    try {
      await SoundUtil.playPronounceSound2(_currentWord!, _audioPlayer);
    } catch (e) {
      ToastUtil.error("播放失败: $e");
    }
  }

  Future<void> _regeneratePronunciation() async {
    if (_currentWord == null || _currentWord!.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认重新生成'),
        content: const Text('系统将尝试重新从有道词典抓取真人发音，如果失败则使用 AI 生成。这会覆盖现有的音频文件，确定吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRegenerating = true);
    try {
      final res = await Api.client.regenerateWordPronunciation(_currentWord!.id!);
      if (res.success) {
        ToastUtil.success("发音重新生成成功");
        // 更新本地 updateTime 以规避缓存
        if (_currentWord != null) {
          setState(() {
            _currentWord!.updateTime = DateTime.now();
          });
        }
        // 重新播放以验证
        _playPronunciation();
      } else {
        ToastUtil.error(res.msg ?? "生成失败");
      }
    } catch (e) {
      ToastUtil.error("生成异常: $e");
    } finally {
      if (mounted) {
        setState(() => _isRegenerating = false);
      }
    }
  }

  Future<void> _deleteImage(WordImage image) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后不可恢复，确定要删除这张图片吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = Global.getLoggedInUser();
      if (user == null) return;
      
      final res = await Api.client.deleteWordImage(image.id, user.id);
      if (res.success) {
        final db = MyDatabase.instance;
        await (db.delete(db.wordImages)..where((tbl) => tbl.id.equals(image.id))).go();
        if (mounted) {
          setState(() {
            _wordImages.removeWhere((img) => img.id == image.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('删除成功'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 400, left: 20, right: 20),
            duration: Duration(seconds: 1),
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('删除失败: ${res.msg}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 400, left: 20, right: 20),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('删除异常: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 400, left: 20, right: 20),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('查词管理', textScaler: TextScaler.linear(1.0)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textColor, fontFamily: 'NotoSansSC'),
              onSubmitted: (_) => _searchWord(),
              onChanged: _onSearchTextChanged,
              decoration: InputDecoration(
                hintText: '输入要查询的单词拼写...',
                hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                prefixIcon: IconButton(
                  icon: Icon(Icons.search, color: AppTheme.primaryColor),
                  onPressed: _searchWord,
                ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.clear, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchTextChanged('');
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
                ),
                filled: true,
                fillColor: cardColor,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _currentWord == null
                    ? _candidates.isNotEmpty
                        ? ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _candidates.length,
                            itemBuilder: (context, index) {
                              final candidate = _candidates[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDarkMode ? Colors.black.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: isDarkMode ? Colors.grey[800]!.withValues(alpha: 0.3) : Colors.grey[200]!.withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _searchWord(spell: candidate.spell),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Icon(Icons.search, color: AppTheme.primaryColor.withValues(alpha: 0.5), size: 20),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  candidate.spell,
                                                  style: TextStyle(
                                                    color: AppTheme.primaryColor,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: 'NotoSansSC',
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  candidate.getMeaningStr(),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 14),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Text(
                              _searchController.text.isEmpty ? '请在上方搜索栏输入单词' : '未找到匹配的单词',
                              style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                            ),
                          )

                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              color: cardColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          _currentWord!.spell,
                                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.volume_up, color: AppTheme.primaryColor, size: 22),
                                          onPressed: _playPronunciation,
                                          tooltip: '播放发音',
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(4),
                                        ),
                                        Text(
                                          '[${Util.getWordDefaultPronounce(_currentWord!)}]',
                                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                                        ),
                                        _isRegenerating
                                            ? const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8),
                                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                              )
                                            : TextButton.icon(
                                                onPressed: _regeneratePronunciation,
                                                icon: const Icon(Icons.refresh, size: 14),
                                                label: const Text('重生成发音', style: TextStyle(fontSize: 11)),
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                              ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('ID: ${_currentWord!.id ?? "未知"}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                                    const Divider(height: 24),
                                    if (_currentWord!.meaningItems != null && _currentWord!.meaningItems!.isNotEmpty)
                                      ..._currentWord!.meaningItems!.map((m) => Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: Text('${m.ciXing ?? ""} ${m.meaning ?? ""}', style: TextStyle(fontSize: 16, color: textColor)),
                                          )),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // 例句管理部分
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '例句管理 (${_sentences.length})',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_sentences.isEmpty)
                              Card(
                                color: cardColor,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text('暂无相关例句', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _sentences.length,
                                itemBuilder: (context, index) {
                                  return _buildSentenceItem(_sentences[index]);
                                },
                              ),
                            const SizedBox(height: 24),
                            Text(
                              '配图管理 (${_wordImages.length})',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                            ),
                            const SizedBox(height: 8),
                            if (_wordImages.isEmpty)
                              Card(
                                color: cardColor,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text('暂无相关配图', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
                                ),
                              )
                            else
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.85,
                                ),
                                itemCount: _wordImages.length,
                                itemBuilder: (context, index) {
                                  final img = _wordImages[index];
                                  return Card(
                                    color: cardColor,
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: Builder(
                                            builder: (context) {
                                              final imageUrl = Uri.encodeFull('${Config.imgBaseUrl}word/${img.imageFile}');
                                              Global.logger.d('加载单词图片 [管理后台]: $imageUrl');
                                              return Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (ctx, err, stack) {
                                                  Global.logger.e('图片加载失败 [管理后台]: $imageUrl', error: err);
                                                  return const Center(child: Icon(Icons.broken_image, size: 40));
                                                },
                                              );
                                            }
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'ID: ${img.id}',
                                                  style: const TextStyle(fontSize: 10),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () => _deleteImage(img),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceItem(SentenceVo sentence) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Util.makeEnglishSpanText(
              sentence.english ?? '',
              _currentWord?.spell ?? '',
              true,
              context,
              false,
              null,
              false,
              FontWeight.w500,
              fontSize: 16,
            ),
            const SizedBox(height: 4),
            Util.makeChineseSpanText(
              sentence.chinese ?? '',
              context,
              style: const TextStyle(fontSize: 14),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editSentence(sentence),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('编辑'),
                ),
                TextButton.icon(
                  onPressed: () => _deleteSentence(sentence),
                  icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                  label: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _editSentence(SentenceVo sentence) {
    showDialog(
      context: context,
      builder: (context) => _SentenceEditDialog(
        sentence: sentence,
        onUpdated: _loadSentences,
      ),
    );
  }

  void _deleteSentence(SentenceVo sentence) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条例句吗？删除后相关资源也会被清理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await Api.client.deleteAdminSentence(sentence.id);
              if (res.success) {
                _loadSentences();
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// 例句编辑对话框
class _SentenceEditDialog extends StatefulWidget {
  final SentenceVo sentence;
  final VoidCallback onUpdated;

  const _SentenceEditDialog({required this.sentence, required this.onUpdated});

  @override
  State<_SentenceEditDialog> createState() => _SentenceEditDialogState();
}

class _SentenceEditDialogState extends State<_SentenceEditDialog> {
  late TextEditingController _englishController;
  late TextEditingController _chineseController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _englishController = TextEditingController(text: widget.sentence.english);
    _chineseController = TextEditingController(text: widget.sentence.chinese);
  }

  @override
  void dispose() {
    _englishController.dispose();
    _chineseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return AlertDialog(
      title: const Text('编辑例句'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _englishController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '英文例句'),
              style: TextStyle(color: textColor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _chineseController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '中文翻译'),
              style: TextStyle(color: textColor),
            ),
            const SizedBox(height: 8),
            const Text(
              '提示：修改后系统会自动通过 AI 重新生成配音、助记等资源。',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final res = await Api.client.updateAdminSentence(
        widget.sentence.id,
        _englishController.text,
        _chineseController.text,
      );
      if (res.success) {
        widget.onUpdated();
        if (mounted) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
