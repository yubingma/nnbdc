import 'package:drift/drift.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';

/// 统一的异常处理工具类
class ErrorHandler {
  /// 处理一般异常，包含日志记录和用户提示
  static void handleError(
    dynamic error,
    StackTrace? stackTrace, {
    String? userMessage,
    String? logPrefix,
    bool showToast = true,
  }) {
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

  /// 处理网络请求异常
  static void handleNetworkError(
    dynamic error,
    StackTrace? stackTrace, {
    String? api,
    bool showToast = true,
  }) {
    final logPrefix = api != null ? '网络请求失败($api)' : '网络请求失败';
    handleError(
      error,
      stackTrace,
      userMessage: '网络连接异常，请检查网络设置',
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
