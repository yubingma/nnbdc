import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../util/ocr_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../util/permission_util.dart';
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

class _ImportFromScanPageState extends State<ImportFromScanPage>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();


  List<String> _extractedWords = [];
  bool _isRecognizing = false;
  bool _isImporting = false;
  int _successImportCount = 0;
  Set<String> _invalidWords = {};
  Set<String> _deselectedWords = {};
  int _importedSoFar = 0;
  int _totalToImport = 0;

  // 手动输入模式
  bool _manualMode = false;
  TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  List<String> get _validWords =>
      _extractedWords.where((w) => !_invalidWords.contains(w)).toList();

  List<String> get _selectedValidWords =>
      _validWords.where((w) => !_deselectedWords.contains(w)).toList();

  /// 拍照并识别文字
  Future<void> _scanFromCamera() async {
    await PermissionUtil.requestWithRationale(
      permission: Permission.camera,
      title: '相机权限',
      purpose: '${Global.appName}需要您的相机权限，用于拍摄书本中的英文单词进行扫描识别，这能帮助您快速导入单词。',
      icon: Icons.camera_alt_rounded,
      onGranted: () async {
        try {
          final XFile? photo = await _picker.pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.rear,
            imageQuality: 90,
          );
          if (photo == null) return; // 用户取消
          await _recognizeImage(photo.path);
        } catch (e) {
          Global.logger.e('拍照失败', error: e);
          ToastUtil.error('拍照失败，请检查相关权限');
        }
      },
    );
  }

  /// 从相册选图并识别
  Future<void> _pickFromGallery() async {
    await PermissionUtil.requestWithRationale(
      permission: Permission.photos,
      title: '相册/存储权限',
      purpose: '${Global.appName}需要您的相册/存储权限，用于从相册选择包含英文单词的图片进行扫描识别。',
      icon: Icons.photo_library_rounded,
      onGranted: () async {
        try {
          final XFile? image = await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 90,
          );
          if (image == null) return;
          await _recognizeImage(image.path);
        } catch (e) {
          Global.logger.e('选图失败', error: e);
          ToastUtil.error('选图失败，请检查相关权限');
        }
      },
    );
  }

  /// OCR 识别图片中的文字并提取单词（iOS 使用 Vision 框架，Android 使用 Google ML Kit）
  Future<void> _recognizeImage(String imagePath) async {
    setState(() {
      _isRecognizing = true;
    });

    try {
      final rawText = await OcrService.recognizeText(imagePath);

      if (rawText.trim().isEmpty) {
        ToastUtil.info('未识别到任何文字，请重试');
        setState(() => _isRecognizing = false);
        return;
      }

      await _extractWordsFromText(rawText);
    } catch (e) {
      Global.logger.e('OCR识别失败', error: e);
      ToastUtil.error('文字识别失败，请重试');
    } finally {
      // 清理临时文件
      try {
        final file = File(imagePath);
        if (await file.exists()) await file.delete();
      } catch (_) {}

      if (mounted) {
        setState(() => _isRecognizing = false);
      }
    }
  }

  /// 从文本（手动输入或OCR）中提取单词
  Future<void> _extractWordsFromText(String text) async {
    setState(() {
      _isRecognizing = true;
      _invalidWords.clear();
      _deselectedWords.clear();
    });

    final RegExp regExp = RegExp(r'[a-zA-Z]+');
    final matches = regExp.allMatches(text);

    Set<String> wordSet = {};
    for (var match in matches) {
      String w = match.group(0)!.toLowerCase();
      if (w.length > 2) {
        wordSet.add(w);
      }
    }

    // 合并已有的单词（追加模式）
    final existingSet = _extractedWords.toSet();
    wordSet.addAll(existingSet);

    Set<String> invalidSet = {};
    for (String w in wordSet) {
      if (_invalidWords.contains(w)) {
        invalidSet.add(w);
        continue;
      }
      final voRes = await WordBo().searchWordLocalOnly(w);
      if (voRes.word == null) {
        invalidSet.add(w);
      }
    }

    if (mounted) {
      setState(() {
        _extractedWords = wordSet.toList();
        _invalidWords = invalidSet;
        _isRecognizing = false;
        _manualMode = false;
      });

      final newCount = wordSet.length - existingSet.length;
      if (newCount == 0 && existingSet.isEmpty) {
        ToastUtil.info('没有识别到有效的英文单词');
      } else if (newCount > 0 && existingSet.isNotEmpty) {
        ToastUtil.info('新增 $newCount 个单词');
      }
    }
  }

  void _importWords() async {
    final wordsToImport = _selectedValidWords;

    if (wordsToImport.isEmpty) {
      ToastUtil.info('没有可导入的单词');
      return;
    }

    setState(() {
      _isImporting = true;
      _importedSoFar = 0;
      _totalToImport = wordsToImport.length;
    });

    int existCount = 0;
    int successCountThisTime = 0;
    final dictId = widget.wordModifier.targetDictId;

    try {
      for (String word in wordsToImport) {
        final voRes = await WordBo().searchWordLocalOnly(word);
        if (voRes.word != null) {
          final wordVo = voRes.word!;
          bool shouldAdd = true;

          if (dictId != null) {
            final existing = await MyDatabase.instance.dictWordsDao
                .getById(dictId, wordVo.id!);
            if (existing != null) {
              shouldAdd = false;
              existCount++;
            }
          }

          if (shouldAdd) {
            final success = await widget.wordModifier.addWord(wordVo.id!);
            if (success) {
              _successImportCount++;
              successCountThisTime++;
            }
          }

          setState(() {
            _extractedWords.remove(word);
            _importedSoFar++;
          });
        }
      }

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
        autoCloseDuration: null,
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
      _deselectedWords.remove(word);
    });
  }

  void _toggleWordSelection(String word) {
    setState(() {
      if (_deselectedWords.contains(word)) {
        _deselectedWords.remove(word);
      } else {
        _deselectedWords.add(word);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final hasWords = _extractedWords.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        Get.back(result: _successImportCount > 0);
      },
      child: Scaffold(
        backgroundColor:
            isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
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
            '扫描导入',
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
          child: _isRecognizing
              ? _buildRecognizingView(isDarkMode)
              : hasWords && !_manualMode
                  ? _buildResultView(isDarkMode)
                  : _manualMode
                      ? _buildManualInputView(isDarkMode)
                      : _buildScanEntryView(isDarkMode),
        ),
      ),
    );
  }

  // ====== 正在识别中 ======
  Widget _buildRecognizingView(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            '正在识别文字...',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode ? Colors.white60 : Colors.black45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '使用设备端 AI 识别，无需联网',
            style: TextStyle(
              fontSize: 13,
              color: isDarkMode ? Colors.white30 : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }

  // ====== 扫描入口（初始页面） ======
  Widget _buildScanEntryView(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // 大扫描按钮
          GestureDetector(
            onTap: _scanFromCamera,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.gradientStartColor, AppTheme.gradientEndColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.document_scanner_rounded, size: 48, color: Colors.white),
                  SizedBox(height: 6),
                  Text(
                    '拍照扫描',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '对准书本拍照，自动提取英文单词',
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.white38 : Colors.black38,
            ),
          ),
          const Spacer(flex: 1),
          // 辅助入口
          Row(
            children: [
              Expanded(
                child: _buildSecondaryEntry(
                  icon: Icons.photo_library_rounded,
                  label: '从相册选',
                  isDarkMode: isDarkMode,
                  onTap: _pickFromGallery,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSecondaryEntry(
                  icon: Icons.keyboard_rounded,
                  label: '手动输入',
                  isDarkMode: isDarkMode,
                  onTap: () => setState(() => _manualMode = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSecondaryEntry({
    required IconData icon,
    required String label,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.15 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 28,
                color: isDarkMode ? Colors.white54 : Colors.black45),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== 手动输入模式 ======
  Widget _buildManualInputView(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  autofocus: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: '粘贴或输入英文文本...',
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.white38 : Colors.black26,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final data =
                        await Clipboard.getData(Clipboard.kTextPlain);
                    if (data != null &&
                        data.text != null &&
                        data.text!.isNotEmpty) {
                      setState(() {
                        _textController.text += data.text!;
                      });
                    } else {
                      ToastUtil.info('剪贴板为空');
                    }
                  },
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('粘贴'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isDarkMode ? Colors.white70 : Colors.black54,
                    side: BorderSide(
                      color:
                          isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final text = _textController.text;
                    if (text.trim().isEmpty) {
                      ToastUtil.info('请先输入文本');
                      return;
                    }
                    _extractWordsFromText(text);
                  },
                  icon: const Icon(Icons.auto_awesome, size: 20),
                  label: const Text(
                    '提取单词',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _manualMode = false),
            child: Text(
              '返回扫描',
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====== 提取结果展示 ======
  Widget _buildResultView(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 统计指示条
          _buildStatBar(isDarkMode),
          const SizedBox(height: 10),
          // 单词标签列表
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isDarkMode ? 0.2 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: _extractedWords.map((word) {
                    final isInvalid = _invalidWords.contains(word);
                    final isDeselected = _deselectedWords.contains(word);
                    return _buildWordChip(
                      word,
                      isInvalid: isInvalid,
                      isDeselected: isDeselected,
                      isDarkMode: isDarkMode,
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 导入进度条
          if (_isImporting && _totalToImport > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _importedSoFar / _totalToImport,
                      minHeight: 4,
                      backgroundColor:
                          isDarkMode ? Colors.grey[800] : Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_importedSoFar / $_totalToImport',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),

          // 导入按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isImporting || _selectedValidWords.isEmpty
                  ? null
                  : _importWords,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    isDarkMode ? Colors.grey[800] : Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 20),
              label: Text(
                _isImporting
                    ? '正在导入...'
                    : '导入选中的 ${_selectedValidWords.length} 个单词',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 底部辅助操作
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBottomAction(
                icon: Icons.document_scanner_rounded,
                label: '继续扫描',
                isDarkMode: isDarkMode,
                onTap: _isImporting ? null : _scanFromCamera,
              ),
              const SizedBox(width: 20),
              _buildBottomAction(
                icon: Icons.refresh_rounded,
                label: '清空重来',
                isDarkMode: isDarkMode,
                onTap: _isImporting
                    ? null
                    : () {
                        setState(() {
                          _extractedWords.clear();
                          _invalidWords.clear();
                          _deselectedWords.clear();
                          _textController.dispose();
                          _textController = TextEditingController();
                        });
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required bool isDarkMode,
    VoidCallback? onTap,
  }) {
    final color = isDarkMode ? Colors.white38 : Colors.black38;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }

  // ====== 统计指示条 ======
  Widget _buildStatBar(bool isDarkMode) {
    final validCount = _validWords.length;
    final invalidCount = _invalidWords.length;
    final selectedCount = _selectedValidWords.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildStatDot(
            '可导入',
            '$selectedCount/$validCount',
            AppTheme.primaryColor,
            isDarkMode,
          ),
          if (invalidCount > 0) ...[
            const SizedBox(width: 12),
            _buildStatDot(
              '未识别',
              '$invalidCount',
              Colors.red,
              isDarkMode,
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                if (_deselectedWords.isEmpty) {
                  _deselectedWords = _validWords.toSet();
                } else {
                  _deselectedWords.clear();
                }
              });
            },
            child: Text(
              _deselectedWords.isEmpty ? '取消全选' : '全选',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDot(
      String label, String value, Color color, bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: TextStyle(
            fontSize: 13,
            color: isDarkMode ? Colors.white60 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ====== 单词标签 ======
  Widget _buildWordChip(
    String word, {
    required bool isInvalid,
    required bool isDeselected,
    required bool isDarkMode,
  }) {
    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isInvalid) {
      bgColor = Colors.red.withValues(alpha: 0.08);
      borderColor = Colors.red.withValues(alpha: 0.25);
      textColor = isDarkMode ? Colors.redAccent : Colors.red;
    } else if (isDeselected) {
      bgColor = isDarkMode
          ? Colors.grey.withValues(alpha: 0.1)
          : Colors.grey.withValues(alpha: 0.06);
      borderColor = isDarkMode
          ? Colors.grey.withValues(alpha: 0.2)
          : Colors.grey.withValues(alpha: 0.2);
      textColor = isDarkMode ? Colors.white30 : Colors.black26;
    } else {
      bgColor = AppTheme.primaryColor.withValues(alpha: 0.08);
      borderColor = AppTheme.primaryColor.withValues(alpha: 0.25);
      textColor = isDarkMode ? Colors.white : AppTheme.primaryColor;
    }

    return GestureDetector(
      onTap: () {
        if (isInvalid) {
          _removeWord(word);
        } else {
          _toggleWordSelection(word);
        }
      },
      onLongPress: () => _removeWord(word),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isInvalid)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  isDeselected
                      ? Icons.check_box_outline_blank_rounded
                      : Icons.check_box_rounded,
                  size: 16,
                  color: isDeselected
                      ? (isDarkMode ? Colors.white30 : Colors.black26)
                      : AppTheme.primaryColor,
                ),
              ),
            Text(
              word,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                decoration: isDeselected ? TextDecoration.lineThrough : null,
              ),
            ),
            if (isInvalid)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
