import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/level_util.dart';

/// 段位晋升仪式感弹窗
class LevelUpDialog extends StatelessWidget {
  final Level level;
  final int rewardBubbles;
  final VoidCallback? onViewPath;

  const LevelUpDialog({
    super.key,
    required this.level,
    this.rewardBubbles = 0,
    this.onViewPath,
  });

  static Future<void> show(
    BuildContext? context, {
    required Level level,
    int rewardBubbles = 0,
    VoidCallback? onViewPath,
  }) {
    if (context == null) return Future.value();
    return showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (_) => LevelUpDialog(
        level: level,
        rewardBubbles: rewardBubbles,
        onViewPath: onViewPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final textColor = themeConfig.textPrimary;
    final subTextColor = themeConfig.textSecondary;
    final primaryColor = themeConfig.primaryColor;
    final accent = level.color;
    final quote = LevelUtil.getTitleQuote(level.level);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        decoration: BoxDecoration(
          color: themeConfig.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: themeStyle.isDark ? 0.22 : 0.16),
              blurRadius: 30,
              spreadRadius: 2,
            ),
            ...themeConfig.cardShadows,
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '段 位 晋 升',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
                color: subTextColor,
              ),
            ),
            const SizedBox(height: 20),

            // 段位徽记与呼吸光晕
            Container(
              width: 106,
              height: 106,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.1),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.3),
                    blurRadius: 34,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Text(level.icon, style: const TextStyle(fontSize: 52)),
            ),
            const SizedBox(height: 18),

            Text(
              level.name,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: textColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'LV.${level.level}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
                color: subTextColor,
              ),
            ),
            const SizedBox(height: 14),

            Text(
              '“$quote”',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: textColor.withValues(alpha: 0.72),
              ),
            ),

            if (rewardBubbles > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🫧', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    '晋升奖励 +$rewardBubbles 魔法泡泡',
                    style: TextStyle(fontSize: 12.5, color: subTextColor),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: themeConfig.cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onViewPath?.call();
                    },
                    child: const Text(
                      '成长之路',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '开心收下',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
