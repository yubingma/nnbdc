import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get/get.dart';
import '../global.dart';
import '../config.dart';
import 'package:appcheck/appcheck.dart';

class AndroidMarket {
  final String name;
  final String packageName;
  final String scheme;
  final Color color;

  AndroidMarket({
    required this.name,
    required this.packageName,
    required this.scheme,
    this.color = Colors.blue,
  });
}

class UpdateInfo {
  final String version;
  final String buildNumber;
  final String downloadUrl;
  final String size;
  final String releaseNotes;
  final bool requiresRestart;
  final String installerType;
  final bool isForce;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.size,
    required this.releaseNotes,
    this.requiresRestart = false,
    this.installerType = 'setup',
    this.isForce = false,
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
      isForce: json['isForce'] ?? false,
    );
  }
}

class UpdateService extends GetxController {
  static UpdateService get instance => Get.find<UpdateService>();

  final RxBool _isChecking = false.obs;
  final Rx<UpdateInfo?> _updateInfo = Rx<UpdateInfo?>(null);
  final RxString _currentVersion = ''.obs;
  final RxString _currentBuildNumber = ''.obs;
  final RxString _packageName = ''.obs;

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
      _packageName.value = packageInfo.packageName;
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
      updateUrl = '$updateUrl${separator}t=${AppClock.now().millisecondsSinceEpoch}';

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
      updateUrl = '$updateUrl${separator}t=${AppClock.now().millisecondsSinceEpoch}';

      final response = await http.get(Uri.parse(updateUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 对象格式：{"verCode":25101301,"verName":"25.10.13", "changes":["修复已知问题，提升稳定性"]}
        if (data is Map<String, dynamic>) {
          final newVersion = data['verName']?.toString() ?? '';
          final newBuildNumberObj = data['verCode'];
          final minVerCodeObj = data['minVerCode'];
          
          int newBuildNumber = 0;
          if (newBuildNumberObj is int) {
            newBuildNumber = newBuildNumberObj;
          } else if (newBuildNumberObj is String) {
            newBuildNumber = int.tryParse(newBuildNumberObj) ?? 0;
          }
          
          int minVerCode = 0;
          if (minVerCodeObj is int) {
            minVerCode = minVerCodeObj;
          } else if (minVerCodeObj is String) {
            minVerCode = int.tryParse(minVerCodeObj) ?? 0;
          }

          final changes = List<String>.from(data['changes'] ?? []);
          final currentBuildInt = int.tryParse(_currentBuildNumber.value) ?? 0;
          
          // 检查是否需要更新或强制更新
          bool isNewer = _isNewerVersion(newVersion, _currentVersion.value);
          bool isBelowMin = minVerCode > 0 && currentBuildInt < minVerCode;

          if (isNewer || isBelowMin) {
            final updateInfo = UpdateInfo(
              version: newVersion,
              buildNumber: newBuildNumber.toString(),
              downloadUrl: _getDownloadUrl(newBuildNumber.toString()),
              size: '0',
              releaseNotes: changes.join('\n'),
              requiresRestart: true,
              installerType: 'setup',
              isForce: isBelowMin,
            );

            _updateInfo.value = updateInfo;
            if (showDialog) {
              if (Platform.isAndroid) {
                _showAndroidUpgradeDialog(updateInfo);
              } else {
                _showUpdateDialog(updateInfo);
              }
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
      } else if (Platform.isAndroid) {
        // Android 显示升级说明，引导到华为市场
        _showAndroidUpgradeDialog(updateInfo);
      } else {
        // 其他平台
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
            Text('2. 搜索"${Global.appName}"'),
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
      const appStoreId = '6756229006'; // App Store ID
      final appName = Global.appName; // App 名称，用于搜索
      
      if (Platform.isIOS) {
        // iOS: 优先尝试直接打开 App Store 页面
        // 如果失败，则使用搜索方式
        try {
          // 方法1: 使用 https URL（推荐，跨地区兼容性好）
          final url = 'https://apps.apple.com/app/id$appStoreId';
          final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          
          if (!launched) {
            // 如果失败，使用搜索方式
            await _openAppStoreBySearch(appName);
          }
        } catch (e) {
          debugPrint('使用 https URL 打开失败: $e，尝试搜索方式');
          await _openAppStoreBySearch(appName);
        }
      } else if (Platform.isMacOS) {
        // macOS: 使用 https URL
        try {
          final url = 'https://apps.apple.com/app/id$appStoreId';
          final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          
          if (!launched) {
            await _openAppStoreBySearch(appName);
          }
        } catch (e) {
          debugPrint('使用 https URL 打开失败: $e，尝试搜索方式');
          await _openAppStoreBySearch(appName);
        }
      }
    } catch (e) {
      debugPrint('打开 App Store 失败: $e');
      Get.snackbar('提示', '无法打开 App Store，请手动搜索"${Global.appName}"进行更新', snackPosition: SnackPosition.TOP);
    }
  }

  /// 通过搜索方式打开 App Store
  Future<void> _openAppStoreBySearch(String appName) async {
    try {
      if (Platform.isIOS) {
        // iOS: 使用搜索 URL
        final searchUrl = 'https://apps.apple.com/search?term=${Uri.encodeComponent(appName)}';
        await launchUrl(Uri.parse(searchUrl), mode: LaunchMode.externalApplication);
      } else if (Platform.isMacOS) {
        // macOS: 使用搜索 URL
        final searchUrl = 'https://apps.apple.com/search?term=${Uri.encodeComponent(appName)}';
        await launchUrl(Uri.parse(searchUrl), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('搜索方式打开失败: $e');
      rethrow;
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

  /// 显示 Android 升级说明
  void _showAndroidUpgradeDialog(UpdateInfo updateInfo) async {
    List<AndroidMarket> installedMarkets = [];
    
    // 检测已安装的市场
    final allMarkets = [
      AndroidMarket(name: '华为应用市场', packageName: 'com.huawei.appmarket', scheme: 'appmarket://details?id=', color: Colors.green[600]!),
      AndroidMarket(name: '小米应用商店', packageName: 'com.xiaomi.market', scheme: 'mimarket://details?id=', color: Colors.orange[700]!),
      AndroidMarket(name: 'OPPO 软件商店', packageName: 'com.oppo.market', scheme: 'oppomarket://details?packagename=', color: Colors.green[700]!),
      AndroidMarket(name: 'vivo 应用商店', packageName: 'com.bbk.appstore', scheme: 'vivomarket://details?id=', color: Colors.blue[700]!), // bbk 是 vivo 的母公司品牌名
      AndroidMarket(name: '三星 Galaxy Store', packageName: 'com.sec.android.app.samsungapps', scheme: 'samsungapps://ProductDetail/', color: Colors.blueAccent),
    ];

    // 备选包名映射 (用于更精准的检测)
    final fallbackPackages = {
      'com.huawei.appmarket': ['com.huawei.market', 'com.huawei.appgallery'],
      'com.bbk.appstore': ['com.vivo.appstore', 'com.vivo.market'],
    };

    try {
      final appCheck = AppCheck();
      for (var market in allMarkets) {
        bool isInstalled = await appCheck.isAppInstalled(market.packageName);
        
        // 如果主包名未检测到，尝试备选包名
        if (!isInstalled && fallbackPackages.containsKey(market.packageName)) {
          for (var fallback in fallbackPackages[market.packageName]!) {
            if (await appCheck.isAppInstalled(fallback)) {
              isInstalled = true;
              break;
            }
          }
        }

        if (isInstalled) {
          installedMarkets.add(market);
        }
      }
    } catch (e) {
      debugPrint('检测应用市场安装情况失败: $e');
    }

    Get.dialog(
      AlertDialog(
        title: Text('发现新版本 ${updateInfo.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本: ${_currentBuildNumber.value}'),
            Text('最新版本: ${updateInfo.buildNumber}'),
            SizedBox(height: 12),
            if (installedMarkets.isNotEmpty)
              Text('检测到您的手机已安装以下应用市场，建议优先通过应用市场更新：')
            else
              Text('由于未检测到主流应用市场，建议直接下载 APK 进行更新：'),
            
            if (updateInfo.releaseNotes.isNotEmpty) ...[
              SizedBox(height: 12),
              Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Container(
                constraints: BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(updateInfo.releaseNotes, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ),
              ),
            ],
            
            SizedBox(height: 20),
            
            // 展示所有检测到的市场按钮
            ...installedMarkets.map((market) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Get.back();
                    openMarket(market);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: market.color,
                    foregroundColor: Colors.white,
                    minimumSize: Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                  child: Text('前往 ${market.name} 更新'),
                ),
              ),
            )),

            // 如果没有安装任何市场，或者作为备选方案展示下载按钮
            Center(
              child: TextButton(
                onPressed: installedMarkets.isEmpty 
                  ? () { Get.back(); launchUrl(Uri.parse(updateInfo.downloadUrl), mode: LaunchMode.externalApplication); }
                  : () => _confirmDirectDownload(updateInfo.downloadUrl),
                child: Text(
                  installedMarkets.isEmpty ? '立即下载 APK 更新' : '仍然选择下载 APK 更新',
                  style: TextStyle(
                    color: Colors.grey[600], 
                    fontSize: 12, 
                    decoration: TextDecoration.underline
                  )
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (!updateInfo.isForce)
            TextButton(
              onPressed: () => Get.back(),
              child: Text('稍后升级'),
            ),
        ],
      ),
      barrierDismissible: !updateInfo.isForce,
    );
  }

  /// 确认直接下载
  void _confirmDirectDownload(String url) {
    Get.dialog(
      AlertDialog(
        title: Text('建议通过应用市场更新'),
        content: Text('通过官网直接下载安装可能会被系统拦截或产生多个重复安装包。确定要直接下载吗？'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('返回市场')),
          TextButton(
            onPressed: () {
              Get.back();
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }, 
            child: Text('确定下载', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  /// 打开指定的应用市场
  Future<void> openMarket(AndroidMarket market) async {
    try {
      final String package = _packageName.value.isNotEmpty ? _packageName.value : "com.nn.nnbdc.android";
      final String schemaUrl = "${market.scheme}$package";

      final launched = await launchUrl(Uri.parse(schemaUrl), mode: LaunchMode.externalApplication);
      if (!launched) {
        // 如果无法通过 Schema 打开，对于华为尝试网页版，其他通用提示
        if (market.packageName == 'com.huawei.appmarket') {
          await launchUrl(Uri.parse("https://appgallery.huawei.com/#/app/$package"), mode: LaunchMode.externalApplication);
        } else {
          Get.snackbar('提示', '无法自动打开 ${market.name}，请手动搜索"${Global.appName}"进行更新', snackPosition: SnackPosition.TOP);
        }
      }
    } catch (e) {
      debugPrint('打开市场失败: $e');
      Get.snackbar('提示', '操作失败，请手动前往市场更新', snackPosition: SnackPosition.TOP);
    }
  }

  /// 自动检查更新（应用启动时调用）
  Future<void> autoCheckUpdate() async {
    // 可以添加时间间隔检查逻辑
    await Future.delayed(Duration(seconds: 3)); // 延迟3秒后检查
    await checkForUpdate(showDialog: false);
  }
}
