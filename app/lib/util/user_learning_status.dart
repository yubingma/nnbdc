import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:flutter/foundation.dart';
import 'package:nnbdc/api/vo.dart';

/// 用户学习状态帮助类
/// 提供计算用户今日学习状态的方法
class UserLearningStatusHelper {
  /// 判断用户今天是否已经开始学习 (User 版本)
  static bool isTodayLearningStartedFromUser(User user) {
    // 如果用户从未开始过学习（lastLearningPosition 为 -1 或 null），则认为未开始
    // 否则检查最后学习日期是否是今天
    if (user.lastLearningPosition == null || user.lastLearningPosition == -1) {
      return false;
    }
    
    // 检查最后学习日期是否是今天
    if (user.lastLearningDate == null) {
      return false;
    }
    
    final today = AppClock.today();
    final lastLearningDate = user.lastLearningDate!;
    
    return _isSameDay(today, lastLearningDate);
  }
  
  /// 判断用户今天是否已经开始学习 (UserVo 版本)
  static bool isTodayLearningStarted(UserVo user) {
    // 如果用户从未开始过学习（lastLearningPosition 为 -1 或 null），则认为未开始
    // 否则检查最后学习日期是否是今天
    if (user.lastLearningPosition == null || user.lastLearningPosition == -1) {
      return false;
    }
    
    // 检查最后学习日期是否是今天
    if (user.lastLearningDate == null) {
      return false;
    }
    
    final today = AppClock.today();
    final lastLearningDate = user.lastLearningDate!;
    
    return _isSameDay(today, lastLearningDate);
  }

  /// 判断用户今天是否已经完成学习 (User 版本)
  static bool isTodayLearningFinishedFromUser(User user) {
    // 需要同时满足两个条件：
    // 1. 学习已完成标记为 true
    // 2. 最后学习日期是今天
    if (user.learningFinished == null || !user.learningFinished!) {
      return false;
    }
    
    if (user.lastLearningDate == null) {
      return false;
    }
    
    final today = AppClock.today();
    final lastLearningDate = user.lastLearningDate!;
    
    return _isSameDay(today, lastLearningDate);
  }
  
  /// 判断用户今天是否已经完成学习 (UserVo 版本)
  static bool isTodayLearningFinished(UserVo user) {
    // 需要同时满足两个条件：
    // 1. 学习已完成标记为 true
    // 2. 最后学习日期是今天
    if (user.learningFinished == null || !user.learningFinished!) {
      return false;
    }
    
    if (user.lastLearningDate == null) {
      return false;
    }
    
    final today = AppClock.today();
    final lastLearningDate = user.lastLearningDate!;
    
    return _isSameDay(today, lastLearningDate);
  }

  /// 检查两个日期是否是同一天
  static bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
}