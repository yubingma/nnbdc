import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/db.dart';
import '../state.dart';
import '../theme/app_theme.dart';

/// 主题选择弹框：展示全部 [AppThemeStyle] 供用户选择。
///
/// 窄屏设备上内嵌横排主题卡片会使主题名称显示不全，因此统一使用弹框承载。
/// 视觉强调色跟随当前主题，切换时实时生效。
class ThemeSelectDialog extends StatelessWidget {
  const ThemeSelectDialog({super.key});

  /// 弹出主题选择弹框
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ThemeSelectDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(selectedStyle);
    final isDarkModeEnabled = selectedStyle.isDark;
    final textColor = themeConfig.textPrimary;
    final subtleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: isDarkModeEnabled ? 0.18 : 0.1),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.palette_outlined, color: accentColor, size: 22),
            const SizedBox(width: 8),
            Text(
              '外观主题',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
      ),
      content: Row(
        children: AppThemeStyle.values.map((style) {
          final cfg = AppThemeConfig.of(style);
          final isSelected = selectedStyle == style;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                context.read<DarkMode>().setThemeStyle(style);
                MyDatabase.instance.localParamsDao.saveThemeStyle(style);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cfg.primaryColor.withValues(alpha: isDarkModeEnabled ? 0.22 : 0.12)
                      : (isDarkModeEnabled
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFF8FAF9)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? cfg.primaryColor
                        : (isDarkModeEnabled ? Colors.white12 : const Color(0xFFE2ECE8)),
                    width: isSelected ? 1.6 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      style.icon,
                      size: 20,
                      color: isSelected ? cfg.primaryColor : subtleColor,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      style.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? cfg.primaryColor : textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '完成',
            style: TextStyle(
              color: accentColor,
              fontFamily: 'NotoSansSC',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}