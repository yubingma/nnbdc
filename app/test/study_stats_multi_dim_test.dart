import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';

import 'package:flutter/services.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;

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

  test('UserStudyDailyStatsDao: 多维统计与按时间范围查询正确性', () async {
    const userId = 'user_dim_test';

    // 插入连续 10 天的统计记录
    for (int i = 0; i < 10; i++) {
      final date = AppClock.today().subtract(Duration(days: i));
      await db.userStudyDailyStatsDao.incrementSeconds(userId, date, (i + 1) * 300); // 每天 300s, 600s, ...
    }

    // 1. 测试 getRecentStats (近7天)
    final last7Stats = await db.userStudyDailyStatsDao.getRecentStats(userId, 7);
    expect(last7Stats.length, 7);
    int sum7 = last7Stats.fold(0, (prev, e) => prev + e.studySeconds);
    // 过去 7 天 (i=0..6)，秒数是 (1+2+3+4+5+6+7)*300 = 28 * 300 = 8400
    expect(sum7, 8400);

    // 2. 测试 getAllStats
    final allStats = await db.userStudyDailyStatsDao.getAllStats(userId);
    expect(allStats.length, 10);

    // 3. 测试 getStatsBetween
    final startDate = AppClock.today().subtract(const Duration(days: 4));
    final endDate = AppClock.today().subtract(const Duration(days: 2));
    final betweenStats = await db.userStudyDailyStatsDao.getStatsBetween(userId, startDate, endDate);
    expect(betweenStats.length, 3);
  });
}
