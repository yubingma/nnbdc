import 'package:flutter/material.dart';
import 'package:nnbdc/models/sync_log.dart';
import 'package:nnbdc/services/sync_log_service.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/global.dart';

/// 云同步日志查看器
class SyncLogViewerPage extends StatefulWidget {
  const SyncLogViewerPage({super.key});

  @override
  State<SyncLogViewerPage> createState() => _SyncLogViewerPageState();
}

class _SyncLogViewerPageState extends State<SyncLogViewerPage> {
  List<SyncLog> _logs = [];
  bool _isLoading = true;
  int _totalCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = SyncLogService();
      _logs = await service.getRecentLogs(limit: 100);
      _totalCount = _logs.length;
    } catch (e) {
      // 不弹出错误提示，只记录日志
      Global.logger.e('加载同步日志失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 手动触发同步
  Future<void> _manualSync() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      ToastUtil.info('正在同步...');
      // 立即执行同步并等待完成
      await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
      
      // 同步完成后刷新日志列表
      await _loadLogs();
      
      // 检查最后一次同步结果，只在成功时提示
      final lastLog = _logs.isNotEmpty ? _logs.first : null;
      if (lastLog != null && lastLog.success) {
        ToastUtil.success('同步成功');
      }
      // 失败时不弹出提示，用户可以在日志列表中查看失败原因
    } catch (e) {
      // 同步失败，刷新日志列表查看失败原因，不弹出错误提示
      await _loadLogs();
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  Future<void> _deleteLog(String id) async {
    try {
      final service = SyncLogService();
      await service.deleteLog(id);
      ToastUtil.success('删除成功');
      _loadLogs();
    } catch (e) {
      // 不弹出错误提示，只记录日志
      Global.logger.e('删除失败: $e');
    }
  }

  Future<void> _deleteAllLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除所有云同步日志吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = SyncLogService();
        await service.clearAllLogs();
        ToastUtil.success('已删除所有同步日志');
        _loadLogs();
      } catch (e) {
        // 不弹出错误提示，只记录日志
        Global.logger.e('删除失败: $e');
      }
    }
  }

  void _showLogDetail(SyncLog log) {
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
                  const Text(
                    '同步日志详情',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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
                      _buildDetailItem('ID', log.id),
                      _buildDetailItem('状态', log.success ? '成功' : '失败'),
                      _buildDetailItem('开始时间', _formatDateTime(log.startTime)),
                      if (log.endTime != null)
                        _buildDetailItem('结束时间', _formatDateTime(log.endTime!)),
                      if (log.durationMs != null)
                        _buildDetailItem('耗时', '${log.durationMs}ms'),
                      if (log.uploadCount != null)
                        _buildDetailItem('上行记录数', '${log.uploadCount}'),
                      if (log.uploadDetails != null && log.uploadDetails!.isNotEmpty)
                        _buildDetailsMap(log.uploadDetails!),
                      if (log.downloadCount != null)
                        _buildDetailItem('下行记录数', '${log.downloadCount}'),
                      if (log.downloadDetails != null && log.downloadDetails!.isNotEmpty)
                        _buildDetailsMap(log.downloadDetails!),
                      if (log.userId != null)
                        _buildDetailItem('用户ID', log.userId!),
                      if (log.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '错误信息',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: SelectableText(
                            log.errorMessage!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
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
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsMap(Map<String, dynamic> details) {
    if (details.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(left: 100, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details.entries.map((e) {
          final tableMap = e.value as Map<String, dynamic>;
          final ops = tableMap.entries.map((op) => '${op.key}: ${op.value}').join(', ');
          return Text(
            '- ${e.key} ($ops)',
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace'),
          );
        }).toList(),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int? ms) {
    if (ms == null) return '-';
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          '云同步',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadLogs,
            tooltip: '刷新',
          ),
          if (_logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              onPressed: _deleteAllLogs,
              tooltip: '清空所有',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_sync,
                        size: 64,
                        color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无同步日志',
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
                    // 手动同步按钮
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: cardColor,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSyncing ? null : _manualSync,
                          icon: _isSyncing
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDarkMode ? Colors.white : Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: Text(_isSyncing ? '同步中...' : '立即同步'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    // 统计信息
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: cardColor,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '共 $_totalCount 条同步记录',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '显示最近${_logs.length}条',
                            style: TextStyle(
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 日志列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: cardColor,
                            elevation: isDarkMode ? 0 : 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: log.success
                                    ? (isDarkMode ? Colors.grey[700]! : Colors.grey[200]!)
                                    : (log.isWarning ? Colors.orange[300]! : Colors.red[300]!),
                                width: log.success ? 1 : 2,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Icon(
                                log.success ? Icons.cloud_done : (log.isWarning ? Icons.warning_amber_rounded : Icons.cloud_off),
                                color: log.success ? Colors.green : (log.isWarning ? Colors.orange : Colors.red),
                                size: 32,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      log.success ? '同步成功' : (log.isWarning ? '同步异常' : '同步失败'),
                                      style: TextStyle(
                                        color: log.success ? Colors.green : (log.isWarning ? Colors.orange : Colors.red),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? Colors.grey[800]
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _formatDuration(log.durationMs),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateTime(log.startTime),
                                    style: TextStyle(
                                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (log.success &&
                                      log.uploadCount != null &&
                                      log.downloadCount != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '↑ ${log.uploadCount}  ↓ ${log.downloadCount}',
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                  if (!log.success && log.errorMessage != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      log.errorMessage!.length > 50
                                          ? '${log.errorMessage!.substring(0, 50)}...'
                                          : log.errorMessage!,
                                      style: TextStyle(
                                        color: log.isWarning ? Colors.orange[400] : Colors.red[400],
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.visibility),
                                    color: AppTheme.primaryColor,
                                    onPressed: () => _showLogDetail(log),
                                    tooltip: '查看详情',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    color: Colors.red,
                                    onPressed: () => _deleteLog(log.id),
                                    tooltip: '删除',
                                  ),
                                ],
                              ),
                              isThreeLine: true,
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
