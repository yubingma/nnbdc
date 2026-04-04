import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:confirm_dialog/confirm_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/index.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get_storage/get_storage.dart';
import 'package:drift/drift.dart' as drift hide Column;
import 'package:umeng_common_sdk/umeng_common_sdk.dart';

import '../config.dart';
import '../global.dart';
import '../services/update_service.dart';
import '../util/app_clock.dart';

class FirstPage extends StatefulWidget {
  const FirstPage({super.key});

  @override
  FirstPageState createState() {
    return FirstPageState();
  }
}

class FirstPageState extends State<FirstPage> with SingleTickerProviderStateMixin {
  /// 下载是否已经开始，下载开始时置为true，不再改变
  bool downloadStarted = false;

  bool downloading = false;
  String savePath = "";
  bool downloadSuccess = false;
  int? downloadedBytes;
  int? totalBytes;
  bool installing = false; // 安装状态
  String? installingMessage; // 安装状态消息

  bool newVersionFound = false;
  bool newVersionIgnored = false;
  int? newVerCode; // 保存新版本的 verCode，用于下载时添加版本参数和显示
  List<dynamic>? newVersionChanges;

  // 准备阶段状态提示
  String _preparingMessage = '正在准备学习环境…';

  /// 自动登录阶段错误（显示在启动页文案下方，不使用toast）
  String? _autoLoginError;

  // 版本信息
  String? _buildNumber;
  String? _versionName;

  // 动态闪屏：动画控制与数据
  late AnimationController _splashController;
  late List<_Bubble> _bubbles;
  final String _splashText = "Progress, not perfection\n进步而非完美";

  void checkNewVersion() async {
    
    // 检查新版本/自动升级
    if (PlatformUtils.isAndroid || PlatformUtils.isWindows || PlatformUtils.isLinux) {
      setState(() {
        _preparingMessage = '正在检查更新…';
      });

      // 获取程序版本信息
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int buildNumber = int.parse(packageInfo.buildNumber);
      Global.version = packageInfo.version;

      // 保存版本代码用于显示
      if (mounted) {
        setState(() {
          _buildNumber = packageInfo.buildNumber;
        });
      }

      // 使用 UpdateService 统一检查版本
      try {
        // 确保 UpdateService 已注册
        UpdateService? updateService;
        try {
          updateService = Get.find<UpdateService>();
        } catch (e) {
          // 如果未注册，则创建并注册
          updateService = UpdateService();
          Get.put(updateService);
        }

        // 调用启动时检查方法
        final versionInfo = await updateService.checkForUpdateOnStartup(buildNumber);

        if (versionInfo != null) {
          // 检查是否低于最低支持版本
          bool belowMinVersion = versionInfo['belowMinVersion'] as bool? ?? false;
          bool hasUpdate = versionInfo['hasUpdate'] as bool? ?? false;
          int verCode = versionInfo['verCode'] as int;
          var changes = versionInfo['changes'] as List<String>;

          setState(() {
            newVersionFound = true;
            newVerCode = verCode; // 保存版本号，用于下载时添加版本参数和显示
            newVersionChanges = changes;
          });

          // 如果低于最低支持版本，显示强制升级对话框
          if (belowMinVersion) {
            await showForceUpgradeDialog(verCode, changes);
          } else if (hasUpdate) {
            // 有新版本但不强制，显示普通升级对话框
            await showUpgradeConfirmDlg(verCode, changes);
          } else {
            // 已经是最新版本
            tryAutoLogin();
          }
        } else {
          /// 已经是最新版本
          tryAutoLogin();
        }
      } catch (e, stackTrace) {
        // 捕获所有类型的异常（包括 Exception 和 Error）
        Global.logger.e('检查更新异常', error: e, stackTrace: stackTrace);
        ToastUtil.error('获取版本信息失败: $e');
        tryAutoLogin();
      }
    } else if (PlatformUtils.isIOS || PlatformUtils.isMacOS) {
      // iOS/macOS 平台也需要检查最低版本
      setState(() {
        _preparingMessage = '正在检查版本…';
      });

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int buildNumber = int.parse(packageInfo.buildNumber);
      Global.version = packageInfo.version;

      if (mounted) {
        setState(() {
          _buildNumber = packageInfo.buildNumber;
        });
      }

      try {
        UpdateService? updateService;
        try {
          updateService = Get.find<UpdateService>();
        } catch (e) {
          updateService = UpdateService();
          Get.put(updateService);
        }

        final versionInfo = await updateService.checkForUpdateOnStartup(buildNumber);

        if (versionInfo != null) {
          bool belowMinVersion = versionInfo['belowMinVersion'] as bool? ?? false;
          int verCode = versionInfo['verCode'] as int;
          var changes = versionInfo['changes'] as List<String>;

          // 如果低于最低支持版本，显示强制升级提示
          if (belowMinVersion) {
            await showForceUpgradeDialogForApple(verCode, changes);
          } else {
            // iOS/macOS 正常进入应用
            tryAutoLogin();
          }
        } else {
          tryAutoLogin();
        }
      } catch (e, stackTrace) {
        Global.logger.e('检查版本异常', error: e, stackTrace: stackTrace);
        tryAutoLogin();
      }
    } else {
      /// 其他平台
      tryAutoLogin();
    }
  }

  /// 设置准备阶段提示文案（自动判断 mounted，避免异步 setState 异常）
  void _setPreparingMessage(String msg) {
    if (!mounted) return;
    if (_preparingMessage == msg) return;
    setState(() {
      _preparingMessage = msg;
    });
  }

  void _setAutoLoginError(String? msg) {
    if (!mounted) return;
    setState(() {
      _autoLoginError = msg;
    });
  }

  Future<void> _retryStartup() async {
    Global.clearStartupError();
    _setAutoLoginError(null);

    try {
      // 1) 清空并重建本地数据库（与 me.dart 的“重建数据库”保持一致）
      _setPreparingMessage('正在清空本地数据…');
      await MyDatabase.instance.wipeAllTables();

      // 2) 清理本地登录态与内存缓存，避免残留 userId 导致后续流程异常
      try {
        await GetStorage().remove('currentUserId');
      } catch (e) {
        // GetStorage 可能尚未初始化；忽略并继续
      }
      Global.clearUserCache();
      Global.currentUserId = null;

      // 3) 重建后重新走启动流程：先检查更新，再自动登录
      _setPreparingMessage('正在重试…');
      checkNewVersion();
    } catch (e, stackTrace) {
      Global.logger.e('清空本地数据并重试失败', error: e, stackTrace: stackTrace);
      _setAutoLoginError('清空本地数据失败：$e');
    }
  }

  /// 初始化版本信息，避免出现"版本 null (dev)"这种误导信息
  Future<void> _initVersionInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      Global.version = packageInfo.version;
      if (!mounted) return;
      setState(() {
        _buildNumber = packageInfo.buildNumber;
        _versionName = packageInfo.version;
      });
    } catch (e, stackTrace) {
      // 仅记录日志，不影响启动流程
      Global.logger.w('获取版本信息失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 显示强制升级对话框（用于 Android/Windows/Linux）
  Future<void> showForceUpgradeDialog(int verCode, List<dynamic> changes) async {
    if (PlatformUtils.isWindows) {
      // Windows 平台：强制升级
      await showDialog(
        context: context,
        barrierDismissible: false, // 不允许点击外部关闭
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('需要升级'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("当前版本过低，必须升级到版本 $verCode 才能继续使用"),
                const SizedBox(height: 8),
                const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
                for (String change in changes) Text('• $change'),
                const SizedBox(height: 8),
                Text('\n将自动完成安装，无需手动操作。', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  downloadWindowsAndUpgrade(useSilent: true);
                },
                child: const Text('立即升级'),
              ),
            ],
          );
        },
      );
    } else if (PlatformUtils.isLinux) {
      // Linux 平台：强制升级
      await showDialog(
        context: context,
        barrierDismissible: false, // 不允许点击外部关闭
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('需要升级'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("当前版本过低，必须升级到版本 $verCode 才能继续使用"),
                const SizedBox(height: 8),
                const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
                for (String change in changes) Text('• $change'),
                const SizedBox(height: 8),
                Text('\n将自动下载并替换应用文件，无需手动操作。', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  downloadLinuxAndUpgrade();
                },
                child: const Text('立即升级'),
              ),
            ],
          );
        },
      );
    } else if (PlatformUtils.isAndroid) {
      // Android 平台：引导到应用市场
      UpdateService? updateService;
      try {
        updateService = Get.find<UpdateService>();
      } catch (e) {
        updateService = UpdateService();
        Get.put(updateService);
      }
      
      final updateInfo = UpdateInfo(
        version: verCode.toString(),
        buildNumber: verCode.toString(),
        downloadUrl: Config.apkUrl,
        size: '0',
        releaseNotes: changes.join('\n'),
      );
      
      await updateService.downloadUpdate(updateInfo);
    }
  }

  /// 显示强制升级对话框（用于 iOS/macOS - 导航到 App Store）
  Future<void> showForceUpgradeDialogForApple(int verCode, List<dynamic> changes) async {
    // 获取 UpdateService
    UpdateService? updateService;
    try {
      updateService = Get.find<UpdateService>();
    } catch (e) {
      updateService = UpdateService();
      Get.put(updateService);
    }

    await showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(PlatformUtils.isIOS ? 'app 版本过低' : 'app 版本过低'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("当前版本过低，必须升级到版本 $verCode 才能继续使用"),
              const SizedBox(height: 16),
              const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (String change in changes) Text('• $change'),
              const SizedBox(height: 16),
              const Text('升级步骤：', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('1. 点击下方按钮打开 App Store'),
              Text('2. 搜索"${Global.appName}"'),
              const Text('3. 点击"更新"按钮'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                updateService?.openAppStore();
                // 打开 App Store 后退出应用
                Future.delayed(const Duration(seconds: 1), () {
                  SystemNavigator.pop();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('前往 App Store'),
            ),
          ],
        );
      },
    );
  }

  Future<void> showUpgradeConfirmDlg(int verCode, changes) async {
    if (PlatformUtils.isWindows) {
      // Windows 平台：直接使用静默安装，显示确认对话框
      if (await confirm(
        context,
        title: const Text('发现新版本'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("发现新版本 $verCode"),
            SizedBox(height: 8),
            Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
            for (String change in changes) Text('• $change'),
            SizedBox(height: 8),
            Text('\n将自动完成安装，无需手动操作。是否升级？', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        textOK: const Text('是'),
        textCancel: const Text('否'),
      )) {
        // 直接执行静默安装
        downloadWindowsAndUpgrade(useSilent: true);
      } else {
        // 用户选择不升级，标记为已忽略，不显示界面提示
        setState(() {
          newVersionIgnored = true;
        });
        tryAutoLogin();
      }
    } else if (PlatformUtils.isLinux) {
      // Linux 平台：使用静默升级
      if (await confirm(
        context,
        title: const Text('发现新版本'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("发现新版本 $verCode"),
            SizedBox(height: 8),
            Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
            for (String change in changes) Text('• $change'),
            SizedBox(height: 8),
            Text('\n将自动下载并替换应用文件，无需手动操作。是否升级？', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        textOK: const Text('是'),
        textCancel: const Text('否'),
      )) {
        // 直接执行自动升级
        downloadLinuxAndUpgrade();
      } else {
        // 用户选择不升级，标记为已忽略，不显示界面提示
        setState(() {
          newVersionIgnored = true;
        });
        tryAutoLogin();
      }
    } else if (PlatformUtils.isAndroid) {
      // Android 平台：引导到应用市场
      UpdateService? updateService;
      try {
        updateService = Get.find<UpdateService>();
      } catch (e) {
        updateService = UpdateService();
        Get.put(updateService);
      }

      final updateInfo = UpdateInfo(
        version: verCode.toString(),
        buildNumber: verCode.toString(),
        downloadUrl: Config.apkUrl,
        size: '0',
        releaseNotes: (changes as List).join('\n'),
      );
      
      // 直接显示市场引导弹窗
      await updateService.downloadUpdate(updateInfo);
    } else {
      // 其他未知平台
      tryAutoLogin();
    }
  }

  Future downloadApkAndUpgrade() async {
    try {
      Dio dio = Dio();

      // 构建带版本号的下载 URL
      String downloadUrl = Config.apkUrl;
      if (newVerCode != null) {
        String separator = downloadUrl.contains('?') ? '&' : '?';
        downloadUrl = '$downloadUrl${separator}ver=$newVerCode';
      }

      String fileName = Config.apkUrl.substring(Config.apkUrl.lastIndexOf("/") + 1);

      savePath = await getFilePath(fileName);
      downloadStarted = true;
      downloading = true;
      var resp = await dio.download(downloadUrl, savePath, deleteOnError: true, onReceiveProgress: (rec, total) {
        setState(() {
          downloading = true;
          downloadedBytes = rec;
          totalBytes = total;
        });
      });
      if (resp.statusCode == 200) {
        setState(() {
          downloading = false;
          downloadSuccess = true;
          installing = true;
          installingMessage = '正在准备安装...';
        });
        installApk();
      } else {
        ToastUtil.error(("download apk failed, status code: ${resp.statusCode}"));
        setState(() {
          downloading = false;
          downloadSuccess = false;
        });
        tryAutoLogin();
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '下载新版本失败', showToast: true);
      setState(() {
        downloading = false;
        downloadSuccess = false;
      });
      tryAutoLogin(); // 仍使用旧版本
    }
  }

  Future<String> getFilePath(uniqueFileName) async {
    String path = '';

    Directory dir = await getApplicationDocumentsDirectory();

    path = '${dir.path}/$uniqueFileName';

    return path;
  }

  Future<void> installApk() async {
    try {
      setState(() {
        installingMessage = '正在请求安装权限...';
      });

      if (!await Permission.requestInstallPackages.request().isGranted) {
        setState(() {
          installing = false;
          installingMessage = null;
        });
        ToastUtil.error("未获得安装权限，仍使用旧版本");
        tryAutoLogin();
        return;
      }

      setState(() {
        installingMessage = '正在启动安装程序...';
      });

      var result = await OpenFile.open(savePath, type: "application/vnd.android.package-archive");
      if (result.type == ResultType.done) {
        setState(() {
          installingMessage = '安装程序已启动，请按照提示完成安装\n(如果未弹出安装界面，请在通知栏或下载中找安装包)';
        });
      } else {
        setState(() {
          installing = false;
          installingMessage = null;
        });
        ToastUtil.error("${result.message}，仍使用旧版本");
        tryAutoLogin();
      }
    } catch (e) {
      setState(() {
        installing = false;
        installingMessage = null;
      });
      ToastUtil.error("安装失败: $e");
      tryAutoLogin();
    }
  }

  Future downloadLinuxAndUpgrade() async {
    try {
      Dio dio = Dio();

      // 构建带版本号的下载 URL
      String downloadUrl = Config.linuxUrl;
      if (newVerCode != null) {
        String separator = downloadUrl.contains('?') ? '&' : '?';
        downloadUrl = '$downloadUrl${separator}ver=$newVerCode';
      }

      String fileName = Config.linuxUrl.substring(Config.linuxUrl.lastIndexOf("/") + 1);

      savePath = await getFilePath(fileName);
      downloadStarted = true;
      downloading = true;
      var resp = await dio.download(downloadUrl, savePath, deleteOnError: true, onReceiveProgress: (rec, total) {
        setState(() {
          downloading = true;
          downloadedBytes = rec;
          totalBytes = total;
        });
      });
      if (resp.statusCode == 200) {
        setState(() {
          downloading = false;
          downloadSuccess = true;
          installing = true;
          installingMessage = '正在准备安装...';
        });
        // 执行 Linux AppImage 升级
        await installLinuxApp();
      } else {
        ToastUtil.error(("下载Linux安装包失败, status code: ${resp.statusCode}"));
        setState(() {
          downloading = false;
          downloadSuccess = false;
        });
        tryAutoLogin();
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '下载Linux新版本失败', showToast: true);
      setState(() {
        downloading = false;
        downloadSuccess = false;
      });
      tryAutoLogin(); // 仍使用旧版本
    }
  }

  Future downloadWindowsAndUpgrade({bool useSilent = false}) async {
    try {
      Dio dio = Dio();

      // 构建带版本号的下载 URL
      String downloadUrl = Config.windowsUrl;
      if (newVerCode != null) {
        String separator = downloadUrl.contains('?') ? '&' : '?';
        downloadUrl = '$downloadUrl${separator}ver=$newVerCode';
      }

      String fileName = Config.windowsUrl.substring(Config.windowsUrl.lastIndexOf("/") + 1);

      savePath = await getFilePath(fileName);
      downloadStarted = true;
      downloading = true;
      var resp = await dio.download(downloadUrl, savePath, deleteOnError: true, onReceiveProgress: (rec, total) {
        setState(() {
          downloading = true;
          downloadedBytes = rec;
          totalBytes = total;
        });
      });
      if (resp.statusCode == 200) {
        setState(() {
          downloading = false;
          downloadSuccess = true;
          installing = true;
          installingMessage = '正在准备安装...';
        });
        // 传递静默安装参数
        await installWindowsApp(silent: useSilent);
      } else {
        ToastUtil.error(("下载Windows安装包失败, status code: ${resp.statusCode}"));
        setState(() {
          downloading = false;
          downloadSuccess = false;
        });
        tryAutoLogin();
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '下载Windows新版本失败', showToast: true);
      setState(() {
        downloading = false;
        downloadSuccess = false;
      });
      tryAutoLogin(); // 仍使用旧版本
    }
  }

  Future<void> installWindowsApp({bool silent = false}) async {
    try {
      // 检查下载的文件是否是 zip 文件
      String installerPath = savePath;
      if (savePath.toLowerCase().endsWith('.zip')) {
        // 如果是 zip 文件，需要先解压
        setState(() {
          installingMessage = '正在解压安装包...';
        });
        Global.logger.d('检测到 zip 文件，开始解压: $savePath');
        installerPath = await _extractZipFile(savePath);
        if (installerPath.isEmpty) {
          setState(() {
            installing = false;
            installingMessage = null;
          });
          ToastUtil.error("解压安装包失败，仍使用旧版本");
          tryAutoLogin();
          return;
        }
      }

      // 更新 savePath 为实际的安装程序路径
      savePath = installerPath;

      if (silent) {
        // 静默安装模式
        await _silentInstallWindowsApp();
      } else {
        // 原有方式：打开安装包让用户手动安装
        setState(() {
          installingMessage = '正在启动安装程序...';
        });
        var result = await OpenFile.open(savePath);
        if (result.type == ResultType.done) {
          setState(() {
            installingMessage = '安装程序已启动，请按照提示完成安装';
          });
          // 提示用户安装新版本
          ToastUtil.success("安装包已下载，请按照提示安装新版本");
        } else {
          setState(() {
            installing = false;
            installingMessage = null;
          });
          ToastUtil.error("打开安装包失败：${result.message}，仍使用旧版本");
          tryAutoLogin();
        }
      }
    } catch (e, stackTrace) {
      setState(() {
        installing = false;
        installingMessage = null;
      });
      ErrorHandler.handleError(e, stackTrace, logPrefix: 'Windows安装失败', showToast: true);
      tryAutoLogin();
    }
  }

  /// 解压 zip 文件并返回 exe 文件路径
  Future<String> _extractZipFile(String zipPath) async {
    try {
      // 获取临时目录
      Directory tempDir = await getApplicationDocumentsDirectory();
      String extractDir = '${tempDir.path}/nnbdc_update_temp';

      // 创建解压目录
      Directory extractDirectory = Directory(extractDir);
      if (await extractDirectory.exists()) {
        await extractDirectory.delete(recursive: true);
      }
      await extractDirectory.create(recursive: true);

      Global.logger.d('解压目录: $extractDir');

      // 使用 PowerShell 解压 zip 文件
      ProcessResult result = await Process.run(
        'powershell',
        ['-Command', 'Expand-Archive', '-Path', zipPath, '-DestinationPath', extractDir, '-Force'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        Global.logger.e('解压失败，退出码: ${result.exitCode}');
        Global.logger.e('错误信息: ${result.stderr}');
        return '';
      }

      // 查找解压后的 exe 文件
      Directory dir = Directory(extractDir);
      List<FileSystemEntity> files = await dir.list(recursive: true).toList();

      for (FileSystemEntity file in files) {
        if (file is File && file.path.toLowerCase().endsWith('.exe')) {
          String exePath = file.path;
          Global.logger.d('找到安装程序: $exePath');
          return exePath;
        }
      }

      Global.logger.e('解压后未找到 exe 文件');
      return '';
    } catch (e, stackTrace) {
      Global.logger.e('解压 zip 文件异常', error: e, stackTrace: stackTrace);
      return '';
    }
  }

  /// 静默安装 Windows 应用
  Future<void> _silentInstallWindowsApp() async {
    try {
      setState(() {
        installingMessage = '正在准备安装...';
      });

      Global.logger.d('开始静默安装 Windows 应用: $savePath');

      // 获取当前进程 ID 和可执行文件路径
      int currentPid = pid;
      String currentExe = Platform.resolvedExecutable;
      String exeName = currentExe.split('\\').last;

      Global.logger.d('当前进程 PID: $currentPid, 可执行文件: $exeName');

      // 获取当前安装目录（如果已安装）
      String? installDir = await _getCurrentInstallDir();
      Global.logger.d('检测到的安装目录: $installDir');

      // 创建批处理脚本来处理安装流程
      String batchScriptPath = await _createWindowsUpdateBatchScript(
        installerPath: savePath,
        currentPid: currentPid,
        exeName: exeName,
        installDir: installDir,
        currentExePath: currentExe,
      );

      if (batchScriptPath.isEmpty) {
        throw Exception('创建更新脚本失败');
      }

      Global.logger.d('更新脚本已创建: $batchScriptPath');

      setState(() {
        installingMessage = '正在启动安装程序，应用即将退出...';
      });

      ToastUtil.success("正在安装新版本，应用即将退出...");

      // 使用 cmd /c start 在新窗口中启动批处理脚本
      // 这样可以确保脚本独立运行，即使应用退出也能继续执行
      // 使用 start "" 可以指定窗口标题为空，避免显示不必要的窗口标题
      Global.logger.d('启动批处理脚本: $batchScriptPath');

      try {
        final process = await Process.start(
          'cmd',
          [
            '/c',
            'start',
            '/min',
            '""',
            batchScriptPath,
          ],
          mode: ProcessStartMode.detached,
        );
        Global.logger.d('批处理脚本进程 PID: ${process.pid}');
      } catch (e, stackTrace) {
        Global.logger.e('启动批处理脚本失败', error: e, stackTrace: stackTrace);
        throw Exception('启动更新脚本失败: $e');
      }

      // 等待足够的时间确保脚本已启动并开始等待进程
      // 给脚本时间检测到当前进程
      await Future.delayed(Duration(milliseconds: 1500));

      // 强制退出应用，让批处理脚本接管安装流程
      // 使用 exit(0) 确保应用立即退出
      exit(0);
    } catch (e, stackTrace) {
      setState(() {
        installing = false;
        installingMessage = null;
      });
      Global.logger.e('静默安装异常', error: e, stackTrace: stackTrace);
      // 降级到手动安装
      ToastUtil.info('静默安装失败，将打开安装包');
      await installWindowsApp(silent: false);
    }
  }

  /// 创建 Windows 更新批处理脚本
  /// 脚本会等待当前应用退出，然后执行安装，最后启动新版本
  Future<String> _createWindowsUpdateBatchScript({
    required String installerPath,
    required int currentPid,
    required String exeName,
    required String currentExePath,
    String? installDir,
  }) async {
    try {
      // 获取临时目录
      Directory tempDir = await getApplicationDocumentsDirectory();
      String scriptDir = '${tempDir.path}/nnbdc_update';
      Directory scriptDirectory = Directory(scriptDir);
      if (!await scriptDirectory.exists()) {
        await scriptDirectory.create(recursive: true);
      }

      String scriptPath = '$scriptDir/update_installer.bat';

      // 转义路径中的特殊字符，使用延迟变量展开发
      String escapedInstallerPath = installerPath.replaceAll('"', '""');

      // 构建安装命令参数
      // 注意：NSIS 的 /D 参数必须是最后一个参数，且路径不需要引号
      String installArgs = '/S'; // 静默安装
      String installDirArg = '';
      if (installDir != null && installDir.isNotEmpty) {
        // NSIS /D 参数格式：/D=路径（不需要引号，即使路径有空格）
        installDirArg = ' /D=$installDir';
        Global.logger.d('安装目录参数: $installDirArg');
      }
      // 批处理脚本中需要将引号转义（使用 "" 表示一个引号）
      String batchInstallArgs = installArgs.replaceAll('"', '""');
      String batchInstallDirArg = installDirArg.replaceAll('"', '""');

      // 根据安装目录确定可执行文件路径
      // 如果有安装目录，使用该目录下的 nnbdc.exe；否则使用默认路径
      String primaryExePath;
      if (installDir != null && installDir.isNotEmpty) {
        primaryExePath = '$installDir\\nnbdc.exe';
        Global.logger.d('使用用户安装目录: $primaryExePath');
      } else {
        primaryExePath = await _resolveWindowsInstallPath();
        Global.logger.d('使用默认安装路径: $primaryExePath');
      }

      const chineseStartMenuPath = r'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\泡泡单词\泡泡单词.lnk';

      // 创建日志文件路径（用于调试）
      String logFilePath = '$scriptDir/update_installer.log';
      String escapedLogPath = logFilePath.replaceAll('"', '""');

      // 转义批处理脚本中需要的路径（避免特殊字符问题）
      // 在批处理脚本中使用变量而不是直接插值
      String escapedPrimaryPath = primaryExePath.replaceAll('\\', '\\\\').replaceAll('"', '""');
      String escapedCurrentExePath = currentExePath.replaceAll('\\', '\\\\').replaceAll('"', '""');
      String escapedChineseLink = chineseStartMenuPath.replaceAll('\\', '\\\\').replaceAll('"', '""');

      // 创建批处理脚本内容
      // 使用变量存储路径，避免字符串插值导致的编码问题
      String batchContent = '''
@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM 设置变量
set "INSTALLER_PATH=$escapedInstallerPath"
set "LOG_FILE=$escapedLogPath"
set "TARGET_PID=$currentPid"
set "PRIMARY_EXE=$escapedPrimaryPath"
set "FALLBACK_EXE=$escapedCurrentExePath"
set "START_MENU_CN=$escapedChineseLink"
set "INSTALL_ARGS=$batchInstallArgs"
set "INSTALL_DIR_ARG=$batchInstallDirArg"
set "SHOULD_EXIT=0"

echo Debug: Primary path = !PRIMARY_EXE!
echo Debug: Fallback path = !FALLBACK_EXE!
echo Debug: Install args = !INSTALL_ARGS!!INSTALL_DIR_ARG!

title nnbdc auto update
echo ========================================
echo nnbdc auto update script
echo ========================================
echo.

echo [%date% %time%] update script start >> "!LOG_FILE!"
echo [%date% %time%] target pid: !TARGET_PID! >> "!LOG_FILE!"
echo [%date% %time%] installer path: !INSTALLER_PATH! >> "!LOG_FILE!"
echo [%date% %time%] log file: !LOG_FILE! >> "!LOG_FILE!"
echo.

echo waiting for app exit...
echo [%date% %time%] waiting for app exit >> "!LOG_FILE!"

REM 等待当前进程退出（最多等待 10 秒），超时后强制结束
set /a timeout=10
:wait_loop
tasklist /FI "PID eq !TARGET_PID!" 2>NUL | findstr /C:"!TARGET_PID!" >NUL 2>&1
if !ERRORLEVEL! EQU 0 (
    if !timeout! LEQ 0 goto force_close
    echo waiting... !timeout! seconds left
    echo [%date% %time%] waiting... !timeout! seconds left >> "!LOG_FILE!"
    timeout /t 1 /nobreak >nul
    set /a timeout-=1
    goto wait_loop
) else (
    goto process_exited
)

:force_close
echo.
echo timeout, try to kill old process...
echo [%date% %time%] timeout, kill old process >> "!LOG_FILE!"
taskkill /F /PID !TARGET_PID! /T >nul 2>&1
timeout /t 2 /nobreak >nul
goto after_wait

:process_exited
echo.
echo old process already exited
echo [%date% %time%] old process already exited >> "!LOG_FILE!"
goto after_wait

:after_wait
REM 额外等待 2 秒确保文件已完全释放
timeout /t 2 /nobreak >nul

echo.
echo [%date% %time%] start installer >> "!LOG_FILE!"

echo.
echo running installer, please wait...
echo.

REM 执行安装程序（/D 参数必须在最后）
call "!INSTALLER_PATH!" !INSTALL_ARGS!!INSTALL_DIR_ARG!

if !ERRORLEVEL! EQU 0 (
    echo.
    echo install success!
    echo [%date% %time%] install success >> "!LOG_FILE!"
    echo.
    
    REM 等待安装完成
    echo wait a moment...
    timeout /t 3 /nobreak >nul
    
    REM 启动新版本应用（使用 PowerShell Start-Process 确保应用独立于命令行窗口）
    echo starting new version...
    echo [%date% %time%] starting new version >> "!LOG_FILE!"
    
    REM 检查并启动主路径的可执行文件
    if exist "!PRIMARY_EXE!" (
        echo found primary exe: !PRIMARY_EXE!
        echo [%date% %time%] found primary exe: !PRIMARY_EXE! >> "!LOG_FILE!"
        powershell -Command "Start-Process -FilePath '!PRIMARY_EXE!'" 2>>"!LOG_FILE!"
        if !ERRORLEVEL! EQU 0 (
            echo new version started from primary path
            echo [%date% %time%] new version started: !PRIMARY_EXE! >> "!LOG_FILE!"
        ) else (
            echo failed to start from primary path, error: !ERRORLEVEL!
            echo [%date% %time%] failed to start from primary path, error: !ERRORLEVEL! >> "!LOG_FILE!"
        )
    ) else if exist "!FALLBACK_EXE!" (
        echo found fallback exe: !FALLBACK_EXE!
        echo [%date% %time%] found fallback exe: !FALLBACK_EXE! >> "!LOG_FILE!"
        powershell -Command "Start-Process -FilePath '!FALLBACK_EXE!'" 2>>"!LOG_FILE!"
        if !ERRORLEVEL! EQU 0 (
            echo new version started from fallback path
            echo [%date% %time%] new version started: !FALLBACK_EXE! >> "!LOG_FILE!"
        ) else (
            echo failed to start from fallback path, error: !ERRORLEVEL!
            echo [%date% %time%] failed to start from fallback path, error: !ERRORLEVEL! >> "!LOG_FILE!"
        )
    ) else (
        echo warning: executable not found in known locations
        echo [%date% %time%] warning: executable not found >> "!LOG_FILE!"
        echo checking start menu shortcut: !START_MENU_CN!
        if exist "!START_MENU_CN!" (
            echo found start menu shortcut
            echo [%date% %time%] found start menu shortcut >> "!LOG_FILE!"
            powershell -Command "Start-Process -FilePath '!START_MENU_CN!'" 2>>"!LOG_FILE!"
            if !ERRORLEVEL! EQU 0 (
                echo launched from chinese start menu shortcut
                echo [%date% %time%] launched from chinese start menu >> "!LOG_FILE!"
            ) else (
                echo failed to launch from start menu, error: !ERRORLEVEL!
                echo [%date% %time%] failed to launch from start menu, error: !ERRORLEVEL! >> "!LOG_FILE!"
            )
        ) else (
            echo error: start menu shortcut not found
            echo [%date% %time%] error: start menu shortcut not found >> "!LOG_FILE!"
        )
    )
    
    echo.
    echo new version launched, closing window...
    echo [%date% %time%] update script finished, closing window >> "!LOG_FILE!"
    
    REM 短暂延迟确保应用启动完成
    timeout /t 2 /nobreak >nul
    
    REM 在后台异步删除临时脚本，不影响窗口关闭
    start "" /b cmd /c "timeout /t 3 /nobreak >nul & del /Q "%~f0"" >nul 2>&1
    
    REM 立即关闭窗口
    exit
) else (
    echo.
    echo install failed, code: !ERRORLEVEL!
    echo [%date% %time%] install failed, code: !ERRORLEVEL! >> "!LOG_FILE!"
    echo [%date% %time%] please run installer manually: !INSTALLER_PATH! >> "!LOG_FILE!"
    REM 显示错误对话框
    msg * "Install failed, code: !ERRORLEVEL!. See log: !LOG_FILE!"
    echo.
    echo update script finished, please check the error message above
    echo [%date% %time%] update script finished with error >> "!LOG_FILE!"
    echo.
    echo Press any key to close this window...
    pause >nul
)

endlocal
''';

      // 写入批处理脚本文件（UTF-8 无 BOM，避免命令前出现不可识别字符）
      // Windows 批处理脚本需要 CRLF 换行符，否则可能被当成单行导致“不是内部或外部命令”
      final batchContentWithCrlf = batchContent.replaceAll('\n', '\r\n');
      File scriptFile = File(scriptPath);
      await scriptFile.writeAsString(batchContentWithCrlf, encoding: utf8);

      Global.logger.d('批处理脚本已创建: $scriptPath');
      return scriptPath;
    } catch (e, stackTrace) {
      Global.logger.e('创建更新脚本失败', error: e, stackTrace: stackTrace);
      return '';
    }
  }

  /// 获取当前安装目录
  Future<String?> _getCurrentInstallDir() async {
    try {
      // 从当前可执行文件路径提取安装目录
      String currentExe = Platform.resolvedExecutable;
      Global.logger.d('当前可执行文件路径: $currentExe');

      // 获取可执行文件的父目录（即安装目录）
      // 例如: C:\Program Files\nn\nnbdc.exe -> C:\Program Files\nn
      String installDir = currentExe.substring(0, currentExe.lastIndexOf('\\'));
      Global.logger.d('提取的安装目录: $installDir');

      // 验证目录是否存在
      if (await Directory(installDir).exists()) {
        return installDir;
      } else {
        Global.logger.w('安装目录不存在: $installDir');
        return null;
      }
    } catch (e) {
      Global.logger.e('获取安装目录失败: $e');
      return null;
    }
  }

  /// 解析 Windows 安装路径，优先读取注册表，失败则回退到默认路径
  Future<String> _resolveWindowsInstallPath() async {
    try {
      // 默认路径（中文目录）
      const defaultPath = r'C:\Program Files\泡泡单词\nnbdc.exe';
      return defaultPath;
    } catch (e) {
      Global.logger.e('解析安装路径失败，使用默认路径', error: e);
      return r'C:\Program Files\泡泡单词\nnbdc.exe';
    }
  }

  /// 安装 Linux AppImage
  Future<void> installLinuxApp() async {
    try {
      setState(() {
        installingMessage = '正在查找安装位置...';
      });

      Global.logger.d('开始安装 Linux AppImage: $savePath');

      // 获取当前运行的 AppImage 路径
      String? currentAppImagePath = await _getCurrentLinuxAppImagePath();

      if (currentAppImagePath == null || currentAppImagePath.isEmpty) {
        Global.logger.w('无法获取当前 AppImage 路径，尝试使用默认路径');
        // 尝试使用常见的 AppImage 位置
        String homeDir = Platform.environment['HOME'] ?? '';
        if (homeDir.isNotEmpty) {
          // 尝试在用户目录下查找
          List<String> possiblePaths = [
            '$homeDir/Applications/nnbdc-linux.AppImage',
            '$homeDir/.local/bin/nnbdc-linux.AppImage',
            '$homeDir/Downloads/nnbdc-linux.AppImage',
            '/opt/nnbdc/nnbdc-linux.AppImage',
            '/usr/local/bin/nnbdc-linux.AppImage',
          ];

          for (String path in possiblePaths) {
            File file = File(path);
            if (await file.exists()) {
              currentAppImagePath = path;
              Global.logger.d('找到 AppImage: $currentAppImagePath');
              break;
            }
          }
        }
      }

      if (currentAppImagePath == null || currentAppImagePath.isEmpty) {
        // 如果找不到当前文件，将新文件保存到用户目录
        String homeDir = Platform.environment['HOME'] ?? '';
        if (homeDir.isNotEmpty) {
          Directory appDir = Directory('$homeDir/.local/bin');
          if (!await appDir.exists()) {
            await appDir.create(recursive: true);
          }
          currentAppImagePath = '${appDir.path}/nnbdc-linux.AppImage';
        } else {
          throw Exception('无法确定 AppImage 安装路径');
        }
      }

      Global.logger.d('目标 AppImage 路径: $currentAppImagePath');

      // 备份旧文件（如果存在）
      File targetFile = File(currentAppImagePath);
      if (await targetFile.exists()) {
        setState(() {
          installingMessage = '正在备份旧版本...';
        });
        String backupPath = '$currentAppImagePath.backup';
        Global.logger.d('备份旧文件到: $backupPath');
        await targetFile.copy(backupPath);
      }

      // 复制新文件到目标位置
      setState(() {
        installingMessage = '正在安装新版本...';
      });
      File newFile = File(savePath);
      Global.logger.d('复制新文件从 $savePath 到 $currentAppImagePath');
      await newFile.copy(currentAppImagePath);

      // 设置执行权限
      setState(() {
        installingMessage = '正在设置权限...';
      });
      ProcessResult chmodResult = await Process.run(
        'chmod',
        ['+x', currentAppImagePath],
        runInShell: false,
      );

      if (chmodResult.exitCode != 0) {
        Global.logger.w('设置执行权限失败: ${chmodResult.stderr}');
      } else {
        Global.logger.d('设置执行权限成功');
      }

      // 删除备份文件（如果升级成功）
      File backupFile = File('$currentAppImagePath.backup');
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      Global.logger.d('Linux AppImage 升级成功');
      setState(() {
        installingMessage = '安装成功，正在重启应用...';
      });
      ToastUtil.success("新版本安装成功，正在重启应用...");

      // 延迟后启动新版本并退出当前版本
      Future.delayed(Duration(seconds: 2), () async {
        await _launchLinuxNewVersion(currentAppImagePath!);
        SystemNavigator.pop();
      });
    } catch (e, stackTrace) {
      setState(() {
        installing = false;
        installingMessage = null;
      });
      Global.logger.e('安装 Linux AppImage 失败', error: e, stackTrace: stackTrace);
      ToastUtil.error('安装失败: $e');

      // 尝试恢复备份
      try {
        String? currentAppImagePath = await _getCurrentLinuxAppImagePath();
        if (currentAppImagePath != null) {
          File backupFile = File('$currentAppImagePath.backup');
          if (await backupFile.exists()) {
            File targetFile = File(currentAppImagePath);
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            await backupFile.copy(currentAppImagePath);
            await Process.run('chmod', ['+x', currentAppImagePath], runInShell: false);
            Global.logger.d('已恢复备份文件');
          }
        }
      } catch (restoreError) {
        Global.logger.e('恢复备份失败: $restoreError');
      }

      tryAutoLogin();
    }
  }

  /// 获取当前运行的 Linux AppImage 路径
  Future<String?> _getCurrentLinuxAppImagePath() async {
    try {
      // 通过 /proc/self/exe 获取当前可执行文件路径
      ProcessResult result = await Process.run(
        'readlink',
        ['-f', '/proc/self/exe'],
        runInShell: false,
      );

      if (result.exitCode == 0) {
        String path = result.stdout.toString().trim();
        Global.logger.d('当前 AppImage 路径: $path');
        return path;
      }
    } catch (e) {
      Global.logger.w('获取当前 AppImage 路径失败: $e');
    }

    // 备用方法：通过 Platform.resolvedExecutable
    try {
      String executable = Platform.resolvedExecutable;
      if (executable.endsWith('.AppImage')) {
        Global.logger.d('通过 Platform.resolvedExecutable 获取路径: $executable');
        return executable;
      }
    } catch (e) {
      Global.logger.w('通过 Platform.resolvedExecutable 获取路径失败: $e');
    }

    return null;
  }

  /// 启动 Linux 新版本应用
  Future<void> _launchLinuxNewVersion(String appImagePath) async {
    try {
      Global.logger.d('启动新版本 Linux AppImage: $appImagePath');

      // 检查文件是否存在
      File exeFile = File(appImagePath);
      if (await exeFile.exists()) {
        // 启动新版本应用（在后台运行）
        await Process.start(appImagePath, [], runInShell: true);
        Global.logger.d('新版本启动成功');
      } else {
        Global.logger.w('新版本 AppImage 不存在: $appImagePath');
        ToastUtil.info('安装完成，请手动启动应用: $appImagePath');
      }
    } catch (e, stackTrace) {
      Global.logger.e('启动新版本失败', error: e, stackTrace: stackTrace);
      ToastUtil.info('安装完成，请手动启动应用');
    }
  }

  /// 启动新版本应用
  /// 注意：在静默安装模式下，此方法不再使用，由批处理脚本负责启动新版本
  // ignore: unused_element
  Future<void> _launchNewVersion() async {
    try {
      // 默认安装路径
      String defaultPath = r'C:\Program Files\泡泡单词\nnbdc.exe';

      // 检查文件是否存在
      File exeFile = File(defaultPath);
      if (await exeFile.exists()) {
        Global.logger.d('启动新版本: $defaultPath');
        // 启动新版本应用
        await Process.start(defaultPath, [], runInShell: true);
      } else {
        Global.logger.w('新版本可执行文件不存在: $defaultPath');
        // 尝试从开始菜单启动
        String startMenuPath = r'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\泡泡单词\泡泡单词.lnk';
        File startMenuFile = File(startMenuPath);
        if (await startMenuFile.exists()) {
          await Process.start('cmd', ['/c', 'start', '', startMenuPath], runInShell: true);
        } else {
          Global.logger.w('开始菜单快捷方式也不存在，请手动启动应用');
          ToastUtil.info('安装完成，请手动启动应用');
        }
      }
    } catch (e, stackTrace) {
      Global.logger.e('启动新版本失败', error: e, stackTrace: stackTrace);
      ToastUtil.info('安装完成，请手动启动应用');
    }
  }

  @override
  void initState() {
    super.initState();
    // 在 FirstPage 生命周期内禁用 API 自动 loading 提示
    Api.setLoadingDisabled(true);
    // 动态闪屏动画初始化
    _bubbles = [];
    final rnd = math.Random();
    for (int i = 0; i < 24; i++) {
      final double radius = 6 + rnd.nextDouble() * 18;
      final double speed = 0.0006 + rnd.nextDouble() * 0.0016; // 每帧上升速度（相对高度）
      final Color color = Colors.white.withValues(alpha: 0.05 + rnd.nextDouble() * 0.10);
      _bubbles.add(_Bubble(rnd.nextDouble(), rnd.nextDouble(), radius, speed, color));
    }

    _splashController = AnimationController(vsync: this, duration: const Duration(seconds: 20))
      ..addListener(() {
        // 更新泡泡位置
        for (final b in _bubbles) {
          b.y -= b.speed * 60 / 1000 * 16; // 粗略按帧率修正
          if (b.y < -0.05) {
            b.y = 1 + math.Random().nextDouble() * 0.2;
            b.x = math.Random().nextDouble();
          }
        }
        if (mounted) {
          setState(() {});
        }
      })
      ..repeat();

    // 隐私合规第一位：需在首帧渲染后才能调用 showDialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPrivacyAndProceed();
    });
  }

  /// 检查隐私协议，同意后才继续启动流程
  void _checkPrivacyAndProceed() async {
    const int currentPrivacyVersion = 20260310;
    int acceptedVersion = GetStorage().read<int>('accepted_privacy_version') ?? 0;

    if (acceptedVersion < currentPrivacyVersion) {
      // 需要展示隐私政策弹窗
      if (mounted) {
        _showPrivacyDialog();
      }
    } else {
      // 已过最新协议，继续原有流程
      _initVersionInfo().then((_) => checkNewVersion());
    }
  }

  /// 展示隐私政策弹窗（启动页专用）
  void _showPrivacyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false, // 禁止手动返回关闭
          child: AlertDialog(
            title: const Text('服务协议与隐私政策'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '欢迎使用${Global.appName}！在您开始使用前，请务必仔细阅读并理解',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Get.toNamed('/protocol'),
                        child: const Text('《用户协议》', style: TextStyle(color: Colors.blue)),
                      ),
                      const Text('和'),
                      TextButton(
                        onPressed: () => Get.toNamed('/privacy'),
                        child: const Text('《隐私政策》', style: TextStyle(color: Colors.blue)),
                      ),
                    ],
                  ),
                  const Text(
                    '我们非常重视您的隐私保护，您点击“同意”即代表您已阅读并接受前述协议的全部内容。我们仅在您授权后才会收集必要信息并初始化友盟等第三方SDK以提供崩溃监测等服务。',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => exit(0), // 不同意直接退出应用（合规要求）
                child: const Text('不同意并退出', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                onPressed: () async {
                  // 1. 记录同意状态
                  await GetStorage().write('accepted_privacy_version', 20260310);
                  // 2. 立即正式初始化友盟（不再推迟到登录页）
                  if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
                    try {
                      UmengCommonSdk.initCommon(Config.umengAndroidAppKey, Config.umengIosAppKey, Config.umengChannel);
                      debugPrint('Umeng initialized immediately after privacy approval on splash');
                    } catch (e) {
                      debugPrint('Umeng init failed: $e');
                    }
                  }
                  // 3. 关闭弹窗并继续原有流程
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    _initVersionInfo().then((_) => checkNewVersion());
                  }
                },
                child: const Text('同意并继续'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // 恢复 API 自动 loading 提示
    Api.setLoadingDisabled(false);
    _splashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFF0EA5E9),
        body: Center(
          ///正在下载或安装
          child: downloading || downloadSuccess || installing
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 版本信息提示
                    if (_buildNumber != null && newVerCode != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          '版本 $_buildNumber ➜ $newVerCode',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 250,
                      width: 250,
                      child: CircularPercentIndicator(
                        radius: 60.0,
                        lineWidth: 5.0,
                        percent: downloading
                            ? ((downloadedBytes ?? 0) / (totalBytes != null && totalBytes! > 0 ? totalBytes! : 1024)).clamp(0.0, 1.0)
                            : installing
                                ? 1.0
                                : 1.0,
                        center: downloading
                            ? Text(
                                "${((downloadedBytes ?? 0) / 1024).round()}k\n${((totalBytes ?? 1024) / 1024).round()}k",
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: Colors.white),
                              )
                            : installing
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        installingMessage ?? '正在安装...',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 14, color: Colors.white),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    "下载完成",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 14, color: Colors.white),
                                  ),
                        progressColor: downloading
                            ? Colors.green
                            : installing
                                ? Colors.blue
                                : Colors.green,
                      ),
                    ),
                    if (installing && installingMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          installingMessage!,
                          style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                )

              /// 正常闪屏界面
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // 动态特效闪屏
                    final double w = constraints.maxWidth;
                    final double h = constraints.maxHeight;
                    final double scale = 1.0 + 0.04 * math.sin(_splashController.value * 2 * math.pi);
                    final String shownText = _splashText;

                    return Container(
                      width: w,
                      height: h,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF0EA5E9), // Sky-500
                            Color(0xFF0284C7), // Sky-600
                            Color(0xFF0369A1), // Sky-700
                            Color(0xFF075985), // Sky-800
                          ],
                          stops: [0.0, 0.3, 0.7, 1.0],
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Decorative glows
                          Positioned(
                            top: -80,
                            right: -60,
                            child: Container(
                              width: 280,
                              height: 280,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFF7DD3FC).withValues(alpha: 0.15),
                                    const Color(0xFF7DD3FC).withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 100,
                            left: -80,
                            child: Container(
                              width: 320,
                              height: 320,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFF38BDF8).withValues(alpha: 0.12),
                                    const Color(0xFF38BDF8).withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 泡泡层
                          CustomPaint(painter: _BubblesPainter(_bubbles)),
                          // 居中LOGO与文字
                          Align(
                            alignment: const Alignment(0, -0.45),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.scale(
                                  scale: scale,
                                  child: Image.asset(
                                    "assets/images/logo.png",
                                    width: 96,
                                    height: 96,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  shownText,
                                  textAlign: TextAlign.center,
                                  textScaler: const TextScaler.linear(1.0),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 1.2,
                                    height: 1.5,
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // 版本号显示
                                Text(
                                  '版本 ${_versionName ?? Global.version}${_buildNumber != null ? '($_buildNumber)' : ''} (${Config.profileName})',
                                  textScaler: const TextScaler.linear(1.0),
                                  style: const TextStyle(
                                    color: Color(0xFFBAE6FD), // Sky-200
                                    fontSize: 10,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // 进度/错误提示：发生异常时，用错误图标替换转圈，并在下方展示错误与按钮（非toast）
                                ValueListenableBuilder<String?>(
                                  valueListenable: Global.startupError,
                                  builder: (context, startupError, _) {
                                    final err = startupError ?? _autoLoginError;
                                    final hasError = err != null && err.isNotEmpty;

                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 轻量的进度提示（异常时用错误图标替换转圈）
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: hasError
                                                  ? const Icon(
                                                      Icons.error_outline,
                                                      size: 18,
                                                      color: Colors.red,
                                                    )
                                                  : const CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                                                    ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _preparingMessage,
                                              textScaler: const TextScaler.linear(1.0),
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w300,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (hasError)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 10),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  err,
                                                  textAlign: TextAlign.center,
                                                  textScaler: const TextScaler.linear(1.0),
                                                  style: TextStyle(
                                                    color: Colors.red.shade100,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                ElevatedButton.icon(
                                                  onPressed: _retryStartup,
                                                  icon: const Icon(Icons.refresh, size: 18),
                                                  label: const Text(
                                                    '清空本地数据并重试',
                                                    textScaler: TextScaler.linear(1.0),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.white.withValues(alpha: 0.92),
                                                    foregroundColor: const Color(0xFF2E5F8A),
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          // 底部提示（仅对桌面平台显示）
                          // 仅在“确实进入升级流程/发现新版本/正在下载安装”时展示，避免登录阶段误导用户
                          if ((PlatformUtils.isWindows || PlatformUtils.isLinux || PlatformUtils.isMacOS) &&
                              ((newVersionFound && !newVersionIgnored) || downloading || installing || downloadSuccess))
                            Align(
                              alignment: const Alignment(0, 0.85),
                              child: GestureDetector(
                                onTap: () async {
                                  final uri = Uri.parse('http://www.nnbdc.com/download.html');
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                },
                                child: Text(
                                  '如果升级失败，请到 www.nnbdc.com 重新下载',
                                  textScaler: const TextScaler.linear(1.0),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w300,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ));
  }

  tryAutoLogin() async {
    // 这里是“登录阶段”，不要显示“同步/升级”相关文案，避免误导
    _setPreparingMessage('正在自动登录…');
    _setAutoLoginError(null);

    try {
      var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
      
      // 隐私政策版本检查
      const int currentPrivacyVersion = 20260310;
      int acceptedVersion = GetStorage().read<int>('accepted_privacy_version') ?? 0;
      bool privacyOutdated = (acceptedVersion < currentPrivacyVersion);

      // 检查是否为访客用户
      if (user != null && user.id == Global.guestId) {
        if (privacyOutdated) {
          _setPreparingMessage('隐私政策已更新，正在跳转登录页…');
          Get.offNamed("/login");
          return;
        }
        final guestVo = UserVo.fromUser(user);
        await Global.setLoggedInUser(guestVo);
        // 游客自动登录也尝试恢复购买状态
        SubscriptionUtil.restorePurchases(showToast: false);
        Get.offNamed("/index", arguments: IndexPageArgs(0));
        return;
      }

      if (user != null) {
        // 如果隐私政策版本过低，强制跳转到登录页重新确认
        if (privacyOutdated) {
          _setPreparingMessage('隐私政策已更新，正在跳转登录页…');
          Get.offNamed("/login");
          return;
        }

        _setPreparingMessage('正在加载用户信息…');

        // 更新最后登录时间
        final now = AppClock.now();
        await MyDatabase.instance.usersDao.saveUser(user.copyWith(lastLoginTime: drift.Value(now)), true);
        await MyDatabase.instance.userOpersDao.recordLogin(user.id, remark: '自动登录');

        // CS架构下，本地有用户信息就可以直接登录，不需要密码验证
        // 直接获取用户信息并登录
        var result = await UserBo().getLoggedInUser();
        if (result.success && result.data != null) {
          await Global.setLoggedInUser(result.data!);
          // 自动登录成功后，静默尝试恢复购买状态
          SubscriptionUtil.restorePurchases(showToast: false);

          // 注意：由于改为延迟连接，此处不再主动上报用户信息
          // 用户信息会在进入需要socket的页面（如me、russia）时自动上报
          // SocketIoClient.instance.tryReportUserToSocketServer();

          Get.offNamed("/index", arguments: IndexPageArgs(0));
        } else {
          _setPreparingMessage('自动登录失败，正在跳转登录页…');
          Get.offNamed("/login");
        }
      } else {
        _setPreparingMessage('未检测到登录信息，正在跳转登录页…');
        Get.offNamed("/login");
      }
    } catch (e, stackTrace) {
      // 不吃异常：记录日志 + 显示在界面上（非toast）
      Global.logger.e('自动登录异常', error: e, stackTrace: stackTrace);
      _setAutoLoginError('自动登录失败：$e');
    }
  }
}

// 以下为动态闪屏实现
class _Bubble {
  double x;
  double y;
  double radius;
  double speed;
  Color color;
  _Bubble(this.x, this.y, this.radius, this.speed, this.color);
}

class _BubblesPainter extends CustomPainter {
  final List<_Bubble> bubbles;
  _BubblesPainter(this.bubbles);
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..isAntiAlias = true;
    for (final b in bubbles) {
      paint.color = b.color;
      canvas.drawCircle(Offset(b.x * size.width, b.y * size.height), b.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
