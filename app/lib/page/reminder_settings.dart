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
      // 自定义主题化的时间选择弹窗（唯美圆角 + 主题色拨盘指针 + 柔和选中值），
      // 让系统自绘的 Material TimePickerDialog 贴合 App 的整体极简美学。
      builder: (BuildContext context, Widget? child) {
        final themeStyle = context.read<DarkMode>().themeStyle;
        final accent = AppThemeConfig.of(themeStyle).primaryColor;
        final isDark = themeStyle.isDark;

        final scheme = ColorScheme.fromSeed(
          seedColor: accent,
          brightness: isDark ? Brightness.dark : Brightness.light,
        ).copyWith(primary: accent, secondary: accent);

        final pickerTheme = TimePickerThemeData(
          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFFCFDFF),
          elevation: 16,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          // 选中数值（小时/分钟）柔和主题色高亮
          hourMinuteColor: accent.withValues(alpha: isDark ? 0.28 : 0.16),
          hourMinuteTextColor: accent,
          hourMinuteTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC', letterSpacing: -0.2),
          hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          // 冒号分隔符
          timeSelectorSeparatorTextStyle: WidgetStatePropertyAll(
            TextStyle(color: accent.withValues(alpha: 0.6), fontWeight: FontWeight.w700, fontFamily: 'Roboto'),
          ),
          // 拨盘
          dialBackgroundColor: isDark ? const Color(0xFF27303F) : const Color(0xFFF1F5F9),
          dialHandColor: accent,
          dialTextColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          // 上下午（AM/PM）切换
          dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          dayPeriodTextColor: accent,
          dayPeriodTextStyle: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'NotoSansSC'),
          // 顶部说明 & 键盘切换图标
          helpTextStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            fontFamily: 'NotoSansSC',
          ),
          entryModeIconColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          // 底部操作按钮
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'NotoSansSC'),
          ),
          confirmButtonStyle: TextButton.styleFrom(
            foregroundColor: accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC'),
          ),
        );

        return Theme(
          data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
            colorScheme: scheme,
            timePickerTheme: pickerTheme,
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
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final isDarkMode = themeStyle.isDark;

    final accentColor = context.primaryColor;
    final textColor = context.textPrimary;
    final subtitleColor = context.textSecondary;
    final mutedColor = context.textMuted;
    final cardBg = context.cardBg;
    final cardShadow = context.cardShadows;
    final cardBorder = context.cardBorder;
    final warningAmber = const Color(0xFFF5A623);

    // 统一样式：是否使用主题自带描边；弱主题在浅色时用透明描边靠磨砂阴影撑起卡片
    final border = cardBorder == Colors.transparent
        ? (isDarkMode ? Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8) : null)
        : Border.all(color: cardBorder, width: 0.8);

    return AppScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '学习提醒设置',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFamily: 'NotoSansSC',
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 权限缺失提示（柔和琥珀提醒，避免生硬警告感）
          if (!_hasPermission) ...[
            _buildPermissionBanner(isDarkMode: isDarkMode, subtitleColor: subtitleColor, warningAmber: warningAmber),
            const SizedBox(height: 14),
          ],

          // 核心设置卡片（一体成型，行间发丝分割线）
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: cardShadow,
              border: border,
            ),
            child: Column(
              children: [
                _buildToggleRow(accentColor: accentColor, textColor: textColor, subtitleColor: subtitleColor),
                _hairline(isDarkMode: isDarkMode),
                _buildTimeRow(
                  accentColor: accentColor,
                  textColor: textColor,
                  subtitleColor: subtitleColor,
                  mutedColor: mutedColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 发送测试通知（独立行动卡片）
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: cardShadow,
              border: border,
            ),
            child: _buildTestRow(
              accentColor: accentColor,
              textColor: textColor,
              subtitleColor: subtitleColor,
              mutedColor: mutedColor,
            ),
          ),

          const SizedBox(height: 16),

          // 智能防打扰说明（轻量脚注）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: mutedColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '智能防打扰：如果您在当天已经完成了打卡学习，系统将自动将提醒顺延到次日，绝不在您学完后打扰您。',
                    style: TextStyle(
                      fontSize: 12,
                      color: mutedColor,
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

  Widget _hairline({required bool isDarkMode}) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 14),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.055),
      ),
    );
  }

  Widget _buildPermissionBanner({
    required bool isDarkMode,
    required Color subtitleColor,
    required Color warningAmber,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warningAmber.withValues(alpha: isDarkMode ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warningAmber.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: warningAmber, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '通知权限已关闭',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    color: isDarkMode ? const Color(0xFFFCD34D) : warningAmber,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '开启后才能准时接收每日学习提醒。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: subtitleColor,
                    height: 1.4,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: openAppSettings,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '去开启',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? const Color(0xFFFCD34D) : warningAmber,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 15, color: isDarkMode ? const Color(0xFFFCD34D) : warningAmber),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required Color accentColor,
    required Color textColor,
    required Color subtitleColor,
  }) {
    return SwitchListTile.adaptive(
      value: _enabled,
      activeTrackColor: accentColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      title: Text(
        '每日学习提醒',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: textColor,
          fontFamily: 'NotoSansSC',
        ),
      ),
      subtitle: Text(
        '每天定时提醒，保持连续打卡好习惯',
        style: TextStyle(
          fontSize: 12.5,
          color: subtitleColor,
          height: 1.4,
          fontFamily: 'NotoSansSC',
        ),
      ),
      onChanged: (val) => _saveSettings(newEnabled: val),
    );
  }

  Widget _buildTimeRow({
    required Color accentColor,
    required Color textColor,
    required Color subtitleColor,
    required Color mutedColor,
  }) {
    final active = _enabled;
    final titleColor = active ? textColor : subtitleColor.withValues(alpha: 0.5);
    final valueColor = active ? accentColor : mutedColor;

    return InkWell(
      onTap: active ? _pickTime : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '提醒时间',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: titleColor,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active ? '将在每天此时发送提醒通知' : '已关闭提醒',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: subtitleColor.withValues(alpha: active ? 1.0 : 0.5),
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimeOfDay(_time),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: valueColor,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 18, color: valueColor.withValues(alpha: 0.7)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestRow({
    required Color accentColor,
    required Color textColor,
    required Color subtitleColor,
    required Color mutedColor,
  }) {
    return InkWell(
      onTap: _sendTestNotification,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.notifications_active_rounded, color: accentColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '发送测试通知',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: textColor,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '测试通知能否在您的设备上正常弹出',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: subtitleColor,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_isSendingTest)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 20, color: mutedColor),
          ],
        ),
      ),
    );
  }
}
