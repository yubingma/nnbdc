// 自动完整性检查器
// 在应用启动时自动执行数据完整性检查

import 'package:flutter/material.dart';
import 'package:nnbdc/util/data_integrity_checker.dart';

class AutoIntegrityChecker {
  static bool _hasRun = false;
  
  /// 在应用启动时自动执行完整性检查
  static Future<void> runOnStartup(BuildContext context) async {
    if (_hasRun) return;
    _hasRun = true;
    
    try {
      // 延迟3秒后执行检查，避免影响应用启动速度
      await Future.delayed(const Duration(seconds: 3));
      
      final checker = DataIntegrityChecker();
      final result = await checker.performFullCheck();
      
      // 如果发现问题，在后台自动修复
      if (result.hasIssues) {
        await checker.autoFix(result);
      }
      
    } catch (e) {
      // 静默处理错误，不影响用户体验
      debugPrint('自动完整性检查失败: $e');
    }
  }
  
  /// 手动触发完整性检查
  static Future<void> runManualCheck(BuildContext context) async {
    try {
      final checker = DataIntegrityChecker();
      final result = await checker.performFullCheck();
      
      if (result.hasIssues) {
        // 显示检查结果
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('数据完整性检查'),
              content: Text('发现 ${result.totalIssues} 个问题，已自动修复。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('完整性检查失败: $e')),
        );
      }
    }
  }
}
