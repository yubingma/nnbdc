import 'package:flutter/material.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
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
