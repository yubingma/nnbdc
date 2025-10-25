import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get/get.dart';
import '../config.dart';

class UpdateInfo {
  final String version;
  final String buildNumber;
  final String downloadUrl;
  final String size;
  final String releaseNotes;
  final bool requiresRestart;
  final String installerType;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.size,
    required this.releaseNotes,
    this.requiresRestart = false,
    this.installerType = 'setup',
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      buildNumber: json['buildNumber'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      size: json['size'] ?? '0',
      releaseNotes: json['releaseNotes'] ?? '',
      requiresRestart: json['requiresRestart'] ?? false,
      installerType: json['installerType'] ?? 'setup',
    );
  }
}

class UpdateService extends GetxController {
  static UpdateService get instance => Get.find<UpdateService>();
  
  final RxBool _isChecking = false.obs;
  final Rx<UpdateInfo?> _updateInfo = Rx<UpdateInfo?>(null);
  final RxString _currentVersion = ''.obs;
  final RxString _currentBuildNumber = ''.obs;

  bool get isChecking => _isChecking.value;
  UpdateInfo? get updateInfo => _updateInfo.value;
  String get currentVersion => _currentVersion.value;
  String get currentBuildNumber => _currentBuildNumber.value;

  @override
  void onInit() {
    super.onInit();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion.value = packageInfo.version;
      _currentBuildNumber.value = packageInfo.buildNumber;
    } catch (e) {
      debugPrint('获取当前版本信息失败: $e');
    }
  }

  /// 检查更新
  Future<bool> checkForUpdate({bool showDialog = true}) async {
    if (_isChecking.value) return false;
    
    _isChecking.value = true;
    
    try {
      final response = await http.get(Uri.parse(Config.updateUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 新格式：数组格式 [{"verCode":25101301,"verName":"25.10.13", "changes":["修复已知问题，提升稳定性"]}]
        if (data is List && data.isNotEmpty) {
          final latestVersion = data[0];
          final newVersion = latestVersion['verName'] ?? '';
          final newBuildNumber = latestVersion['verCode']?.toString() ?? '';
          final changes = List<String>.from(latestVersion['changes'] ?? []);
          
          // 比较版本号
          if (_isNewerVersion(newVersion, _currentVersion.value)) {
            final updateInfo = UpdateInfo(
              version: newVersion,
              buildNumber: newBuildNumber,
              downloadUrl: _getDownloadUrl(),
              size: '0',
              releaseNotes: changes.join('\n'),
              requiresRestart: true,
              installerType: 'setup',
            );
            
            _updateInfo.value = updateInfo;
            if (showDialog) {
              _showUpdateDialog(updateInfo);
            }
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('检查更新失败: $e');
      if (showDialog) {
        Get.snackbar('检查更新', '检查更新失败，请稍后重试', snackPosition: SnackPosition.TOP);
      }
    } finally {
      _isChecking.value = false;
    }
    
    if (showDialog) {
      Get.snackbar('检查更新', '当前已是最新版本', snackPosition: SnackPosition.TOP);
    }
    return false;
  }

  /// 获取下载链接
  String _getDownloadUrl() {
    if (Platform.isWindows) {
      return Config.windowsUrl;
    } else if (Platform.isMacOS) {
      return 'http://www.nnbdc.com/app/nnbdc-macos.zip';
    } else if (Platform.isLinux) {
      return 'http://www.nnbdc.com/app/nnbdc-linux.tar.gz';
    } else {
      return Config.apkUrl;
    }
  }

  /// 比较版本号
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = newVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      
      // 补齐版本号长度
      while (newParts.length < 3) {
        newParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      
      for (int i = 0; i < 3; i++) {
        if (newParts[i] > currentParts[i]) return true;
        if (newParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 显示更新对话框
  void _showUpdateDialog(UpdateInfo updateInfo) {
    Get.dialog(
      AlertDialog(
        title: Text('发现新版本 ${updateInfo.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本: ${_currentVersion.value}'),
            Text('最新版本: ${updateInfo.version}'),
            if (updateInfo.releaseNotes.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('更新内容:'),
              Text(updateInfo.releaseNotes, style: TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('稍后更新'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              downloadUpdate(updateInfo);
            },
            child: Text('立即更新'),
          ),
        ],
      ),
    );
  }

  /// 下载更新
  Future<void> downloadUpdate(UpdateInfo updateInfo) async {
    try {
      if (Platform.isWindows) {
        // Windows 安装包直接打开下载链接
        await launchUrl(Uri.parse(updateInfo.downloadUrl));
        Get.snackbar('下载更新', '正在打开下载页面，请下载并安装新版本', 
                    snackPosition: SnackPosition.TOP, duration: Duration(seconds: 5));
      } else if (Platform.isMacOS) {
        // macOS 显示升级说明
        _showMacOSUpgradeDialog(updateInfo);
      } else if (Platform.isLinux) {
        // Linux 显示升级说明
        _showLinuxUpgradeDialog(updateInfo);
      } else {
        // Android 等其他平台
        await launchUrl(Uri.parse(updateInfo.downloadUrl));
        Get.snackbar('下载更新', '正在打开下载页面', snackPosition: SnackPosition.TOP);
      }
    } catch (e) {
      Get.snackbar('下载更新', '打开下载页面失败: $e', snackPosition: SnackPosition.TOP);
    }
  }

  /// 显示 macOS 升级说明
  void _showMacOSUpgradeDialog(UpdateInfo updateInfo) {
    Get.dialog(
      AlertDialog(
        title: Text('macOS 版本升级'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本 ${updateInfo.version} 已发布！'),
            SizedBox(height: 16),
            Text('升级步骤：', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('1. 打开 App Store'),
            Text('2. 搜索"泡泡单词"'),
            Text('3. 点击"更新"按钮'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Get.back();
                // 打开 App Store
                launchUrl(Uri.parse('macappstore://itunes.apple.com/app/id[YOUR_APP_ID]'));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('前往 App Store'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('稍后升级'),
          ),
        ],
      ),
    );
  }

  /// 显示 Linux 升级说明
  void _showLinuxUpgradeDialog(UpdateInfo updateInfo) {
    Get.dialog(
      AlertDialog(
        title: Text('Linux 版本升级'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新版本 ${updateInfo.version} 已发布！'),
            SizedBox(height: 16),
            Text('升级步骤：', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('1. 下载新版本：'),
            Text('   • 访问下载页面获取最新版本'),
            SizedBox(height: 8),
            Text('2. 安装新版本：'),
            Text('   • 解压下载的 TAR.GZ 文件'),
            Text('   • 将新版本复制到安装目录'),
            Text('   • 替换旧版本文件'),
            SizedBox(height: 8),
            Text('3. 重启应用'),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Get.back();
                launchUrl(Uri.parse('http://www.nnbdc.com/download.html'));
              },
              child: Text('前往下载页面'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('稍后升级'),
          ),
        ],
      ),
    );
  }

  /// 自动检查更新（应用启动时调用）
  Future<void> autoCheckUpdate() async {
    // 可以添加时间间隔检查逻辑
    await Future.delayed(Duration(seconds: 3)); // 延迟3秒后检查
    await checkForUpdate(showDialog: false);
  }
}
