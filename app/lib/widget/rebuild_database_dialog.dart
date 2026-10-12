import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// 备份云端 → 清空本地数据 → 重建本地库 的完整流程。
///
/// 用户确认后才执行；返回 true 表示本地数据已清空，调用方据此回登录页重新登录。
/// 抽成公共弹窗，是因为学习页、单词详情页遇到本地数据缺失时也要给这条出路。
Future<bool> showRebuildDatabaseDialog(BuildContext context) async {
  final isDarkModeEnabled = context.read<DarkMode>().isDarkMode;
  final textColor = isDarkModeEnabled ? Colors.white : Colors.black87;
  final subtitleColor = isDarkModeEnabled ? Colors.white60 : Colors.black54;
  const warningAmber = Color(0xFFF59E0B);

  bool? choice = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'dismiss_wipe_data',
    barrierColor: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.45 : 0.22),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, anim1, anim2, child) {
      return ScaleTransition(
        scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
        child: child,
      );
    },
    pageBuilder: (dialogCtx, anim1, anim2) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDarkModeEnabled
                        ? [
                            const Color(0xB8161B26),
                            const Color(0x9910141D),
                          ]
                        : [
                            const Color(0x66FFFFFF),
                            const Color(0x4DFFFFFF),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDarkModeEnabled ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.35 : 0.08),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 标题栏
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: warningAmber.withValues(alpha: isDarkModeEnabled ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: warningAmber.withValues(alpha: isDarkModeEnabled ? 0.35 : 0.20),
                              width: 0.8,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.cleaning_services_outlined,
                            color: warningAmber,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '确认重建数据库',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: textColor,
                                  fontFamily: 'NotoSansSC',
                                  fontFamilyFallback: AppTheme.sansSerifFallback,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '备份云端并重构本地缓存',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: subtitleColor.withValues(alpha: 0.75),
                                  fontFamily: 'NotoSansSC',
                                  fontFamilyFallback: AppTheme.sansSerifFallback,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(dialogCtx, false),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isDarkModeEnabled
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.45),
                              border: Border.all(
                                color: isDarkModeEnabled ? Colors.white12 : const Color(0x66FFFFFF),
                                width: 0.8,
                              ),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: subtitleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 提示文案轻量卡片
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: warningAmber.withValues(alpha: isDarkModeEnabled ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: warningAmber.withValues(alpha: isDarkModeEnabled ? 0.25 : 0.18),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '此操作将清除所有本地数据（服务端数据不受影响）。系统将在清除前自动备份数据到云端，并实时展示进度。',
                        style: TextStyle(
                          color: isDarkModeEnabled ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                          fontSize: 12.5,
                          height: 1.45,
                          fontFamily: 'NotoSansSC',
                          fontFamilyFallback: AppTheme.sansSerifFallback,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 底部按钮
                    Row(
                      children: [
                        Expanded(
                          child: _dialogButton(dialogCtx,
                            text: '取消',
                            onPressed: () => Navigator.pop(dialogCtx, false),
                            isPrimary: false,
                            isDarkMode: isDarkModeEnabled,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dialogButton(dialogCtx,
                            text: '继续重建',
                            primaryColor: warningAmber,
                            onPressed: () => Navigator.pop(dialogCtx, true),
                            isPrimary: true,
                            isDarkMode: isDarkModeEnabled,
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
  );

  if (choice != true) return false;
  // 确认弹窗停留期间页面可能已经退出，此时不能再弹进度窗
  if (!context.mounted) return false;

  // 显示进度弹窗，并在该弹窗内完成同步和清空
  final finished = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _RebuildDatabaseProgressDialog(),
  );

  return finished == true;
}

/// 弹窗底部按钮（与「我的」页里的对话框按钮同一套观感）。
Widget _dialogButton(
  BuildContext context, {
  required String text,
  required VoidCallback onPressed,
  required bool isPrimary,
  required bool isDarkMode,
  Color? primaryColor,
}) {
  final effectivePrimary = primaryColor ?? context.primaryColor;
  return SizedBox(
    height: 42,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary
            ? effectivePrimary.withValues(alpha: isDarkMode ? 0.28 : 0.16)
            : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.45)),
        foregroundColor: isPrimary ? effectivePrimary : (isDarkMode ? Colors.white70 : Colors.black87),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.center,
        side: BorderSide(
          color: isPrimary
              ? effectivePrimary.withValues(alpha: isDarkMode ? 0.45 : 0.30)
              : (isDarkMode ? Colors.white12 : const Color(0x80FFFFFF)),
          width: 0.8,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w500,
          color: isPrimary ? effectivePrimary : (isDarkMode ? Colors.white70 : Colors.black87),
          letterSpacing: 0.2,
          height: 1.2,
          leadingDistribution: TextLeadingDistribution.even,
          fontFamily: 'NotoSansSC',
          fontFamilyFallback: AppTheme.sansSerifFallback,
        ),
      ),
    ),
  );
}

class _RebuildDatabaseProgressDialog extends StatefulWidget {
  const _RebuildDatabaseProgressDialog();

  @override
  State<_RebuildDatabaseProgressDialog> createState() => _RebuildDatabaseProgressDialogState();
}

enum _StepStatus { pending, processing, completed, error }

class _RebuildDatabaseProgressDialogState extends State<_RebuildDatabaseProgressDialog> {
  _StepStatus _syncStatus = _StepStatus.processing;
  _StepStatus _wipeStatus = _StepStatus.pending;
  String? _error;

  @override
  void initState() {
    super.initState();
    _executeProcess();
  }

  Future<void> _executeProcess() async {
    // 步骤1: 同步备份
    try {
      await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
      if (mounted) {
        setState(() {
          _syncStatus = _StepStatus.completed;
          _wipeStatus = _StepStatus.processing;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = _StepStatus.error;
          _error = '备份失败: $e';
        });
      }
      return; 
    }

    // 步骤2: 清空数据
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      await MyDatabase.instance.wipeAllTables();
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.error;
          _error = '清空失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor = isDarkMode ? Colors.white60 : Colors.black54;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          const Color(0xB8161B26),
                          const Color(0x9910141D),
                        ]
                      : [
                          const Color(0x66FFFFFF),
                          const Color(0x4DFFFFFF),
                        ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDarkMode ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 标题区域
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: isDarkMode ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: isDarkMode ? 0.35 : 0.20),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.sync_rounded,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '正在重建数据库',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                fontFamily: 'NotoSansSC',
                                fontFamilyFallback: AppTheme.sansSerifFallback,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '同步云端并重置本地数据',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: subtitleColor.withValues(alpha: 0.75),
                                fontFamily: 'NotoSansSC',
                                fontFamilyFallback: AppTheme.sansSerifFallback,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 步骤展示卡片
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.40),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDarkMode ? Colors.white12 : const Color(0x66FFFFFF),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildStepRow('1. 备份数据到云端', _syncStatus, isDarkMode, subtitleColor, textColor),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        _buildStepRow('2. 清空本地数据', _wipeStatus, isDarkMode, subtitleColor, textColor),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: isDarkMode ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.25), width: 0.8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                height: 1.4,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),

                  if (_syncStatus == _StepStatus.error) ...[
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.45),
                                foregroundColor: isDarkMode ? Colors.white70 : Colors.black87,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                side: BorderSide(
                                  color: isDarkMode ? Colors.white12 : const Color(0x80FFFFFF),
                                  width: 0.8,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
                              ),
                              child: const Text(
                                '取消',
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, fontFamily: 'NotoSansSC'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _syncStatus = _StepStatus.completed;
                                  _wipeStatus = _StepStatus.processing;
                                  _error = null;
                                });
                                _executeWipeOnly();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444).withValues(alpha: isDarkMode ? 0.28 : 0.16),
                                foregroundColor: const Color(0xFFEF4444),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                side: BorderSide(
                                  color: const Color(0xFFEF4444).withValues(alpha: isDarkMode ? 0.45 : 0.30),
                                  width: 0.8,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
                              ),
                              child: const Text(
                                '忽略并清空',
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_wipeStatus == _StepStatus.completed || _wipeStatus == _StepStatus.error) ...[
                    SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, _wipeStatus == _StepStatus.completed),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981).withValues(alpha: isDarkMode ? 0.28 : 0.16),
                          foregroundColor: const Color(0xFF10B981),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          side: BorderSide(
                            color: const Color(0xFF10B981).withValues(alpha: isDarkMode ? 0.45 : 0.30),
                            width: 0.8,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
                        ),
                        child: const Text(
                          '完成',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executeWipeOnly() async {
    try {
      await MyDatabase.instance.wipeAllTables();
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.error;
          _error = '清空失败: $e';
        });
      }
    }
  }

  Widget _buildStepRow(String label, _StepStatus status, bool isDarkMode, Color subtitleColor, Color textColor) {
    Widget statusIcon;
    Color rowColor = subtitleColor;
    FontWeight fontWeight = FontWeight.normal;

    switch (status) {
      case _StepStatus.pending:
        statusIcon = Icon(Icons.circle_outlined, color: subtitleColor.withValues(alpha: 0.3), size: 20);
        break;
      case _StepStatus.processing:
        rowColor = textColor;
        fontWeight = FontWeight.normal;
        statusIcon = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6))),
        );
        break;
      case _StepStatus.completed:
        rowColor = const Color(0xFF10B981);
        fontWeight = FontWeight.normal;
        statusIcon = const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20);
        break;
      case _StepStatus.error:
        rowColor = const Color(0xFFEF4444);
        fontWeight = FontWeight.normal;
        statusIcon = const Icon(Icons.error_rounded, color: Color(0xFFEF4444), size: 20);
        break;
    }

    return Row(
      children: [
        statusIcon,
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: rowColor,
            fontSize: 16,
            fontWeight: fontWeight,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ],
    );
  }
}
