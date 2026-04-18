import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/utils.dart';

/// 数据库日志工具类
class DbLogUtil {
  /// 记录数据库操作日志
  /// [userId] 用户ID
  /// [operate] 操作类型：INSERT、UPDATE、DELETE
  /// [table] 表名
  /// [recordId] 记录ID
  /// [record] 原始记录对象，会在函数内部转换为JSON字符串
  static Future<void> logOperation(
    String userId,
    String operate,
    String table,
    String recordId,
    Object? record,
  ) async {
    // 【快速失败机制】检查关键字段是否为空
    if (userId.isEmpty) {
      throw Exception('【快速失败】无法记录数据库日志：userId 为空，表: $table, 操作: $operate, recordId: $recordId');
    }
    if (recordId.isEmpty) {
      throw Exception('【快速失败】无法记录数据库日志：recordId 为空，表: $table, 操作: $operate, userId: $userId');
    }

    // 将原始对象转换为JSON字符串
    Object? recordToLog = record;
    if (table == 'users' && record is User) {
      // 【优化】对于用户表，移除体积巨大且服务端会自行覆盖的字段（头像、收据等），以极大减小同步包体积
      // 同时如果头像是一个长字符串（Base64），也不记录到日志中，只保留正常的 URL。
      recordToLog = record.copyWith(
        wechatAvatar: (record.wechatAvatar != null && record.wechatAvatar!.length > 1000)
            ? const Value(null)
            : Value(record.wechatAvatar),
        lastReceiptDataIos: const Value(null),
        // 以下敏感字段同样建议设为 null，因为服务端会自行从权威数据库补全，避免客户端篡改
        wechatOpenId: const Value(null),
        wechatUnionId: const Value(null),
        wechatNickname: const Value(null),
        appleUserId: const Value(null),
      );
    }

    final String recordJson;
    try {
      recordJson = jsonEncode(recordToLog);
    } catch (e) {
      throw Exception('【快速失败】无法将记录对象转换为JSON：表: $table, 操作: $operate, userId: $userId, recordId: $recordId, 错误: $e');
    }
    if (recordJson.isEmpty) {
      throw Exception('【快速失败】无法记录数据库日志：record 转换后为空，表: $table, 操作: $operate, userId: $userId, recordId: $recordId');
    }

        // 对于 dakas 表，额外检查 record 中是否包含 userId
    if (table == 'dakas') {
      // 直接从对象中检查 userId，避免先序列化再反序列化
      if (record is Daka) {
        final dakaUserId = record.userId;
        if (dakaUserId.isEmpty) {
          throw Exception('【快速失败】dakas 表记录中 userId 为空，无法同步到服务端。record: $recordJson');
        }
      } else {
        // 如果不是 Map，说明对象转换有问题
        throw Exception('【快速失败】dakas 表记录不是有效 Map 对象，无法检查 userId。表: $table, 操作: $operate');
      }
    }

    try {
      final db = MyDatabase.instance;

      // 创建日志记录，version 字段为空，由服务端在同步时设置
      var now = AppClock.now();
      try {
        // 【智能合并日志】如果是 UPDATE 操作，检查之前是否有未同步的对应的 INSERT/UPDATE 日志
        if (operate == 'UPDATE') {
          final existingLog = await db.userDbLogsDao.getLatestLog(userId, table, recordId);
          if (existingLog != null && (existingLog.operate == 'INSERT' || existingLog.operate == 'UPDATE')) {
            final updatedLog = existingLog.copyWith(
              record: recordJson,
              updateTime: now,
            );
            await db.userDbLogsDao.updateEntity(updatedLog);
            return;
          }
        }

        final logId = Util.uuid();

        await db.userDbLogsDao.insertEntity(
          UserDbLog(
            id: logId,
            userId: userId,
            operate: operate,
            tblName: table,
            recordId: recordId,
            record: recordJson,
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
