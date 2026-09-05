import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

/// 优先取词的业务规则说明弹窗（纯净大白话极简版）
class PrivilegedDictExplanationDialog extends StatelessWidget {
  const PrivilegedDictExplanationDialog({super.key});

  /// 快捷调起弹窗的静态方法
  static Future<void> show(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.50 : 0.28),
      builder: (context) => const PrivilegedDictExplanationDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final darkMode = context.watch<DarkMode>();
    final isDarkMode = darkMode.isDarkMode;
    final themeConfig = AppThemeConfig.of(darkMode.themeStyle);
    final primaryColor = themeConfig.primaryColor;
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDarkMode ? Colors.white.withValues(alpha: 0.60) : const Color(0xFF64748B);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode
                    ? [
                        const Color(0xFF1E2433).withValues(alpha: 0.96),
                        const Color(0xFF131824).withValues(alpha: 0.94),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.98),
                        const Color(0xFFF9FAFB).withValues(alpha: 0.96),
                      ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.90),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 顶部标题栏
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: isDarkMode ? 0.20 : 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.star_rounded, size: 17, color: primaryColor),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '什么是「优先取词」？',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: subtitleColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. 规则一：每天优先学它
                _buildCleanPoint(
                  icon: Icons.filter_1_rounded,
                  title: '每天优先学它',
                  desc: '多本词书并存时，系统每天的新词全先从这本词书抽取，帮你集中精力逐本攻克。',
                  titleColor: titleColor,
                  subtitleColor: subtitleColor,
                  primaryColor: primaryColor,
                  isDarkMode: isDarkMode,
                ),
                const SizedBox(height: 16),

                // 3. 规则二：学完无缝衔接
                _buildCleanPoint(
                  icon: Icons.sync_rounded,
                  title: '学完无缝衔接',
                  desc: '当这本词书学完或没有新词时，会自动学习其他词书，每天的背词计划不中断。',
                  titleColor: titleColor,
                  subtitleColor: subtitleColor,
                  primaryColor: primaryColor,
                  isDarkMode: isDarkMode,
                ),
                const SizedBox(height: 22),

                // 4. 柔和优雅的胶囊确认按钮
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: primaryColor.withValues(alpha: isDarkMode ? 0.20 : 0.10),
                      foregroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      '我知道了',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCleanPoint({
    required IconData icon,
    required String title,
    required String desc,
    required Color titleColor,
    required Color subtitleColor,
    required Color primaryColor,
    required bool isDarkMode,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: isDarkMode ? 0.18 : 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: primaryColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.48,
                  color: subtitleColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
