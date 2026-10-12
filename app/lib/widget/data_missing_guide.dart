import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/page/admin/health_check.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/widget/rebuild_database_dialog.dart';

/// 「本机缺少这个单词的通用释义」时给用户的出路面板。
///
/// 这个错误只有两种成因：本机的通用词典数据缺了这一块（可以从云端补回来），
/// 或者本机数据已经缺到点对点补不回来（清空本地数据、重新同步一次）。
/// 所以面板只给这两条路，不把「重试」当主出路 —— 单纯重试必然再次失败。
class MissingMeaningGuide extends StatelessWidget {
  const MissingMeaningGuide({super.key, this.wordSpell, this.onRetry, this.onBack});

  /// 出问题的单词拼写，取自异常对象；取不到时不显示具体单词。
  final String? wordSpell;

  /// 页面自己的「重试」动作。为空时不显示重试入口。
  final VoidCallback? onRetry;

  /// 页面自己的「返回」动作。为空时不显示返回入口。
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 48, color: theme.textSecondary),
          const SizedBox(height: 16),
          Text(
            '本机缺少这个词的释义',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            wordSpell == null
                ? '要学的这个单词，中文释义在本机丢了。先做一次数据健康检查，把缺的数据从云端补回来；补不回来时，再清空本地数据重新同步一次。'
                : '「$wordSpell」的中文释义在本机丢了。先做一次数据健康检查，把缺的数据从云端补回来；补不回来时，再清空本地数据重新同步一次。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.6, color: theme.textSecondary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HealthCheckPage(autoStart: true)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              child: const Text(
                '修复数据（数据健康检查）',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: () async {
                final wiped = await showRebuildDatabaseDialog(context);
                if (wiped && context.mounted) {
                  context.go('/login');
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white70 : Colors.black87,
                side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.black26,
                  width: 0.8,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              child: const Text(
                '清空本地数据重新同步',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (onRetry != null || onBack != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                      '重试',
                      style: TextStyle(fontSize: 14, color: theme.textSecondary),
                    ),
                  ),
                if (onBack != null)
                  TextButton(
                    onPressed: onBack,
                    child: Text(
                      '返回',
                      style: TextStyle(fontSize: 14, color: theme.textSecondary),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
