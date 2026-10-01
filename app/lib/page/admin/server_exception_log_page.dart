import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';

/// 服务端异常日志 - 管理员专用（只读）
///
/// 读的是服务端的 `sys_error` 表：客户端上报的同步失败、数据不自洽，
/// 以及服务端自己发现的问题（如词书词序非法）。比本机那张 `local_exceptions`
/// 多出「客户端平台」与「客户端版本」两列 —— 这两列是判断"问题是不是集中在某一端某一版"的关键。
class ServerExceptionLogPage extends StatefulWidget {
  const ServerExceptionLogPage({super.key});

  @override
  State<ServerExceptionLogPage> createState() => _ServerExceptionLogPageState();
}

class _ServerExceptionLogPageState extends State<ServerExceptionLogPage> {
  List<SysErrorVo> _errors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadErrors();
  }

  Future<void> _loadErrors() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final result = await Api.client.getSysErrors();
      if (!mounted) return;
      if (result.success) {
        setState(() {
          _errors = result.data ?? [];
        });
      } else {
        ToastUtil.error('加载失败: ${result.msg}');
      }
    } catch (e) {
      ToastUtil.error('加载异常日志失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime? time) {
    if (time == null) return '--';
    final t = time.toLocal();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  /// 该条异常来自"哪一端、哪一版"：两列都缺时说明是服务端自身产生或旧版客户端未上报
  String _clientLabel(SysErrorVo error) {
    final type = error.clientType;
    final version = error.clientVersion;
    if ((type == null || type.isEmpty) && (version == null || version.isEmpty)) {
      return '服务端自身 / 未上报';
    }
    final parts = <String>[];
    if (type != null && type.isNotEmpty) parts.add(type);
    if (version != null && version.isNotEmpty) parts.add('版本 $version');
    return parts.join(' · ');
  }

  void _showDetail(SysErrorVo error) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final detailColor = isDarkMode ? const Color(0xFF1A202C) : const Color(0xFFF1F5F9);
    final detailTextColor = isDarkMode ? const Color(0xFFEDF2F7) : const Color(0xFF1A202C);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      '异常详情',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailItem('ID', error.id),
                      _buildDetailItem('异常分类', error.errorType),
                      _buildDetailItem('时间', _formatDateTime(error.createTime)),
                      _buildDetailItem('客户端平台', _clientLabel(error)),
                      _buildDetailItem('关联用户',
                          '${error.nickName ?? "未知"} (${error.userId ?? "未登录"})'),
                      const SizedBox(height: 16),
                      const Text(
                        '现场上下文',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: detailColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          error.details?.isNotEmpty == true ? error.details! : '无',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: detailTextColor,
                          ),
                        ),
                      ),
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

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return AppScaffold(
      appBar: AppAppBar(
        title: '服务端异常日志',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _loadErrors,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无异常日志',
                        style: TextStyle(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: cardColor,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '最近 ${_errors.length} 条异常记录',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '按时间倒序',
                            style: TextStyle(
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _errors.length,
                        itemBuilder: (context, index) {
                          final error = _errors[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: cardColor,
                            elevation: isDarkMode ? 0 : 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: Text(
                                error.errorType,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  if (error.details != null && error.details!.isNotEmpty)
                                    Text(
                                      error.details!,
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        _clientLabel(error),
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        error.nickName ?? error.userId ?? '未登录/游客',
                                        style: TextStyle(
                                          color: isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        _formatDateTime(error.createTime),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.visibility),
                                color: AppTheme.primaryColor,
                                onPressed: () => _showDetail(error),
                                tooltip: '查看详情',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
