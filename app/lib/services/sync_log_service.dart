import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/models/sync_log.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/utils.dart';

/// 同步日志服务
/// 用于管理同步日志的存储和查询
class SyncLogService {
  static final SyncLogService _instance = SyncLogService._internal();
  factory SyncLogService() => _instance;
  SyncLogService._internal();

  static const String _syncLogsKey = 'sync_logs';
  static const int _maxLogCount = 100; // 最多保留100条日志

  /// 获取所有同步日志
  Future<List<SyncLog>> getAllLogs() async {
    try {
      final db = MyDatabase.instance;
      final param = await (db.select(db.localParams)
            ..where((e) => e.name.equals(_syncLogsKey)))
          .getSingleOrNull();
      
      if (param == null) {
        return [];
      }
      
      final jsonString = param.value;
      
      if (jsonString.isEmpty || jsonString == 'null') {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((e) => SyncLog.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      Global.logger.e('获取同步日志失败: $e');
      return [];
    }
  }

  /// 获取最近的同步日志（按时间倒序）
  Future<List<SyncLog>> getRecentLogs({int limit = 50}) async {
    final logs = await getAllLogs();
    // 按时间倒序排列
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    return logs.take(limit).toList();
  }

  /// 获取最近一次同步日志
  Future<SyncLog?> getLastSyncLog() async {
    final logs = await getAllLogs();
    if (logs.isEmpty) return null;
    // 按时间倒序排列，取第一条
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    return logs.first;
  }

  /// 检查最近一次同步是否失败
  Future<bool> isLastSyncFailed() async {
    final lastLog = await getLastSyncLog();
    return lastLog != null && !lastLog.success;
  }

  /// 添加同步日志
  Future<void> addLog(SyncLog log) async {
    try {
      final logs = await getAllLogs();
      logs.add(log);
      
      // 限制日志数量，保留最新的
      if (logs.length > _maxLogCount) {
        // 按时间排序，保留最新的
        logs.sort((a, b) => b.startTime.compareTo(a.startTime));
        logs.removeRange(_maxLogCount, logs.length);
      }

      await _saveLogs(logs);
    } catch (e) {
      Global.logger.e('添加同步日志失败: $e');
    }
  }

  /// 清空所有同步日志
  Future<void> clearAllLogs() async {
    try {
      final db = MyDatabase.instance;
      final existing = await db.localParamsDao.getParamByName(_syncLogsKey);
      await db.update(db.localParams).replace(existing.copyWith(value: '[]'));
    } catch (e) {
      Global.logger.e('清空同步日志失败: $e');
    }
  }

  /// 删除单条日志
  Future<void> deleteLog(String id) async {
    try {
      final logs = await getAllLogs();
      logs.removeWhere((log) => log.id == id);
      await _saveLogs(logs);
    } catch (e) {
      Global.logger.e('删除同步日志失败: $e');
    }
  }

  /// 保存日志列表到本地存储
  Future<void> _saveLogs(List<SyncLog> logs) async {
    try {
      final db = MyDatabase.instance;
      final jsonString = jsonEncode(logs.map((e) => e.toJson()).toList());
      
      final existing = await (db.select(db.localParams)
            ..where((e) => e.name.equals(_syncLogsKey)))
          .getSingleOrNull();
      
      if (existing == null) {
        await db.into(db.localParams).insert(
          LocalParamsCompanion.insert(
            name: _syncLogsKey,
            value: jsonString,
            description: Value('同步日志记录'),
          ),
        );
      } else {
        await (db.update(db.localParams)
              ..where((e) => e.name.equals(_syncLogsKey)))
            .write(LocalParamsCompanion(value: Value(jsonString)));
      }
    } catch (e) {
      Global.logger.e('保存同步日志失败: $e');
    }
  }

  /// 创建一个新的同步日志并开始记录
  /// 返回日志ID，用于后续完成或失败时更新
  Future<String> startSync({String? userId, String? appVersion}) async {
    final id = Util.uuid();
    final log = SyncLog.start(
      id: id,
      startTime: AppClock.now(),
      userId: userId,
      appVersion: appVersion,
    );
    await addLog(log);
    return id;
  }

  /// 完成同步日志（成功时调用）
  Future<void> completeSync({
    required String logId,
    required int uploadCount,
    required int downloadCount,
    Map<String, dynamic>? uploadDetails,
    Map<String, dynamic>? downloadDetails,
    int? dbVersion,
  }) async {
    try {
      final logs = await getAllLogs();
      final index = logs.indexWhere((log) => log.id == logId);
      
      if (index == -1) {
        Global.logger.w('未找到同步日志: $logId');
        return;
      }

      final updatedLog = logs[index].complete(
        endTime: AppClock.now(),
        uploadCount: uploadCount,
        downloadCount: downloadCount,
        uploadDetails: uploadDetails,
        downloadDetails: downloadDetails,
        dbVersion: dbVersion,
      );
      
      logs[index] = updatedLog;
      await _saveLogs(logs);
    } catch (e) {
      Global.logger.e('完成同步日志失败: $e');
    }
  }

  /// 标记同步失败
  Future<void> failSync({
    required String logId,
    required String errorMessage,
  }) async {
    try {
      final logs = await getAllLogs();
      final index = logs.indexWhere((log) => log.id == logId);
      
      if (index == -1) {
        Global.logger.w('未找到同步日志: $logId');
        return;
      }

      final updatedLog = logs[index].fail(
        endTime: AppClock.now(),
        errorMessage: errorMessage,
      );
      
      logs[index] = updatedLog;
      await _saveLogs(logs);
    } catch (e) {
      Global.logger.e('标记同步失败日志失败: $e');
    }
  }
}
