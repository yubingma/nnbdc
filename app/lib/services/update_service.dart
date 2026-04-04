import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nnbdc/util/toast_util.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get/get.dart';
import '../config.dart';
import 'package:appcheck/appcheck.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

class AndroidMarket {
  final String name;
  final String packageName;
  final String scheme;
  final Color color;
  final bool isLive;

  AndroidMarket({
    required this.name,
    required this.packageName,
    required this.scheme,
    this.color = Colors.blue,
    this.isLive = false,
  });
}

class UpdateInfo {
  final String version;
  final String buildNumber;
  final String downloadUrl;
  final String size;
  final String releaseNotes;
  final bool isForce;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.size,
    required this.releaseNotes,
    this.isForce = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      buildNumber: json['verCode']?.toString() ?? '',
      downloadUrl: json['downloadUrl'] ?? Config.apkUrl,
      size: json['size'] ?? '0',
      releaseNotes: List<String>.from(json['changes'] ?? []).join('\n'),
      isForce: false,
    );
  }
}

class UpdateService extends GetxController {
  static UpdateService get instance => Get.find<UpdateService>();

  final RxBool _isChecking = false.obs;
  final RxString _packageName = ''.obs;
  final RxString _currentVersion = ''.obs;
  final Rx<UpdateInfo?> _updateInfo = Rx<UpdateInfo?>(null);

  bool get isChecking => _isChecking.value;
  UpdateInfo? get updateInfo => _updateInfo.value;
  String get currentVersion => _currentVersion.value;

  @override
  void onInit() {
    super.onInit();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _packageName.value = packageInfo.packageName;
      _currentVersion.value = packageInfo.version;
    } catch (e) {
      debugPrint('获取包信息失败: $e');
    }
  }

  Future<Map<String, dynamic>?> checkForUpdateOnStartup(int currentBuildNumber) async {
    if (_isChecking.value) return null;
    _isChecking.value = true;
    try {
      String updateUrl = Config.updateUrl;
      final response = await http.get(Uri.parse('$updateUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final verCode = (data['verCode'] is String) ? int.tryParse(data['verCode']) : data['verCode'] as int?;
        final minVerCode = (data['minVerCode'] is String) ? int.tryParse(data['minVerCode']) : data['minVerCode'] as int?;
        if (verCode != null) {
          bool hasUpdate = verCode > currentBuildNumber;
          bool belowMin = (minVerCode != null && currentBuildNumber < minVerCode);
          if (hasUpdate || belowMin) {
            return {
              'hasUpdate': hasUpdate,
              'belowMinVersion': belowMin,
              'verCode': verCode,
              'changes': List<String>.from(data['changes'] ?? []),
            };
          }
        }
      }
    } catch (e) {
      debugPrint('检查更新失败: $e');
    } finally {
      _isChecking.value = false;
    }
    return null;
  }

  Future<void> checkForUpdate({bool showToastIfLatest = true}) async {
    final info = await PackageInfo.fromPlatform();
    final result = await checkForUpdateOnStartup(int.parse(info.buildNumber));
    if (result != null) {
      // 根据平台动态匹配下载链接
      String downloadUrl = Config.apkUrl;
      if (Platform.isWindows) {
        downloadUrl = Config.windowsUrl;
      } else if (Platform.isLinux) {
        downloadUrl = Config.linuxUrl;
      }

      final updateInfo = UpdateInfo(
        version: result['verCode'].toString(),
        buildNumber: result['verCode'].toString(),
        downloadUrl: '$downloadUrl?ver=${result['verCode']}',
        size: '0',
        releaseNotes: (result['changes'] as List).join('\n'),
        isForce: result['belowMinVersion'] ?? false,
      );
      _updateInfo.value = updateInfo;
      await downloadUpdate(updateInfo);
    } else if (showToastIfLatest) {
      ToastUtil.success('当前已是最新版本');
    }
  }

  Future<void> downloadUpdate(UpdateInfo info) async {
    if (Platform.isAndroid) {
      await _showAndroidUpgradeDialog(info);
    } else if (Platform.isIOS || Platform.isMacOS) {
      await openAppStore();
    } else if (Platform.isWindows) {
      await _downloadAndInstallWindows(info);
    } else if (Platform.isLinux) {
      await _downloadAndInstallLinux(info);
    } else {
      await launchUrl(Uri.parse(info.downloadUrl));
    }
  }

  /// Linux 自动更新逻辑
  Future<void> _downloadAndInstallLinux(UpdateInfo info) async {
    final progress = 0.0.obs;
    Get.dialog(
      Obx(() => AlertDialog(
            title: const Text('正在更新 Linux 版本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress.value),
                const SizedBox(height: 10),
                const Text('正在下载安装包...', style: TextStyle(fontSize: 12)),
              ],
            ),
          )),
      barrierDismissible: false,
    );

    try {
      final dio = Dio();
      final dir = await getApplicationDocumentsDirectory();
      final fileName = info.downloadUrl.substring(info.downloadUrl.lastIndexOf("/") + 1);
      final savePath = "${dir.path}/$fileName";

      await dio.download(info.downloadUrl, savePath, onReceiveProgress: (rec, total) {
        if (total != -1) progress.value = rec / total;
      });

      Get.back();

      // Linux 核心补全：加权，启动，自杀
      try {
        // 1. 给 AppImage 加执行权限
        await Process.run('chmod', ['+x', savePath]);

        // 2. 启动新进程
        await Process.start(savePath, [], runInShell: true);

        // 3. 退出当前版本完成更新
        exit(0);
      } catch (e) {
        // 如果自动加权启动失败，尝试普通打开
        await OpenFile.open(savePath);
        ToastUtil.info('由于系统限制无法直接启动，请手动打开安装包');
      }
    } catch (e) {
      Get.back();
      ToastUtil.error('Linux 更新失败: $e');
    }
  }

  /// Windows 静默安装逻辑
  Future<void> _downloadAndInstallWindows(UpdateInfo info) async {
    final progress = 0.0.obs;
    final status = '正在准备下载...'.obs;

    Get.dialog(
      Obx(() => AlertDialog(
            title: const Text('正在更新 Windows 版本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress.value),
                const SizedBox(height: 10),
                Text(status.value, style: const TextStyle(fontSize: 12)),
              ],
            ),
          )),
      barrierDismissible: false,
    );

    try {
      final dio = Dio();
      final dir = await getApplicationDocumentsDirectory();
      final fileName = info.downloadUrl.substring(info.downloadUrl.lastIndexOf("/") + 1);
      final savePath = "${dir.path}/$fileName";

      status.value = '正在下载安装包...';
      await dio.download(info.downloadUrl, savePath, onReceiveProgress: (rec, total) {
        if (total != -1) progress.value = rec / total;
      });

      status.value = '正在执行静默安装，应用即将重启...';
      await _performWindowsSilentInstall(savePath);
    } catch (e) {
      Get.back();
      ToastUtil.error('更新失败: $e');
    }
  }

  Future<void> _performWindowsSilentInstall(String installerPath) async {
    final currentPid = pid;
    final currentExe = Platform.resolvedExecutable;
    final exeName = currentExe.split(Platform.pathSeparator).last;
    final dir = await getApplicationDocumentsDirectory();
    final scriptPath = "${dir.path}/update_installer.bat";

    final script = '''
@echo off
timeout /t 2 /nobreak > nul
taskkill /f /pid $currentPid > nul 2>&1
taskkill /f /im "$exeName" /t > nul 2>&1
timeout /t 1 /nobreak > nul
start /wait "" "$installerPath" /S
start "" "$currentExe"
del "%~f0"
exit
''';
    await File(scriptPath).writeAsString(script);
    await Process.start('cmd', ['/c', 'start', '/min', '""', scriptPath], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> _showAndroidUpgradeDialog(UpdateInfo info) async {
    List<AndroidMarket> installed = [];
    final all = [
      AndroidMarket(name: '华为应用市场', packageName: 'com.huawei.appmarket', scheme: 'appmarket://details?id=', color: Colors.green[600]!, isLive: true),
      AndroidMarket(name: '小米应用商店', packageName: 'com.xiaomi.market', scheme: 'mimarket://details?id=', color: Colors.orange[700]!, isLive: false),
      AndroidMarket(name: 'vivo 应用商店', packageName: 'com.bbk.appstore', scheme: 'vivomarket://details?id=', color: Colors.blue[700]!, isLive: false),
    ];
    try {
      final appCheck = AppCheck();
      for (var m in all) {
        if (m.isLive && await appCheck.isAppInstalled(m.packageName)) {
          installed.add(m);
        }
      }
    } catch (_) {}

    Get.dialog(
      AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发现新版本 ${info.version}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text('当前版本: ${_currentVersion.value}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.normal)),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.releaseNotes.isNotEmpty) ...[
              const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Text(info.releaseNotes, style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 12), // 缩减间距
            ...installed.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6), // 市场按钮也变紧凑
                  child: ElevatedButton(
                    onPressed: () {
                      Get.back();
                      openMarket(m);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: m.color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 40)),
                    child: Text('前往 ${m.name} 更新'),
                  ),
                )),
            Center(
              child: TextButton(
                onPressed: () {
                  Get.back();
                  _downloadAndInstallApk(info);
                },
                child: const Text('从官网下载更新', style: TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
              ),
            ),
          ],
        ),
        actions: [
          if (!info.isForce)
            TextButton(
                onPressed: () => Get.back(),
                child: const Text('稍后升级', style: TextStyle(color: Colors.grey, fontSize: 13))),
        ],
      ),
      barrierDismissible: !info.isForce,
    );
  }

  Future<void> _downloadAndInstallApk(UpdateInfo info) async {
    if (Platform.isAndroid) await Permission.requestInstallPackages.request();
    final progress = 0.0.obs;
    Get.dialog(
      Obx(() => AlertDialog(
            title: const Text('正在下载更新'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: progress.value),
              SizedBox(height: 10),
              Text('${(progress.value * 100).toStringAsFixed(1)}%')
            ]),
          )),
      barrierDismissible: !info.isForce,
    );
    try {
      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final path = "${dir.path}/nnbdc_update.apk";
      await dio.download(info.downloadUrl, path, onReceiveProgress: (rec, total) {
        if (total != -1) progress.value = rec / total;
      });
      if (Get.isDialogOpen ?? false) Get.back();
      await OpenFile.open(path, type: "application/vnd.android.package-archive");
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      ToastUtil.error('下载失败: $e');
    }
  }

  Future<void> openMarket(AndroidMarket market) async {
    final String package = _packageName.value.isNotEmpty ? _packageName.value : "com.nn.nnbdc.android";
    final url = "${market.scheme}$package";
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (market.packageName == 'com.huawei.appmarket') {
        launchUrl(Uri.parse("https://appgallery.huawei.com/#/app/$package"), mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> openAppStore() async {
    await launchUrl(Uri.parse('https://apps.apple.com/app/id6756229006'), mode: LaunchMode.externalApplication);
  }
}
