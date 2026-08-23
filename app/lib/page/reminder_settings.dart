import 'package:flutter/material.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/notification_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> with WidgetsBindingObserver {
  late bool _enabled;
  late TimeOfDay _time;
  bool _hasPermission = true;
  bool _isCheckingPermission = false;
  bool _isSendingTest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enabled = NotificationUtil.isReminderEnabled();
    _time = NotificationUtil.getReminderTime();
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    if (_isCheckingPermission) return;
    _isCheckingPermission = true;
    try {
      final status = await Permission.notification.status;
      if (mounted) {
        setState(() {
          _hasPermission = status.isGranted || status.isLimited || status.isProvisional;
        });
      }
    } catch (e) {
      Global.logger.w('检查通知权限失败: $e');
    } finally {
      _isCheckingPermission = false;
    }
  }

  Future<void> _saveSettings({bool? newEnabled, TimeOfDay? newTime}) async {
    final targetEnabled = newEnabled ?? _enabled;
    final targetTime = newTime ?? _time;

    setState(() {
      _enabled = targetEnabled;
      _time = targetTime;
    });

    await NotificationUtil.updateReminderSettings(
      enabled: targetEnabled,
      hour: targetTime.hour,
      minute: targetTime.minute,
    );

    if (mounted) {
      ToastUtil.success(targetEnabled ? '学习提醒已更新' : '学习提醒已关闭');
    }
  }

  Future<void> _pickTime() async {
    if (!_enabled) return;

    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (BuildContext context, Widget? child) {
        final isDarkMode = context.read<DarkMode>().isDarkMode;
        return Theme(
          data: isDarkMode
              ? ThemeData.dark().copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: AppTheme.primaryColor,
                    onPrimary: Colors.white,
                    surface: const Color(0xFF1E293B),
                    onSurface: Colors.white,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: ColorScheme.light(
                    primary: AppTheme.primaryColor,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: const Color(0xFF1E293B),
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null && (picked.hour != _time.hour || picked.minute != _time.minute)) {
      await _saveSettings(newTime: picked);
    }
  }

  Future<void> _sendTestNotification() async {
    if (_isSendingTest) return;
    setState(() => _isSendingTest = true);

    try {
      final status = await Permission.notification.status;
      if (!status.isGranted && !status.isLimited && !status.isProvisional) {
        final req = await Permission.notification.request();
        if (!req.isGranted && !req.isLimited && !req.isProvisional) {
          if (mounted) {
            ToastUtil.error('未获得通知权限，请在系统设置中允许通知');
          }
          return;
        }
      }

      await NotificationUtil.showTestNotification();
      if (mounted) {
        ToastUtil.success('测试通知已发出，请查看通知栏');
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.error('发送测试通知失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingTest = false);
      }
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final cardColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '学习提醒设置',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'NotoSansSC',
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 权限缺失提示卡片
          if (!_hasPermission) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '通知权限已关闭',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber,
                            fontFamily: 'NotoSansSC',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '系统通知已被禁用，开启后才能准时接收每日学习提醒。',
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor,
                            fontFamily: 'NotoSansSC',
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => openAppSettings(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      backgroundColor: Colors.amber.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      '去开启',
                      style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 核心设置卡片
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // 开启/关闭提醒
                  SwitchListTile.adaptive(
                    value: _enabled,
                    activeTrackColor: AppTheme.primaryColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    title: Text(
                      '每日学习提醒',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    subtitle: Text(
                      '每天定时提醒，保持连续打卡好习惯',
                      style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    onChanged: (val) => _saveSettings(newEnabled: val),
                  ),
                  Divider(height: 1, thickness: 0.5, color: borderColor),
                  // 提醒时间选择
                  InkWell(
                    onTap: _enabled ? _pickTime : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '提醒时间',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: _enabled ? textColor : subtitleColor.withValues(alpha: 0.5),
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _enabled ? '将在每天此时发送提醒通知' : '已关闭提醒',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: subtitleColor.withValues(alpha: _enabled ? 1.0 : 0.5),
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _enabled
                                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                  : (isDarkMode ? Colors.white10 : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _formatTimeOfDay(_time),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _enabled ? AppTheme.primaryColor : subtitleColor,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: _enabled ? AppTheme.primaryColor : subtitleColor,
                                ),
                              ],
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

          const SizedBox(height: 20),

          // 测试通知卡片
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _sendTestNotification,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: AppTheme.primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '发送测试通知',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '测试通知是否能够正常在您的设备上弹出',
                              style: TextStyle(
                                fontSize: 12,
                                color: subtitleColor,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isSendingTest
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 贴心防打扰机制说明
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: subtitleColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '智能防打扰：如果您在当天已经完成了打卡学习，系统将自动将提醒顺延到次日，绝不在您学完后打扰您。',
                    style: TextStyle(
                      fontSize: 12,
                      color: subtitleColor,
                      height: 1.5,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
