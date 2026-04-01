import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 统一的异常处理工具类
class ErrorHandler {
  // 错误统计（可用于调试和监控）
  static int _totalErrorCount = 0;
  static int _networkErrorCount = 0;
  static int _databaseErrorCount = 0;
  static final Map<String, int> _errorTypeCount = {};

  /// 获取错误统计信息
  static Map<String, dynamic> getErrorStats() {
    return {
      'total': _totalErrorCount,
      'network': _networkErrorCount,
      'database': _databaseErrorCount,
      'byType': Map.from(_errorTypeCount),
    };
  }

  /// 重置错误统计
  static void resetErrorStats() {
    _totalErrorCount = 0;
    _networkErrorCount = 0;
    _databaseErrorCount = 0;
    _errorTypeCount.clear();
  }

  /// 内部方法：记录错误统计
  static void _recordErrorStats(String errorType) {
    _totalErrorCount++;
    _errorTypeCount[errorType] = (_errorTypeCount[errorType] ?? 0) + 1;
  }

  /// 记录异常到数据库
  static Future<void> _recordExceptionToDb(
    dynamic error,
    StackTrace? stackTrace, {
    String? context,
  }) {
    // 强制在 Zone.root 下运行，防止继承自可能正在关闭的事务 zone
    return Zone.root.run(() async {
      try {
        final db = MyDatabase.instance;
        final userId = Global.getLoggedInUser()?.id; // 避免通过 Global.getLoggedInUser() 可能产生的复杂逻辑
        final now = AppClock.now();

        final exception = LocalException(
          id: Util.uuid(),
          errorType: error.runtimeType.toString(),
          message: error.toString(),
          stackTrace: stackTrace?.toString(),
          context: context,
          userId: userId,
          createTime: now,
        );

        await db.localExceptionsDao.insertException(exception);
      } catch (e) {
        // 记录异常到数据库失败时，只记录到日志，不抛出异常，避免循环
        // 注意：这里的 logger 输出也可能伴随着 Bad state，但由于是在 catch 里，且 logger 为 root，不应递归。
        Global.logger.w('记录异常到数据库失败: $e');
      }
    });
  }

  /// 处理一般异常，包含日志记录和用户提示
  static void handleError(
    dynamic error,
    StackTrace? stackTrace, {
    String? userMessage,
    String? logPrefix,
    bool showToast = true,
  }) {
    // 记录统计
    _recordErrorStats(logPrefix ?? 'general');

    final logMessage = logPrefix != null ? '$logPrefix: $error' : '$error';

    // 使用 Global.logger 的原生功能，它会自动处理异常栈的深度
    Global.logger.e(logMessage, error: error, stackTrace: stackTrace);

    // 异步记录异常到数据库（不等待，避免阻塞）
    _recordExceptionToDb(error, stackTrace, context: logPrefix);

    if (showToast) {
      final displayMessage = userMessage != null ? '$userMessage ($error)' : '操作失败: $error';
      ToastUtil.error(displayMessage);
    }
  }

  /// 统一的数据库异常处理（含外键约束诊断）
  static Future<void> handleDatabaseError(
    Object error,
    StackTrace stackTrace, {
    DatabaseAccessor<GeneratedDatabase>? db,
    String? operation,
    bool showToast = false,
  }) async {
    // 记录统计
    _databaseErrorCount++;
    _recordErrorStats('database_${operation ?? "unknown"}');

    // 检测是否是表不存在的错误，如果是则自动重建数据库
    if (_isTableNotFoundError(error)) {
      Global.logger.w('⚠️ 检测到表不存在错误，自动重建数据库...');
      try {
        // 直接调用 wipeAllTables 来重建数据库，并在 root zone 中运行
        await Zone.root.run(() => MyDatabase.instance.wipeAllTables());
        Global.logger.i('✅ 数据库自动重建完成');
        // 重建后不显示错误提示，让操作可以重试
        return;
      } catch (e, st) {
        Global.logger.e('❌ 自动重建数据库失败: $e', error: e, stackTrace: st);
        // 如果重建失败，继续正常的错误处理流程
      }
    }

    // 增强日志输出，确保能看到错误信息
    final errorMessage = '数据库操作失败: ${operation ?? "未知操作"}';

    // 2. 输出到日志文件
    Global.logger.e(errorMessage, error: error, stackTrace: stackTrace);

    // 3. 外键约束失败诊断（仅当db不为null），同样确保在 root zone 中运行
    if (db != null && _isForeignKeyConstraintError(error)) {
      await Zone.root.run(() => _logForeignKeyViolations(db));
    }

    // 4. 异步记录异常到数据库（不等待，避免阻塞）
    _recordExceptionToDb(error, stackTrace, context: '数据库操作: ${operation ?? "未知"}');

    // 5. 用户提示
    if (showToast) {
      final userMessage = '数据操作失败: $error';
      ToastUtil.error(userMessage);
    }
  }

  /// 判断是否是表不存在的错误
  static bool _isTableNotFoundError(Object error) {
    return error.runtimeType.toString().contains('SqliteException') && error.toString().contains('no such table');
  }

  static bool _isForeignKeyConstraintError(Object error) {
    return error.runtimeType.toString().contains('SqliteException') && error.toString().contains('FOREIGN KEY constraint failed');
  }

  static Future<void> _logForeignKeyViolations(DatabaseAccessor db) async {
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violations.isEmpty) {
      Global.logger.e('外键约束失败: 但PRAGMA foreign_key_check未返回任何结果');
    } else {
      for (final row in violations) {
        final v = row.data;
        Global.logger.e('外键约束失败: 表=${v['table']}, 行id=${v['rowid']}, 父表=${v['parent']}, 外键序号=${v['fkey']}, 详情=$v');
      }
    }
  }

  /// 判断是否为网络相关异常
  static bool isNetworkError(dynamic error) {
    if (error == null) return false;

    // 检查 DioException 类型
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.unknown;
    }

    // 检查 SocketException
    if (error is SocketException) {
      return true;
    }

    // 检查 HttpException
    if (error is HttpException) {
      return true;
    }

    // 检查异常消息中的关键词
    String errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('timeout') ||
        errorStr.contains('socket') ||
        errorStr.contains('http') ||
        errorStr.contains('dns') ||
        errorStr.contains('unreachable') ||
        errorStr.contains('refused') ||
        errorStr.contains('reset') ||
        errorStr.contains('broken pipe');
  }

  /// 获取网络异常的用户友好提示
  static String getNetworkErrorMessage(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return '连接超时，请检查网络连接';
        case DioExceptionType.receiveTimeout:
          return '接收数据超时，请稍后重试';
        case DioExceptionType.sendTimeout:
          return '发送数据超时，请稍后重试';
        case DioExceptionType.connectionError:
          return '网络连接失败，请检查网络设置';
        case DioExceptionType.unknown:
          return '网络异常，请检查网络连接';
        default:
          return '网络请求失败，请稍后重试';
      }
    }

    if (error is SocketException) {
      if (error.message.contains('Connection refused')) {
        return '服务器连接被拒绝，请稍后重试';
      } else if (error.message.contains('Network is unreachable')) {
        return '网络不可达，请检查网络连接';
      } else if (error.message.contains('No route to host')) {
        return '无法连接到服务器，请检查网络设置';
      }
      return '网络连接异常，请检查网络设置';
    }

    if (error is HttpException) {
      return 'HTTP请求失败，请稍后重试';
    }

    return '网络异常，请检查网络连接';
  }

  /// 处理网络请求异常
  static void handleNetworkError(
    dynamic error,
    StackTrace? stackTrace, {
    String? api,
    bool showToast = false,
  }) {
    // 记录统计
    _networkErrorCount++;

    final logPrefix = api != null ? '网络请求失败($api)' : '网络请求失败';
    final userMessage = getNetworkErrorMessage(error);

    // 对于常见网络错误，我们只记录一条简洁的消息，不打印长长的堆栈
    Global.logger.w('$logPrefix: $userMessage ($error)');

    // 仍记录到数据库以便后台分析
    _recordExceptionToDb(error, stackTrace, context: logPrefix);

    if (showToast) {
      ToastUtil.error(userMessage);
    }
  }

  /// 处理文件操作异常
  static void handleFileError(
    dynamic error,
    StackTrace? stackTrace, {
    String? fileName,
    bool showToast = true,
  }) {
    final logPrefix = fileName != null ? '文件操作失败($fileName)' : '文件操作失败';
    handleError(
      error,
      stackTrace,
      userMessage: '文件操作失败，请检查存储权限',
      logPrefix: logPrefix,
      showToast: showToast,
    );
  }

  /// 处理音频播放异常
  static void handleAudioError(
    dynamic error,
    StackTrace? stackTrace, {
    String? audioType,
    bool showToast = false, // 音频错误通常不需要用户提示
  }) {
    final logPrefix = audioType != null ? '音频播放失败($audioType)' : '音频播放失败';
    handleError(
      error,
      stackTrace,
      userMessage: '音频播放失败',
      logPrefix: logPrefix,
      showToast: showToast,
    );
  }

  /// 包装异步操作，提供统一的异常处理
  static Future<T?> safeExecute<T>(
    Future<T> Function() operation, {
    String? operationName,
    String? userErrorMessage,
    bool showToast = true,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      handleError(
        error,
        stackTrace,
        userMessage: userErrorMessage,
        logPrefix: operationName,
        showToast: showToast,
      );
      return null;
    }
  }

  /// 包装同步操作，提供统一的异常处理
  static T? safeExecuteSync<T>(
    T Function() operation, {
    String? operationName,
    String? userErrorMessage,
    bool showToast = true,
  }) {
    try {
      return operation();
    } catch (error, stackTrace) {
      handleError(
        error,
        stackTrace,
        userMessage: userErrorMessage,
        logPrefix: operationName,
        showToast: showToast,
      );
      return null;
    }
  }
}
