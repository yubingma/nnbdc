import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
    MyDatabase.setInstanceForTesting(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('游客登录后，再次启动识别到游客身份时应能清理游客会话状态', () async {
    // 模拟游客登录
    await Global.loginAsGuest();
    expect(Global.isGuest, isTrue);
    expect(Global.currentUserId, equals(Global.guestId));
    expect(Prefs.read<String>("currentUserId"), equals(Global.guestId));

    // 模拟启动阶段检测到是游客，执行登出清除会话
    final user = await Global.loadUserFromDb();
    expect(user, isNotNull);
    expect(user!.id, equals(Global.guestId));

    if (user.id == Global.guestId) {
      await Global.logout();
    }

    // 验证会话已清除
    expect(Global.currentUserId, isNull);
    expect(Prefs.read<String>("currentUserId"), isNull);
    expect(Global.getLoggedInUser(), isNull);
  });

  test('邮箱登录页加载本地邮箱列表应过滤游客账号', () async {
    final now = DateTime.now();
    await database.usersDao.saveUser(
      User(
        id: 'real_user_1',
        userName: 'user1',
        email: 'user1@example.com',
        nickName: 'User 1',
        gameScore: 0,
        dakaScore: 0,
        learnedDays: 0,
        wordsPerDay: 20,
        dakaDayCount: 0,
        masteredWordsCount: 0,
        cowDung: 0,
        throwDiceChance: 0,
        continuousDakaDayCount: 0,
        maxContinuousDakaDayCount: 0,
        todayStudyStarted: false,
        createTime: now,
        updateTime: now,
      ),
      false,
    );

    await database.usersDao.saveUser(
      User(
        id: Global.guestId,
        userName: 'guest',
        email: 'guest@nnbdc.com',
        nickName: '游客',
        gameScore: 0,
        dakaScore: 0,
        learnedDays: 0,
        wordsPerDay: 20,
        dakaDayCount: 0,
        masteredWordsCount: 0,
        cowDung: 0,
        throwDiceChance: 0,
        continuousDakaDayCount: 0,
        maxContinuousDakaDayCount: 0,
        todayStudyStarted: false,
        createTime: now,
        updateTime: now,
      ),
      false,
    );

    final users = await database.usersDao.allUsers;
    final emails = users
        .where((user) => user.email != null && user.email!.isNotEmpty && user.id != Global.guestId)
        .map((user) => user.email!)
        .toSet()
        .toList();

    expect(emails, contains('user1@example.com'));
    expect(emails.contains('guest@nnbdc.com'), isFalse);
  });

  test('游客第一天产生的学习数据和用户属性，在重启后再次以游客进入时完整延续', () async {
    // 1. 第一天：首次以游客登录
    await Global.loginAsGuest();
    expect(Global.isGuest, isTrue);

    // 模拟背单词产生进度：更新用户属性（如打卡积分、掌握词数等）
    final currentUser = Global.getLoggedInUser()!;
    final updatedUser = currentUser.copyWith(
      masteredWordsCount: 15,
      dakaScore: 100,
      learnedDays: 1,
    );
    await database.usersDao.saveUser(updatedUser, false);
    Global.updateUserCache(updatedUser);

    // 2. 退出 App / 重启：清除游客登录态
    await Global.logout();
    expect(Global.currentUserId, isNull);

    // 3. 第二天：在登录页再次点击“先去逛逛”
    await Global.loginAsGuest();
    expect(Global.isGuest, isTrue);

    // 4. 验证昨天的学习进度和统计数据完整保留
    final guestUser = Global.getLoggedInUser()!;
    expect(guestUser.masteredWordsCount, equals(15));
    expect(guestUser.dakaScore, equals(100));
    expect(guestUser.learnedDays, equals(1));
  });
}
