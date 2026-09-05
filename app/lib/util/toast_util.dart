import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// 全局 Toast 工具：统一采用「平铺毛玻璃」样式，
/// 关联 App 整体极简美学（圆角卡片 + 语义色图标 + 柔影 + 中文字体），
/// 且随浅色/深色主题自动适配。
class ToastUtil {
  static void info(String info, {Duration? autoCloseDuration = const Duration(seconds: 3)}) {
    _show(info, ToastificationType.info, autoCloseDuration);
  }

  static void error(String info, {Duration? autoCloseDuration = const Duration(seconds: 3)}) {
    _show(info, ToastificationType.error, autoCloseDuration);
  }

  static void success(String info, {Duration? autoCloseDuration = const Duration(seconds: 3)}) {
    _show(info, ToastificationType.success, autoCloseDuration);
  }

  static void _show(String info, ToastificationType type, Duration? autoCloseDuration) {
    toastification.show(
      title: Text(
        info,
        maxLines: 3,
        softWrap: true,
        style: const TextStyle(
          fontSize: 14.5,
          letterSpacing: 0.1,
          fontFamily: 'NotoSansSC',
        ),
      ),
      autoCloseDuration: autoCloseDuration,
      type: type,
      style: ToastificationStyle.flat,
      // 局部毛玻璃：让 Toast 自身圆角区域内透出底下内容的朦胧色块
      applyBlurEffect: true,
      showProgressBar: false,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
