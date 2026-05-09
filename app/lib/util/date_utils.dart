/// 日期工具类
class DateUtils {
  /// 获取纯日期（去掉时分秒，凌晨3点切换业务天）
  static DateTime pureDate(DateTime date) {
    return businessDate(date);
  }

  /// 获取业务日期（凌晨3点前归属于前一天）
  static DateTime businessDate(DateTime date) {
    final local = date.toLocal();
    if (local.hour < 3) {
      final yesterday = local.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    }
    return DateTime(local.year, local.month, local.day);
  }

  /// 判断两个日期是否是同一个业务天
  static bool isSameDay(DateTime date1, DateTime date2) {
    return isSameBusinessDay(date1, date2);
  }

  /// 判断两个日期是否是同一个业务天（凌晨3点切换）
  static bool isSameBusinessDay(DateTime d1, DateTime d2) {
    final bd1 = businessDate(d1);
    final bd2 = businessDate(d2);
    return bd1.year == bd2.year && bd1.month == bd2.month && bd1.day == bd2.day;
  }

  /// 获取业务天的开始时间（当地时区 03:00:00）
  static DateTime businessDayStart(DateTime date) {
    final bd = businessDate(date);
    return DateTime(bd.year, bd.month, bd.day, 3, 0, 0);
  }

  /// 获取业务天的结束时间（当地时区 次日 02:59:59）
  static DateTime businessDayEnd(DateTime date) {
    final bd = businessDate(date);
    return DateTime(bd.year, bd.month, bd.day, 2, 59, 59).add(const Duration(days: 1));
  }
}
