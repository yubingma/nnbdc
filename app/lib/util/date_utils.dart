/// 日期工具类
class DateUtils {
  /// 获取纯日期（去掉时分秒）
  static DateTime pureDate(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
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

  /// 判断两个日期是否是同一天
  static bool isSameDay(DateTime date1, DateTime date2) {
    final d1 = date1.toLocal();
    final d2 = date2.toLocal();
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  /// 判断两个日期是否是同一个业务天（凌晨3点切换）
  static bool isSameBusinessDay(DateTime d1, DateTime d2) {
    final bd1 = businessDate(d1);
    final bd2 = businessDate(d2);
    return bd1.year == bd2.year && bd1.month == bd2.month && bd1.day == bd2.day;
  }
}
