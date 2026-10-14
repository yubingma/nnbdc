import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme/app_theme.dart';
import '../util/study_config.dart';

/// 释义展示偏好弹框：选择通用词典的释义最多显示几条。
///
/// 只约束通用词典释义；在学词书里的定制释义永远全部展示，不受本设置影响。
/// 遵循局部毛玻璃规范（flutter-frosted-glass）：ScaleTransition 转场，模糊半径取 7。
class MeaningDisplayDialog extends StatefulWidget {
  const MeaningDisplayDialog({super.key});

  /// 弹出对话框，返回选中的条数上限（0 表示全部显示）；未切换或取消时返回 null
  static Future<int?> show(BuildContext context) {
    final isDark = context.read<DarkMode>().isDarkMode;
    return showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss_meaning_display',
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogCtx, anim1, anim2) => const MeaningDisplayDialog(),
      transitionBuilder: (context, anim1, anim2, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
  }

  @override
  State<MeaningDisplayDialog> createState() => _MeaningDisplayDialogState();
}

class _MeaningDisplayDialogState extends State<MeaningDisplayDialog> {
  late int _currentLimit;

  /// 由宽到严排列；0 表示全部显示，也是默认档
  static const List<({int limit, String title, String subtitle})> _options = [
    (limit: 0, title: '全部显示', subtitle: '通用词典的释义全部展示'),
    (limit: 5, title: '最多 5 条', subtitle: '95% 的单词释义不超过 5 条，多义词只给最常用的 5 条'),
    (limit: 3, title: '最多 3 条', subtitle: '只保留最常用的 3 条释义'),
    (limit: 1, title: '只看最常用 1 条', subtitle: '每张卡片只留一个最常用的释义，适合快速过词'),
  ];

  @override
  void initState() {
    super.initState();
    _currentLimit = StudyConfig.fromCurrentUser().meaningDisplayLimit;
  }

  Future<void> _select(int limit) async {
    if (_currentLimit != limit) {
      setState(() => _currentLimit = limit);
      final config = StudyConfig.fromCurrentUser();
      config.meaningDisplayLimit = limit;
      await config.saveToCurrentUser();
      if (mounted) Navigator.pop(context, limit);
    } else {
      Navigator.pop(context, limit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkMode = context.watch<DarkMode>();
    final selectedStyle = darkMode.themeStyle;
    final themeConfig = AppThemeConfig.of(selectedStyle);
    final isDark = selectedStyle.isDark || darkMode.isDarkMode;

    final primaryColor = themeConfig.primaryColor;
    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xB8161B26), const Color(0x9910141D)]
                      : [const Color(0x66FFFFFF), const Color(0x4DFFFFFF)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: isDark ? 0.35 : 0.20),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.format_list_bulleted_rounded, color: primaryColor, size: 19),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '释义展示',
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
                              '通用词典的释义最多显示几条',
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
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.45),
                            border: Border.all(
                              color: isDark ? Colors.white12 : const Color(0x66FFFFFF),
                              width: 0.8,
                            ),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.close_rounded, size: 16, color: subtitleColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final option in _options) ...[
                    _buildOptionCard(
                      limit: option.limit,
                      title: option.title,
                      subtitle: option.subtitle,
                      isSelected: _currentLimit == option.limit,
                      primaryColor: primaryColor,
                      textColor: textColor,
                      subtitleColor: subtitleColor,
                      isDark: isDark,
                    ),
                    if (option != _options.last) const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '在学词书里的定制释义永远全部展示，不受这里限制',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: subtitleColor.withValues(alpha: 0.7),
                      fontFamily: 'NotoSansSC',
                      fontFamilyFallback: AppTheme.sansSerifFallback,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor.withValues(alpha: isDark ? 0.25 : 0.15),
                        foregroundColor: primaryColor,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.center,
                        side: BorderSide(
                          color: primaryColor.withValues(alpha: isDark ? 0.40 : 0.25),
                          width: 1.0,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
                      ),
                      child: Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                          letterSpacing: 0.3,
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                          fontFamily: 'NotoSansSC',
                          fontFamilyFallback: AppTheme.sansSerifFallback,
                        ),
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

  Widget _buildOptionCard({
    required int limit,
    required String title,
    required String subtitle,
    required bool isSelected,
    required Color primaryColor,
    required Color textColor,
    required Color subtitleColor,
    required bool isDark,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _select(limit),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: isDark ? 0.24 : 0.14)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0x80FFFFFF)),
            width: isSelected ? 1.5 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primaryColor.withValues(alpha: 0.16) : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.5)
                      : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                limit == 0 ? '∞' : '$limit',
                style: TextStyle(
                  fontSize: limit == 0 ? 16 : 15,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? primaryColor : subtitleColor,
                  fontFamily: 'NotoSansSC',
                  fontFamilyFallback: AppTheme.sansSerifFallback,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? primaryColor : textColor,
                          fontFamily: 'NotoSansSC',
                          fontFamilyFallback: AppTheme.sansSerifFallback,
                        ),
                      ),
                      if (limit == 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '默认',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                              fontFamily: 'NotoSansSC',
                              fontFamilyFallback: AppTheme.sansSerifFallback,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primaryColor : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.white38 : const Color(0xFFCBD5E1)),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
