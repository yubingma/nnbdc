import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../api/bo/word_bo.dart';
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

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _analyzeText() {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      ToastUtil.info('请输入或扫描文本后再分析');
      return;
    }

    setState(() {
      _isAnalyzing = true;
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

    setState(() {
      _extractedWords = wordSet.toList()..sort();
      _isAnalyzing = false;
    });

    if (_extractedWords.isEmpty) {
      ToastUtil.info('没有分析到有效的英文单词');
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

    try {
      for (String word in _extractedWords.toList()) {
        final voRes = await WordBo().searchWordLocalOnly(word);
        if (voRes.word != null) {
          final wordVo = voRes.word!;
          await widget.wordModifier.addWord(wordVo.id!);
          _successImportCount++;
          setState(() {
            _extractedWords.remove(word);
          });
        }
      }
      
      if (_extractedWords.isEmpty) {
        ToastUtil.info('全部单词导入成功！共 $_successImportCount 个');
        Get.back(result: true);
      } else {
        ToastUtil.info('导入 $_successImportCount 个，还有 ${_extractedWords.length} 个本地词库中未找到');
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
                                        return InkWell(
                                          onTap: () => _removeWord(word),
                                          borderRadius: BorderRadius.circular(16),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              word,
                                              style: TextStyle(
                                                color: isDarkMode ? Colors.white : AppTheme.primaryColor,
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
