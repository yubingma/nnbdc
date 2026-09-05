import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/dialog_service.dart';
import '../theme/app_theme.dart';

class PermissionUtil {
  /// 请求权限并显示说明对话框（符合应用商店合规要求）
  /// 
  /// [permission] 权限类型
  /// [title] 权限名称 (如: 相机权限)
  /// [purpose] 详细的使用目的说明
  /// [icon] 显示在对话框中的图标
  /// [onGranted] 授权成功后的回调
  static Future<void> requestWithRationale({
    required Permission permission,
    required String title,
    required String purpose,
    required IconData icon,
    required VoidCallback onGranted,
    VoidCallback? onDenied,
  }) async {
    // 桌面端（macOS / Windows / Linux 等）文件/硬件选择由系统窗口或原生沙箱直接托管，
    // permission_handler 在桌面端未实现此类权限通道，直接放行
    if (!Platform.isAndroid && !Platform.isIOS) {
      onGranted();
      return;
    }

    final bool isGranted = await _checkPermissionGranted(permission);
    
    if (isGranted) {
      onGranted();
      return;
    }

    if (Platform.isIOS) {
      final newStatus = await permission.request();
      if (newStatus.isGranted) {
        onGranted();
      } else {
        if (newStatus.isPermanentlyDenied) {
          openAppSettings();
        }
        if (onDenied != null) onDenied();
      }
      return;
    }

    final isDarkMode = DialogService.context != null && Theme.of(DialogService.context!).brightness == Brightness.dark;

    // 显示符合合规要求的说明对话框
    final result = await DialogService.showDialog<bool>(
      AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '权限申请说明：',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white70 : Colors.black87,
                fontFamily: 'NotoSansSC',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              purpose,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white60 : Colors.black54,
                height: 1.5,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => DialogService.pop(false),
            child: Text(
              '暂不授权',
              style: TextStyle(color: isDarkMode ? Colors.white38 : Colors.black38),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => DialogService.pop(true),
            child: const Text('去授权'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (result == true) {
      final newStatus = await _requestPermission(permission);
      if (newStatus.isGranted) {
        onGranted();
      } else {
        if (newStatus.isPermanentlyDenied) {
          openAppSettings();
        }
        if (onDenied != null) onDenied();
      }
    } else {
      if (onDenied != null) onDenied();
    }
  }

  /// 检查权限是否已授予（兼容 Android 各版本相册/存储权限差异）
  static Future<bool> _checkPermissionGranted(Permission permission) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }
    if (Platform.isAndroid && permission == Permission.photos) {
      // Android 13+ 使用 READ_MEDIA_IMAGES (Permission.photos)
      if (await Permission.photos.isGranted) return true;
      // Android 12 及以下使用 READ_EXTERNAL_STORAGE (Permission.storage)
      if (await Permission.storage.isGranted) return true;
      return false;
    }
    return await permission.isGranted;
  }

  /// 请求权限（兼容 Android 跨版本相册/存储权限申请）
  static Future<PermissionStatus> _requestPermission(Permission permission) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return PermissionStatus.granted;
    }
    if (Platform.isAndroid && permission == Permission.photos) {
      // 1. 先尝试 Android 13+ 的相册权限
      final photoStatus = await Permission.photos.request();
      if (photoStatus.isGranted) return photoStatus;

      // 2. 如果 photos 无法授权（Android 12- 会直接返回 denied），再尝试 Android 12- 的存储权限
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return storageStatus;

      // 若其中任一被永久拒绝，则返回 permanentlyDenied 以便引导去设置页
      if (photoStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
        return PermissionStatus.permanentlyDenied;
      }
      return photoStatus;
    }
    return await permission.request();
  }
}
