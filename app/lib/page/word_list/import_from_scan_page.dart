import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../api/bo/word_bo.dart';
import '../../db/db.dart';
import '../../global.dart';
import '../../state.dart';
import '../../theme/app_theme.dart';
import '../../util/toast_util.dart';
import 'word_list.dart';

class ImportFromScanPage extends StatefulWidget {
  final WordModifier wordModifier;

  const ImportFromScanPage({super.key, required this.wordModifier});

  @override
  State<ImportFromScanPage> createState() => _ImportFromScanPageState();
}

class _ImportFromScanPageState extends State<ImportFromScanPage> {
  TextEditingController _textController = TextEditingController();
  List<String> _extractedWords = [];
  bool _isAnalyzing = false;
  bool _isImporting = false;
  int _successImportCount = 0;
  Set<String> _invalidWords = {}; // 本地词库未找到的单词

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _analyzeText() async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      ToastUtil.info('请输入或扫描文本后再分析');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _invalidWords.clear();
    });

    // 粗略提取所有连续的英文字母，作为待处理单词
    final RegExp regExp = RegExp(r'[a-zA-Z]+');
    final matches = regExp.allMatches(text);
    
    Set<String> wordSet = {};
    for (var match in matches) {
      String w = match.group(0)!.toLowerCase();
      if (w.length > 2) { // 过滤掉太短的无意义词
        wordSet.add(w);
      }
    }

    Set<String> invalidSet = {};
    for (String w in wordSet) {
      final voRes = await WordBo().searchWordLocalOnly(w);
      if (voRes.word == null) {
        invalidSet.add(w);
      }
    }

    if (mounted) {
      setState(() {
        _extractedWords = wordSet.toList();
        _invalidWords = invalidSet;
        _isAnalyzing = false;
      });

      if (_extractedWords.isEmpty) {
        ToastUtil.info('没有分析到有效的英文单词');
      }
    }
  }

  void _importWords() async {
    if (_extractedWords.isEmpty) {
      ToastUtil.info('没有可导入的单词');
      return;
    }

    setState(() {
      _isImporting = true;
    });

    int existCount = 0;
    int successCountThisTime = 0;
    final dictId = widget.wordModifier.targetDictId;

    try {
      for (String word in _extractedWords.toList()) {
        final voRes = await WordBo().searchWordLocalOnly(word);
        if (voRes.word != null) {
          final wordVo = voRes.word!;
          bool shouldAdd = true;
          
          // 如果能够获取到当前词书ID，提前查重，跳过已存在的单词以防报错刷屏
          if (dictId != null) {
            final existing = await MyDatabase.instance.dictWordsDao.getById(dictId, wordVo.id!);
            if (existing != null) {
              shouldAdd = false;
              existCount++;
            }
          }
          
          if (shouldAdd) {
            // 如果内部抛出错误，会被 catch 拦截，或者如果内部弹出错误 Toast 我们也无法完全干预，
            // 但上方提前查重能拦截约 90% 的 "单词已存在" 错误
            final success = await widget.wordModifier.addWord(wordVo.id!);
            if (success) {
              _successImportCount++;
              successCountThisTime++;
            }
          }
          
          setState(() {
            _extractedWords.remove(word);
          });
        }
      }
      
      // 组装分行汇总提示
      final msg = StringBuffer();
      msg.writeln('本次处理完成：');
      msg.writeln('• 成功导入: $successCountThisTime 个');
      if (existCount > 0) {
        msg.writeln('• 已在词书中: $existCount 个');
      }
      if (_invalidWords.isNotEmpty) {
        msg.writeln('• 无法识别: ${_invalidWords.length} 个（不在泡泡词典中）');
      }
      if (_extractedWords.isNotEmpty && _invalidWords.isEmpty) {
        msg.writeln('• 剩余未处理: ${_extractedWords.length} 个');
      }
      
      ToastUtil.info(
        msg.toString().trim(),
        autoCloseDuration: null, // 当设置为 null 时，不自动关闭，需用户手动点击关闭
      );

      if (_extractedWords.isEmpty && _invalidWords.isEmpty) {
        Get.back(result: _successImportCount > 0);
      }
    } catch (e) {
      Global.logger.e('导入失败', error: e);
      ToastUtil.error('导入失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  void _removeWord(String word) {
    setState(() {
      _extractedWords.remove(word);
      _invalidWords.remove(word);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        Get.back(result: _successImportCount > 0);
      },
      child: Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppTheme.gradientStartColor,
                  AppTheme.gradientEndColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          title: const Text(
            '扫描实体书导入',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Get.back(result: _successImportCount > 0),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用iOS自带OCR扫词',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'iOS 15及以上系统：点击下方输入框光标处，选择"扫描文本"(Scan Text) 即可打开相机自动提取实体书上的英文。',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (_extractedWords.isEmpty && !_isAnalyzing)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
                              ),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: TextField(
                              controller: _textController,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: TextStyle(
                                fontSize: 16,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: '在此长按，点击"扫描文本"\n或直接粘贴段落...',
                                hintStyle: TextStyle(
                                  color: isDarkMode ? Colors.white38 : Colors.black26,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                      if (_isAnalyzing)
                        const Expanded(
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      if (_extractedWords.isNotEmpty && !_isAnalyzing)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '识别到 ${_extractedWords.length} 个单词（点击可删除）：',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: SingleChildScrollView(
                                    child: Wrap(
                                      spacing: 8.0,
                                      runSpacing: 8.0,
                                      children: _extractedWords.map((word) {
                                        final isInvalid = _invalidWords.contains(word);
                                        return InkWell(
                                          onTap: () => _removeWord(word),
                                          borderRadius: BorderRadius.circular(16),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isInvalid ? Colors.red.withValues(alpha: 0.1) : AppTheme.primaryColor.withValues(alpha: 0.1),
                                              border: Border.all(color: isInvalid ? Colors.red.withValues(alpha: 0.3) : AppTheme.primaryColor.withValues(alpha: 0.3)),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              word,
                                              style: TextStyle(
                                                color: isDarkMode 
                                                    ? (isInvalid ? Colors.redAccent : Colors.white) 
                                                    : (isInvalid ? Colors.red : AppTheme.primaryColor),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isAnalyzing || _isImporting
                              ? null
                              : (_extractedWords.isEmpty ? _analyzeText : _importWords),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _isImporting
                                ? '正在导入...'
                                : (_extractedWords.isEmpty ? '提取单词' : '一键导入'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_extractedWords.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: TextButton(
                            onPressed: _isImporting
                                ? null
                                : () {
                                    FocusScope.of(context).unfocus();
                                    setState(() {
                                      _extractedWords.clear();
                                      _invalidWords.clear();
                                      _textController.dispose();
                                      _textController = TextEditingController();
                                    });
                                  },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                            ),
                            child: const Text('清空重新输入'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
