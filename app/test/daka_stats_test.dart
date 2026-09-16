import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  late String userId;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        return [];
      },
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);

    // 注册 7 天前的用户（打卡率分母 = 7 天）
    userId = 'daka_test_user';
    final now = AppClock.now();
    final today = DateUtils.businessDate(now);
    // 注册日 = 6 个业务日前（用日历回退而非 Duration，避免夏令时切换日偏移）
    final createTime = DateTime(today.year, today.month, today.day - 6);
    final user = User(
      id: userId,
      userName: 'daka_test',
      password: '',
      nickName: 'DakaTester',
      email: '',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 0,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: 5,
      dakaDayCount: 0,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: false,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: createTime,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);

    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Global.currentUserId = null;
  });

  tearDown(() async {
    // 取消可能因 genLog=true 触发的节流同步定时器，避免 pending timer
    ThrottledDbSyncService().reset();
    await db.close();
  });

  Future<void> addDaka(DateTime forLearningDate) async {
    await db.dakasDao.saveDaka(
      Daka(
        userId: userId,
        forLearningDate: DateUtils.businessDate(forLearningDate),
        textContent: '打卡',
        createTime: forLearningDate,
        updateTime: forLearningDate,
      ),
      false,
    );
  }

  /// 以业务日为单位做日历回退：用 DateTime 构造器而不是 Duration 减法，
  /// 避免在夏令时切换日算出 01:00/23:00 这类落到相邻业务日的时刻。
  DateTime bizDaysAgo(int days) {
    final t = AppClock.today();
    return DateTime(t.year, t.month, t.day - days);
  }

  group('打卡统计推导 (多端一致性)', () {
    test('从本机 dakas 表幂等推导：3 天打卡 → 天数=3、打卡率=3/7', () async {
      final today = DateUtils.businessDate(AppClock.now());
      await addDaka(today);
      await addDaka(bizDaysAgo(1));
      await addDaka(bizDaysAgo(2));

      await UserBo().updateAndSyncUserDakaStats(userId);

      final updated = await db.usersDao.getUserById(userId);
      expect(updated!.dakaDayCount, 3);
      expect(updated.continuousDakaDayCount, 3);
      expect(updated.dakaRatio, closeTo(3 / 7, 0.001));
      expect(DateUtils.businessDate(updated.lastDakaDate!), today);
    });

    test('单调兜底：本机 dakas 只到 3 天，但不把服务端已聚合的 7 压低', () async {
      final today = DateUtils.businessDate(AppClock.now());
      await addDaka(today);
      await addDaka(bizDaysAgo(1));
      await addDaka(bizDaysAgo(2));

      // 模拟：另一台设备/服务端已聚合出正确的 7 天，并回写到了本机 user 行
      await db.usersDao.saveUser(
        (await db.usersDao.getUserById(userId))!.copyWith(dakaDayCount: 7),
        false,
      );

      await UserBo().updateAndSyncUserDakaStats(userId);

      // 本机 dakas 虽只有 3 天，但累计天数只增不减，不应被压低
      final updated = await db.usersDao.getUserById(userId);
      expect(updated!.dakaDayCount, 7);
      expect(updated.dakaRatio, closeTo(1.0, 0.001));
    });

    test('重复推导幂等：同样数据连续推导两次，数值不再变化', () async {
      final today = DateUtils.businessDate(AppClock.now());
      await addDaka(today);
      await addDaka(bizDaysAgo(1));

      await UserBo().updateAndSyncUserDakaStats(userId);
      final first = await db.usersDao.getUserById(userId);

      await UserBo().updateAndSyncUserDakaStats(userId);
      final second = await db.usersDao.getUserById(userId);

      expect(second!.dakaDayCount, first!.dakaDayCount);
      expect(second.continuousDakaDayCount, first.continuousDakaDayCount);
      expect(second.dakaRatio, first.dakaRatio);
    });
  });

  group('业务日期与真实物理日期（跨凌晨/夜猫子打卡）深度完备性测试', () {
    test('夜猫子跨凌晨打卡：物理时间跨天但凌晨3点前归属前一天，连续打卡不中断', () async {
      // 场景：
      // Day 1: 真实物理时间 2026-05-10 22:30 (业务日 2026-05-10)
      // Day 2: 真实物理时间 2026-05-12 01:30 (自然日已是 12日，但由于在凌晨 3点前，业务日为 2026-05-11)
      // Day 3: 真实物理时间 2026-05-12 03:15 (自然日 12日，且过了凌晨 3点，业务日为 2026-05-12)

      final day1RealTime = DateTime(2026, 5, 10, 22, 30, 0);
      final day2RealTime = DateTime(2026, 5, 12, 1, 30, 0);
      final day3RealTime = DateTime(2026, 5, 12, 3, 15, 0);

      // 验证业务日期映射
      expect(DateUtils.businessDate(day1RealTime), DateTime(2026, 5, 10));
      expect(DateUtils.businessDate(day2RealTime), DateTime(2026, 5, 11));
      expect(DateUtils.businessDate(day3RealTime), DateTime(2026, 5, 12));

      // 1. 第 1 天打卡
      AppClock.setClock(FakeClock(day1RealTime));
      await addDaka(day1RealTime);
      await UserBo().updateAndSyncUserDakaStats(userId);
      var user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 1);
      expect(user.continuousDakaDayCount, 1);

      // 2. 第 2 天凌晨打卡 (夜猫子在 5月12日 01:30 打卡，归入 5月11日业务天)
      AppClock.setClock(FakeClock(day2RealTime));
      await addDaka(day2RealTime);
      await UserBo().updateAndSyncUserDakaStats(userId);
      user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 2);
      expect(user.continuousDakaDayCount, 2, reason: '未过凌晨3点，算作5月11日业务天，连续打卡保持为2天');

      // 3. 第 3 天凌晨3点后打卡 (5月12日 03:15 打卡，归入 5月12日业务天)
      AppClock.setClock(FakeClock(day3RealTime));
      await addDaka(day3RealTime);
      await UserBo().updateAndSyncUserDakaStats(userId);
      user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 3);
      expect(user.continuousDakaDayCount, 3, reason: '过了凌晨3点进入新业务日，连续打卡成功累进为3天');

      AppClock.reset();
    });

    test('同一业务日内多次打卡（夜间 23:30 与 次日凌晨 01:30）不重计、不漏记', () async {
      // 场景：同一业务日(2026-05-10)内，用户在 23:30 打了一次卡，又在次日 01:30 打了一次
      final dakaTime1 = DateTime(2026, 5, 10, 23, 30, 0);
      final dakaTime2 = DateTime(2026, 5, 11, 1, 30, 0);

      expect(DateUtils.isSameBusinessDay(dakaTime1, dakaTime2), isTrue);

      AppClock.setClock(FakeClock(dakaTime1));
      await addDaka(dakaTime1);
      await UserBo().updateAndSyncUserDakaStats(userId);
      var user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 1);
      expect(user.continuousDakaDayCount, 1);

      // 相同业务日再打一次卡（因为主键是 userId + forLearningDate，会覆盖或更新相同业务日记录）
      AppClock.setClock(FakeClock(dakaTime2));
      await addDaka(dakaTime2);
      await UserBo().updateAndSyncUserDakaStats(userId);
      user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 1, reason: '同一业务日多次打卡，累计打卡天数仍为1');
      expect(user.continuousDakaDayCount, 1, reason: '同一业务日多次打卡，连续天数仍为1');

      AppClock.reset();
    });

    test('跨年与跨月连续打卡：12月31日夜间到1月1日凌晨平滑衔接', () async {
      final dec31 = DateTime(2025, 12, 31, 22, 0, 0);
      final jan01 = DateTime(2026, 1, 1, 15, 0, 0);
      final jan02 = DateTime(2026, 1, 2, 2, 0, 0); // 1月2日凌晨2点，归入 1月1日业务天
      final jan03 = DateTime(2026, 1, 2, 10, 0, 0); // 1月2日业务天

      AppClock.setClock(FakeClock(dec31));
      await addDaka(dec31);

      AppClock.setClock(FakeClock(jan01));
      await addDaka(jan01);

      AppClock.setClock(FakeClock(jan02));
      await addDaka(jan02); // 1月1日业务天重复打卡

      AppClock.setClock(FakeClock(jan03));
      await addDaka(jan03); // 1月2日业务天打卡

      await UserBo().updateAndSyncUserDakaStats(userId);
      final user = await db.usersDao.getUserById(userId);

      // 涵盖了 2025-12-31, 2026-01-01, 2026-01-02 三个业务天
      expect(user!.dakaDayCount, 3);
      expect(user.continuousDakaDayCount, 3);

      AppClock.reset();
    });
  });

  group('连续打卡的天数语义（断档 / 今天未打卡 / 未来业务日 / 跨年）', () {
    test('中间断档：连续天数只数最近一段，累计天数仍是全部', () async {
      await addDaka(AppClock.today());
      await addDaka(bizDaysAgo(1));
      // 断掉今天-2
      await addDaka(bizDaysAgo(3));
      await addDaka(bizDaysAgo(4));

      await UserBo().updateAndSyncUserDakaStats(userId);

      final user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 4);
      expect(user.continuousDakaDayCount, 2, reason: '今天-2 断档，连续段只能是最近 2 天');
    });

    test('今天尚未打卡：连续天数从昨天起算，不清零', () async {
      await addDaka(bizDaysAgo(1));
      await addDaka(bizDaysAgo(2));
      await addDaka(bizDaysAgo(3));

      await UserBo().updateAndSyncUserDakaStats(userId);

      final user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 3);
      expect(user.continuousDakaDayCount, 3, reason: '今天还没打卡不该把昨天的连续记录清零');
    });

    test('久未打卡：最近一段既不挨着今天也不挨着昨天时，连续天数为 0', () async {
      await addDaka(bizDaysAgo(3));
      await addDaka(bizDaysAgo(4));

      await UserBo().updateAndSyncUserDakaStats(userId);

      final user = await db.usersDao.getUserById(userId);
      expect(user!.continuousDakaDayCount, 0);
    });

    test('未来业务日的打卡（他机时钟超前）不破坏本机连续统计', () async {
      await addDaka(bizDaysAgo(-1));
      await addDaka(bizDaysAgo(1));
      await addDaka(bizDaysAgo(2));

      await UserBo().updateAndSyncUserDakaStats(userId);

      final user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 3);
      expect(user.continuousDakaDayCount, 2,
          reason: '未来记录既不参与连续段，也不得打断本机从昨天起算的连续');
    });

    test('跨年断档：不把跨年两侧无脑连起来，只数最近一段', () async {
      AppClock.setClock(FakeClock(DateTime(2026, 1, 3, 10)));
      await addDaka(DateTime(2026, 1, 3, 9)); // 业务日 1/3
      await addDaka(DateTime(2026, 1, 2, 9)); // 业务日 1/2
      // 1/1 断档
      await addDaka(DateTime(2025, 12, 31, 22)); // 业务日 12/31

      await UserBo().updateAndSyncUserDakaStats(userId);

      final user = await db.usersDao.getUserById(userId);
      expect(user!.dakaDayCount, 3);
      expect(user.continuousDakaDayCount, 2, reason: '1/1 断档，连续段为 1/2~1/3');

      AppClock.reset();
    });
  });
}
