import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/db.dart';
import '../state.dart';
import '../theme/app_theme.dart';

/// 主题选择弹框：极简现代毛玻璃（Frosted Glass）风格。
///
/// 严格遵循 flutter-frosted-glass 规范：
/// 1. 局部高斯模糊（sigma: 18）+ 半透明磨砂质感；
/// 2. 移除粗重实心顶条，采用纯净一体化排版；
/// 3. 转场采用 ScaleTransition，避开 OpacityLayer 阻断底层采样的渲染陷阱；
/// 4. 底部统一温润半透主题色胶囊主按钮。
class ThemeSelectDialog extends StatelessWidget {
  const ThemeSelectDialog({super.key});

  /// 弹出主题选择毛玻璃弹框
  static Future<void> show(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss_theme_select',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return const ThemeSelectDialog();
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
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
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
                            Icons.palette_outlined,
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
                                '外观主题',
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
                                '选择契合当前心境的色彩风格',
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
                                color: isDarkModeEnabled
                                    ? Colors.white12
                                    : const Color(0x66FFFFFF),
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

                    // 2. 9 个主题网格选择器
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.12,
                      ),
                      itemCount: AppThemeStyle.values.length,
                      itemBuilder: (context, index) {
                        final style = AppThemeStyle.values[index];
                        final cfg = AppThemeConfig.of(style);
                        final isSelected = selectedStyle == style;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            context.read<DarkMode>().setThemeStyle(style);
                            MyDatabase.instance.localParamsDao.saveThemeStyle(style);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cfg.primaryColor.withValues(alpha: isDarkModeEnabled ? 0.24 : 0.14)
                                  : (isDarkModeEnabled
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.white.withValues(alpha: 0.30)),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? cfg.primaryColor
                                    : (isDarkModeEnabled
                                        ? Colors.white.withValues(alpha: 0.10)
                                        : const Color(0x80FFFFFF)),
                                width: isSelected ? 1.5 : 0.8,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: cfg.primaryColor.withValues(alpha: 0.20),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  style.icon,
                                  size: 22,
                                  color: isSelected ? cfg.primaryColor : subtleColor.withValues(alpha: 0.7),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  style.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? cfg.primaryColor : textColor,
                                    fontFamily: 'NotoSansSC',
                                    fontFamilyFallback: AppTheme.sansSerifFallback,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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
      ),
    );
  }
}