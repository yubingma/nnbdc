/// 日期工具类
class DateUtils {
  /// 获取纯日期（去掉时分秒）
  static DateTime pureDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 判断两个日期是否是同一天
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month && date1.day == date2.day;
  }
}
