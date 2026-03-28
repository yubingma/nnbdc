import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get/get.dart';
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
    final status = await _getEffectivePermission(permission).status;
    
    if (status.isGranted) {
      onGranted();
      return;
    }

    final isDarkMode = Get.isDarkMode;

    // 显示符合合规要求的说明对话框
    final result = await Get.dialog<bool>(
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
            onPressed: () => Get.back(result: false),
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
            onPressed: () => Get.back(result: true),
            child: const Text('去授权'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (result == true) {
      final effectivePermission = _getEffectivePermission(permission);
      final newStatus = await effectivePermission.request();
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

  /// 针对 Android 平台处理权限映射差异
  static Permission _getEffectivePermission(Permission permission) {
    if (GetPlatform.isAndroid) {
      if (permission == Permission.photos) {
        // 在 Android 上，Permission.storage 兼容性通常更好，且能覆盖相册访问需求
        // 或者是使用 Permission.photos，但部分设备上 manifest 识别会有问题
        return Permission.storage;
      }
    }
    return permission;
  }
}
