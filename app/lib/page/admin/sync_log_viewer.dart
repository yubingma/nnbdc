import 'dart:ui';
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
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss_delete_logs_dialog',
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                // 黄金参数 sigma=8，既抹散底层字符形态，又完美保留朦胧温润的墨水色块晕开质感
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xB81C2127) // 72% 曜石深灰磨砂
                        : const Color(0x73FFFFFF), // 45% 凝润乳白通透磨砂，底层内容自然晕开，杜绝实心死白
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x33FFFFFF)
                          : const Color(0x99FFFFFF), // 精致微光切边，烘托毛玻璃高光
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 头部图标与标题
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.delete_sweep_rounded,
                              size: 22,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '清空同步历史日志',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: theme.textPrimary,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '仅清理本地诊断快照，不影响学习数据',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 好处与影响解释卡片（内嵌轻雾半透层）
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.white.withValues(alpha: 0.40),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.70),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 好处说明
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.check_circle_outline_rounded, size: 15, color: Color(0xFF10B981)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(fontSize: 12.5, height: 1.45, color: theme.textSecondary),
                                      children: [
                                        TextSpan(
                                          text: '有哪些好处？\n',
                                          style: TextStyle(fontWeight: FontWeight.w600, color: theme.textPrimary),
                                        ),
                                        const TextSpan(
                                          text: '释放本地数据库存储，清空历史堆积的同步记录与报错缓存，让诊断列表保持整洁。',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Divider(
                                height: 1,
                                thickness: 0.5,
                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            // 影响说明（坏作用）
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(Icons.info_outline_rounded, size: 15, color: theme.primaryColor),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(fontSize: 12.5, height: 1.45, color: theme.textSecondary),
                                      children: [
                                        TextSpan(
                                          text: '是否有坏影响？\n',
                                          style: TextStyle(fontWeight: FontWeight.w600, color: theme.textPrimary),
                                        ),
                                        TextSpan(
                                          text: '绝不影响任何词汇、打卡与学习进度',
                                          style: TextStyle(fontWeight: FontWeight.w600, color: theme.primaryColor),
                                        ),
                                        const TextSpan(
                                          text: '，后续云同步依然正常进行。唯一影响是无法再回溯查看过去的单次耗时及历史报错详情。',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // 底部按钮栏
                      Row(
                        children: [
                          // 取消按钮
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextButton(
                                onPressed: () => Navigator.pop(dialogCtx, false),
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.textSecondary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(100),
                                    side: BorderSide(color: theme.cardBorder, width: 0.8),
                                  ),
                                ),
                                child: const Text('暂不清理', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 确认删除按钮（最新美学：薄雾微光底 + 柔和红边框）
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(dialogCtx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.22 : 0.12),
                                  foregroundColor: const Color(0xFFEF4444),
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  side: BorderSide(
                                    color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.40 : 0.25),
                                    width: 0.8,
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                ),
                                child: const Text('确认清空', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
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

    final Color statusColor = log.success
        ? const Color(0xFF10B981)
        : (log.isWarning ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    final IconData statusIcon = log.success
        ? Icons.cloud_done_rounded
        : (log.isWarning ? Icons.warning_amber_rounded : Icons.cloud_off_rounded);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(bottomSheetContext).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xE61A202C) // 90% 深空曜石质感磨砂
                    : const Color(0xF2FFFFFF), // 95% 凝润乳白通透磨砂
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0x33FFFFFF) : const Color(0xD9FFFFFF),
                    width: 1.0,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部抽屉把手
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 6),
                      width: 38,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: theme.textMuted.withValues(alpha: isDark ? 0.35 : 0.22),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),

                  // 顶部标题栏：纯粹排版 + 状态微徽章 + 轻灵关闭按钮
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: isDark ? 0.16 : 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(statusIcon, size: 20, color: statusColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    log.success ? '同步详情' : (log.isWarning ? '同步异常' : '同步失败'),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: theme.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: isDark ? 0.14 : 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      log.success ? '正常完成' : (log.isWarning ? '部分告警' : '连接中断'),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDateTime(log.startTime),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.textMuted,
                                  fontFamily: 'Roboto',
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(bottomSheetContext),
                            borderRadius: BorderRadius.circular(100),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: theme.textMuted.withValues(alpha: isDark ? 0.12 : 0.06),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close_rounded, color: theme.textSecondary, size: 17),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Divider(
                    height: 1,
                    thickness: 0.6,
                    color: isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
                  ),

                  // 内容滚动区
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 核心三大指标（Typography-driven，告别生硬粗暴大底块，通透呼吸感）
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x2EFFFFFF) : const Color(0x52FFFFFF),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isDark ? const Color(0x1FFFFFFF) : const Color(0x66FFFFFF),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildMetricItem(
                                    label: '耗时',
                                    value: _formatDuration(log.durationMs),
                                    unit: '',
                                    theme: theme,
                                    highlightColor: theme.primaryColor,
                                  ),
                                ),
                                _buildMetricDivider(isDark),
                                Expanded(
                                  child: _buildMetricItem(
                                    label: '上行记录',
                                    value: '${log.uploadCount ?? 0}',
                                    unit: '条',
                                    theme: theme,
                                  ),
                                ),
                                _buildMetricDivider(isDark),
                                Expanded(
                                  child: _buildMetricItem(
                                    label: '下行记录',
                                    value: '${log.downloadCount ?? 0}',
                                    unit: '条',
                                    theme: theme,
                                    highlightColor: (log.downloadCount ?? 0) > 0 ? theme.primaryColor : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 基本参数列表：优雅对齐与细致灰阶
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x1F242C35) : const Color(0x38FFFFFF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? const Color(0x14FFFFFF) : const Color(0x33FFFFFF),
                                width: 0.6,
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildDetailRow('记录 ID', log.id, theme),
                                if (log.dbVersion != null || log.sysDbVersion != null)
                                  _buildDetailRow('数据版本', '${log.dbVersion ?? 0}  /  ${log.sysDbVersion ?? 0}', theme),
                                if (log.appVersion != null)
                                  _buildDetailRow('App 版本', log.appVersion!, theme),
                                if (log.userId != null)
                                  _buildDetailRow('用户 ID', log.userId!, theme),
                                if (log.endTime != null)
                                  _buildDetailRow('结束时间', _formatDateTime(log.endTime!), theme, isLast: true),
                              ],
                            ),
                          ),

                          // 上行详情
                          if (log.uploadDetails != null && log.uploadDetails!.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _buildSectionHeader('上行同步实体', log.uploadDetails!.length, theme),
                            const SizedBox(height: 8),
                            _buildDetailsMapCard(log.uploadDetails!, theme, isDark),
                          ],

                          // 下行详情
                          if (log.downloadDetails != null && log.downloadDetails!.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _buildSectionHeader('下行同步实体', log.downloadDetails!.length, theme),
                            const SizedBox(height: 8),
                            _buildDetailsMapCard(log.downloadDetails!, theme, isDark),
                          ],

                          // 错误信息
                          if (log.errorMessage != null) ...[
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFEF4444)),
                                const SizedBox(width: 5),
                                Text(
                                  '异常中断信息',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.12 : 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.25 : 0.18),
                                  width: 0.8,
                                ),
                              ),
                              child: SelectableText(
                                log.errorMessage!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // 底部轻量幽灵删除按钮（极简克制，告别刺眼红色药丸）
                          Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(bottomSheetContext);
                                  _deleteLog(log.id);
                                },
                                borderRadius: BorderRadius.circular(100),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.12 : 0.06),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(
                                      color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.22 : 0.14),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.delete_outline_rounded, size: 14.5, color: Color(0xFFEF4444)),
                                      SizedBox(width: 5),
                                      Text(
                                        '删除此条记录',
                                        style: TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required String unit,
    required AppThemeConfig theme,
    Color? highlightColor,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
                letterSpacing: -0.3,
                color: highlightColor ?? theme.textPrimary,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.textMuted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: theme.textSecondary.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricDivider(bool isDark) {
    return Container(
      width: 0.8,
      height: 24,
      color: isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
    );
  }

  Widget _buildSectionHeader(String title, int count, AppThemeConfig theme) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count 个表',
          style: TextStyle(
            fontSize: 11.5,
            fontFamily: 'Roboto',
            color: theme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, AppThemeConfig theme, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(top: 5, bottom: isLast ? 2 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: theme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w500,
                color: theme.textPrimary,
                height: 1.35,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x1C242C35) : const Color(0x38FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0x14FFFFFF) : const Color(0x33FFFFFF),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details.entries.map((e) {
          final tableMap = e.value as Map<String, dynamic>;
          final ops = tableMap.entries.map((op) => '${op.key.toUpperCase()}: ${op.value}').join(' · ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  e.key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                    color: theme.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: isDark ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ops,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                      color: theme.primaryColor,
                    ),
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
                          const SizedBox(height: 14),
                          // 立即同步按钮（最新美学：薄雾微光底 + 精细描边 + 主题色文字与图标）
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isSyncing ? null : _manualSync,
                              borderRadius: BorderRadius.circular(100),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 40,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: theme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.08),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: theme.primaryColor.withValues(alpha: isDark ? 0.35 : 0.22),
                                    width: 0.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.primaryColor.withValues(alpha: isDark ? 0.15 : 0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isSyncing) ...[
                                      SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.8,
                                          valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ] else ...[
                                      Icon(
                                        Icons.sync_rounded,
                                        size: 17,
                                        color: theme.primaryColor,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      _isSyncing ? '正在同步中...' : '立即同步',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: theme.primaryColor,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
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
