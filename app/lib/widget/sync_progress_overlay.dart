import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nnbdc/services/sync_progress.dart';

/// 首屏端云同步的醒目标识：全屏遮罩 + 不透明卡片 + 实时数字。
///
/// 之前首屏只有一个细转圈和一行小字，首页铺了壁纸后几乎看不见；
/// 云端日志很多、同步要十几分钟时，用户会以为卡死并反复重启。
/// 这里用遮罩压暗壁纸，卡片里持续显示：
/// - 本次已下载的字节数（累计，只增不减）
/// - 当前阶段已处理条数 / 总条数
/// - 当前阶段、已用时、多少秒前有进展（用来区分"慢"和"真卡住"）
class SyncProgressOverlay extends StatefulWidget {
  const SyncProgressOverlay({
    super.key,
    required this.isDarkMode,
    required this.accentColor,
    required this.syncing,
  });

  final bool isDarkMode;
  final Color accentColor;

  /// true：正在等端云同步；false：同步已结束，正在准备今日计划。
  final bool syncing;

  @override
  State<SyncProgressOverlay> createState() => _SyncProgressOverlayState();
}

class _SyncProgressOverlayState extends State<SyncProgressOverlay> {
  late final Timer _ticker;
  DateTime _startedAt = DateTime.now();
  DateTime _lastAdvanceAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    syncProgress.addListener(_onProgressChanged);
    syncReceivedBytes.addListener(_onProgressChanged);
    // 每秒重绘一次「已用时 / 多少秒前有进展」；数字本身由 notifier 驱动。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SyncProgressOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.syncing && !oldWidget.syncing) {
      _startedAt = DateTime.now();
      _lastAdvanceAt = _startedAt;
    }
  }

  void _onProgressChanged() {
    if (!mounted) return;
    _lastAdvanceAt = DateTime.now();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.cancel();
    syncProgress.removeListener(_onProgressChanged);
    syncReceivedBytes.removeListener(_onProgressChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = widget.isDarkMode;
    final Color cardBg = isDark ? const Color(0xFF151A23) : const Color(0xFFF8FAFC);
    final Color textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final Color textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final Color lineColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Stack(
      children: [
        Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: isDark ? 0.72 : 0.50),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.22),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: widget.syncing
                              ? _buildSyncingContent(
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  lineColor: lineColor,
                                )
                              : _buildPreparingContent(
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  lineColor: lineColor,
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncingContent({
    required Color textPrimary,
    required Color textSecondary,
    required Color lineColor,
  }) {
    final SyncProgress progress = syncProgress.value;
    final int received = syncReceivedBytes.value;
    final bool hasBytes = received > 0;
    final bool hasCount = progress.hasTotal;
    final bool isUpload = progress.phase == 'UPLOADING CHANGES';
    final Duration elapsed = DateTime.now().difference(_startedAt);
    final Duration sinceAdvance = DateTime.now().difference(_lastAdvanceAt);
    final bool stalled = sinceAdvance.inSeconds >= 45;
    final String silence = sinceAdvance.inSeconds < 60
        ? '${sinceAdvance.inSeconds} 秒'
        : '${sinceAdvance.inMinutes} 分钟';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_sync_rounded, size: 20, color: widget.accentColor),
            const SizedBox(width: 8),
            Text(
              '端云同步',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: textSecondary,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '正在同步学习记录',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '正在和云端核对学习记录，记录较多时可能要几分钟。'
          '下面的数字还在变化，就说明同步没有卡住；请保持应用在前台，不要退出。',
          style: TextStyle(fontSize: 12, height: 1.6, color: textSecondary),
        ),
        const SizedBox(height: 20),
        Container(height: 0.5, color: lineColor),
        const SizedBox(height: 18),
        if (hasBytes) ...[
          Text(
            '本次已下载',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatBytes(received),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              fontFamily: 'Roboto',
              letterSpacing: -0.8,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          Text(
            '正在等待云端响应…',
            style: TextStyle(fontSize: 12.5, color: textSecondary),
          ),
          const SizedBox(height: 16),
        ],
        if (hasCount) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isUpload ? '已上传记录' : '已处理记录',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${_formatCount(progress.done)} / ${_formatCount(progress.total)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                        letterSpacing: -0.2,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildProgressLine(
            value: (progress.done / progress.total).clamp(0.0, 1.0),
            lineColor: lineColor,
          ),
        ] else
          _buildProgressLine(value: null, lineColor: lineColor),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _phaseLabel(progress.phase),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.accentColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '已用时 ${_formatElapsed(elapsed)}',
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          stalled
              ? '已 $silence没有新进展。如果超过 1 分钟仍没有变化，请检查网络后重试。'
              : '$silence前有进展',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.5,
            fontWeight: stalled ? FontWeight.w500 : FontWeight.w400,
            color: stalled
                ? (widget.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
                : textSecondary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildPreparingContent({
    required Color textPrimary,
    required Color textSecondary,
    required Color lineColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hourglass_top_rounded, size: 20, color: widget.accentColor),
            const SizedBox(width: 8),
            Text(
              '今日计划',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: textSecondary,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '正在准备今日计划',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '云端数据已就绪，正在生成本次学习计划，马上就好。',
          style: TextStyle(fontSize: 12, height: 1.6, color: textSecondary),
        ),
        const SizedBox(height: 22),
        _buildProgressLine(value: null, lineColor: lineColor),
      ],
    );
  }

  Widget _buildProgressLine({required double? value, required Color lineColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 3.5,
        backgroundColor: lineColor,
        valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
      ),
    );
  }

  /// 把同步内部阶段名翻译成用户看得懂的人话。
  String _phaseLabel(String phase) {
    switch (phase) {
      case 'CHECKING SYSTEM DATA':
        return '正在检查云端版本';
      case 'FETCHING SYSTEM DATA':
        return '正在下载系统数据';
      case 'WRITING SYSTEM DATA':
        return '正在准备系统数据';
      case 'FETCHING USER DATA':
        return '正在下载你的云端数据';
      case 'WRITING LOCAL DATA':
        return '正在把云端记录写入本机';
      case 'UPLOADING CHANGES':
        return '正在上传本机改动';
      default:
        return phase.isEmpty ? '正在连接云端' : '正在同步云端数据';
    }
  }

  String _formatElapsed(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds % 60;
    if (minutes >= 60) {
      return '${minutes ~/ 60} 小时 ${minutes % 60} 分';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final double kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final double mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  String _formatCount(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }
}
