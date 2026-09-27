import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/models/sync_log.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/utils.dart';

/// 云同步状态枚举
enum SyncStatus {
  idle,     // 空闲 / 已是最新
  syncing,  // 正在同步
  failed,   // 上次同步失败
}

/// 同步日志服务
/// 用于管理同步日志的存储和查询
class SyncLogService {
  static final SyncLogService _instance = SyncLogService._internal();
  factory SyncLogService() => _instance;
  SyncLogService._internal();

  static const String _syncLogsKey = 'sync_logs';
  static const int _maxLogCount = 100; // 最多保留100条日志

  /// 同步状态响应式通知器（供 UI 响应式监听）
  final ValueNotifier<SyncStatus> syncStatusNotifier = ValueNotifier<SyncStatus>(SyncStatus.idle);

  SyncStatus get currentStatus => syncStatusNotifier.value;
  bool get isSyncing => syncStatusNotifier.value == SyncStatus.syncing;

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
      final logs = jsonList.map((e) => SyncLog.fromJson(e as Map<String, dynamic>)).toList();

      // 检测并修复超时的未完成僵尸日志（如上次同步时进程被强制杀死）
      final now = AppClock.now();
      bool needSave = false;
      for (int i = 0; i < logs.length; i++) {
        final log = logs[i];
        if (log.isInProgress && now.difference(log.startTime).inMinutes >= 2) {
          logs[i] = log.fail(
            endTime: log.startTime.add(const Duration(seconds: 10)),
            errorMessage: '同步意外中断（应用关闭或异常退出）',
          );
          needSave = true;
        }
      }
      if (needSave) {
        unawaited(_saveLogs(logs));
      }

      return logs;
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

  /// 获取最近一次同步日志（包含正在进行中的）
  Future<SyncLog?> getLastSyncLog() async {
    final logs = await getAllLogs();
    if (logs.isEmpty) return null;
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    return logs.first;
  }

  /// 获取最近一次已完成的同步日志
  Future<SyncLog?> getLastFinishedSyncLog() async {
    final logs = await getAllLogs();
    if (logs.isEmpty) return null;
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    for (final log in logs) {
      if (log.isFinished) {
        return log;
      }
    }
    return null;
  }

  /// 检查最近一次同步是否失败
  /// 注意：如果当前同步正在进行中，绝不能判定为失败
  Future<bool> isLastSyncFailed() async {
    if (isSyncing) return false;
    final lastFinished = await getLastFinishedSyncLog();
    return lastFinished != null && !lastFinished.success;
  }

  /// 刷新并获取最新的同步状态
  Future<SyncStatus> refreshSyncStatus() async {
    if (isSyncing) return SyncStatus.syncing;
    final lastFinished = await getLastFinishedSyncLog();
    final status = (lastFinished != null && !lastFinished.success)
        ? SyncStatus.failed
        : SyncStatus.idle;
    syncStatusNotifier.value = status;
    return status;
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
            description: const Value('同步日志记录'),
            updateTime: Value(AppClock.now()),
          ),
        );
      } else {
        await (db.update(db.localParams)
              ..where((e) => e.name.equals(_syncLogsKey)))
            .write(LocalParamsCompanion(value: Value(jsonString), updateTime: Value(AppClock.now())));
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
    syncStatusNotifier.value = SyncStatus.syncing;
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
    int? sysDbVersion,
  }) async {
    try {
      final logs = await getAllLogs();
      final index = logs.indexWhere((log) => log.id == logId);
      
      if (index == -1) {
        Global.logger.w('未找到同步日志: $logId');
        syncStatusNotifier.value = SyncStatus.idle;
        return;
      }

      final updatedLog = logs[index].complete(
        endTime: AppClock.now(),
        uploadCount: uploadCount,
        downloadCount: downloadCount,
        uploadDetails: uploadDetails,
        downloadDetails: downloadDetails,
        dbVersion: dbVersion,
        sysDbVersion: sysDbVersion,
      );
      
      logs[index] = updatedLog;
      await _saveLogs(logs);
      syncStatusNotifier.value = SyncStatus.idle;
    } catch (e) {
      Global.logger.e('完成同步日志失败: $e');
      syncStatusNotifier.value = SyncStatus.idle;
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
        syncStatusNotifier.value = SyncStatus.failed;
        return;
      }

      final updatedLog = logs[index].fail(
        endTime: AppClock.now(),
        errorMessage: errorMessage,
      );
      
      logs[index] = updatedLog;
      await _saveLogs(logs);
      syncStatusNotifier.value = SyncStatus.failed;
    } catch (e) {
      Global.logger.e('标记同步失败日志失败: $e');
      syncStatusNotifier.value = SyncStatus.failed;
    }
  }
}
