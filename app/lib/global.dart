import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:logger/logger.dart' as logger_pkg;
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/analytics_util.dart';
import 'package:nnbdc/util/platform_util.dart';

import 'api/vo.dart';



class Global {
  static String get appName => PlatformUtils.isAndroid ? '牛牛背单词' : '泡泡单词';
  static String version = 'NONE';
  static const Color highlight = Colors.teal;

  /// 启动/初始化阶段错误（用于在启动页展示，而不是toast）
  static final ValueNotifier<String?> startupError = ValueNotifier<String?>(null);

  /// 全局 API 请求计数（用于在后台显示加载状态，而不阻塞用户操作）
  static final ValueNotifier<int> activeRequestCount = ValueNotifier<int>(0);

  /// 词表管理页面脏标志：产生新错词时置为 true，数据更新后置为 false
  static final ValueNotifier<bool> wordListsPageIsDirty = ValueNotifier<bool>(false);



  static void setStartupError(String message) {
    startupError.value = message;
  }

  static void clearStartupError() {
    startupError.value = null;
  }

  // 改进日志配置，确保能看到详细错误信息
  static final logger = logger_pkg.Logger(
    printer: _TimestampPrinter(),
    level: logger_pkg.Level.debug, // 使用别名避免冲突
  );
  static String commonDictId = "0"; // 通用词典ID，通用词典是一个虚拟词典，它含有不属于任何词典的单词资源
  static int localDbVersionForNewlyInstalled = 0; // 新安装或清空数据库后的初始版本，设为0以获取所有历史数据
  static String? currentUserId; // 当前登录用户ID
  static int userDbVersionInitial = 0; // 用户初始数据库版本
  static const String sysUserId = "15118"; // 系统用户ID，用于系统词典的所有者

  // 当前登录用户缓存
  static User? _currentUser;

  // 获取当前登录用户，直接返回缓存的用户对象
  static User? getLoggedInUser() {
    return _currentUser;
  }

  static User getLoggedInUserNotNull() {
    if (_currentUser == null) {
      Global.logger.d('用户未登录');
      ToastUtil.error('请先登录');
      throw Exception('用户未登录');
    }
    return _currentUser!;
  }

  // 从数据库异步加载用户并更新缓存
  static Future<User?> loadUserFromDb() async {
    // 从local storage中获取当前登录用户ID
    String? userId = GetStorage().read<String>("currentUserId");
    if (userId == null) {
      _currentUser = null;
      return null;
    }

    // 从本地数据库获取用户信息
    final db = MyDatabase.instance;
    _currentUser = await db.usersDao.getUserById(userId);
    return _currentUser;
  }

  static Future<UserVo?> refreshLoggedInUser() async {
    var result = await UserBo().getLoggedInUser();
    if (result.success) {
      await setLoggedInUser(result.data!);
      return result.data;
    }
    return null;
  }

  // 设置用户信息
  static Future<void> setLoggedInUser(UserVo user) async {
    // 保存用户ID到local storage
    await GetStorage().write("currentUserId", user.id);
    currentUserId = user.id; // 更新当前登录用户ID

    // 重新从数据库加载用户信息到缓存
    await loadUserFromDb();
  }

  // 清除用户缓存
  static void clearUserCache() {
    _currentUser = null;
  }

  // 更新用户缓存
  static void updateUserCache(User user) {
    _currentUser = user;
  }

  // 访客相关
  static const String guestId = "guest";
  static bool get isGuest => currentUserId == guestId;

  // 访客登录
  static Future<void> loginAsGuest() async {
    final now = AppClock.now();
    // 创建访客用户Vo
    final guestVo = UserVo(guestId, 'guest@nnbdc.com');
    // 设置其他属性
    guestVo.nickName = '游客';
    guestVo.displayNickName = '游客';
    guestVo.email = 'guest@nnbdc.com';
    guestVo.lastLoginTime = now;
    guestVo.wordsPerDay = 20;
    guestVo.totalScore = 0;

    // 初始化其他必要字段，防止 userVo2User 转换时通过 ! 强转空值导致 crash
    guestVo.cowDung = 0;
    guestVo.gameScore = 0;
    guestVo.inviteAwardTaken = false;
    guestVo.isAdmin = false;
    guestVo.isInputor = false;
    guestVo.isSuperAdmin = false;

    guestVo.learnedDays = 0;
    guestVo.learningFinished = false;
    guestVo.masteredWordsCount = 0;
    guestVo.maxContinuousDakaDayCount = 0;
    guestVo.throwDiceChance = 0;
    guestVo.isPremiumIos = false;
    guestVo.premiumOverrideEnabled = false;

    // missing initialized fields fix null exceptions
    guestVo.continuousDakaDayCount = 0;
    guestVo.dakaDayCount = 0;
    guestVo.dakaScore = 0; 

    // 保存到本地数据库
    final db = MyDatabase.instance;
    await db.usersDao.saveUser(userVo2User(guestVo), false);

    // 为访客创建"生词本"和"已掌握"词书（与后端 createNewUser 对齐）
    // 仅在首次创建访客时生成，避免重复登录时产生重复词书
    final existingRawDict = await db.dictsDao.findUserRawDict(guestId);
    if (existingRawDict == null) {
      final rawDictId = Util.uuid();
      final rawDict = Dict(
        id: rawDictId,
        isReady: true,
        isShared: false,
        name: '生词本',
        wordCount: 0,
        ownerId: guestId,
        visible: true,
        editable: true,
        deletable: false,
        createTime: now,
        updateTime: now,
      );
      await db.dictsDao.saveEntity(rawDict, false);
      logger.i('已为访客创建生词本: id=$rawDictId');
    }

    final existingMasteredDict = await db.dictsDao.findUserMasteredDict(guestId);
    if (existingMasteredDict == null) {
      final masteredDictId = Util.uuid();
      final masteredDict = Dict(
        id: masteredDictId,
        isReady: true,
        isShared: false,
        name: '已掌握',
        wordCount: 0,
        ownerId: guestId,
        visible: true,
        editable: false,
        deletable: false,
        createTime: now,
        updateTime: now,
      );
      await db.dictsDao.saveEntity(masteredDict, false);
      logger.i('已为访客创建已掌握词书: id=$masteredDictId');
    }

    // 为访客初始化学习步骤（与后端 createNewUser 对齐）
    // 仅在首次创建访客时生成，避免重复登录时产生重复记录
    final existingSteps = await db.userStudyStepsDao.getUserStudySteps(guestId);
    if (existingSteps.isEmpty) {
      final newSteps = [
        UserStudyStep(
          userId: guestId,
          studyStep: 'En2Ch',
          seq: 0,
          state: 'Active',
          createTime: now,
        ),
        UserStudyStep(
          userId: guestId,
          studyStep: 'Ch2En',
          seq: 1,
          state: 'Active',
          createTime: now,
        ),
        UserStudyStep(
          userId: guestId,
          studyStep: 'List',
          seq: 2,
          state: 'Active',
          createTime: now,
        ),
      ];
      await db.batch((batch) {
        batch.insertAll(db.userStudySteps, newSteps);
      });
      logger.i('已为访客初始化学习步骤');
    }

    // 设置为当前登录用户
    await setLoggedInUser(guestVo);
    
    // 漏斗：无痛登入（游客登录完成）
    AnalyticsUtil.trackLogin('guest', true);
  }
}

/// 自定义的带时间戳的日志打印器
class _TimestampPrinter extends logger_pkg.LogPrinter {
  // info/debug：不打印方法栈，且不使用边框，关闭颜色避免 ANSI 转义序列
  final logger_pkg.PrettyPrinter _printerInfoDebug = logger_pkg.PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 0,
    lineLength: 120,
    colors: false,
    printEmojis: true,
    noBoxingByDefault: true,
    dateTimeFormat: logger_pkg.DateTimeFormat.none,
  );

  // 其它级别（warning/error等）保持方法栈打印，更加紧凑，禁用边框
  final logger_pkg.PrettyPrinter _printerOthers = logger_pkg.PrettyPrinter(
    methodCount: 2, // 减少调用栈行数
    errorMethodCount: 8, // 异常栈行数
    lineLength: 80, // 标准行宽
    colors: false, // 关闭颜色避免 ANSI 转义序列
    printEmojis: true,
    noBoxingByDefault: true, // 禁用边框，让日志更像 Java
    dateTimeFormat: logger_pkg.DateTimeFormat.none,
  );

  @override
  List<String> log(logger_pkg.LogEvent event) {
    final now = AppClock.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final isInfoOrDebug = event.level == logger_pkg.Level.info || event.level == logger_pkg.Level.debug;
    final prettyOutput = (isInfoOrDebug ? _printerInfoDebug : _printerOthers).log(event);

    // 在每一行前面添加时分秒时间戳
    return prettyOutput.map((line) => '[$timestamp] $line').toList();
  }
}
