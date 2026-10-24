import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/game.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 书桌已有词书，但乐园的「自选词书针对特训」提示书桌为空。
///
/// 根因：本页与词表页在启动时一起构建，登录后的首次同步晚于本页 initState，
/// 只读一次就会把"同步前书桌为空"的瞬间永久缓存。此用例模拟"页面初始化后
/// 词书才落库"，验证进入乐园时重读能立刻恢复。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MyDatabase db;
  const String userId = 'game_dict_test_user';
  final DateTime now = AppClock.now();

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    Global.clearUserCache();

    await db.into(db.users).insert(User(
          id: userId,
          userName: 'game_tester',
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
          wordsPerDay: 20,
          dakaDayCount: 0,
          masteredWordsCount: 0,
          maxContinuousDakaDayCount: 0,
          continuousDakaDayCount: 0,
          todayStudyStarted: false,
          totalLearningSeconds: 0,
          todayLearningSeconds: 0,
          createTime: now,
          updateTime: now,
        ));

    // 词书元数据已在本地（系统数据同步结果），但书桌关系还没同步下来
    await db.into(db.dicts).insert(DictsCompanion.insert(
          id: 'dict_cet4',
          name: '四级高频词汇',
          wordCount: 580,
          isReady: true,
          isShared: true,
          visible: true,
          ownerId: const Value(Global.sysUserId),
          createTime: now,
        ));

    SharedPreferences.setMockInitialValues({'currentUserId': userId});
    await Prefs.init();
    await Global.loadUserFromDb();
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildPage() {
    return ChangeNotifierProvider<DarkMode>(
      create: (_) => DarkMode(),
      child: const MaterialApp(home: GamePage()),
    );
  }

  testWidgets('书桌词书在页面初始化后才写入时，重读书桌即可选到', (tester) async {
    await tester.pumpWidget(buildPage());
    // 页面 initState 里的大厅请求在测试环境会拿到 400；
    // 推进两帧让 Dio 的零时定时器与错误上报收尾，避免残留 pending timer。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('《点击选择特训词书》'), findsOneWidget,
        reason: '初始化时书桌关系尚未落库，快照应为空（复现现场）');

    final GamePageState gamePage =
        tester.state<GamePageState>(find.byType(GamePage));

    // 模拟登录后的首次同步把书桌关系写进了本地库；
    // 用 runAsync 在真实异步里推进，避免与页面错误上报的数据库写入互相卡住。
    await tester.runAsync(() async {
      await db.learningDictsDao.saveEntity(
          LearningDict(
            userId: userId,
            dictId: 'dict_cet4',
            isPrivileged: false,
            fetchMastered: false,
            sortAlg: 'ORIGINAL',
            createTime: now,
            updateTime: now,
          ),
          false);

      // 模拟用户切回乐园（IndexPage 会调用 refreshTrainingDicts）
      await gamePage.refreshTrainingDicts();
    });
    await tester.pump();

    expect(find.text('《四级高频词汇》'), findsOneWidget,
        reason: '进入乐园必须按最新书桌刷新，不能继续展示启动时的空快照');
    expect(find.text('《点击选择特训词书》'), findsNothing);
  });
}
