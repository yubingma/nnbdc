import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:logger/logger.dart' as logger_pkg;
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/analytics_util.dart';

import 'api/vo.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/api/bo/study_bo.dart';



class Global {
  static String get appName => '泡泡单词';
  static String version = 'NONE';
  static String buildNumber = 'NONE';
  static const Color highlight = Colors.teal;

  /// 启动/初始化阶段错误（用于在启动页展示，而不是toast）
  static final ValueNotifier<String?> startupError = ValueNotifier<String?>(null);

  /// 全局 API 请求计数（用于在后台显示加载状态，而不阻塞用户操作）
  static final ValueNotifier<int> activeRequestCount = ValueNotifier<int>(0);

  /// 词表管理页面脏标志：产生新错词时置为 true，数据更新后置为 false
  static final ValueNotifier<bool> wordListsPageIsDirty = ValueNotifier<bool>(false);
  static Stopwatch openPencilStopwatch = Stopwatch();



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
    try {
      // 从local storage中获取当前登录用户ID
      String? userId = Prefs.read<String>("currentUserId");
      if (userId == null) {
        _currentUser = null;
        return null;
      }

      // 从本地数据库获取用户信息
      final db = MyDatabase.instance;
      _currentUser = await db.usersDao.getUserById(userId);
      if (_currentUser != null) {
        currentUserId = _currentUser!.id;
      }
      return _currentUser;
    } catch (e, stackTrace) {
      Global.logger.e('loadUserFromDb 失败: $e', error: e, stackTrace: stackTrace);
      _currentUser = null;
      return null;
    }
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
    // 如果切换了用户，重置 API 客户端和 Socket，清除旧会话
    if (currentUserId != null && currentUserId != user.id) {
      Api.resetClient();
      SocketIoClient.instance.reset();
      Global.logger.i('检测到用户切换: $currentUserId -> ${user.id}，已重置会话');
    }

    // 保存用户ID到local storage
    await Prefs.write("currentUserId", user.id);
    currentUserId = user.id; // 更新当前登录用户ID

    // 重新从数据库加载用户信息到缓存
    await loadUserFromDb();
  }

  // 登出并清除所有会话状态
  static Future<void> logout() async {
    // 1. 清除本地存储的当前用户ID
    await Prefs.remove("currentUserId");
    currentUserId = null;
    
    // 2. 清除全局用户缓存
    _currentUser = null;
    
    // 3. 重置 API 客户端，清除 Cookie 和会话状态
    Api.resetClient();
    
    // 4. 重置 Socket 连接状态
    SocketIoClient.instance.reset();

    // 5. 清理业务缓存与同步服务，防止旧账号任务残留
    ThrottledDbSyncService().reset();
    StudyBo.clearUserCaches();
    
    Global.logger.i('用户已登出，会话与业务缓存已清除');
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

    // 三组结构下访客无需初始化学习步骤：表空时运行时使用默认三组（StudyStepsService.getThreeGroupConfig）

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
