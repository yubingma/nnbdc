import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/db/user_extensions.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/user_privilege_manager.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

User _buildTestUser({
  required String id,
  required String userName,
  int wordsPerDay = 20,
  bool isAdmin = false,
  bool isSuperAdmin = false,
}) {
  final now = DateTime.now();
  return User(
    id: id,
    userName: userName,
    wordsPerDay: wordsPerDay,
    gameScore: 0,
    dakaScore: 0,
    learnedDays: 0,
    dakaDayCount: 0,
    continuousDakaDayCount: 0,
    maxContinuousDakaDayCount: 0,
    masteredWordsCount: 0,
    cowDung: 0,
    throwDiceChance: 0,
    todayStudyStarted: false,
    learningFinished: false,
    isAdmin: isAdmin,
    isSuperAdmin: isSuperAdmin,
    createTime: now,
    updateTime: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
    MyDatabase.setInstanceForTesting(database);
    UserPrivilegeManager.isPremiumOverrideForTesting = null;
    UserPrivilegeManager.isIOSOverrideForTesting = null;
  });

  tearDown(() async {
    UserPrivilegeManager.isPremiumOverrideForTesting = null;
    UserPrivilegeManager.isIOSOverrideForTesting = null;
    await database.close();
  });

  group('UserPrivilegeManager - 单词配额与加量权限测试', () {
    test('非会员每日单词上限为20，超额拦截与截断', () {
      UserPrivilegeManager.isPremiumOverrideForTesting = false;

      expect(UserPrivilegeManager.isPremium, isFalse);
      expect(UserPrivilegeManager.maxDailyWords, equals(20));

      expect(UserPrivilegeManager.isDailyWordsAllowed(10), isTrue);
      expect(UserPrivilegeManager.isDailyWordsAllowed(20), isTrue);
      expect(UserPrivilegeManager.isDailyWordsAllowed(21), isFalse);
      expect(UserPrivilegeManager.isDailyWordsAllowed(50), isFalse);

      expect(UserPrivilegeManager.sanitizeDailyWords(50), equals(20));
      expect(UserPrivilegeManager.sanitizeDailyWords(15), equals(15));
      expect(UserPrivilegeManager.sanitizeDailyWords(0), equals(0));

      expect(UserPrivilegeManager.canExtraStudy, isFalse);
    });

    test('会员无每日单词上限，支持加量', () {
      UserPrivilegeManager.isPremiumOverrideForTesting = true;

      expect(UserPrivilegeManager.isPremium, isTrue);
      expect(UserPrivilegeManager.maxDailyWords, equals(99999));

      expect(UserPrivilegeManager.isDailyWordsAllowed(20), isTrue);
      expect(UserPrivilegeManager.isDailyWordsAllowed(50), isTrue);
      expect(UserPrivilegeManager.isDailyWordsAllowed(200), isTrue);

      expect(UserPrivilegeManager.sanitizeDailyWords(50), equals(50));
      expect(UserPrivilegeManager.sanitizeDailyWords(100), equals(100));

      expect(UserPrivilegeManager.canExtraStudy, isTrue);
    });
  });

  group('UserPrivilegeManager - 自定义词书权限测试', () {
    test('非 iOS 平台对所有用户开放自定义词书', () {
      UserPrivilegeManager.isIOSOverrideForTesting = false;

      // 无论非会员还是会员均开放
      UserPrivilegeManager.isPremiumOverrideForTesting = false;
      expect(UserPrivilegeManager.canManageCustomDict, isTrue);

      UserPrivilegeManager.isPremiumOverrideForTesting = true;
      expect(UserPrivilegeManager.canManageCustomDict, isTrue);
    });

    test('iOS 平台仅对会员开放自定义词书', () {
      UserPrivilegeManager.isIOSOverrideForTesting = true;

      UserPrivilegeManager.isPremiumOverrideForTesting = false;
      expect(UserPrivilegeManager.canManageCustomDict, isFalse);

      UserPrivilegeManager.isPremiumOverrideForTesting = true;
      expect(UserPrivilegeManager.canManageCustomDict, isTrue);
    });
  });

  group('UserPrivilegeManager - AI 助手权限测试', () {
    test('普通用户非会员不可用，会员或管理员可用', () {
      final normalUser = _buildTestUser(id: 'user_1', userName: 'normal_user');
      Global.updateUserCache(normalUser);

      // 非会员普通用户
      UserPrivilegeManager.isPremiumOverrideForTesting = false;
      expect(UserPrivilegeManager.canUseAiAssistant, isFalse);

      // 会员普通用户
      UserPrivilegeManager.isPremiumOverrideForTesting = true;
      expect(UserPrivilegeManager.canUseAiAssistant, isTrue);

      // 非会员管理员用户
      UserPrivilegeManager.isPremiumOverrideForTesting = false;
      final adminUser = normalUser.copyWith(isAdmin: const Value(true));
      Global.updateUserCache(adminUser);
      expect(UserPrivilegeManager.canUseAiAssistant, isTrue);

      // 非会员超级管理员用户
      final superAdminUser = normalUser.copyWith(isAdmin: const Value(false), isSuperAdmin: const Value(true));
      Global.updateUserCache(superAdminUser);
      expect(UserPrivilegeManager.canUseAiAssistant, isTrue);
    });
  });

  group('UserPrivilegeManager - UserExtensions 与 UserVo 适配集成测试', () {
    test('UserExtensions.effectiveWordsPerDay 联动权限管理器', () {
      final user = _buildTestUser(id: 'u1', userName: 'u1', wordsPerDay: 50);

      UserPrivilegeManager.isPremiumOverrideForTesting = false;
      expect(user.effectiveWordsPerDay, equals(20));

      UserPrivilegeManager.isPremiumOverrideForTesting = true;
      expect(user.effectiveWordsPerDay, equals(50));
    });

    test('UserVo.effectiveWordsPerDay 联动权限管理器', () {
      final userVo = UserVo.c2('u1');
      userVo.wordsPerDay = 50;

      UserPrivilegeManager.isPremiumOverrideForTesting = false;
      expect(userVo.effectiveWordsPerDay, equals(20));

      UserPrivilegeManager.isPremiumOverrideForTesting = true;
      expect(userVo.effectiveWordsPerDay, equals(50));
    });
  });

  group('UserPrivilegeManager - checkAndEnforceMemberLimits 强制执行', () {
    test('非会员设置50词时被强制缩减回20词', () async {
      final user = _buildTestUser(id: 'user_limit_test', userName: 'limit_user', wordsPerDay: 50);
      await database.usersDao.saveUser(user, false);
      Global.updateUserCache(user);

      UserPrivilegeManager.isPremiumOverrideForTesting = false;

      await UserPrivilegeManager.checkAndEnforceMemberLimits();

      final updated = Global.getLoggedInUser();
      expect(updated?.wordsPerDay, equals(20));

      final dbUser = await database.usersDao.getUserById('user_limit_test');
      expect(dbUser?.wordsPerDay, equals(20));
    });

    test('会员设置50词时不被缩减', () async {
      final user = _buildTestUser(id: 'vip_limit_test', userName: 'vip_user', wordsPerDay: 50);
      await database.usersDao.saveUser(user, false);
      Global.updateUserCache(user);

      UserPrivilegeManager.isPremiumOverrideForTesting = true;

      await UserPrivilegeManager.checkAndEnforceMemberLimits();

      final updated = Global.getLoggedInUser();
      expect(updated?.wordsPerDay, equals(50));

      final dbUser = await database.usersDao.getUserById('vip_limit_test');
      expect(dbUser?.wordsPerDay, equals(50));
    });
  });
}
