import 'dart:async';
import 'package:nnbdc/util/sync.dart' as dbsync;
import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/network_util.dart';

class ThrottledDbSyncService {
  static final ThrottledDbSyncService _instance = ThrottledDbSyncService._internal();
  factory ThrottledDbSyncService() => _instance;

  ThrottledDbSyncService._internal();

  Timer? _syncTimer;
  DateTime? _lastSyncAttemptTime;
  bool _syncScheduled = false;  // 是否有同步任务已安排
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





}
