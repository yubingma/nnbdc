import 'dart:async';
import 'package:nnbdc/util/sync.dart' as dbsync;
import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/network_util.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';

class ThrottledDbSyncService {
  static final ThrottledDbSyncService _instance = ThrottledDbSyncService._internal();
  factory ThrottledDbSyncService() => _instance;

  ThrottledDbSyncService._internal();

  Timer? _syncTimer;
  DateTime? _lastSyncAttemptTime;
  bool _syncScheduled = false; // 是否有同步任务已安排
  int _suspendCount = 0;
  bool _syncRequestedWhileSuspended = false; // 在暂停期间是否有同步请求被记录
  final NetworkUtil _networkUtil = NetworkUtil();

  // 同步请求计数器，用于调试
  int _syncRequestCount = 0;

  final Duration _throttleInterval = Config.dbSyncThrottleInterval;
  final List<Completer<void>> _waiters = [];

  /// 请求数据库同步，支持节流控制
  /// 如果已有同步任务安排，直接返回
  /// 如果在节流时间内，安排延迟执行
  /// 否则立即执行
  ///
  /// [immediate] 如果为 true，则忽略节流控制，立即执行同步
  Future<void> requestSync({bool immediate = false}) async {
    _syncRequestCount++;

    // 导入/大事务期间暂停同步，避免 database is locked
    if (_suspendCount > 0) {
      _syncRequestedWhileSuspended = true;
      Global.logger.d('⏸️ 同步已暂停（导入中），记录待同步请求 (请求计数: $_syncRequestCount)');
      return;
    }

    // 如果已有同步任务安排且不是立即执行，直接返回
    if (_syncScheduled && !immediate) {
      Global.logger.d('⏳ 同步任务已安排，忽略此次请求 (请求计数: $_syncRequestCount)');
      return;
    }

    DateTime now = AppClock.now();

    // 计算还要等待多长时间进行同步
    Duration delay = Duration.zero;
    if (!immediate && _lastSyncAttemptTime != null) {
      Duration timeSinceLastAttempt = now.difference(_lastSyncAttemptTime!);
      if (timeSinceLastAttempt < _throttleInterval) {
        delay = _throttleInterval - timeSinceLastAttempt;
      }
    }

    // 取消之前的定时器（如果存在）
    _syncTimer?.cancel();

    // 设置定时任务执行同步
    _syncScheduled = true;
    _syncTimer = Timer(delay, () {
      _performSync();
    });
  }

  /// 请求同步并等待同步完成（受节流控制）
  ///
  /// [immediate] 如果为 true，则忽略节流控制，立即执行同步
  Future<void> requestSyncAndWait({bool immediate = false}) async {
    final completer = Completer<void>();
    _waiters.add(completer);
    await requestSync(immediate: immediate);
    return completer.future;
  }

  /// 执行实际的同步操作
  Future<void> _performSync() async {
    final startTime = AppClock.now();
    Global.logger.d('🔄 开始执行数据库同步操作');

    // 若正在导入/大事务，直接跳过，待恢复后再触发一次
    if (_suspendCount > 0) {
      _syncRequestedWhileSuspended = true;
      Global.logger.d('⏸️ 同步被暂停（导入中），跳过本次执行');
      _syncScheduled = false;
      return;
    }

    // 检查网络连接
    bool isConnected = await _networkUtil.isConnected();
    if (!isConnected) {
      Global.logger.d('🌐 网络连接不可用，静默跳过同步操作');
      _syncScheduled = false;
      return;
    }

    _lastSyncAttemptTime = startTime;

    // 清除待执行的定时器
    _syncTimer?.cancel();
    _syncTimer = null;

    try {
      await dbsync.syncDb();

      final endTime = AppClock.now();
      final duration = endTime.difference(startTime);
      Global.logger.d('✅ 数据库同步操作完成，耗时: ${duration.inMilliseconds}ms');
    } catch (e, stackTrace) {
      final endTime = AppClock.now();
      final duration = endTime.difference(startTime);
      Global.logger.e('❌ 数据库同步操作失败，耗时: ${duration.inMilliseconds}ms, 错误: $e');
      Global.logger.e('错误堆栈: $stackTrace');

      // 核心异常：弹出对话框提示用户
      if (e is dbsync.SyncCoreException) {
        _showCoreDataErrorDialog(e);
      }

      // 同步失败后的重试策略
      _handleSyncFailure(e);

      rethrow;
    } finally {
      _syncScheduled = false;
      // 完成所有等待者
      for (final waiter in _waiters) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
      _waiters.clear();
    }
  }

  /// 暂停同步（可重入）
  void suspend() {
    _suspendCount++;
    // 暂停期间取消已安排的定时器，避免到点触发占用资源
    _syncTimer?.cancel();
    _syncTimer = null;
    _syncScheduled = false;
    Global.logger.d('⏸️ 暂停数据库同步: suspendCount=$_suspendCount');
  }

  /// 恢复同步（与 suspend 配对）
  void resume() {
    if (_suspendCount > 0) {
      _suspendCount--;
    }
    Global.logger.d('▶️ 恢复数据库同步: suspendCount=$_suspendCount');
    if (_suspendCount == 0 && _syncRequestedWhileSuspended) {
      _syncRequestedWhileSuspended = false;
      // 恢复后触发一次同步（受节流控制）
      unawaited(requestSync());
    }
  }

  /// 处理同步失败的情况
  void _handleSyncFailure(dynamic error) {
    // 如果是网络相关错误，允许更快的重试
    if (_isNetworkError(error)) {
      Global.logger.w('🌐 检测到网络错误，允许更快的重试');
      // 将上次尝试时间提前，允许更快的重试
      if (_lastSyncAttemptTime != null) {
        _lastSyncAttemptTime = _lastSyncAttemptTime!.subtract(Duration(seconds: 30));
      }
    } else {
      Global.logger.w('⚠️ 同步失败，下次重试仍受节流控制');
    }
  }

  /// 判断是否为网络相关错误
  bool _isNetworkError(dynamic error) {
    if (error == null) return false;

    String errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('timeout') ||
        errorStr.contains('socket') ||
        errorStr.contains('http');
  }

  /// 显示核心数据丢失对话框
  void _showCoreDataErrorDialog(dbsync.SyncCoreException error) {
    // 确保在主线程执行 UI 操作
    Future.microtask(() {
      String dialogTitle = '核心数据异常';
      if (error is dbsync.SyncDataParseException) {
        dialogTitle = '同步数据解析失败';
      }

      Get.dialog(
        AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text(dialogTitle, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error.message),
                SizedBox(height: 16),
                if (error is dbsync.CoreDataMissingException)
                  Text('这种情况通常意味着本地核心词书丢失，可能会导致同步失败。请尝试使用"我的" -> "健康检查"并执行自动修复。', style: TextStyle(fontSize: 13, color: Colors.grey[700]))
                else if (error is dbsync.SyncDataParseException)
                  Text('可能服务端更新了必填字段导致旧版应用不兼容。请记录上述错误并联系管理员，或重装应用。', style: TextStyle(fontSize: 13, color: Colors.grey[700]))
                else
                  Text('同步过程中检测到严重的数据一致性或安全问题。如果此问题持续出现，请尝试清空本地数据重新登录。', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text('确定'),
            ),
          ],
        ),
        barrierDismissible: false,
      );
    });
  }
}
