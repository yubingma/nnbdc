import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';

/// 记忆历史弹窗（毛玻璃）：只读展示某个单词的历史评分记录。
///
/// 两点实现约束（否则毛玻璃会静默失效或直接崩）：
/// - `ClipRRect + BackdropFilter` 必须紧贴弹窗自身的矩形：`AlertDialog` 会撑满整屏，
///   直接包住会把整屏都模糊掉，故自行排版；
/// - `showGeneralDialog` 不像 `AlertDialog` 自带 `Material`，需自己补一个透明 `Material`。
Future<void> showLearningHistoryDialog(
  BuildContext context, {
  required List<LearningLog> history,
}) {
  final isDarkMode = context.read<DarkMode>().isDarkMode;
  final textColor = isDarkMode ? Colors.white70 : Colors.black87;
  final primaryColor = context.primaryColor;

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '记忆历史',
    // 遮罩留亮：底层内容被模糊成柔和色块才好看，全屏死黑会把毛玻璃压成灰板
    barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.40 : 0.18),
    transitionDuration: const Duration(milliseconds: 200),
    // 转场用 ScaleTransition：FadeTransition 的 OpacityLayer 会阻断 BackdropFilter 采样
    transitionBuilder: (_, anim, __, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
      child: child,
    ),
    pageBuilder: (dlgCtx, _, __) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: SizedBox(
            width: min(MediaQuery.sizeOf(dlgCtx).width - 56, 420),
            // 阴影必须留在 ClipRRect 之外，否则会被自己的圆角裁剪掉
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  // sigma 5~7：抹掉底层字形、只留其墨水色块，弹窗文字才读得清
                  filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                  child: Container(
                    // 比 cardBg(50%) 实得多：毛玻璃负责"透"，底色负责"读得清"
                    color: isDarkMode
                        ? const Color(0xD91C2127)
                        : const Color(0xD9FFFFFF),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                            child: Text('记忆历史',
                                style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          Flexible(
                            child: history.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 0, 20, 16),
                                    child: Text('暂无记忆历史',
                                        style: TextStyle(
                                            color: textColor
                                                .withValues(alpha: 0.6))),
                                  )
                                : ConstrainedBox(
                                    constraints: BoxConstraints(
                                        maxHeight: MediaQuery.sizeOf(dlgCtx)
                                                .height *
                                            0.55),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 2, 20, 4),
                                      itemCount: history.length,
                                      itemBuilder: (context, index) =>
                                          _buildHistoryItem(history[index],
                                              isDarkMode, textColor),
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.pop(dlgCtx),
                                child: Text('关闭',
                                    style: TextStyle(color: primaryColor)),
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
          ),
        ),
      );
    },
  );
}

Widget _buildHistoryItem(
    LearningLog log, bool isDarkMode, Color textColor) {
  final rating = FsrsRatingExt.fromInt(log.rating);
  final timeStr =
      '${log.createTime.year}-${log.createTime.month.toString().padLeft(2, '0')}-${log.createTime.day.toString().padLeft(2, '0')} ${log.createTime.hour.toString().padLeft(2, '0')}:${log.createTime.minute.toString().padLeft(2, '0')}';

  final ratingColor = rating.colorWithDark(isDarkMode);

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isDarkMode
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ratingColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: ratingColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            rating.label,
            style: TextStyle(
                color: ratingColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: '下次复习: ',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    TextSpan(
                      text: '${log.scheduledDays}',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                        text: '天后',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timeStr,
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.5), fontSize: 11),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded,
            size: 16, color: textColor.withValues(alpha: 0.3)),
      ],
    ),
  );
}
