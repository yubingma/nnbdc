import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';

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

    if (showToast) {
      final displayMessage = userMessage ?? '操作失败，请稍后重试';
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
    
    // 增强日志输出，确保能看到错误信息
    final errorMessage = '数据库操作失败: ${operation ?? "未知操作"}';

    // 2. 输出到日志文件
    Global.logger.e(errorMessage, error: error, stackTrace: stackTrace);

    // 3. 外键约束失败诊断（仅当db不为null）
    if (db != null && _isForeignKeyConstraintError(error)) {
      await _logForeignKeyViolations(db);
    }

    // 4. 用户提示
    if (showToast) {
      final userMessage = '数据操作失败，请稍后重试';
      ToastUtil.error(userMessage);
    }
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
    bool showToast = true,
  }) {
    // 记录统计
    _networkErrorCount++;
    
    final logPrefix = api != null ? '网络请求失败($api)' : '网络请求失败';
    final userMessage = getNetworkErrorMessage(error);
    
    handleError(
      error,
      stackTrace,
      userMessage: userMessage,
      logPrefix: logPrefix,
      showToast: showToast,
    );
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
