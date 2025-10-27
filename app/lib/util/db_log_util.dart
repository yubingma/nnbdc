import 'dart:convert';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/utils.dart';

/// 数据库日志工具类
class DbLogUtil {
  /// 记录数据库操作日志
  static Future<void> logOperation(
    String userId,
    String operate,
    String table,
    String recordId,
    String record,
  ) async {
    try {
      final db = MyDatabase.instance;

      // 创建日志记录，version 字段为空，由服务端在同步时设置
      var now = AppClock.now();
      try {
        final logId = Util.uuid();

        await db.userDbLogsDao.insertEntity(
          UserDbLog(
            id: logId,
            userId: userId,
            operate: operate,
            tblName: table,
            recordId: recordId,
            record: record,
            version: 0, // 客户端不设置版本号
            createTime: now,
            updateTime: now,
          ),
        );

        // 验证日志是否真的被写入
        final insertedLog = await db.userDbLogsDao.getUserDbLogById(logId);
        if (insertedLog == null) {
          Global.logger.d('警告：日志写入失败，无法验证日志ID：$logId');
        }
      } catch (insertError) {
        Global.logger.d('日志插入异常: $insertError');
        // 重新抛出以便记录和调试
        rethrow;
      }
    } catch (e, stackTrace) {
      Global.logger.d('Error in logDbOperation: $e');
      Global.logger.d('错误堆栈: $stackTrace');

      // 调试标记，可以在发布时改为false
      throw Exception("数据库日志记录失败: $e");
    }
  }

  /// 记录删除用户某个表所有记录的特殊日志
  /// [userId] 用户ID
  /// [table] 表名
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  static Future<void> logDeleteAllTableRecords(
    String userId,
    String table, {
    Map<String, dynamic>? filters,
  }) async {
    try {
      final db = MyDatabase.instance;

      // 创建特殊日志记录，用于删除用户某个表的所有记录
      var now = AppClock.now();
      try {
        final logId = Util.uuid();

        // 使用特殊的recordId标识这是删除所有记录的操作
        final specialRecordId = 'BATCH_DELETE_${table.toUpperCase()}';

        // record字段直接存储过滤条件（部分字段值）
        final recordData = filters ?? {};

        await db.userDbLogsDao.insertEntity(
          UserDbLog(
            id: logId,
            userId: userId,
            operate: 'BATCH_DELETE',
            tblName: table,
            recordId: specialRecordId,
            record: jsonEncode(recordData),
            version: 0, // 客户端不设置版本号
            createTime: now,
            updateTime: now,
          ),
        );
      } catch (insertError) {
        Global.logger.d('删除所有记录日志插入异常: $insertError');
        // 重新抛出以便记录和调试
        rethrow;
      }
    } catch (e, stackTrace) {
      Global.logger.d('Error in logDeleteAllTableRecords: $e');
      Global.logger.d('错误堆栈: $stackTrace');
      throw Exception("删除所有记录日志记录失败: $e");
    }
  }
}
