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

class PdfConvertPage extends StatefulWidget {
  const PdfConvertPage({super.key});

  @override
  State<PdfConvertPage> createState() => _PdfConvertPageState();
}

class _PdfConvertPageState extends State<PdfConvertPage> {
  String? _selectedFileName;
  dynamic _selectedFileContent; // Web 下是 Uint8List, Native 下是 String (path)
  String _extractedWords = "";
  bool _isProcessing = false;
  final TextEditingController _resultController = TextEditingController();

  @override
  void dispose() {
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

  Future<void> _startConversion() async {
    if (_selectedFileContent == null) {
      ToastUtil.info("请先选择 PDF 文件");
      return;
    }

    setState(() {
      _isProcessing = true;
      _extractedWords = "";
      _resultController.text = "";
    });

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
        // Native 路径模式
        formData = FormData.fromMap({
          "file": await MultipartFile.fromFile(
            _selectedFileContent as String,
            filename: _selectedFileName,
          ),
        });
      } else {
        throw Exception("不支持的文件选择模式");
      }

      // 直接使用 dio 调用接口，绕过 retrofit 的 File 类型限制
      final response = await Api.dio.post(
        "/admin/pdf/extractWords.do",
        data: formData,
      );

      if (response.data != null && response.data['success'] == true) {
        setState(() {
          _extractedWords = response.data['data'] ?? "";
          _resultController.text = _extractedWords;
        });
        ToastUtil.success("提取完成！共计 ${(_extractedWords.trim().split('\n').length)} 个单词");
      } else {
        ToastUtil.error("转换失败: ${response.data['msg']}");
      }
    } catch (e) {
      Global.logger.e("PDF 转换异常", error: e);
      ToastUtil.error("转换异常: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_extractedWords.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _extractedWords));
    ToastUtil.success("已复制到剪贴板");
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
            // 第一步：上传区域
            _buildSectionCard(
              title: "第一步：选择 PDF 文件",
              icon: Icons.upload_file,
              color: Colors.blue,
              child: Column(
                children: [
                  const Text(
                    "支持提取炭炭背单词导出的 PDF 表格，AI 将自动识别并提取单词列。",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _isProcessing ? null : _pickFile,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.blue.withValues(alpha: 0.05),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.picture_as_pdf, size: 48, color: Colors.blue),
                          const SizedBox(height: 16),
                          Text(
                            _selectedFileName ?? "点击选择 PDF 文件",
                            style: TextStyle(
                              fontSize: 16,
                              color: _selectedFileName == null ? Colors.grey : Colors.blue,
                              fontWeight: _selectedFileName == null ? FontWeight.normal : FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "支持提取炭炭背单词导出的 PDF 表格",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if (_selectedFileName != null) ...[
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text("重新选择"),
                            ),
                          ],
                          // 添加手动输入入口，解决警告并提供备选方案
                          TextButton(
                            onPressed: _showPathInputDialog,
                            child: const Text("手动输入路径", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 第二步：开始转换按钮
            Center(
              child: SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_selectedFileContent == null || _isProcessing) ? null : _startConversion,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isProcessing ? "转换中..." : "开始提取单词"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 第三步：结果预览
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
                      Text(
                        "共计 ${_extractedWords.trim().split('\n').where((s) => s.isNotEmpty).length} 个单词",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      TextButton.icon(
                        onPressed: _extractedWords.isEmpty ? null : _copyToClipboard,
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text("复制全部", style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.black26 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: TextField(
                      controller: _resultController,
                      maxLines: null,
                      readOnly: true,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.all(12),
                        border: InputBorder.none,
                        hintText: "转换后的结果将显示在这里...",
                      ),
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
