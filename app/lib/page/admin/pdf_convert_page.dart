import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';

class PdfConvertPage extends StatefulWidget {
  const PdfConvertPage({super.key});

  @override
  State<PdfConvertPage> createState() => _PdfConvertPageState();
}

class ExtractedWord {
  final int index;
  final String word;
  final String meaning;
  final int pageIndex;
  ExtractedWord(this.index, this.word, this.meaning, this.pageIndex);
}

class _PdfConvertPageState extends State<PdfConvertPage> {
  String? _selectedFileName;
  dynamic _selectedFileContent; // Web 下是 Uint8List, Native 下是 String (path)
  final List<ExtractedWord> _extractedWordsList = [];
  bool _isProcessing = false; // true: 正在上传新文件
  bool _isSyncing = false;    // true: 正在查看已有任务结果
  bool _includeMeaning = false;
  List<dynamic> _availableTasks = [];
  int _currentPageIndex = 0;
  int _totalPages = 0;
  Timer? _refreshTimer;
  CancelToken? _cancelToken;
  final TextEditingController _resultController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTasks(autoSync: true);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _resultController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      // 尝试直接调用静态方法（部分版本支持）
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: kIsWeb,
      );

      if (result != null) {
        setState(() {
          if (kIsWeb) {
            _selectedFileName = result.files.first.name;
            _selectedFileContent = result.files.first.bytes;
          } else {
            _selectedFileName = result.files.first.name;
            _selectedFileContent = result.files.first.path;
          }
        });
      }
    } catch (e) {
      Global.logger.e("选择文件失败", error: e);
      ToastUtil.error("选择文件失败: $e");
    }
  }

  void _showPathInputDialog() {
    // 保留手动输入路径作为备选方案
    String path = "";
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("手动输入 PDF 路径"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("请输入 PDF 文件的完整路径：", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: "/path/to/your/words.pdf",
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => path = val,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          TextButton(
            onPressed: () {
              if (path.trim().isEmpty) return;
              setState(() {
                _selectedFileName = path.split('/').last;
                _selectedFileContent = path;
              });
              Navigator.pop(context);
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTasks({bool autoSync = false}) async {
    try {
      final response = await Api.dio.get("/admin/pdf/tasks.do");
      if (response.data['success'] == true) {
        final tasks = response.data['data'] as List<dynamic>;
        setState(() {
          _availableTasks = tasks;
        });

        // 如果预览区是空的，自动同步最相关的任务结果
        if (autoSync && _extractedWordsList.isEmpty && tasks.isNotEmpty) {
          // 优先选取：正在运行 > 已停止但有进度 > 已完成
          dynamic taskToSync = tasks.firstWhere(
            (t) => t['finished'] != true && t['stopped'] != true,
            orElse: () => tasks.firstWhere(
              (t) => t['stopped'] == true && (t['processedPages'] as int? ?? 0) > 0,
              orElse: () => tasks.firstWhere(
                (t) => t['finished'] == true,
                orElse: () => null,
              ),
            ),
          );
          if (taskToSync != null) {
            _syncTask(taskToSync['taskId'] as String);
          }
        }
      }
    } catch (e) {
      Global.logger.e("获取任务列表失败", error: e);
    }
  }

  Future<void> _startConversion() async {
    if (_selectedFileContent == null) {
      ToastUtil.info("请先选择 PDF 文件");
      return;
    }

    setState(() {
      _isProcessing = true;
      _extractedWordsList.clear();
      _resultController.text = "";
      _currentPageIndex = 0;
      _totalPages = 0;
      _cancelToken = CancelToken();
    });
    _startRefreshTimer();

    try {
      FormData formData;
      if (kIsWeb && _selectedFileContent is List<int>) {
        formData = FormData.fromMap({
          "file": MultipartFile.fromBytes(
            _selectedFileContent as List<int>,
            filename: _selectedFileName,
          ),
        });
      } else if (_selectedFileContent is String) {
        formData = FormData.fromMap({
          "file": await MultipartFile.fromFile(
            _selectedFileContent as String,
            filename: _selectedFileName,
          ),
        });
      } else {
        throw Exception("不支持的文件选择模式");
      }

      final response = await Api.dio.post(
        "/admin/pdf/extractWords.do",
        data: formData,
        options: Options(responseType: ResponseType.stream),
        cancelToken: _cancelToken,
      );

      final responseBody = response.data as ResponseBody;
      await _processStream(responseBody.stream.cast<List<int>>());
      _loadTasks(); // 刷新任务列表
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        Global.logger.i("用户取消了 PDF 转换");
        ToastUtil.info("已停止提取");
      } else {
        Global.logger.e("PDF 转换异常", error: e);
        ToastUtil.error("转换异常: $e");
      }
    } finally {
      setState(() {
        _isProcessing = false;
        _cancelToken = null;
      });
      _stopRefreshTimer();
    }
  }

  Future<void> _syncTask(String taskId) async {
    setState(() {
      _isSyncing = true;
      _extractedWordsList.clear();
      _resultController.text = "";
      _currentPageIndex = 0;
      _totalPages = 0;
      _cancelToken = CancelToken();
    });
    _startRefreshTimer();

    try {
      final response = await Api.dio.get(
        "/admin/pdf/syncTask.do",
        queryParameters: {"taskId": taskId},
        options: Options(responseType: ResponseType.stream),
        cancelToken: _cancelToken,
      );

      final responseBody = response.data as ResponseBody;
      await _processStream(responseBody.stream.cast<List<int>>());
    } catch (e) {
      if (!CancelToken.isCancel(e as DioException)) {
        Global.logger.e("同步任务异常", error: e);
        ToastUtil.error("同步失败: $e");
      }
    } finally {
      setState(() {
        _isSyncing = false;
        _cancelToken = null;
      });
      _stopRefreshTimer();
      _loadTasks();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isProcessing && !_isSyncing) {
        _stopRefreshTimer();
        return;
      }
      _loadTasks(); // 刷新任务面板进度
      // 从任务列表中同步总页数
      for (final task in _availableTasks) {
        final total = task['totalPages'] as int? ?? 0;
        if (total > 0 && _totalPages != total) {
          setState(() => _totalPages = total);
          break;
        }
      }
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _processStream(Stream<List<int>> stream) async {
    String buffer = "";
    int currentPageIndex = 1;
    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer += chunk;
      
      // 解析 SSE 格式
      while (buffer.contains("\n\n")) {
        int index = buffer.indexOf("\n\n");
        String eventString = buffer.substring(0, index);
        buffer = buffer.substring(index + 2);

        String? eventName;
        String? eventData;

        for (String line in eventString.split("\n")) {
          if (line.startsWith("event:")) {
            eventName = line.substring(6).trim();
          } else if (line.startsWith("data:")) {
            eventData = line.substring(5).trim();
          }
        }

        Global.logger.d("收到 SSE 事件: event=$eventName, data=$eventData");

        if (eventName == "page_start" && eventData != null) {
          final pageIdx = int.tryParse(eventData) ?? currentPageIndex;
          currentPageIndex = pageIdx;
          setState(() => _currentPageIndex = pageIdx);
        } else if (eventName == "page" && eventData != null) {
          final data = eventData;
          setState(() {
            final lines = data.split('\n');
            for (var line in lines) {
              if (line.trim().isEmpty) continue;
              final parts = line.split('\t');
              final word = parts[0];
              final meaning = parts.length > 1 ? parts[1] : "";
              
              _extractedWordsList.add(ExtractedWord(
                _extractedWordsList.length + 1,
                word,
                meaning,
                currentPageIndex,
              ));
            }
            _resultController.text = _extractedWordsList.map((e) => e.word).join("\n");
          });
        } else if (eventName == "error" && eventData != null) {
          ToastUtil.error(eventData);
        } else if (eventName == "complete") {
          ToastUtil.success("提取完成！共计 ${_extractedWordsList.length} 个单词");
        }
      }
    }
  }

  Future<void> _stopTask(String taskId) async {
    try {
      await Api.dio.post("/admin/pdf/stopTask.do", queryParameters: {"taskId": taskId});
      _loadTasks();
      ToastUtil.success("已请求停止任务");
    } catch (e) {
      ToastUtil.error("停止失败: $e");
    }
  }

  /// 恢复一个因错误停止的任务：先重启后台 OCR，再同步接入结果流
  Future<void> _resumeAndSync(String taskId) async {
    try {
      await Api.dio.post("/admin/pdf/resumeTask.do", queryParameters: {"taskId": taskId});
      ToastUtil.info("任务已从断点重启，正在同步结果...");
    } catch (e) {
      ToastUtil.error("恢复失败: $e");
      return;
    }
    await _syncTask(taskId);
  }

  Future<void> _removeTask(String taskId) async {
    try {
      await Api.dio.post("/admin/pdf/removeTask.do", queryParameters: {"taskId": taskId});
      _loadTasks();
      ToastUtil.success("任务已从内存移除");
    } catch (e) {
      ToastUtil.error("移除失败: $e");
    }
  }

  void _stopConversion() {
    _cancelToken?.cancel("用户主动停止");
  }

  void _copyToClipboard() {
    if (_extractedWordsList.isEmpty) return;
    final text = _extractedWordsList.map((e) {
      if (_includeMeaning && e.meaning.isNotEmpty) {
        return "${e.word}|${e.meaning}";
      }
      return e.word;
    }).join("\n");
    Clipboard.setData(ClipboardData(text: text));
    ToastUtil.success("已复制到剪贴板${_includeMeaning ? '(含释义)' : ''}");
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: 'PDF 词书转换 (AI 解析)',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 创建新的解析任务
            _buildSectionCard(
              title: "创建新的解析任务",
              icon: Icons.add_task,
              color: Colors.deepPurple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "选择一个 PDF 词表，AI 将在后台自动识别并提取单词，过程中可以离开页面。",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  // 文件选择区
                  InkWell(
                    onTap: _isProcessing ? null : _pickFile,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.deepPurple.withValues(alpha: 0.3),
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.deepPurple.withValues(alpha: 0.04),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedFileName != null ? Icons.picture_as_pdf : Icons.upload_file,
                            size: 36,
                            color: _selectedFileName != null ? Colors.deepPurple : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedFileName ?? "点击选择 PDF 文件",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _selectedFileName == null ? Colors.grey : Colors.deepPurple,
                                    fontWeight: _selectedFileName == null ? FontWeight.normal : FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_selectedFileName == null)
                                  const Text(
                                    "支持炭炭背单词导出的 PDF 词表",
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                          if (_selectedFileName != null)
                            TextButton(
                              onPressed: _pickFile,
                              child: const Text("重新选择", style: TextStyle(fontSize: 12)),
                            )
                          else
                            TextButton(
                              onPressed: _showPathInputDialog,
                              child: const Text("手动输入路径", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 创建任务按钮
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_selectedFileContent == null || _isProcessing) ? null : _startConversion,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.rocket_launch, size: 18),
                          label: Text(_isProcessing ? "正在创建..." : "创建解析任务"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      if (_isProcessing) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _stopConversion,
                          icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
                          label: const Text("取消", style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. 解析任务列表
            if (_availableTasks.isNotEmpty) _buildTasksSection(),

            if (_availableTasks.isNotEmpty) const SizedBox(height: 20),

            // 3. 结果预览
            _buildSectionCard(
              title: "提取结果预览",
              icon: Icons.list_alt,
              color: Colors.green,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (_isSyncing) ...[ 
                            const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _totalPages > 0
                                ? "共 ${_extractedWordsList.length} 个单词  ·  第 $_currentPageIndex / $_totalPages 页"
                                : "共计 ${_extractedWordsList.length} 个单词",
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text("含释义", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 24,
                            width: 36,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: Switch(
                                value: _includeMeaning,
                                onChanged: (val) => setState(() => _includeMeaning = val),
                                activeThumbColor: Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: _extractedWordsList.isEmpty ? null : _copyToClipboard,
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text("复制全部", style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 400,
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.black26 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        // 表头
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white10 : Colors.grey.shade200,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 40, child: Text("序号", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 120, child: Text("单词拼写", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(child: Text("中文释义", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                          ),
                        ),
                        // 列表内容
                        Expanded(
                          child: _extractedWordsList.isEmpty
                              ? Center(
                                  child: Text(
                                    "转换后的结果将显示在这里...",
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _extractedWordsList.length,
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context, index) {
                                    final item = _extractedWordsList[index];
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: item.pageIndex % 2 == 0 
                                            ? (isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.white)
                                            : (isDarkMode ? Colors.blue.withValues(alpha: 0.06) : Colors.blue.shade50.withValues(alpha: 0.5)),
                                        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 40, 
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text("${item.index}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                Text("P${item.pageIndex}", style: TextStyle(fontSize: 9, color: Colors.blue.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
                                              ],
                                            )
                                          ),
                                          SizedBox(width: 120, child: Text(item.word, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                                          Expanded(child: Text(item.meaning, style: const TextStyle(fontSize: 13))),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "💡 提示：提取完成后，您可以点击“复制全部”，然后前往“AI 词书导入”页面粘贴进行导入。",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksSection() {
    return _buildSectionCard(
      title: "正在进行/最近的任务",
      icon: Icons.running_with_errors,
      color: Colors.orange,
      child: Column(
        children: _availableTasks.map((task) {
          final taskId = task['taskId'] as String;
          final fileName = task['fileName'] as String? ?? "Unknown";
          final processed = task['processedPages'] as int? ?? 0;
          final total = task['totalPages'] as int? ?? 0;
          final isFinished = task['finished'] as bool? ?? false;
          final isStopped = task['stopped'] as bool? ?? false;
          final error = task['error'] as String?;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isFinished)
                      const Icon(Icons.check_circle, color: Colors.green, size: 16)
                    else if (isStopped)
                      const Icon(Icons.pause_circle_filled, color: Colors.orange, size: 16)
                    else
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (total > 0) ...[
                  LinearProgressIndicator(
                    value: processed / total,
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                    minHeight: 4,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "进度: $processed / $total 页",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ] else
                  const Text("正在准备...", style: TextStyle(fontSize: 11, color: Colors.grey)),
                
                if (error != null) 
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(error, style: const TextStyle(fontSize: 11, color: Colors.red)),
                  ),
                
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isFinished && !isStopped)
                      TextButton.icon(
                        onPressed: () => _stopTask(taskId),
                        icon: const Icon(Icons.stop, size: 14, color: Colors.orange),
                        label: const Text("停止", style: TextStyle(fontSize: 11, color: Colors.orange)),
                      ),
                    if (isStopped && !isFinished)
                      TextButton.icon(
                        onPressed: () => _resumeAndSync(taskId),
                        icon: const Icon(Icons.play_arrow, size: 14, color: Colors.green),
                        label: const Text("继续/重试", style: TextStyle(fontSize: 11, color: Colors.green)),
                      ),
                    if (!isFinished)
                      TextButton.icon(
                        onPressed: () => _syncTask(taskId),
                        icon: const Icon(Icons.sync, size: 14, color: Colors.blue),
                        label: const Text("同步结果", style: TextStyle(fontSize: 11, color: Colors.blue)),
                      ),
                    TextButton.icon(
                      onPressed: () => _removeTask(taskId),
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.grey),
                      label: const Text("移除", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    final isDarkMode = Provider.of<DarkMode>(context).isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
