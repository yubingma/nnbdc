import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

/// CDN管理页面
class CdnManagementPage extends StatefulWidget {
  const CdnManagementPage({super.key});

  @override
  State<CdnManagementPage> createState() => _CdnManagementPageState();
}

class _CdnManagementPageState extends State<CdnManagementPage> {
  final TextEditingController _urlController = TextEditingController();
  String _selectedType = 'File'; // File 或 Directory
  
  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 刷新CDN缓存
  Future<void> _refreshCache() async {
    final urls = _urlController.text.trim();
    
    if (urls.isEmpty) {
      ToastUtil.info('请输入需要刷新的URL');
      return;
    }

    // 验证URL格式
    final urlList = urls.split('\n').where((url) => url.trim().isNotEmpty).toList();
    for (final url in urlList) {
      final trimmedUrl = url.trim();
      if (!trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://')) {
        ToastUtil.error('URL必须以http://或https://开头: $trimmedUrl');
        return;
      }
    }

    try {
      final result = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.refreshCdnCache(urls, _selectedType);
      });

      if (result.success) {
        ToastUtil.success('缓存刷新任务提交成功');
        _urlController.clear();
      } else {
        ToastUtil.error('刷新失败: ${result.msg ?? "未知错误"}');
      }
    } catch (e) {
      Global.logger.e('刷新CDN缓存失败', error: e);
      ToastUtil.error('刷新失败: $e');
    }
  }

  /// 快速填充示例URL
  void _fillExampleUrls() {
    setState(() {
      _urlController.text = 'http://www.nnbdc.com/back/getDictResById.do?dictId=xxx\n'
          'http://www.nnbdc.com/img/word/';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'CDN缓存管理',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            fontFamily: 'NotoSansSC',
          ),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 刷新类型选择
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '刷新类型',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTypeOption(
                          type: 'File',
                          label: '文件刷新',
                          description: '适用于单个文件',
                          icon: Icons.insert_drive_file,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTypeOption(
                          type: 'Directory',
                          label: '目录刷新',
                          description: '适用于整个目录',
                          icon: Icons.folder,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // URL输入区域
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '需要刷新的URL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: isDarkMode ? Colors.white : Colors.black87,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _fillExampleUrls,
                        icon: const Icon(Icons.lightbulb_outline, size: 18),
                        label: const Text('示例'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    maxLines: 8,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      fontFamily: 'NotoSansSC',
                    ),
                    decoration: InputDecoration(
                      hintText: '请输入需要刷新的URL，多个URL请换行分隔\n\n例如:\nhttp://www.nnbdc.com/back/getDictResById.do?dictId=xxx\nhttp://www.nnbdc.com/img/word/',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? Colors.grey[600] : Colors.grey[500],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode ? const Color(0xFF444444) : const Color(0xFFD0D0D0),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDarkMode ? const Color(0xFF444444) : const Color(0xFFD0D0D0),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFFAFAFA),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 操作按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _refreshCache,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text(
                  '提交刷新',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 使用说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1A3A52) : const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? const Color(0xFF2E5984) : const Color(0xFFBBDEFB),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '使用说明',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTipItem('• URL必须以http://或https://开头'),
                  _buildTipItem('• 支持多个URL，每个URL占一行'),
                  _buildTipItem('• 文件刷新：适用于单个文件'),
                  _buildTipItem('• 目录刷新：适用于整个目录下的所有文件'),
                  _buildTipItem('• 刷新任务通常在5-6分钟内生效'),
                  _buildTipItem('• 每日最多可提交10,000条URL刷新请求'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建刷新类型选项
  Widget _buildTypeOption({
    required String type,
    required String label,
    required String description,
    required IconData icon,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final isSelected = _selectedType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDarkMode ? const Color(0xFF2E3F4F) : const Color(0xFFE3F2FD))
              : (isDarkMode ? const Color(0xFF252525) : const Color(0xFFF5F5F5)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : (isDarkMode ? const Color(0xFF333333) : const Color(0xFFD0D0D0)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : (isDarkMode ? Colors.white : Colors.black87),
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建提示项
  Widget _buildTipItem(String text) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: isDarkMode ? Colors.grey[300] : const Color(0xFF424242),
          fontFamily: 'NotoSansSC',
        ),
      ),
    );
  }
}

