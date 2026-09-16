import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/db.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../theme/font_scale.dart';

/// 字体大小选择弹框：小 / 中 / 大三档胶囊选择器。
///
/// 严格遵循 flutter-frosted-glass 规范：
/// 1. 局部高斯模糊（sigma: 14）+ 半透明磨砂质感；
/// 2. 转场采用 ScaleTransition，避开 OpacityLayer 阻断底层采样的渲染陷阱；
/// 3. 每档胶囊内的"字"字按该档系数实际渲染，所见即所得。
class FontScaleDialog extends StatelessWidget {
  const FontScaleDialog({super.key});

  /// 弹出字体大小选择毛玻璃弹框
  static Future<void> show(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss_font_scale',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return const FontScaleDialog();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final darkMode = context.watch<DarkMode>();
    final selectedStyle = darkMode.themeStyle;
    final themeConfig = AppThemeConfig.of(selectedStyle);
    final isDarkModeEnabled = selectedStyle.isDark || darkMode.isDarkMode;
    final textColor = themeConfig.textPrimary;
    final subtleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
                  color: isDarkModeEnabled
                      ? const Color(0x33FFFFFF)
                      : const Color(0x80FFFFFF),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 顶部标题与轻量关闭按钮
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: isDarkModeEnabled ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: accentColor.withValues(alpha: isDarkModeEnabled ? 0.35 : 0.20),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.format_size_rounded,
                          color: accentColor,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '字体大小',
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
                              '调节整体界面文字的阅读大小',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: subtleColor.withValues(alpha: 0.75),
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
                            color: subtleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 2. 三档胶囊选择器（凭自身字重与色彩高亮表达选中态，不加胶囊衬垫）
                  Row(
                    children: [
                      for (final scale in AppFontScale.values) ...[
                        if (scale != AppFontScale.values.first) const SizedBox(width: 10),
                        Expanded(
                          child: _buildScaleTile(
                            context: context,
                            scale: scale,
                            isSelected: darkMode.fontScale == scale,
                            accentColor: accentColor,
                            textColor: textColor,
                            subtleColor: subtleColor,
                            isDarkModeEnabled: isDarkModeEnabled,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 3. 底部温润长胶囊操作按钮
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor.withValues(alpha: isDarkModeEnabled ? 0.25 : 0.15),
                        foregroundColor: accentColor,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        alignment: Alignment.center,
                        side: BorderSide(
                          color: accentColor.withValues(alpha: isDarkModeEnabled ? 0.40 : 0.25),
                          width: 1.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(21),
                        ),
                      ),
                      child: Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
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

  Widget _buildScaleTile({
    required BuildContext context,
    required AppFontScale scale,
    required bool isSelected,
    required Color accentColor,
    required Color textColor,
    required Color subtleColor,
    required bool isDarkModeEnabled,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        context.read<DarkMode>().setFontScale(scale);
        MyDatabase.instance.localParamsDao.saveFontScale(scale);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 52,
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: isDarkModeEnabled ? 0.24 : 0.08)
              : (isDarkModeEnabled
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accentColor
                : (isDarkModeEnabled ? Colors.white.withValues(alpha: 0.10) : const Color(0x80FFFFFF)),
            width: isSelected ? 1.5 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        // 用该档系数实际渲染示例文字，让用户直观预览效果
        child: Text(
          scale.label,
          textScaler: TextScaler.linear(scale.factor),
          style: TextStyle(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? accentColor : subtleColor.withValues(alpha: 0.85),
            fontFamily: 'NotoSansSC',
            fontFamilyFallback: AppTheme.sansSerifFallback,
          ),
        ),
      ),
    );
  }
}
