import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/learning_word_extensions.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';

/// 构造一个只关心"今日进度归属"的 LearningWord。
LearningWord _wordWithProgress({int todayLearnedTimes = 1, DateTime? lastLearningDate}) {
  final now = DateTime(2026, 5, 10, 12);
  return LearningWord(
    userId: 'u',
    wordId: 'w',
    addDay: 1,
    addTime: now,
    lastLearningDate: lastLearningDate,
    learningOrder: 1,
    isExtra: false,
    isTodayNewWord: true,
    learnedTimes: 1,
    todayLearnedTimes: todayLearnedTimes,
    createTime: now,
    updateTime: now,
  );
}

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

    test('DateUtils.isSameBusinessDay should follow business day rules', () {
      final monday10PM = DateTime(2026, 5, 11, 22, 0, 0);
      final tuesday2AM = DateTime(2026, 5, 12, 2, 0, 0);
      final tuesday4AM = DateTime(2026, 5, 12, 4, 0, 0);

      // 晚上 10 点和凌晨 2 点是同一个业务天（周一）
      expect(DateUtils.isSameBusinessDay(monday10PM, tuesday2AM), isTrue);
      
      // 凌晨 2 点和凌晨 4 点不是同一个业务天（周一 vs 周二）
      expect(DateUtils.isSameBusinessDay(tuesday2AM, tuesday4AM), isFalse);
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
      
      // 5月10日的业务天是从 5月10日 03:00 开始（闭区间下界）
      final start = DateUtils.businessDayStart(date);
      expect(start, DateTime(2026, 5, 10, 3, 0, 0));
      
      // 到 5月11日 03:00 结束（开区间上界），区间为 [start, end)
      final end = DateUtils.businessDayEnd(date);
      expect(end, DateTime(2026, 5, 11, 3, 0, 0));
      expect(end, DateUtils.businessDayStart(DateTime(2026, 5, 11, 12, 0, 0)),
          reason: '本业务日的开区间上界必须恰为下一业务日的起点，窗口无缝且不重叠');
    });

    test('不变式：任意瞬时恰好落在其业务日窗口 [start, end) 内（跨时区/夏令时均成立）', () {
      // 采样覆盖普通日、跨月、跨年，以及夏令时切换的高发日期。
      // 该不变式不依赖运行时区；但在夏令时时区下，旧实现（按绝对时长回拨 3 小时）会失败。
      final samples = <DateTime>[
        DateTime(2026, 5, 10, 0, 0, 0, 0, 1),
        DateTime(2026, 5, 10, 2, 59, 59),
        DateTime(2026, 5, 10, 3),
        DateTime(2026, 5, 10, 23, 59, 59),
        DateTime(2026, 1, 1, 3),
        DateTime(2025, 12, 31, 23),
        DateTime(2026, 3, 8, 1, 30),
        DateTime(2026, 3, 8, 2, 30),
        DateTime(2026, 3, 8, 3),
        DateTime(2026, 3, 8, 4),
        DateTime(2026, 11, 1, 0, 30),
        DateTime(2026, 11, 1, 1, 30),
        DateTime(2026, 11, 1, 2, 30),
        DateTime(2026, 11, 1, 3, 30),
        DateTime.utc(2026, 3, 8, 7),
      ];

      for (final t in samples) {
        final bd = DateUtils.businessDate(t);
        final start = DateUtils.businessDayStart(t);
        final end = DateUtils.businessDayEnd(t);

        expect(!t.isBefore(start) && t.isBefore(end), isTrue,
            reason: '$t 必须落在业务日 $bd 的窗口 [$start, $end) 内');
        expect(DateUtils.businessDate(start), bd,
            reason: '窗口起点必须归入同一业务日');
        expect(DateUtils.businessDate(end.subtract(const Duration(microseconds: 1))), bd,
            reason: '窗口内最后一个瞬时必须归入同一业务日');
        expect(DateUtils.businessDayStart(end), end,
            reason: '窗口上界必须恰为下一业务日的起点（无缝、不重叠）');
      }
    });

    test('夏令时春令当天：墙钟过 3 点即归当天（旧实现按绝对时长回拨会推迟到 4 点）', () {
      // America/New_York 2026-03-08 本地时钟 02:00 直接跳到 03:00。
      // 注意：该时区的 02:00~02:59 并不存在，Dart 会把不存在的墙钟时刻规范化到 03:00，
      // 因此只断言确实存在的墙钟时刻，保证本用例在任何时区下都成立。
      expect(DateUtils.businessDate(DateTime(2026, 3, 8, 0, 30)), DateTime(2026, 3, 7));
      expect(DateUtils.businessDate(DateTime(2026, 3, 8, 1, 30)), DateTime(2026, 3, 7));
      expect(DateUtils.businessDate(DateTime(2026, 3, 8, 3)), DateTime(2026, 3, 8),
          reason: '墙钟已过 3 点，必须归入当天；旧实现按绝对时长回拨会把 03:00~03:59 误判为前一天');
      expect(DateUtils.businessDate(DateTime(2026, 3, 8, 3, 59)), DateTime(2026, 3, 8));
    });

    test('夏令时秋令当天：03:00 前仍归前一天，窗口不被压缩出空洞', () {
      // America/New_York 2026-11-01 本地时钟 02:00 回拨到 01:00
      expect(DateUtils.businessDate(DateTime(2026, 11, 1, 1, 30)), DateTime(2026, 10, 31));
      expect(DateUtils.businessDate(DateTime(2026, 11, 1, 2, 30)), DateTime(2026, 10, 31));
      expect(DateUtils.businessDate(DateTime(2026, 11, 1, 3)), DateTime(2026, 11, 1));

      final end = DateUtils.businessDayEnd(DateTime(2026, 10, 31, 12));
      final nextStart = DateUtils.businessDayStart(DateTime(2026, 11, 1, 12));
      expect(end, nextStart, reason: '秋令当天也不能在 02:00~03:00 出现无人认领的空洞');
    });

    test('整点午夜特例：已归一化的业务日被原样认领，并记录其 1 秒窗口的取舍', () {
      // 业务日期以本地/UTC 午夜持久化，跨时区读回后必须原样认领，否则会被 toLocal 整体挪一天。
      expect(DateUtils.businessDate(DateTime(2026, 5, 11)), DateTime(2026, 5, 11));
      expect(DateUtils.businessDate(DateTime.utc(2026, 5, 11)), DateTime(2026, 5, 11));

      // 已知取舍：整点午夜走幂等保护归入当天，其后 1 个微秒即按 3 点界归入前一天，
      // 故二者分属不同业务日。这是幂等保护的代价，不是回归。
      expect(DateUtils.businessDate(DateTime(2026, 5, 11, 0, 0, 0, 0, 1)), DateTime(2026, 5, 10));
      expect(
        DateUtils.isSameBusinessDay(
          DateTime(2026, 5, 11, 0, 0, 0),
          DateTime(2026, 5, 11, 0, 0, 0, 0, 1),
        ),
        isFalse,
      );
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

      // 更复杂的时差偏移场景：
      // 我们创建一个本地时间（比如下午 14:00）
      final localTime = DateTime(2026, 5, 21, 14, 0, 0);
      // 基于该时间减去 5 个小时得到 09:00，在 3 AM 划分规则下它们依然属于同一个本地业务天
      final anotherLocal = localTime.subtract(const Duration(hours: 5));
      // 模拟混合 UTC 和 Local：将 anotherLocal 转换为 UTC DateTime
      final utcTime = anotherLocal.toUtc();
      
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

      // 场景 2：模拟时区下从 SQLite / Drift 读写反序列化 DateTime 的真实转换
      // 用户在本地 5月20日业务天学习，记为 DateTime(2026, 5, 20) (Local 0点)
      // 存入 SQLite 并被 Drift 反序列化读出时，变为了对应的 UTC DateTime
      final dbUserLastLearningDate = DateTime(2026, 5, 20).toUtc(); 
      final businessDateOfDb = DateUtils.businessDate(dbUserLastLearningDate);

      // 数据库读出的带有时区偏移的时间，必须依然准确归入 5月20日 业务天
      expect(businessDateOfDb.year, 2026);
      expect(businessDateOfDb.month, 5);
      expect(businessDateOfDb.day, 20);

      // 验证在美东时区下，从数据库读出来的 lastLearningDate 与本地计算的 today 必须是同一个业务天！
      expect(DateUtils.isSameBusinessDay(dbUserLastLearningDate, todayEST), isTrue);
    });
  });

  group('今日进度归属：LearningWord.hasTodayProgressBefore', () {
    final planDay = DateTime(2026, 5, 10); // 本日计划所属业务日

    test('今日次数为 0 时，无论如何都不算残留', () {
      expect(
        _wordWithProgress(todayLearnedTimes: 0, lastLearningDate: DateTime(2026, 5, 1))
            .hasTodayProgressBefore(planDay),
        isFalse,
      );
    });

    test('有进度但缺 lastLearningDate：无法证明属于本日，按残留处理', () {
      expect(_wordWithProgress(lastLearningDate: null).hasTodayProgressBefore(planDay), isTrue);
    });

    test('进度日严格早于计划日 → 残留（本日跨天重置尚未执行）', () {
      expect(
        _wordWithProgress(lastLearningDate: DateTime(2026, 5, 9)).hasTodayProgressBefore(planDay),
        isTrue,
      );
    });

    test('进度日等于计划日 → 不是残留', () {
      expect(
        _wordWithProgress(lastLearningDate: DateTime(2026, 5, 10)).hasTodayProgressBefore(planDay),
        isFalse,
      );
    });

    test('进度日更晚（多设备/时区差异）→ 绝不当作残留，否则会倒扣别的设备的进度', () {
      expect(
        _wordWithProgress(lastLearningDate: DateTime(2026, 5, 11)).hasTodayProgressBefore(planDay),
        isFalse,
      );
    });

    test('判定走业务日而非自然日：5/11 凌晨 01:30 的进度仍属业务日 5/10，不算残留', () {
      expect(
        _wordWithProgress(lastLearningDate: DateTime(2026, 5, 11, 1, 30))
            .hasTodayProgressBefore(planDay),
        isFalse,
      );
      // 5/10 凌晨 01:30 属业务日 5/9 → 才是残留
      expect(
        _wordWithProgress(lastLearningDate: DateTime(2026, 5, 10, 1, 30))
            .hasTodayProgressBefore(planDay),
        isTrue,
      );
    });
  });
}
