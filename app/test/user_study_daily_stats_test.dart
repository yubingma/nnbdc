import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每日学习统计表（user_study_daily_stats）的业务日归一测试。
///
/// 该表的 date 列是业务日期主键，全部写入路径都必须走 DateUtils.businessDate，
/// 否则同一次"夜猫子"学习会被拆成两行，或被算进错误的业务天。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  const userId = 'daily_stats_user';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  tearDown(() async {
    ThrottledDbSyncService().reset();
    AppClock.reset();
    await db.close();
  });

  test('同一业务日内的时长与复习次数累加到同一行（23:30 与次日 01:30）', () async {
    AppClock.setClock(FakeClock(DateTime(2026, 5, 10, 23, 30)));
    await db.userStudyDailyStatsDao.incrementSeconds(userId, AppClock.now(), 60);
    await db.userStudyDailyStatsDao.incrementReviewCount(userId, AppClock.now());

    AppClock.setClock(FakeClock(DateTime(2026, 5, 11, 1, 30)));
    await db.userStudyDailyStatsDao.incrementSeconds(userId, AppClock.now(), 30);
    await db.userStudyDailyStatsDao.incrementReviewCount(userId, AppClock.now());

    // 03:30 已跨入业务日 5/11
    AppClock.setClock(FakeClock(DateTime(2026, 5, 11, 3, 30)));
    await db.userStudyDailyStatsDao.incrementSeconds(userId, AppClock.now(), 10);

    final rows = await db.select(db.userStudyDailyStats).get();
    expect(rows.length, 2, reason: '23:30 与次日 01:30 必须落在同一业务日，不得拆成两行');

    final may10 = rows.singleWhere((r) => r.date == DateTime(2026, 5, 10));
    expect(may10.studySeconds, 90);
    expect(may10.reviewCount, 2);

    final may11 = rows.singleWhere((r) => r.date == DateTime(2026, 5, 11));
    expect(may11.studySeconds, 10);
    expect(may11.reviewCount, 0);
  });

  test('getRecentStats 以业务日为界取最近 N 天', () async {
    // 时钟落在 5/11 凌晨：此时"今天"的业务日仍是 5/10
    AppClock.setClock(FakeClock(DateTime(2026, 5, 11, 1)));
    await db.userStudyDailyStatsDao.incrementSeconds(userId, DateTime(2026, 5, 8, 10), 10);
    await db.userStudyDailyStatsDao.incrementSeconds(userId, DateTime(2026, 5, 9, 10), 10);
    // 必须用 5/10 白天：01:00 属于业务日 5/9
    await db.userStudyDailyStatsDao.incrementSeconds(userId, DateTime(2026, 5, 10, 10), 10);

    final stats = await db.userStudyDailyStatsDao.getRecentStats(userId, 2);
    expect(stats.map((s) => s.date).toList(),
        [DateTime(2026, 5, 9), DateTime(2026, 5, 10)],
        reason: '最近 2 个业务日是 5/9 与 5/10，不含 5/8');
  });

  test('updateDayStatus 按业务日归一，且同日状态只升级不回退', () async {
    // 5/11 01:00 仍属业务日 5/10
    await db.userStudyDailyStatsDao
        .updateDayStatus(userId, DateTime(2026, 5, 11, 1), UserDayStatus.dakaed);
    // 同一业务日试图用更弱的状态覆盖
    await db.userStudyDailyStatsDao
        .updateDayStatus(userId, DateTime(2026, 5, 10, 20), UserDayStatus.loggedIn);
    // 另一个业务日
    await db.userStudyDailyStatsDao
        .updateDayStatus(userId, DateTime(2026, 5, 11, 3, 1), UserDayStatus.studied);

    final list = await db.select(db.userStudyDailyStats).get()
      ..sort((a, b) => a.date.compareTo(b.date));

    expect(list.length, 2);
    expect(list[0].date, DateTime(2026, 5, 10));
    expect(list[0].dayStatus, UserDayStatus.dakaed.json, reason: 'dakaed 不得被 loggedIn 降级');
    expect(list[1].date, DateTime(2026, 5, 11));
    expect(list[1].dayStatus, UserDayStatus.studied.json);
  });
}
