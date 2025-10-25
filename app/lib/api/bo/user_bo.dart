import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/sync.dart' as dbsync;
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/util/oper_type.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/util/client_type.dart';

class UserBo {
  static final UserBo _instance = UserBo._internal();
  factory UserBo() => _instance;
  UserBo._internal();

  Future<Result<UserVo>> checkUser(
      CheckBy checkBy,
      String? email,
      String? userName,
      String password,
      String clientType,
      String clientVersion) async {
    try {
      // 在正式进入系统前, 首先同步系统数据库, 因为系统数据更加基础
      try {
        await dbsync.syncSysDb();
      } catch (e, stackTrace) {
        ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: 'syncSysDb in checkUser', showToast: false);
      }

      final db = MyDatabase.instance;
      User? user;

      if (checkBy == CheckBy.email && email != null && email.isNotEmpty) {
        user = await db.usersDao.getUserByEmail(email);
        if (user == null) {
          final result = await Api.client.checkUser(checkBy.json, email,
              userName, password, clientType, clientVersion);
          if (result.success) {
            final userVo = UserVo.fromJson(result.data as Map<String, dynamic>);
            userVo.password = password;
            userVo.lastLoginTime = AppClock.now();
            await db.usersDao.saveUser(userVo2User(userVo), false);
            Global.currentUserId = userVo.id;
            final ret = Result<UserVo>("SUCCESS", "登录成功", true);
            ret.data = userVo;
            return ret;
          } else {
            ToastUtil.error(result.msg ?? '登录失败');
            final ret = Result<UserVo>("ERROR", result.msg ?? "登录失败", false);
            ret.data = null;
            return ret;
          }
        }
      } else if (checkBy == CheckBy.userName && userName != null) {
        user = await db.usersDao.getUserByUserName(userName);
        if (user == null) {
          final result = Result<UserVo>("ERROR", "用户不存在", false);
          result.data = null;
          return result;
        }
      } else {
        final result =
            Result<UserVo>("ERROR", "登录参数(checkBy=$checkBy)无效！", false);
        result.data = null;
        return result;
      }

      if (user.password != password) {
        final result = Result<UserVo>("ERROR", "密码错误", false);
        result.data = null;
        return result;
      }

      try {
        // 统一通过节流服务触发同步
        ThrottledDbSyncService().requestSync();
      } catch (e, stackTrace) {
        ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: 'syncUserDb in checkUser', showToast: false);
      }

      final now = AppClock.now();
      await db.usersDao
          .saveUser(user.copyWith(lastLoginTime: Value(now)), true);
      Global.currentUserId = user.id;

      final userVo = UserVo.fromUser(user);
      userVo.password = password;
      userVo.lastLoginTime = now;

      final result = Result<UserVo>("SUCCESS", "登录成功", true);
      result.data = userVo;
      return result;
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'checkUser');
      final result = Result<UserVo>("ERROR", "登录失败，请稍后重试", false);
      result.data = null;
      return result;
    }
  }

  Future<Result<UserVo>> getLoggedInUser() async {
    try {
      final db = MyDatabase.instance;
      User? user;

      if (Global.currentUserId != null) {
        user = await db.usersDao.getUserById(Global.currentUserId!);
      }

      if (user == null) {
        try {
          final allUsers = await db.usersDao.allUsers;
          Global.logger.d('getLoggedInUser: 数据库中共有${allUsers.length}个用户');
          for (final u in allUsers) {
            Global.logger.d('getLoggedInUser: 用户 ${u.id}, ${u.userName}');
          }

          user = await db.usersDao.getLastLoggedInUser();
          Global.logger.d(
              'getLoggedInUser: 通过lastLoggedInUser获取用户 ${user?.id}, ${user?.userName}');
        } catch (e, stackTrace) {
          ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: 'getUserInfo in getLoggedInUser', showToast: false);
        }
      }

      if (user != null) {
        try {
          final userVo = UserVo.fromUser(user);

          final levelVo = LevelVo(user.levelId);
          levelVo.name = "默认等级";
          userVo.level = levelVo;

          final today = DateTime(
              AppClock.now().year, AppClock.now().month, AppClock.now().day);
          userVo.hasDakaToday =
              await db.dakasDao.findById(user.id, today) != null;

          Global.currentUserId = user.id;

          final result = Result<UserVo>("SUCCESS", "获取成功", true);
          result.data = userVo;
          return result;
        } catch (e, stackTrace) {
          ErrorHandler.handleError(e, stackTrace, logPrefix: 'getLoggedInUser: 构造UserVo对象失败', showToast: false);
          rethrow;
        }
      }

      final result = Result<UserVo>("401", "用户未登录", false);
      result.data = null;
      return result;
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'getLoggedInUser', showToast: false);
      final result =
          Result<UserVo>("ERROR", "获取用户信息失败，请稍后重试", false);
      result.data = null;
      return result;
    }
  }

  Future<Result> getPwd(String email) async {
    return await Api.client.getPwd(email);
  }

  Future<Result<List<String>>> getDayStatuses(int recentNDays) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getLastLoggedInUser();
    if (user == null || user.id.isEmpty) {
      final result = Result<List<String>>("ERROR", "用户未登录", false);
      result.data = null;
      return result;
    }

    final userId = user.id;
    final endDate =
        DateTime(AppClock.now().year, AppClock.now().month, AppClock.now().day);
    final startDate = endDate.subtract(Duration(days: recentNDays - 1));

    final List<UserDayStatus> dayStatuses =
        List.filled(recentNDays, UserDayStatus.notLogin);

    final allOpers = await db.userOpersDao.getUserOpers(userId);

    final filteredOpers = allOpers.where((hist) {
      final operDate =
          DateTime(hist.operTime.year, hist.operTime.month, hist.operTime.day);
      return operDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
          operDate.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();

    final Map<DateTime, Set<String>> dateOperMap = {};
    for (final hist in filteredOpers) {
      final operDate =
          DateTime(hist.operTime.year, hist.operTime.month, hist.operTime.day);
      dateOperMap.putIfAbsent(operDate, () => {}).add(hist.operType);
    }

    for (int i = 0; i < recentNDays; i++) {
      final date = startDate.add(Duration(days: i));
      final operTypes = dateOperMap[date] ?? {};

      if (operTypes.contains(OperType.daka.value)) {
        dayStatuses[i] = UserDayStatus.dakaed;
      } else if (operTypes.contains(OperType.startLearn.value)) {
        dayStatuses[i] = UserDayStatus.studied;
      } else if (operTypes.contains(OperType.login.value)) {
        dayStatuses[i] = UserDayStatus.loggedIn;
      }
    }

    final List<String> result =
        dayStatuses.map((status) => status.json).toList();
    final ret = Result<List<String>>("SUCCESS", "获取成功", true);
    ret.data = result;
    return ret;
  }

  Future<Result<bool>> hasDakaToday(String userId) async {
    try {
      final db = MyDatabase.instance;
      final today = DateTime(
          AppClock.now().year, AppClock.now().month, AppClock.now().day);
      final hasDakaToday = await db.dakasDao.findById(userId, today) != null;
      final result = Result<bool>("SUCCESS", "获取成功", true);
      result.data = hasDakaToday;
      return result;
    } catch (e) {
      final result = Result<bool>("ERROR", "查询打卡状态失败: ${e.toString()}", false);
      result.data = null;
      return result;
    }
  }

  Future<User?> getUserInfo() async => Global.getLoggedInUser();

  Future<String?> getUserId() async => Global.getLoggedInUser()?.id;


  Future<Result> sendAdvice(String content, String userId) async {
    return await Api.client.sendAdvice(content, getClientType().name, userId);
  }

  Future<Result> updateUserInfo(
      String email, String nickname, String password, String password2, String userId) async {
    final db = MyDatabase.instance;
    try {
      if (email.isEmpty) {
        return Result("ERROR", "邮箱不能为空", false);
      }
      if (password != password2) {
        return Result("ERROR", "两次输入的密码不一致", false);
      }
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        return Result("ERROR", "用户不存在", false);
      }
      final updatedUser = user.copyWith(
        email: Value(email),
        nickName: Value(nickname),
        password: password.isNotEmpty ? Value(password) : Value(user.password),
      );
      await db.usersDao.saveUser(updatedUser, true);
      return Result("SUCCESS", "修改成功", true);
    } catch (e) {
      return Result("ERROR", "本地修改失败: ${e.toString()}", false);
    }
  }

  Future<Result> unRegister(String userId) async {
    try {
      // 1. 调用后端API注销账户
      final result = await Api.client.unRegister(userId);
      
      if (result.success) {
        // 2. 清理本地数据库中该用户的所有数据
        final db = MyDatabase.instance;
        
        Global.logger.d('开始清理用户本地数据: userId=$userId');
        
        // 删除用户相关的所有表数据
        await db.learningDictsDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除学习词典数据');
        
        await db.learningWordsDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除学习单词数据');
        
        await db.masteredWordsDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除已掌握单词数据');
        
        await db.userWrongWordsDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除错题集数据');
        
        await db.dakasDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除打卡记录');
        
        await db.userOpersDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除用户操作记录');
        
        await db.bookmarksDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除收藏记录');
        
        await db.userStudyStepsDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除学习步骤数据');
        
        await db.userCowDungLogsDao.batchDeleteUserRecords(userId);
        Global.logger.d('已删除泡泡糖记录');
        
        await db.userDbLogsDao.deleteUserDbLogs(userId);
        Global.logger.d('已删除数据库日志');
        
        // 删除用户拥有的词典（需要先查询）
        final userDicts = await (db.select(db.dicts)
              ..where((d) => d.ownerId.equals(userId)))
            .get();
        for (final dict in userDicts) {
          // 删除词典的单词
          await db.dictWordsDao.batchDeleteUserRecords(userId, filters: {'dictId': dict.id});
          // 删除词典本身
          await (db.delete(db.dicts)..where((d) => d.id.equals(dict.id))).go();
        }
        Global.logger.d('已删除用户词典: ${userDicts.length}个');
        
        // 删除用户记录本身
        await db.usersDao.deleteUser(userId);
        Global.logger.d('已删除用户记录');
        
        // 3. 清除缓存和本地存储
        Global.clearUserCache();
        await GetStorage().remove("currentUserId");
        Global.currentUserId = null;
        Global.logger.d('已清除用户缓存和本地存储');
        
        Global.logger.i('用户本地数据清理完成: userId=$userId');
      }
      
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('注销用户失败: $e', stackTrace: stackTrace);
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'unRegister', userMessage: '注销失败，请稍后重试');
      return Result("ERROR", "注销失败: ${e.toString()}", false);
    }
  }

  Future<Result<String>> saveErrorReport(String word, String content) async =>
      Api.client.saveErrorReport(word, content, getClientType().name);

  Future<Result<List<UserDbLogDto>>> getNewDbLogs(
          int localDbVersion, String userId) async =>
      Api.client.getNewDbLogs(localDbVersion, userId);

  Future<Result<int>> syncUserDb(int expectedServerDbVersion, String userId,
          List<UserDbLogDto> logs) async =>
      Api.client.syncUserDb(expectedServerDbVersion, userId, logs);

  Future<Result<int>> getSystemDbVersion() async => Api.client.getSystemDbVersion();


  Future<Result<bool>> recordLogin(String? remark) async =>
      Api.client.recordLogin(remark);
}


