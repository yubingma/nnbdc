
/// 日期工具类
class DateUtils {
  /// 获取业务日期（凌晨3点前归属于前一天）
  static DateTime businessDate(DateTime date) {
    // 1. 前置原始对象幂等校验：如果是 0 点且没有任何时间分量，说明它已经是一个经过抹除处理的业务日期，直接返回
    // 无论是 UTC (如 2026-05-21 00:00:00.000Z) 还是 Local (如 2026-05-21 00:00:00.000)，
    // 我们都应该直接以它的年、月、日作为本地业务日期返回，防止在不同时区下 toLocal() 导致日期发生偏移扣天。
    if (date.hour == 0 &&
        date.minute == 0 &&
        date.second == 0 &&
        date.millisecond == 0 &&
        date.microsecond == 0) {
      return DateTime(date.year, date.month, date.day);
    }

    final local = date.toLocal();

    // 2. 本地化后幂等保护：如果已经是 0 点且没有任何时间分量，说明它已经是一个经过处理的业务日期，直接返回
    if (local.hour == 0 &&
        local.minute == 0 &&
        local.second == 0 &&
        local.millisecond == 0 &&
        local.microsecond == 0) {
      return DateTime(local.year, local.month, local.day);
    }

    // 3. 偏移映射法：统一回拨 3 小时后再取日期部分
    // 00:00:00 -> 前一天 21:00 -> 归为前一天
    // 02:59:59 -> 前一天 23:59 -> 归为前一天
    // 03:00:00 -> 当天 00:00 -> 归为当天
    final shifted = local.subtract(const Duration(hours: 3));
    return DateTime(shifted.year, shifted.month, shifted.day);
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
