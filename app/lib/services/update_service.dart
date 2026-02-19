import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nnbdc/util/toast_util.dart';
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

  /// 检查更新（用于启动时检查，返回版本信息但不显示对话框）
  /// 如果没有新版本或检查失败，返回 null
  /// 返回结果中包含：
  /// - hasUpdate: 是否有新版本
  /// - belowMinVersion: 是否低于最低支持版本
  /// - verCode: 最新版本号
  /// - minVerCode: 最低支持版本号
  /// - verName: 版本名称
  /// - changes: 更新内容
  Future<Map<String, dynamic>?> checkForUpdateOnStartup(int currentBuildNumber) async {
    if (_isChecking.value) return null;

    _isChecking.value = true;

    try {
      // 添加时间戳参数避免缓存，确保获取最新版本
      String updateUrl = Config.updateUrl;
      String separator = updateUrl.contains('?') ? '&' : '?';
      updateUrl = '$updateUrl${separator}t=${DateTime.now().millisecondsSinceEpoch}';

      final response = await http.get(Uri.parse(updateUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 对象格式：{"verCode":25101301,"verName":"25.10.13", "minVerCode":25101301, "changes":["修复已知问题"]}
        if (data is Map<String, dynamic>) {
          final verCodeObj = data['verCode'];
          int? verCode;
          if (verCodeObj is int) {
            verCode = verCodeObj;
          } else if (verCodeObj is String) {
            verCode = int.tryParse(verCodeObj);
          }

          // 解析最低支持版本
          final minVerCodeObj = data['minVerCode'];
          int? minVerCode;
          if (minVerCodeObj is int) {
            minVerCode = minVerCodeObj;
          } else if (minVerCodeObj is String) {
            minVerCode = int.tryParse(minVerCodeObj);
          }

          // 检查是否低于最低支持版本
          bool belowMinVersion = false;
          if (minVerCode != null && currentBuildNumber < minVerCode) {
            belowMinVersion = true;
          }

          // 检查是否有新版本或低于最低支持版本
          if (verCode != null && (verCode > currentBuildNumber || belowMinVersion)) {
            return {
              'hasUpdate': verCode > currentBuildNumber,
              'belowMinVersion': belowMinVersion,
              'verCode': verCode,
              'minVerCode': minVerCode,
              'verName': data['verName']?.toString() ?? '',
              'changes': List<String>.from(data['changes'] ?? []),
            };
          }
        }
      }
    } catch (e) {
      debugPrint('启动时检查更新失败: $e');
    } finally {
      _isChecking.value = false;
    }

    return null;
  }

  /// 检查更新
  Future<bool> checkForUpdate({bool showDialog = true}) async {
    if (_isChecking.value) return false;

    _isChecking.value = true;

    try {
      // 添加时间戳参数避免缓存，确保获取最新版本
      String updateUrl = Config.updateUrl;
      String separator = updateUrl.contains('?') ? '&' : '?';
      updateUrl = '$updateUrl${separator}t=${DateTime.now().millisecondsSinceEpoch}';

      final response = await http.get(Uri.parse(updateUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 对象格式：{"verCode":25101301,"verName":"25.10.13", "changes":["修复已知问题，提升稳定性"]}
        if (data is Map<String, dynamic>) {
          final newVersion = data['verName']?.toString() ?? '';
          final newBuildNumber = data['verCode']?.toString() ?? '';
          final changes = List<String>.from(data['changes'] ?? []);

          // 比较版本号
          if (_isNewerVersion(newVersion, _currentVersion.value)) {
            final updateInfo = UpdateInfo(
              version: newVersion,
              buildNumber: newBuildNumber,
              downloadUrl: _getDownloadUrl(newBuildNumber),
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

  /// 获取下载链接，添加版本号参数避免 CDN 缓存
  String _getDownloadUrl(String verCode) {
    String baseUrl;
    if (Platform.isWindows) {
      baseUrl = Config.windowsUrl;
    } else if (Platform.isLinux) {
      baseUrl = Config.linuxUrl;
    } else if (Platform.isAndroid) {
      baseUrl = Config.apkUrl;
    } else {
      ToastUtil.error('不支持的下载平台: ${Platform.operatingSystem}');
      return '';
    }

    // 添加版本号参数
    String separator = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl${separator}ver=$verCode';
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
        title: Text('发现新版本 ${updateInfo.buildNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本: ${_currentBuildNumber.value}'),
            Text('最新版本: ${updateInfo.buildNumber}'),
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
        Get.snackbar('下载更新', '正在打开下载页面，请下载并安装新版本', snackPosition: SnackPosition.TOP, duration: Duration(seconds: 5));
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
                openAppStore();
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

  /// 打开 App Store（用于 iOS/macOS）
  Future<void> openAppStore() async {
    try {
      // TODO: 替换为实际的 App Store ID
      const appStoreId = '6479052096'; // 这里需要替换为实际的 App Store ID
      
      if (Platform.isIOS) {
        // iOS: 使用 itms-apps URL scheme
        final url = 'itms-apps://itunes.apple.com/app/id$appStoreId';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else if (Platform.isMacOS) {
        // macOS: 使用 macappstore URL scheme
        final url = 'macappstore://itunes.apple.com/app/id$appStoreId';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('打开 App Store 失败: $e');
      Get.snackbar('提示', '无法打开 App Store，请手动搜索"泡泡单词"进行更新', snackPosition: SnackPosition.TOP);
    }
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
