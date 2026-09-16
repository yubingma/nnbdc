
/// 日期工具类
class DateUtils {
  /// 获取业务日期（凌晨3点前归属于前一天）。
  ///
  /// 3 点界基于**本地墙钟**判定，而不是对瞬时做 3 小时的绝对时长回拨：后者在夏令时切换日会算错。
  /// 例如 America/New_York 2026-03-08 本地时钟从 02:00 直接跳到 03:00，此时 03:00 对应的 UTC 瞬时
  /// 回拨 3 小时会落到 03-07，把一个本属于当天的事件误判成前一天。
  ///
  /// 特例：整点午夜（本地或 UTC 的 00:00:00.000000）直接返回其年月日，不再走 3 点界。
  /// 业务日期以本地午夜的 [DateTime] 持久化，从 SQLite / 云端读回时可能带 UTC 标志与整秒精度，
  /// 若再走 3 点界会被 toLocal 在不同时区整体挪一天，故必须原样认领。
  /// 代价：真实发生于 00:00:00.000 ~ 00:00:00.999 的事件会归入当天而非前一业务日。
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

    // 3. 墙钟映射：本地 00:00:00 ~ 02:59:59 归前一天，03:00:00 起归当天。
    //    用 DateTime 构造器的日历进位（day - 1 自动跨月跨年）而不是 Duration 减法，夏令时切换日同样正确。
    final day = local.hour < 3 ? local.day - 1 : local.day;
    return DateTime(local.year, local.month, day);
  }

  /// 判断两个日期是否是同一个业务天（凌晨3点切换）
  static bool isSameBusinessDay(DateTime d1, DateTime d2) {
    final bd1 = businessDate(d1);
    final bd2 = businessDate(d2);
    return bd1.year == bd2.year && bd1.month == bd2.month && bd1.day == bd2.day;
  }

  /// 获取业务天的开始时间（当地时区 03:00:00，闭区间下界）
  static DateTime businessDayStart(DateTime date) {
    final bd = businessDate(date);
    return DateTime(bd.year, bd.month, bd.day, 3);
  }

  /// 获取业务天的结束时间（当地时区**次日 03:00:00，开区间上界**）。
  ///
  /// 业务日区间恒为 [businessDayStart(date), businessDayEnd(date))，既无缝也不重叠。
  /// 查询必须写成 `>= start & < end`：写成 `<= end` 会把次日 03:00:00 这一个瞬间算进当天。
  static DateTime businessDayEnd(DateTime date) {
    final start = businessDayStart(date);
    return DateTime(start.year, start.month, start.day + 1, 3);
  }
}
