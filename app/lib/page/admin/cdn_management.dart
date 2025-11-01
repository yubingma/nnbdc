import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/cdn_url_config.dart';
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

class _CdnManagementPageState extends State<CdnManagementPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _fileUrlsController = TextEditingController();
  final TextEditingController _dirUrlsController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedUrls();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fileUrlsController.dispose();
    _dirUrlsController.dispose();
    super.dispose();
  }

  /// 加载已保存的URL配置
  Future<void> _loadSavedUrls() async {
    try {
      final result = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getCdnRefreshUrls();
      });

      if (result.success && result.data != null) {
        final config = CdnUrlConfig.fromJson(result.data!);
        setState(() {
          _fileUrlsController.text = config.fileUrls ?? '';
          _dirUrlsController.text = config.dirUrls ?? '';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      Global.logger.e('加载CDN配置失败', error: e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 保存URL配置
  Future<void> _saveUrls() async {
    final fileUrls = _fileUrlsController.text.trim();
    final dirUrls = _dirUrlsController.text.trim();

    try {
      final result = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.saveCdnRefreshUrls(fileUrls, dirUrls);
      });

      if (result.success) {
        ToastUtil.success('配置保存成功');
      } else {
        ToastUtil.error('保存失败: ${result.msg ?? "未知错误"}');
      }
    } catch (e) {
      Global.logger.e('保存CDN配置失败', error: e);
      ToastUtil.error('保存失败: $e');
    }
  }

  /// 刷新CDN缓存
  Future<void> _refreshCache() async {
    final fileUrls = _fileUrlsController.text.trim();
    final dirUrls = _dirUrlsController.text.trim();

    if (fileUrls.isEmpty && dirUrls.isEmpty) {
      ToastUtil.info('请先配置需要刷新的URL');
      return;
    }

    // 验证文件URL格式
    final fileUrlList = fileUrls.split('\n').where((url) => url.trim().isNotEmpty).toList();
    for (final url in fileUrlList) {
      final trimmedUrl = url.trim();
      if (!trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://')) {
        ToastUtil.error('文件URL必须以http://或https://开头: $trimmedUrl');
        return;
      }
    }

    // 验证目录URL格式
    final dirUrlList = dirUrls.split('\n').where((url) => url.trim().isNotEmpty).toList();
    for (final url in dirUrlList) {
      final trimmedUrl = url.trim();
      if (!trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://')) {
        ToastUtil.error('目录URL必须以http://或https://开头: $trimmedUrl');
        return;
      }
    }

    // 刷新文件缓存
    if (fileUrls.isNotEmpty) {
      try {
        Global.logger.i('准备刷新文件缓存，URL内容：\n$fileUrls');
        final result = await LoadingUtils.withoutApiLoading(() async {
          return await Api.client.refreshCdnCache(fileUrls, 'File');
        });

        if (!result.success) {
          ToastUtil.error('文件缓存刷新失败: ${result.msg ?? "未知错误"}');
          return;
        }
      } catch (e) {
        Global.logger.e('刷新文件缓存失败', error: e);
        ToastUtil.error('文件缓存刷新失败: $e');
        return;
      }
    }

    // 刷新目录缓存
    if (dirUrls.isNotEmpty) {
      try {
        Global.logger.i('准备刷新目录缓存，URL内容：\n$dirUrls');
        final result = await LoadingUtils.withoutApiLoading(() async {
          return await Api.client.refreshCdnCache(dirUrls, 'Directory');
        });

        if (!result.success) {
          ToastUtil.error('目录缓存刷新失败: ${result.msg ?? "未知错误"}');
          return;
        }
      } catch (e) {
        Global.logger.e('刷新目录缓存失败', error: e);
        ToastUtil.error('目录缓存刷新失败: $e');
        return;
      }
    }

    ToastUtil.success('缓存刷新任务已全部提交');
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(
              icon: Icon(Icons.insert_drive_file),
              text: '文件刷新',
            ),
            Tab(
              icon: Icon(Icons.folder),
              text: '目录刷新',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUrlEditor(
                        controller: _fileUrlsController,
                        type: '文件',
                        hintText: '请输入需要刷新的文件URL，多个URL请换行分隔\n\n示例:\nhttp://www.nnbdc.com/img/word/test.jpg\nhttp://www.nnbdc.com/img/word/example.png',
                        isDarkMode: isDarkMode,
                      ),
                      _buildUrlEditor(
                        controller: _dirUrlsController,
                        type: '目录',
                        hintText: '请输入需要刷新的目录URL，多个URL请换行分隔\n\n示例:\nhttp://www.nnbdc.com/img/word/\nhttp://www.nnbdc.com/img/',
                        isDarkMode: isDarkMode,
                      ),
                    ],
                  ),
                ),
                _buildActionButtons(isDarkMode),
              ],
            ),
    );
  }

  Widget _buildUrlEditor({
    required TextEditingController controller,
    required String type,
    required String hintText,
    required bool isDarkMode,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1A3A52) : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode ? const Color(0xFF2E5984) : const Color(0xFFBBDEFB),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  type == '文件' ? Icons.info_outline : Icons.folder_outlined,
                  color: isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$type刷新会批量处理该类型的所有URL',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white : Colors.black87,
                fontFamily: 'NotoSansSC',
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDarkMode ? Colors.grey[600] : Colors.grey[500],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDarkMode ? const Color(0xFF444444) : const Color(0xFFD0D0D0),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDarkMode ? const Color(0xFF444444) : const Color(0xFFD0D0D0),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saveUrls,
              icon: const Icon(Icons.save, size: 20),
              label: const Text(
                '保存配置',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(color: AppTheme.primaryColor),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
        ],
      ),
    );
  }
}


