import 'package:flutter/material.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/widget/dynamic_clock_text.dart';
import 'package:provider/provider.dart';

/// 学习日期的业务说明与时区弹窗说明组件
class StudyDateExplanationDialog extends StatelessWidget {
  const StudyDateExplanationDialog({super.key});

  /// 快捷调起弹窗的静态方法
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const StudyDateExplanationDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final now = AppClock.now();
    final timeZoneName = now.timeZoneName;
    final offsetSign = now.timeZoneOffset.isNegative ? '-' : '+';
    final offsetHours = now.timeZoneOffset.inHours.abs();

    return AlertDialog(
      title: const Text('学习日期说明'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本应用以凌晨 03:00 作为学习日期的切换点。\n\n如果您在凌晨 3 点前背单词，系统仍会将其计入前一天的学习任务中，以照顾习惯熬夜学习的同学。'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF181C28) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: isDarkMode ? Colors.white60 : const Color(0xFF4B5563),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '当前系统时间 (业务学习日期):',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white70 : const Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                DynamicClockText(
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: isDarkMode ? const Color(0xFFF9FAFB) : const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '当前时区: $timeZoneName (UTC$offsetSign$offsetHours)',
            style: TextStyle(
              fontSize: 10,
              color: isDarkMode ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
