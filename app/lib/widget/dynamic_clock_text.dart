import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart' as app_date;

/// 动态局部刷新的时间与业务学习日期显示组件
class DynamicClockText extends StatefulWidget {
  final TextStyle style;

  const DynamicClockText({
    super.key,
    required this.style,
  });

  @override
  State<DynamicClockText> createState() => _DynamicClockTextState();
}

class _DynamicClockTextState extends State<DynamicClockText> {
  Timer? _timer;
  late DateTime _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = AppClock.now();
    // 每一秒更新一次，确保顺滑度与极高的计时精确度
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = AppClock.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final businessDateStr = DateFormat('yyyy-MM-dd').format(app_date.DateUtils.businessDate(_currentTime));
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(_currentTime);
    return Text(
      '$timeStr ($businessDateStr)',
      style: widget.style,
    );
  }
}
