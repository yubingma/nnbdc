import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/badge_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/date_utils.dart' as du;
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();
  const userId = 'badge_test_user';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  Future<User> createUser({
    int masteredWordsCount = 0,
    int streakDays = 0,
    int maxStreakDays = -1,
    int cowDung = 0,
  }) async {
    final user = User(
      id: userId,
      userName: 'badge_user',
      password: '',
      nickName: 'Badge',
      email: '',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 0,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: cowDung,
      throwDiceChance: 0,
      wordsPerDay: 20,
      dakaDayCount: streakDays,
      masteredWordsCount: masteredWordsCount,
      continuousDakaDayCount: streakDays,
      maxContinuousDakaDayCount: maxStreakDays < 0 ? streakDays : maxStreakDays,
      todayStudyStarted: false,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    return user;
  }

  /// 写入今日评分日志(按传入顺序即时间顺序)
  Future<void> insertTodayRatings(List<int> ratings) async {
    for (var i = 0; i < ratings.length; i++) {
      final time = AppClock.today().add(Duration(seconds: i + 1));
      await db.learningLogsDao.saveEntity(
        LearningLog(
          id: 'log_$i',
          userId: userId,
          wordId: 'word_$i',
          rating: ratings[i],
          stability: 1,
          difficulty: 5,
          elapsedDays: 0,
          scheduledDays: 1,
          createTime: time,
          updateTime: time,
        ),
        false,
      );
    }
  }

  /// 把"已掌握"词书填充到指定词条数(updateUserMasteredWordCount 的唯一事实源)
  Future<void> setMasteredDictCount(int count) async {
    var dict = await db.dictsDao.findUserMasteredDict(userId);
    if (dict == null) {
      await db.into(db.dicts).insert(Dict(
        id: 'mastered_dict',
        name: '已掌握',
        wordCount: 0,
        isShared: false,
        isReady: true,
        ownerId: userId,
        visible: true,
        editable: false,
        deletable: false,
        createTime: now,
        updateTime: now,
      ));
      dict = await db.dictsDao.findUserMasteredDict(userId);
    }
    await (db.delete(db.dictWords)..where((dw) => dw.dictId.equals(dict!.id))).go();
    for (var i = 0; i < count; i++) {
      await db.into(db.dictWords).insert(DictWord(
        dictId: dict!.id,
        wordId: 'w_$i',
        seq: i,
        unit: 0,
        createTime: now,
        updateTime: now,
      ));
    }
  }

  /// 写入一条打卡记录(用于破晓/夜行勋章重放)
  Future<void> insertDaka(DateTime createTime, {int dayOffset = 0}) async {
    await db.dakasDao.saveDaka(
      Daka(
        userId: userId,
        forLearningDate: AppClock.today().subtract(Duration(days: dayOffset)),
        createTime: createTime,
        updateTime: createTime,
      ),
      false,
    );
  }

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Global.currentUserId = null;
  });

  group('词汇量勋章', () {
    test('达到阈值首次授予并发放魔法泡泡', () async {
      await createUser(masteredWordsCount: 100);

      final awarded = await BadgeService().checkMasteredWords(masteredCount: 100);

      expect(awarded.map((e) => e.badgeCode), contains('VOCAB_100'));
      final badge = await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_100');
      expect(badge, isNotNull);
      expect(badge!.obtainCount, 1);
      expect((await db.usersDao.getUserById(userId))!.cowDung, 60);
    });

    test('未达阈值不授予', () async {
      await createUser(masteredWordsCount: 99);

      final awarded = await BadgeService().checkMasteredWords(masteredCount: 99);

      expect(awarded, isEmpty);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_100'), isNull);
    });

    test('不可叠层勋章重复达标只授予一次', () async {
      await createUser(masteredWordsCount: 100);

      await BadgeService().checkMasteredWords(masteredCount: 100);
      await BadgeService().checkMasteredWords(masteredCount: 120);

      final badge = await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_100');
      expect(badge!.obtainCount, 1);
      // 第二次不应重复发放泡泡
      expect((await db.usersDao.getUserById(userId))!.cowDung, 60);
    });

    test('一次跨越多个阈值时两枚勋章都授予且泡泡累加', () async {
      await createUser(masteredWordsCount: 1000);

      final awarded = await BadgeService().checkMasteredWords(masteredCount: 1000);

      expect(awarded.map((e) => e.badgeCode), containsAll(['VOCAB_100', 'VOCAB_1000']));
      expect((await db.usersDao.getUserById(userId))!.cowDung, 60 + 200);
    });
  });

  group('可叠层勋章', () {
    test('每次达成都叠加获得次数与星级', () async {
      await createUser();

      await BadgeService().checkAndAward(conditionType: 'PERFECT_SCORE', currentValue: 1);
      await BadgeService().checkAndAward(conditionType: 'PERFECT_SCORE', currentValue: 1);

      final badge = await db.userBadgesDao.getBadgeByUserAndCode(userId, 'PERFECT_SCORE');
      expect(badge!.obtainCount, 2);
      expect(badge.starLevel, 1);
    });

    test('叠层到 10 次时升为 2 星', () async {
      await createUser();

      for (var i = 0; i < 10; i++) {
        await BadgeService().checkAndAward(conditionType: 'PERFECT_SCORE', currentValue: 1);
      }

      final badge = await db.userBadgesDao.getBadgeByUserAndCode(userId, 'PERFECT_SCORE');
      expect(badge!.obtainCount, 10);
      expect(badge.starLevel, 2);
    });
  });

  group('不可获得的勋章', () {
    test('isAvailable 为 false 的勋章即使达标也不判定', () async {
      await createUser();

      final awarded = await BadgeService().checkAndAward(
        conditionType: 'INVITE_FRIEND',
        currentValue: 1,
      );

      expect(awarded, isEmpty);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'INVITE_FRIEND'), isNull);
    });
  });

  group('单次学习表现', () {
    test('今日全程无答错则授予百发百中', () async {
      await createUser();
      await insertTodayRatings([
        FsrsRating.good.value,
        FsrsRating.easy.value,
        FsrsRating.good.value,
      ]);

      final awarded = await BadgeService().checkStudyPerformance();

      expect(awarded.map((e) => e.badgeCode), contains('PERFECT_SCORE'));
    });

    test('今日有过答错则不授予百发百中', () async {
      await createUser();
      await insertTodayRatings([
        FsrsRating.good.value,
        FsrsRating.again.value,
        FsrsRating.good.value,
      ]);

      final awarded = await BadgeService().checkStudyPerformance();

      expect(awarded.map((e) => e.badgeCode), isNot(contains('PERFECT_SCORE')));
    });

    test('连续 29 次轻松不授予极速心流, 连续 30 次才授予', () async {
      await createUser();
      await insertTodayRatings([
        FsrsRating.again.value,
        ...List.filled(29, FsrsRating.easy.value),
      ]);

      var awarded = await BadgeService().checkStudyPerformance();
      expect(awarded.map((e) => e.badgeCode), isNot(contains('EASY_FLOW')));

      await insertTodayRatings(List.filled(1, FsrsRating.easy.value));
      // 追加一条后的连续长度变为 30
      awarded = await BadgeService().checkStudyPerformance();
      expect(awarded.map((e) => e.badgeCode), contains('EASY_FLOW'));
    });
  });

  group('状态型勋章对齐补发', () {
    test('老用户历史已达标但从未判定过的勋章被静默补发', () async {
      await createUser(masteredWordsCount: 1000, streakDays: 3);

      await BadgeService().syncStateBadges();

      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_100'), isNotNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_1000'), isNotNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_3'), isNotNull);
      // 补发同样发放奖励
      expect((await db.usersDao.getUserById(userId))!.cowDung, 60 + 200 + 50);
    });

    test('未达标的勋章不会被补发', () async {
      await createUser(masteredWordsCount: 10, streakDays: 1);

      await BadgeService().syncStateBadges();

      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_100'), isNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_3'), isNull);
    });

    test('连续记录已中断的用户, 依据历史最长连续天数补发', () async {
      // 曾经连续 21 天, 但当前连续天数已归零
      await createUser(streakDays: 0, maxStreakDays: 21);

      await BadgeService().syncStateBadges();

      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_3'), isNotNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_21'), isNotNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_100'), isNull);
    });

    test('真实连续打卡 21 天全流程仿真：逐步累加并在第 21 天精准解锁，中断后勋章不撤销', () async {
      await createUser(streakDays: 0, maxStreakDays: 0);

      // 连续推进 21 天打卡
      for (var day = 1; day <= 21; day++) {
        final currentUser = (await db.usersDao.getUserById(userId))!;
        await db.usersDao.saveUser(
          currentUser.copyWith(
            dakaDayCount: day,
            continuousDakaDayCount: day,
            maxContinuousDakaDayCount: day,
          ),
          true,
        );

        // 每次打卡完成时触发连续勋章判定
        await BadgeService().checkStreakDays(celebrate: false);

        if (day < 3) {
          expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_3'), isNull);
        } else {
          expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_3'), isNotNull);
        }

        if (day < 21) {
          expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_21'), isNull);
        } else {
          expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_21'), isNotNull);
        }
      }

      // 模拟第 22 天发生漏打断签，连续天数归为 1
      final brokenUser = (await db.usersDao.getUserById(userId))!;
      await db.usersDao.saveUser(
        brokenUser.copyWith(
          continuousDakaDayCount: 1,
        ),
        true,
      );

      // 再次判定或对齐补发
      await BadgeService().checkStreakDays(celebrate: false);

      // 已解锁的 21 天勋章依旧稳固存在，绝不被撤销
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_21'), isNotNull);
    });
  });

  group('历史峰值与掌握词数', () {
    test('掌握词数回落时历史峰值只增不减', () async {
      await createUser();

      await setMasteredDictCount(1000);
      await db.masteredWordsDao.updateUserMasteredWordCount(userId);
      expect((await db.usersDao.getUserById(userId))!.maxMasteredWords, 1000);

      // 退火重学导致当前掌握数回落
      await setMasteredDictCount(400);
      await db.masteredWordsDao.updateUserMasteredWordCount(userId);

      final user = await db.usersDao.getUserById(userId);
      expect(user!.masteredWordsCount, 400);
      expect(user.maxMasteredWords, 1000);
    });

    test('掌握数回落后, 曾达标的词汇勋章仍按峰值授予且不被撤销', () async {
      await createUser();

      await setMasteredDictCount(1000);
      await db.masteredWordsDao.updateUserMasteredWordCount(userId);
      await setMasteredDictCount(400);
      await db.masteredWordsDao.updateUserMasteredWordCount(userId);

      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_100'), isNotNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_1000'), isNotNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'VOCAB_5000'), isNull);
    });
  });

  group('按事实源全量重放', () {
    test('dryRun 只诊断不落库', () async {
      await createUser();
      await insertTodayRatings([FsrsRating.good.value, FsrsRating.good.value]);

      final report = await BadgeService().rebuildBadgesFromFacts(dryRun: true);

      expect(report.granted, contains('PERFECT_SCORE'));
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'PERFECT_SCORE'), isNull);
    });

    test('重放按天累计可叠层勋章的达成次数', () async {
      await createUser();
      // 两天都是全程无答错
      for (var day = 0; day < 2; day++) {
        for (var i = 0; i < 3; i++) {
          final time = AppClock.today()
              .subtract(Duration(days: day))
              .add(Duration(seconds: i + 1));
          await db.learningLogsDao.saveEntity(
            LearningLog(
              id: 'log_${day}_$i',
              userId: userId,
              wordId: 'word_$i',
              rating: FsrsRating.good.value,
              stability: 1,
              difficulty: 5,
              elapsedDays: 0,
              scheduledDays: 1,
              createTime: time,
              updateTime: time,
            ),
            false,
          );
        }
      }

      final report = await BadgeService().rebuildBadgesFromFacts();

      expect(report.granted, contains('PERFECT_SCORE'));
      final badge = await db.userBadgesDao.getBadgeByUserAndCode(userId, 'PERFECT_SCORE');
      expect(badge!.obtainCount, 2);
    });

    test('重放补齐叠层次数差额时只补差额奖励', () async {
      await createUser(cowDung: 0);
      await insertTodayRatings([FsrsRating.good.value, FsrsRating.good.value]);

      await BadgeService().rebuildBadgesFromFacts();

      // PERFECT_SCORE 单次奖励 20, 事实为 1 次 → 只补 20
      expect((await db.usersDao.getUserById(userId))!.cowDung, 20);
    });

    test('重放只补不撤: 已持有次数高于事实值时不下调', () async {
      await createUser();
      // 只有 1 天达标, 但已记录 5 次
      await insertTodayRatings([FsrsRating.good.value]);
      await db.userBadgesDao.saveEntity(
        UserBadge(
          id: 'pre_badge',
          userId: userId,
          badgeCode: 'PERFECT_SCORE',
          obtainCount: 5,
          starLevel: 1,
          unlockedAt: now,
          isEquipped: false,
          isViewed: false,
          createTime: now,
          updateTime: now,
        ),
        false,
      );

      final report = await BadgeService().rebuildBadgesFromFacts();

      expect(report.adjusted.containsKey('PERFECT_SCORE'), isFalse);
      expect((await db.userBadgesDao.getBadgeByUserAndCode(userId, 'PERFECT_SCORE'))!.obtainCount, 5);
    });

    test('重放依据打卡时间补齐破晓/夜行勋章', () async {
      await createUser();
      await insertDaka(AppClock.today().add(const Duration(hours: 6, minutes: 30)), dayOffset: 0);
      await insertDaka(AppClock.today().add(const Duration(hours: 23, minutes: 10)), dayOffset: 1);

      final report = await BadgeService().rebuildBadgesFromFacts();

      expect(report.granted, containsAll(['DAWN_LEARN', 'NIGHT_LEARN']));
    });

    test('重放依据打卡记录重算最长连续天数', () async {
      await createUser(streakDays: 0, maxStreakDays: 0);
      // 连续 3 天打卡, 但 user 表里的最长连续字段被写坏为 0
      for (var day = 0; day < 3; day++) {
        await insertDaka(AppClock.today().add(const Duration(hours: 9)), dayOffset: day);
      }

      final report = await BadgeService().rebuildBadgesFromFacts();

      expect(report.granted, contains('STREAK_3'));
    });

    test('重放幂等: 重复执行无差异也不重复发奖', () async {
      await createUser();
      await insertTodayRatings([FsrsRating.good.value, FsrsRating.good.value]);
      await insertDaka(AppClock.today().add(const Duration(hours: 23, minutes: 10)), dayOffset: 1);

      await BadgeService().rebuildBadgesFromFacts();
      final cowDung = (await db.usersDao.getUserById(userId))!.cowDung;
      // 补发确实发放了奖励, 否则下面的"不再重复发奖"无从谈起
      expect(cowDung, greaterThan(0));

      final again = await BadgeService().rebuildBadgesFromFacts();
      expect(again.granted, isEmpty);
      expect(again.adjusted, isEmpty);
      expect((await db.usersDao.getUserById(userId))!.cowDung, cowDung);
    });
  });

  group('用户侧自愈', () {
    test('原始打卡记录缺失时, 依据 user 表缓存字段补发连续勋章', () async {
      // 只有缓存字段、没有 daka 原始记录 —— 这是纯事实源重放覆盖不到的盲区
      await createUser(streakDays: 0, maxStreakDays: 21);

      await BadgeService().healBadges();

      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_21'), isNotNull);
    });

    test('缓存字段被写坏时, 依据原始打卡记录补发连续勋章', () async {
      await createUser(streakDays: 0, maxStreakDays: 0);
      for (var day = 0; day < 21; day++) {
        await insertDaka(AppClock.today().add(const Duration(hours: 9)), dayOffset: day);
      }

      await BadgeService().healBadges();

      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_21'), isNotNull);
    });

    test('事件型勋章的历史漏发被补齐', () async {
      await createUser();
      await insertTodayRatings([FsrsRating.good.value, FsrsRating.good.value]);
      await insertDaka(AppClock.today().add(const Duration(hours: 23, minutes: 10)), dayOffset: 1);

      await BadgeService().healBadges();

      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'PERFECT_SCORE'), isNotNull);
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'NIGHT_LEARN'), isNotNull);
    });
  });

  group('业务日期与真实物理打卡时间下的勋章结算', () {
    test('夜猫子跨凌晨打卡既解锁夜行学者勋章，又按业务日期连续天数解锁萌芽初醒勋章', () async {
      await createUser(streakDays: 0, maxStreakDays: 0);

      // Day 1: 5月10日 22:00 打卡 (业务日: 5月10日)
      final t1 = DateTime(2026, 5, 10, 22, 0, 0);
      AppClock.setClock(FakeClock(t1));
      await db.dakasDao.saveDaka(
        Daka(
          userId: userId,
          forLearningDate: du.DateUtils.businessDate(t1),
          textContent: '打卡1',
          createTime: t1,
          updateTime: t1,
        ),
        false,
      );

      // Day 2: 5月12日 01:30 (凌晨夜猫子打卡, 业务日归属 5月11日)
      final t2 = DateTime(2026, 5, 12, 1, 30, 0);
      AppClock.setClock(FakeClock(t2));
      await db.dakasDao.saveDaka(
        Daka(
          userId: userId,
          forLearningDate: du.DateUtils.businessDate(t2),
          textContent: '打卡2',
          createTime: t2,
          updateTime: t2,
        ),
        false,
      );

      // Day 3: 5月12日 03:30 (过了凌晨3点, 业务日归属 5月12日)
      final t3 = DateTime(2026, 5, 12, 3, 30, 0);
      AppClock.setClock(FakeClock(t3));
      await db.dakasDao.saveDaka(
        Daka(
          userId: userId,
          forLearningDate: du.DateUtils.businessDate(t3),
          textContent: '打卡3',
          createTime: t3,
          updateTime: t3,
        ),
        false,
      );

      // 执行事实源重放/勋章自愈
      await BadgeService().rebuildBadgesFromFacts();

      // 验证：
      // 1. 连续 3 个业务日打卡(5月10日, 5月11日, 5月12日)，精准解锁连续 3 天勋章 STREAK_3
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'STREAK_3'), isNotNull);

      // 2. 在 01:30 和 03:30 打卡（落在 23:00~次日04:00 之间），精准解锁 NIGHT_LEARN
      expect(await db.userBadgesDao.getBadgeByUserAndCode(userId, 'NIGHT_LEARN'), isNotNull);

      AppClock.reset();
    });
  });
}
