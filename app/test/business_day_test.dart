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
  });
}
