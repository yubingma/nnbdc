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
import 'package:drift/drift.dart' hide isNotNull;
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
    final createTime = DateUtils.businessDate(now).subtract(const Duration(days: 6));
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

  group('打卡统计推导 (多端一致性)', () {
    test('从本机 dakas 表幂等推导：3 天打卡 → 天数=3、打卡率=3/7', () async {
      final today = DateUtils.businessDate(AppClock.now());
      await addDaka(today);
      await addDaka(today.subtract(const Duration(days: 1)));
      await addDaka(today.subtract(const Duration(days: 2)));

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
      await addDaka(today.subtract(const Duration(days: 1)));
      await addDaka(today.subtract(const Duration(days: 2)));

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
      await addDaka(today.subtract(const Duration(days: 1)));

      await UserBo().updateAndSyncUserDakaStats(userId);
      final first = await db.usersDao.getUserById(userId);

      await UserBo().updateAndSyncUserDakaStats(userId);
      final second = await db.usersDao.getUserById(userId);

      expect(second!.dakaDayCount, first!.dakaDayCount);
      expect(second.continuousDakaDayCount, first.continuousDakaDayCount);
      expect(second.dakaRatio, first.dakaRatio);
    });
  });
}
