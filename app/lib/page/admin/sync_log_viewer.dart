import 'package:flutter/material.dart';
import 'package:nnbdc/models/sync_log.dart';
import 'package:nnbdc/services/sync_log_service.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/theme/app_theme.dart';
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
        Global.logger.e('删除失败: $e');
      }
    }
  }

  void _showLogDetail(SyncLog log) {
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: theme.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.textMuted.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: log.success
                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                          : (log.isWarning
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                              : const Color(0xFFEF4444).withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      log.success
                          ? Icons.cloud_done_rounded
                          : (log.isWarning ? Icons.warning_amber_rounded : Icons.cloud_off_rounded),
                      size: 20,
                      color: log.success
                          ? const Color(0xFF10B981)
                          : (log.isWarning ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.success ? '同步详情' : (log.isWarning ? '同步异常' : '同步失败'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          _formatDateTime(log.startTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textMuted,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: theme.textMuted, size: 20),
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.subtleBg.withValues(alpha: isDark ? 0.35 : 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.cardBorder, width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMiniStat('耗时', _formatDuration(log.durationMs), theme),
                          _buildMiniDivider(theme),
                          _buildMiniStat('上行记录', '${log.uploadCount ?? 0}', theme),
                          _buildMiniDivider(theme),
                          _buildMiniStat('下行记录', '${log.downloadCount ?? 0}', theme),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow('记录 ID', log.id, theme),
                    if (log.dbVersion != null || log.sysDbVersion != null)
                      _buildDetailRow('数据版本', '${log.dbVersion ?? 0} | ${log.sysDbVersion ?? 0}', theme),
                    if (log.appVersion != null)
                      _buildDetailRow('App 版本', log.appVersion!, theme),
                    if (log.userId != null)
                      _buildDetailRow('用户 ID', log.userId!, theme),
                    if (log.endTime != null)
                      _buildDetailRow('结束时间', _formatDateTime(log.endTime!), theme),
                    if (log.uploadDetails != null && log.uploadDetails!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '上行详情',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildDetailsMapCard(log.uploadDetails!, theme, isDark),
                    ],
                    if (log.downloadDetails != null && log.downloadDetails!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '下行详情',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildDetailsMapCard(log.downloadDetails!, theme, isDark),
                    ],
                    if (log.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        '错误信息',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: SelectableText(
                          log.errorMessage!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteLog(log.id);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                        label: const Text(
                          '删除此条记录',
                          style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
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
    );
  }

  Widget _buildMiniStat(String label, String value, AppThemeConfig theme) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Roboto',
            color: theme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: theme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniDivider(AppThemeConfig theme) {
    return Container(
      width: 1,
      height: 22,
      color: theme.cardBorder,
    );
  }

  Widget _buildDetailRow(String label, String value, AppThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Roboto',
                color: theme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsMapCard(Map<String, dynamic> details, AppThemeConfig theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.subtleBg.withValues(alpha: isDark ? 0.3 : 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.cardBorder, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details.entries.map((e) {
          final tableMap = e.value as Map<String, dynamic>;
          final ops = tableMap.entries.map((op) => '${op.key}: ${op.value}').join(', ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text(
                  '• ${e.key}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                    color: theme.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '($ops)',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Roboto',
                      color: theme.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _formatShortTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int? ms) {
    if (ms == null) return '-';
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;
    final lastLog = _logs.isNotEmpty ? _logs.first : null;

    return AppScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '云同步',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: '返回',
          splashRadius: 22,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: theme.textPrimary, size: 22),
            onPressed: (_isLoading || _isSyncing) ? null : _loadLogs,
            tooltip: '刷新记录',
            splashRadius: 22,
          ),
          if (_logs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: theme.textSecondary, size: 22),
              onPressed: _deleteAllLogs,
              tooltip: '清空所有记录',
              splashRadius: 22,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.primaryColor,
              ),
            )
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.cardBorder, width: 1.0),
                        boxShadow: theme.cardShadows,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _isSyncing
                                      ? theme.primaryColor.withValues(alpha: 0.12)
                                      : (lastLog?.success == true
                                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                          : (lastLog == null
                                              ? theme.primaryColor.withValues(alpha: 0.12)
                                              : const Color(0xFFEF4444).withValues(alpha: 0.12))),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Center(
                                  child: _isSyncing
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                                          ),
                                        )
                                      : Icon(
                                          lastLog?.success == true
                                              ? Icons.cloud_done_rounded
                                              : (lastLog == null ? Icons.cloud_sync_rounded : Icons.cloud_off_rounded),
                                          size: 24,
                                          color: lastLog?.success == true
                                              ? const Color(0xFF10B981)
                                              : (lastLog == null ? theme.primaryColor : const Color(0xFFEF4444)),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isSyncing
                                          ? '正在同步数据...'
                                          : (lastLog?.success == true
                                              ? '数据已是最新'
                                              : (lastLog == null ? '尚未同步' : '上次同步异常')),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: theme.textPrimary,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      lastLog != null
                                          ? '上次同步 ${_formatShortTime(lastLog.startTime)} · 耗时 ${_formatDuration(lastLog.durationMs)}'
                                          : '保持手机与平板等多设备学习数据一致',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.textMuted,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 立即同步主按钮
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _isSyncing ? null : _manualSync,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                disabledBackgroundColor: theme.primaryColor.withValues(alpha: 0.6),
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isSyncing) ...[
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ] else ...[
                                    const Icon(Icons.sync_rounded, size: 18),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    _isSyncing ? '正在同步中...' : '立即同步',
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
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
                ),
                // 分节标题：同步记录统计
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '同步记录',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.textSecondary,
                            letterSpacing: -0.1,
                          ),
                        ),
                        Text(
                          '共 $_totalCount 条',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.textMuted,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 列表或空状态
                if (_logs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: theme.subtleBg.withValues(alpha: isDark ? 0.3 : 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.cloud_sync_outlined,
                              size: 32,
                              color: theme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '暂无云同步日志',
                            style: TextStyle(
                              color: theme.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '点击上方“立即同步”发起初次同步',
                            style: TextStyle(
                              color: theme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final log = _logs[index];
                          return _buildLogCard(log, theme, isDark);
                        },
                        childCount: _logs.length,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildLogCard(SyncLog log, AppThemeConfig theme, bool isDark) {
    final statusColor = log.success
        ? const Color(0xFF10B981)
        : (log.isWarning ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    final statusIcon = log.success
        ? Icons.cloud_done_rounded
        : (log.isWarning ? Icons.warning_amber_rounded : Icons.cloud_off_rounded);

    final statusText = log.success ? '同步成功' : (log.isWarning ? '同步异常' : '同步失败');

    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
            SizedBox(width: 4),
            Text(
              '删除',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => _deleteLog(log.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: log.success
                ? theme.cardBorder
                : statusColor.withValues(alpha: 0.35),
            width: log.success ? 0.8 : 1.0,
          ),
          boxShadow: theme.cardShadows,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showLogDetail(log),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // 左侧状态微底座
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      statusIcon,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 主体内容
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 第一行：状态标题 + 耗时 + 上下行
                        Row(
                          children: [
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (log.durationMs != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                _formatDuration(log.durationMs),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Roboto',
                                  color: theme.textMuted,
                                ),
                              ),
                            ],
                            const Spacer(),
                            // 上下行轻量指示
                            if (log.success &&
                                (log.uploadCount != null || log.downloadCount != null))
                              Text(
                                '↑${log.uploadCount ?? 0}  ↓${log.downloadCount ?? 0}',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.textMuted,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 第二行：时间戳与版本号
                        Row(
                          children: [
                            Text(
                              _formatDateTime(log.startTime),
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: 12,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            if (log.dbVersion != null || log.sysDbVersion != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                'v${log.dbVersion ?? 0}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w500,
                                  color: theme.textMuted.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // 错误信息提示（若失败）
                        if (!log.success && log.errorMessage != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            log.errorMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 右侧导向微箭头
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.textMuted.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
