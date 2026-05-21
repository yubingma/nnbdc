import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';

void main() {
  group('Business Day (3 AM Cutoff) Tests', () {
    test('DateUtils.businessDate should handle 3 AM cutoff correctly', () {
      // 场景 1: 当天 02:59:59 -> 归属于前一天
      final earlyMorning = DateTime(2026, 5, 10, 2, 59, 59);
      final bd1 = DateUtils.businessDate(earlyMorning);
      expect(bd1.year, 2026);
      expect(bd1.month, 5);
      expect(bd1.day, 9);

      // 场景 2: 当天 03:00:00 -> 归属于当天
      final cutoffTime = DateTime(2026, 5, 10, 3, 0, 0);
      final bd2 = DateUtils.businessDate(cutoffTime);
      expect(bd2.year, 2026);
      expect(bd2.month, 5);
      expect(bd2.day, 10);

      // 场景 3: 深夜 23:59:59 -> 归属于当天
      final lateNight = DateTime(2026, 5, 10, 23, 59, 59);
      final bd3 = DateUtils.businessDate(lateNight);
      expect(bd3.year, 2026);
      expect(bd3.month, 5);
      expect(bd3.day, 10);

      // 边界场景 4: 恰好 00:00:00 -> 由于幂等保护，归属于当天
      // （这是为了保证 businessDate(businessDate(date)) 不变）
      final midnight = DateTime(2026, 5, 11, 0, 0, 0);
      final bd4 = DateUtils.businessDate(midnight);
      expect(bd4.year, 2026);
      expect(bd4.month, 5);
      expect(bd4.day, 11);

      // 边界场景 5: 00:00:00.001 -> 归属于前一天（偏移映射生效）
      final justAfterMidnight = DateTime(2026, 5, 11, 0, 0, 0, 0, 1);
      final bd5 = DateUtils.businessDate(justAfterMidnight);
      expect(bd5.year, 2026);
      expect(bd5.month, 5);
      expect(bd5.day, 10);
    });

    test('DateUtils.isSameDay should follow business day rules', () {
      final monday10PM = DateTime(2026, 5, 11, 22, 0, 0);
      final tuesday2AM = DateTime(2026, 5, 12, 2, 0, 0);
      final tuesday4AM = DateTime(2026, 5, 12, 4, 0, 0);

      // 晚上 10 点和凌晨 2 点是同一个业务天（周一）
      expect(DateUtils.isSameDay(monday10PM, tuesday2AM), isTrue);
      
      // 凌晨 2 点和凌晨 4 点不是同一个业务天（周一 vs 周二）
      expect(DateUtils.isSameDay(tuesday2AM, tuesday4AM), isFalse);
    });

    test('AppClock.today() should return business date', () {
      // 模拟系统时间为凌晨 1 点
      final fakeNow = DateTime(2026, 5, 10, 1, 0, 0);
      AppClock.setClock(FakeClock(fakeNow));
      
      // 业务日期应该是 5 月 9 日
      final today = AppClock.today();
      expect(today.year, 2026);
      expect(today.month, 5);
      expect(today.day, 9);
      
      AppClock.reset();
    });

    test('Business day boundary calculation', () {
      final date = DateTime(2026, 5, 10, 12, 0, 0);
      
      // 5月10日的业务天是从 5月10日 03:00 开始
      final start = DateUtils.businessDayStart(date);
      expect(start, DateTime(2026, 5, 10, 3, 0, 0));
      
      // 到 5月11日 02:59:59 结束
      final end = DateUtils.businessDayEnd(date);
      expect(end, DateTime(2026, 5, 11, 2, 59, 59));
    });

    test('DateUtils.isSameBusinessDay should correctly handle mixed UTC and Local DateTimes', () {
      // 模拟从数据库 Drift/SQLite 取回的带 UTC 标志的日期（比如 2026-05-21 00:00:00.000Z，isUtc: true）
      final dbUtcDate = DateTime.utc(2026, 5, 21, 0, 0, 0); 
      
      // 模拟通过 AppClock.today() 生成的 Local 日期（比如 2026-05-21 00:00:00.000，isUtc: false）
      final localDate = DateTime(2026, 5, 21, 0, 0, 0);

      // 【Bug 防范性断言】确保它们在 Dart 中直接直接比对或者 value 比对是绝对不相等的，用以证明为何不能直接 != / == 对比
      expect(dbUtcDate == localDate, isFalse);
      expect(dbUtcDate.isUtc, isTrue);
      expect(localDate.isUtc, isFalse);

      // 【安全工具方法断言】验证使用 DateUtils.isSameBusinessDay 进行对比时，它们必须是同一个业务天！
      expect(DateUtils.isSameBusinessDay(dbUtcDate, localDate), isTrue);
      expect(DateUtils.isSameDay(dbUtcDate, localDate), isTrue);

      // 更复杂的时差偏移场景：
      // UTC 5月21日凌晨 01:00 (isUtc = true) 对应北京时间 5月21日早上 09:00
      final utcTime = DateTime.utc(2026, 5, 21, 1, 0, 0);
      // Local 北京时间 5月21日下午 14:00 (isUtc = false)
      final localTime = DateTime(2026, 5, 21, 14, 0, 0);
      
      expect(DateUtils.isSameBusinessDay(utcTime, localTime), isTrue);
    });

    test('DateUtils.businessDate should robustly preserve standard UTC business dates across all simulated timezone scenarios', () {
      // 场景 1：传入 UTC 的纯 0 点业务日期 2026-05-21 00:00:00.000Z
      final utcBusinessDate = DateTime.utc(2026, 5, 21, 0, 0, 0);
      final result1 = DateUtils.businessDate(utcBusinessDate);
      
      // 不论测试运行在什么时区，业务天必须是 5月21日，绝不能由于时差偏移转化为前一天
      expect(result1.year, 2026);
      expect(result1.month, 5);
      expect(result1.day, 21);
      expect(result1.isUtc, isFalse); // 返回本地时间的业务日期
      expect(result1.hour, 0);
      expect(result1.minute, 0);

      // 场景 2：双向一致性，即使已经是 Local 的纯 0 点业务日期，传入后依然幂等返回该业务天
      final localBusinessDate = DateTime(2026, 5, 21, 0, 0, 0);
      final result2 = DateUtils.businessDate(localBusinessDate);
      expect(result2.year, 2026);
      expect(result2.month, 5);
      expect(result2.day, 21);
      expect(result2.isUtc, isFalse);
      expect(result2.hour, 0);
      expect(result2.minute, 0);
      
      // 场景 3：校验 isSameBusinessDay 绝对比对一致性
      expect(DateUtils.isSameBusinessDay(utcBusinessDate, localBusinessDate), isTrue);
    });

    test('DateUtils.businessDate should robustly preserve standard UTC and simulated Drift timezone transitions in US negative timezones', () {
      // 场景 1：模拟美东时区 (UTC-5) 晚上 20:00 的跨天与超前同步校验
      // 此时本地时间是 2026-05-20 20:00:00.000 (对应 UTC 的 2026-05-21 01:00:00.000Z)
      final localTimeEST = DateTime(2026, 5, 20, 20, 0, 0); 
      final todayEST = DateUtils.businessDate(localTimeEST);
      
      // 美东时间 20日 20点，回拨 3 小时为 17点，属于 5月20日 业务天
      expect(todayEST.year, 2026);
      expect(todayEST.month, 5);
      expect(todayEST.day, 20);

      // 模拟从云端同步过来的超前学习日期（例如在另一台北京设备完成的学习，记为 21日 业务天并同步为 UTC 0点）
      final syncedUtcBusinessDate = DateTime.utc(2026, 5, 21, 0, 0, 0); 
      final syncedBusinessDate = DateUtils.businessDate(syncedUtcBusinessDate);
      expect(syncedBusinessDate.year, 2026);
      expect(syncedBusinessDate.month, 5);
      expect(syncedBusinessDate.day, 21); // 精确提取字面 21日

      // 【核心验证】测试单向跨天比对演进逻辑：超前的已同步日期绝对不能被判定为早于今天！
      final bool isCrossDayEST = syncedBusinessDate.isBefore(todayEST);
      expect(isCrossDayEST, isFalse); // 正确判定：并未跨入未来新一天（进度超前或相等，不触发重置与报错）

      // 场景 2：模拟美东时区 (UTC-5) 下从 SQLite / Drift 读写反序列化 DateTime 的真实转换
      // 用户在本地 5月20日业务天学习，记为 DateTime(2026, 5, 20) (Local 0点)
      // 存入 SQLite 并被 Drift 反序列化读出时，变为了对应的 UTC DateTime，即 2026-05-20 05:00:00.000Z
      final dbUserLastLearningDate = DateTime.utc(2026, 5, 20, 5, 0, 0); 
      final businessDateOfDb = DateUtils.businessDate(dbUserLastLearningDate);

      // 数据库读出的带有时区偏移的时间，必须依然准确归入 5月20日 业务天
      expect(businessDateOfDb.year, 2026);
      expect(businessDateOfDb.month, 5);
      expect(businessDateOfDb.day, 20);

      // 验证在美东时区下，从数据库读出来的 lastLearningDate 与本地计算的 today 必须是同一个业务天！
      expect(DateUtils.isSameBusinessDay(dbUserLastLearningDate, todayEST), isTrue);
    });
  });
}
