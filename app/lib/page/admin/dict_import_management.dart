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
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/page/word_detail.dart'; 
import 'package:nnbdc/page/admin/admin_image_review_page.dart';
import 'package:get/get.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nnbdc/db/db.dart'; 

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
  bool _generateWordImage = false;
  bool _generateShuffledVersion = false;
  final List<String> _availableVoices = ['longanyang', 'longanhuan', 'longxiaochun_v3', 'longxiaoxia_v3', 'longniuniu_v3', 'longhuhu_v3', 'longjielidou_v3']; 
  final List<String> _selectedVoices = ['longanyang', 'longanhuan', 'longxiaochun_v3', 'longxiaoxia_v3', 'longniuniu_v3', 'longhuhu_v3', 'longjielidou_v3'];

  final TextEditingController _dictNameCtrl = TextEditingController(text: "系统词典");
  final TextEditingController _wordsCtrl = TextEditingController(text: "apple|一种甜酸可口的水果\nbanana\ncat");
  final TextEditingController _deleteDictIdCtrl = TextEditingController();
  final TextEditingController _domainCtrl = TextEditingController();

  bool _isDictMatched = false;
  int _matchedDictWordCount = 0;

  @override
  void initState() {
    super.initState();
    _checkDictMatch(_dictNameCtrl.text);
  }

  void _checkDictMatch(String name) async {
    final trimName = name.trim();
    if (trimName.isEmpty) {
      if (mounted) setState(() { _isDictMatched = false; });
      return;
    }
    try {
      final db = MyDatabase.instance;
      final results = await (db.select(db.dicts)..where((d) => d.name.equals(trimName))).get();
      if (results.isNotEmpty) {
        final dict = results.first;
        if (mounted) {
          setState(() {
            _isDictMatched = true;
            _matchedDictWordCount = dict.wordCount;
          });
          if (dict.domain != null && dict.domain!.isNotEmpty) {
            _domainCtrl.text = dict.domain!;
          }
        }
      } else {
        if (mounted) setState(() { _isDictMatched = false; });
      }
    } catch (e) {
      Global.logger.e('查询匹配词书失败', error: e);
    }
  }

  @override
  void dispose() {
    _dictNameCtrl.dispose();
    _wordsCtrl.dispose();
    _deleteDictIdCtrl.dispose();
    _domainCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _submitTask() async {
    final lines = _wordsCtrl.text.split('\n');
    final wordsToImport = lines.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final dictName = _dictNameCtrl.text.trim();

    if (wordsToImport.isEmpty || dictName.isEmpty) {
      ToastUtil.info("请输入词书名称和单词列表");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _taskId = null;
      _taskDetails = null;
    });

    try {
      // 导入前: 主动清除目标单词在本地缓存的发音，避免跨系统状态污染
      // 对于例句，由于无法直接预知所有旧例句的 englishDigest，这里为了管理员测试能立刻听到全新合成发音，
      // 最暴力的手段是直接调用 emptyCache() 释放手机端全部旧发音。
      for (var wordLine in wordsToImport) {
        final pureWord = wordLine.split('|')[0].trim();
        final soundUrl = Util.getWordSoundUrl(pureWord);
        if (soundUrl.isNotEmpty) {
          await DefaultCacheManager().removeFile(soundUrl);
        }
      }
      await DefaultCacheManager().emptyCache();
      Global.logger.i('已在导入前清理目标单词及例句关联的全部本地媒体缓存');

      final request = JsonMap({
        "ownerId": Global.sysUserId, 
        "fileName": "词书导入: $dictName",
        "config": jsonEncode({
          "isSystemImport": true,
          "dictId": "",
          "dictName": dictName,
          "domain": _domainCtrl.text.trim(),
          "ttsVoices": _selectedVoices.join(","),
          "words": wordsToImport,
          "generateWordImage": _generateWordImage,
          "generateShuffledVersion": _generateShuffledVersion
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

  void _deleteDict() async {
    final dictId = _deleteDictIdCtrl.text.trim();
    if (dictId.isEmpty) {
      ToastUtil.info("请输入要删除的系统词书ID");
      return;
    }
    try {
      final res = await Api.client.deleteSystemDict(dictId);
      if (res.success) {
        ToastUtil.success("系统词典[$dictId]及孤儿文件彻底删除成功");
      } else {
        ToastUtil.error("删除词书失败: ${res.msg}");
      }
    } catch(e) {
      ToastUtil.error("删除异常: $e");
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
          }
          final status = res.data!.data['status'];
          if (status == 'COMPLETED' || status == 'FAILED' || status == 'SKIPPED') {
            timer.cancel();
            
            if (status == 'COMPLETED') {
              ThrottledDbSyncService().requestSync(immediate: true);

              // 清除前端有关这些新导入单词的发音文件本地缓存，避免继续播放旧版本（如AI错误生成的）发音
              try {
                final resultsStr = res.data!.data['results'];
                if (resultsStr != null) {
                  final results = jsonDecode(resultsStr);
                  final List<dynamic>? wordDetails = results['wordDetails'];
                  if (wordDetails != null) {
                    final wordsToClear = wordDetails.map((w) => w['spell'].toString()).toList();
                    for (var word in wordsToClear) {
                      final soundUrl = Util.getWordSoundUrl(word);
                      if (soundUrl.isNotEmpty) {
                        try {
                          await DefaultCacheManager().removeFile(soundUrl);
                          Global.logger.i('已清理单词发音缓存: $soundUrl');
                        } catch(e) { /* ignore */ }
                      }
                    }
                  }
                }
              } catch (ce) {
                Global.logger.e('清理导入后缓存异常', error: ce);
              }
            }
          }
        }
      } catch (e) {
        Global.logger.e('polling error', error: e);
      }
    });
  }

  void _showDictSearchSheet() {
    String keyword = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('搜索系统词书', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: '输入系统词库名称进行查询...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (val) {
                      setSheetState(() => keyword = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: FutureBuilder(
                      future: Api.client.searchSystemDicts(keyword),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.success) {
                          return const Center(child: Text('搜索失败, 请检查网络'));
                        }
                        final list = snapshot.data!.data ?? [];
                        if (list.isEmpty) {
                          return const Center(child: Text('未能找到符合条件的系统词书', style: TextStyle(color: Colors.grey)));
                        }
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final dict = list[index] as Map<String, dynamic>;
                            return ListTile(
                              leading: const Icon(Icons.library_books, color: AppTheme.primaryColor),
                              title: Text(dict['name'] ?? '未命名词库', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('ID: ${dict['id']}'),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _deleteDictIdCtrl.text = dict['id'].toString();
                                  });
                                  Navigator.pop(context);
                                },
                                child: const Text('选择'),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'COMPLETED': color = Colors.green; break;
      case 'FAILED': color = Colors.red; break;
      case 'RUNNING': color = Colors.blue; break;
      default: color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatItem(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
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
        title: 'AI 词书资源管理',
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.image_search, color: Colors.white), tooltip: 'AI 配图审核', onPressed: () => Get.to(() => const AdminImageReviewPage())),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.delete_forever, color: Colors.red)),
                        const SizedBox(width: 12),
                        const Text('删除系统词书及垃圾回收', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _deleteDictIdCtrl,
                      decoration: InputDecoration(
                        labelText: '要删除的系统词书ID',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, color: AppTheme.primaryColor),
                          onPressed: _showDictSearchSheet,
                          tooltip: '搜索系统自带的词库查询ID',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _deleteDict, 
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('彻底粉碎此词书'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.post_add, color: AppTheme.primaryColor)),
                        const SizedBox(width: 12),
                        const Text('导入系统词库', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _dictNameCtrl,
                      onChanged: _checkDictMatch,
                      decoration: InputDecoration(
                        labelText: '目标词典名称 (如果同名则追加, 否则新建)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    if (_isDictMatched)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          '✅ 已找到该词库，当前包含 $_matchedDictWordCount 个单词',
                          style: const TextStyle(color: Colors.green, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180, 
                      child: TextField(
                        controller: _wordsCtrl,
                        maxLines: null,
                        expands: true,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        labelText: '单词列表 (每行一个，支持"单词|自定义释义")',
                        hintText: "",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _domainCtrl,
                      decoration: InputDecoration(
                        labelText: '专业领域 (选填，告诉AI按此发散释义，如"医学"、"计算机")',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TTS 发音人选择 (多选，默认随机分配)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children: _availableVoices.map((voice) {
                            final isSelected = _selectedVoices.contains(voice);
                            return FilterChip(
                              label: Text(voice, style: TextStyle(fontSize: 13, color: isSelected ? Colors.white : Colors.black87)),
                              selected: isSelected,
                              selectedColor: AppTheme.primaryColor,
                              checkmarkColor: Colors.white,
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedVoices.add(voice);
                                  } else {
                                    // 保证至少选一个，不要清空
                                    if (_selectedVoices.length > 1) {
                                      _selectedVoices.remove(voice);
                                    } else {
                                      ToastUtil.info("至少保留一个发音人");
                                    }
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                      ),
                      child: SwitchListTile(
                        title: const Text('生成单词配图', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('调用大模型根据单词含义绘画，可能显著增加消耗', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        value: _generateWordImage,
                        onChanged: _isSubmitting ? null : (val) {
                          setState(() {
                            _generateWordImage = val;
                          });
                        },
                        activeThumbColor: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                      ),
                      child: SwitchListTile(
                        title: const Text('同时生成乱序版', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('将生成一个名称带"(乱序版)"的重复词书，单词按MD5混淆排序，且共享发音原图等资源', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        value: _generateShuffledVersion,
                        onChanged: _isSubmitting ? null : (val) {
                          setState(() {
                            _generateShuffledVersion = val;
                          });
                        },
                        activeThumbColor: AppTheme.primaryColor,
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
                          Expanded(
                            child: Text( 
                              '任务 ID: ${_taskId!}', 
                              style: const TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(_taskDetails!['status'] ?? 'UNKNOWN'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // 进度展示 
                      Builder(builder: (context) {
                        final total = _taskDetails!['totalWords'] ?? 0;
                        final processed = _taskDetails!['processedWords'] ?? 0;
                        final double progressVal = total > 0 ? (processed / total) : 0.0;
                        final bool isRunning = _taskDetails!['status'] == 'RUNNING';
                        
                        if (isRunning) {
                          return Column( 
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LinearProgressIndicator(value: total > 0 ? progressVal : null),
                              const SizedBox(height: 8),
                              Center(child: Text('进度: ${total > 0 ? '$processed / $total' : '计算中'} (AI 正在全力生成中...)', style: const TextStyle(fontSize: 12, color: Colors.grey))),
                            ],
                          );
                        } else if (_taskDetails!['status'] == 'COMPLETED') {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LinearProgressIndicator(value: 1.0, color: Colors.green, backgroundColor: Colors.green.withValues(alpha: 0.2)),
                              const SizedBox(height: 8),
                              Center(child: Text('任务已完成 (总计处理 $total 个)', style: const TextStyle(fontSize: 12, color: Colors.green))),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      }),

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
                              final wordDetails = stats['wordDetails'] as List<dynamic>?;
                              String? currentDictId;
                              try {
                                if (_taskDetails!['config'] != null) {
                                  final configJson = jsonDecode(_taskDetails!['config'] as String);
                                  currentDictId = configJson['dictId']?.toString();
                                }
                              } catch(e) {
                                Global.logger.e('解析任务配置(config)异常', error: e);
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
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
                                  ),
                                  if (wordDetails != null && wordDetails.isNotEmpty) ...[
                                    const SizedBox(height: 24),
                                    const Divider(),
                                    const SizedBox(height: 16),
                                    const Text('处理单词列表 (点击查看详情)', style: TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: wordDetails.map((w) {
                                        final detail = w as Map<String, dynamic>;
                                        final status = detail['status'] as String? ?? '';
                                        Color statusColor;
                                        if (status == 'ADDED' || status == 'RECREATED' || status == 'APPENDED') {
                                          statusColor = Colors.green;
                                        } else if (status == 'SKIPPED') {
                                          statusColor = Colors.orange;
                                        } else {
                                          statusColor = Colors.red;
                                        }
                                        return ActionChip(
                                          avatar: Icon(Icons.circle, color: statusColor, size: 12),
                                          label: Text(detail['spell'] ?? '未知'),
                                          onPressed: () async {
                                            final spell = detail['spell'];
                                            if (spell != null && spell.isNotEmpty) {
                                              final wordRes = await WordBo().searchWordLocalOnly(spell);
                                              if (wordRes.word != null) {
                                                Get.to(() => const WordDetailPage(), arguments: WordDetailPageArgs(wordRes.word!, true, null, false, priorityDictIds: currentDictId != null && currentDictId.isNotEmpty ? [currentDictId] : null));
                                              } else {
                                                ToastUtil.error('未在本地找到单词，可能同步还在进行中');
                                              }
                                            }
                                          },
                                          backgroundColor: statusColor.withValues(alpha: 0.05),
                                          side: BorderSide(color: statusColor.withValues(alpha: 0.2)),
                                        );
                                      }).toList(),
                                    ),
                                  ],
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
