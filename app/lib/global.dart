import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:logger/logger.dart' as logger_pkg;
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';

import 'api/vo.dart';

class Global {
  static String version = 'NONE';
  static const Color highlight = Colors.teal;

  // 改进日志配置，确保能看到详细错误信息
  static final logger = logger_pkg.Logger(
    printer: _TimestampPrinter(),
    level: logger_pkg.Level.debug, // 使用别名避免冲突
  );
  static String commonDictId = "0"; // 通用词典ID，通用词典是一个虚拟词典，它含有不属于任何词典的单词资源
  static int localDbVersionForNewlyInstalled = 1;
  static String? currentUserId; // 当前登录用户ID
  static int userDbVersionInitial = 0; // 用户初始数据库版本
  static const String sysUserId = "15118"; // 系统用户ID，用于系统词典的所有者

  // 当前登录用户缓存
  static User? _currentUser;

  // 获取当前登录用户，直接返回缓存的用户对象
  static User? getLoggedInUser() {
    return _currentUser;
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

  // 其它级别（warning/error等）保持方法栈打印，便于排查问题
  final logger_pkg.PrettyPrinter _printerOthers = logger_pkg.PrettyPrinter(
    methodCount: 3,
    errorMethodCount: 20,
    lineLength: 120,
    colors: false, // 关闭颜色避免 ANSI 转义序列
    printEmojis: true,
    dateTimeFormat: logger_pkg.DateTimeFormat.none,
  );

  @override
  List<String> log(logger_pkg.LogEvent event) {
    final now = AppClock.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final isInfoOrDebug = event.level == logger_pkg.Level.info ||
        event.level == logger_pkg.Level.debug;
    final prettyOutput =
        (isInfoOrDebug ? _printerInfoDebug : _printerOthers).log(event);

    // 在每一行前面添加时分秒时间戳
    return prettyOutput.map((line) => '[$timestamp] $line').toList();
  }
}
