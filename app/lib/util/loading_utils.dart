import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';

/// 统一管理loading的工具类
/// 用于避免页面加载过程中出现双重loading的情况
class LoadingUtils {
  /// 在需要自行处理loading的页面加载数据时调用
  /// 禁用API调用自动显示的loading
  static void disableApiLoading() {
    Api.disableAutoLoading = true;
  }

  /// 在需要API调用自动显示loading时调用
  /// 启用API调用自动显示的loading
  static void enableApiLoading() {
    Api.disableAutoLoading = false;
  }

  /// 包装异步操作，在执行过程中禁用API自动loading
  /// 操作完成后恢复API自动loading
  static Future<T> withoutApiLoading<T>(Future<T> Function() operation) async {
    bool wasDisabled = Api.disableAutoLoading;
    try {
      Api.disableAutoLoading = true;
      return await operation();
    } finally {
      Api.disableAutoLoading = wasDisabled;
    }
  }

  /// 包装异步操作，在执行过程中启用API自动loading
  /// 提供自定义的loading信息
  static Future<T> withApiLoading<T>({
    required Future<T> Function() operation,
    String loadingText = 'loading...',
    bool dismissOnTap = false,
  }) async {
    Api.disableAutoLoading = false;
    try {
      await Api.loadingService.show(
        status: loadingText,
        dismissOnTap: dismissOnTap,
        maskColor: Colors.transparent,
      );
      return await operation();
    } finally {
      await Api.loadingService.dismiss();
    }
  }
}
