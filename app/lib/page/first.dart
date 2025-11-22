import 'dart:io';
import 'dart:math' as math;

import 'package:confirm_dialog/confirm_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/index.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../global.dart';
import '../util/client_type.dart';
import '../services/update_service.dart';

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
  String? newVersionName;
  List<dynamic>? newVersionChanges;
  int? newVerCode; // 保存新版本的 verCode，用于下载时添加版本参数

  // 准备阶段状态提示
  String _preparingMessage = '正在准备学习环境…';
  
  // 版本信息
  String? _buildNumber;

  // 动态闪屏：动画控制与数据
  late AnimationController _splashController;
  late List<_Bubble> _bubbles;
  final String _splashText = "听说读写玩，背词不再难";

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
          // 发现新版本
          int verCode = versionInfo['verCode'] as int;
          var verName = versionInfo['verName'] as String;
          var changes = versionInfo['changes'] as List<String>;
          
          setState(() {
            newVersionFound = true;
            newVersionName = verName;
            newVersionChanges = changes;
            newVerCode = verCode; // 保存版本号，用于下载时添加版本参数
          });
          // 调用升级确认对话框
          await showUpgradeConfirmDlg(verName, changes);
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
    } else {
      /// 非android/windows/linux
      tryAutoLogin();
    }
  }

  Future<void> showUpgradeConfirmDlg(verName, changes) async {
    if (PlatformUtils.isWindows) {
      // Windows 平台：直接使用静默安装，显示确认对话框
      if (await confirm(
        context,
        title: const Text('发现新版本'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("发现新版本 $verName"),
            SizedBox(height: 8),
            Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
            for (String change in changes) Text('• $change'),
            SizedBox(height: 8),
            Text('\n将自动完成安装，无需手动操作。是否升级？', 
                 style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        textOK: const Text('是'),
        textCancel: const Text('否'),
      )) {
        // 直接执行静默安装
        downloadWindowsAndUpgrade(useSilent: true);
      } else {
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
            Text("发现新版本 $verName"),
            SizedBox(height: 8),
            Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
            for (String change in changes) Text('• $change'),
            SizedBox(height: 8),
            Text('\n将自动下载并替换应用文件，无需手动操作。是否升级？', 
                 style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        textOK: const Text('是'),
        textCancel: const Text('否'),
      )) {
        // 直接执行自动升级
        downloadLinuxAndUpgrade();
      } else {
        tryAutoLogin();
      }
    } else {
      // Android 平台：保持原有逻辑
      if (await confirm(
        context,
        title: const Text('确认'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [Text("发现新版本 $verName"), for (String change in changes) Text('• $change'), const Text('\n是否升级？')],
        ),
        textOK: const Text('是'),
        textCancel: const Text('否'),
      )) {
        downloadApkAndUpgrade();
      } else {
        tryAutoLogin();
      }
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
          installingMessage = '安装程序已启动，请按照提示完成安装';
        });
        // 延迟退出，让用户看到提示
        Future.delayed(Duration(seconds: 2), () {
          SystemNavigator.pop();
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
          // 延迟退出，让用户看到提示
          Future.delayed(Duration(seconds: 2), () {
            SystemNavigator.pop();
          });
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
        [
          '-Command',
          'Expand-Archive',
          '-Path',
          zipPath,
          '-DestinationPath',
          extractDir,
          '-Force'
        ],
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
      
      // NSIS 静默安装参数说明：
      // /S - 静默安装（Silent）
      // /D=路径 - 指定安装目录（可选，默认使用注册表中的路径）
      
      // 获取当前安装目录（如果已安装）
      String? installDir = await _getCurrentInstallDir();
      
      // 构建静默安装命令
      List<String> arguments = ['/S']; // 静默安装参数
      if (installDir != null && installDir.isNotEmpty) {
        // 如果已安装，使用相同目录进行升级
        arguments.add('/D=$installDir');
        Global.logger.d('使用已安装目录: $installDir');
      }
      
      // 执行静默安装
      setState(() {
        installingMessage = '正在安装新版本，请稍候...';
      });
      
      Global.logger.d('执行命令: $savePath ${arguments.join(" ")}');
      ProcessResult result = await Process.run(
        savePath,
        arguments,
        runInShell: true,
      );
      
      Global.logger.d('安装进程退出码: ${result.exitCode}');
      if (result.stdout.toString().isNotEmpty) {
        Global.logger.d('安装输出: ${result.stdout}');
      }
      if (result.stderr.toString().isNotEmpty) {
        Global.logger.d('安装错误: ${result.stderr}');
      }
      
      if (result.exitCode == 0) {
        // 安装成功
        Global.logger.d('静默安装成功');
        setState(() {
          installingMessage = '安装成功，正在重启应用...';
        });
        ToastUtil.success("新版本安装成功，正在重启应用...");
        
        // 延迟后启动新版本并退出当前版本
        Future.delayed(Duration(seconds: 2), () async {
          await _launchNewVersion();
          SystemNavigator.pop();
        });
      } else {
        // 安装失败，可能需要管理员权限
        Global.logger.w('静默安装失败，退出码: ${result.exitCode}，尝试使用管理员权限');
        setState(() {
          installingMessage = '需要管理员权限，正在请求...';
        });
        
        // 尝试使用管理员权限重新执行
        await _silentInstallWithElevation();
      }
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

  /// 获取当前安装目录
  Future<String?> _getCurrentInstallDir() async {
    try {
      // 从注册表读取安装目录
      // Windows 注册表路径: HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\泡泡单词
      // 由于 Flutter 无法直接读取注册表，这里返回 null，使用默认安装路径
      // NSIS 安装程序会自动使用注册表中的路径，如果不存在则使用默认路径
      // 如果需要精确控制，可以使用 Windows 平台通道（Platform Channel）
      return null;
    } catch (e) {
      Global.logger.e('获取安装目录失败: $e');
      return null;
    }
  }

  /// 使用管理员权限执行静默安装
  Future<void> _silentInstallWithElevation() async {
    try {
      Global.logger.d('尝试使用管理员权限执行静默安装');
      
      // 使用 PowerShell 以管理员权限执行安装
      // 注意：这会触发 UAC 提示
      // 转义路径中的特殊字符
      String escapedPath = savePath.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      String script = 'Start-Process -FilePath "$escapedPath" -ArgumentList "/S" -Verb RunAs -Wait';
      
      ProcessResult result = await Process.run(
        'powershell',
        ['-Command', script],
        runInShell: true,
      );
      
      Global.logger.d('管理员权限安装退出码: ${result.exitCode}');
      
      if (result.exitCode == 0) {
        Global.logger.d('管理员权限安装成功');
        setState(() {
          installingMessage = '安装成功，正在重启应用...';
        });
        ToastUtil.success("新版本安装成功，正在重启应用...");
        Future.delayed(Duration(seconds: 2), () async {
          await _launchNewVersion();
          SystemNavigator.pop();
        });
      } else {
        // 降级到手动安装
        setState(() {
          installingMessage = '正在打开安装包...';
        });
        Global.logger.w('管理员权限安装失败，降级到手动安装');
        ToastUtil.info('需要管理员权限，将打开安装包');
        await installWindowsApp(silent: false);
      }
    } catch (e, stackTrace) {
      setState(() {
        installing = false;
        installingMessage = null;
      });
      Global.logger.e('管理员权限安装异常', error: e, stackTrace: stackTrace);
      // 降级到手动安装
      await installWindowsApp(silent: false);
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
      final Color color = Colors.white.withValues(alpha: 0.10 + rnd.nextDouble() * 0.18);
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
    checkNewVersion();
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
        backgroundColor: Colors.lightBlue, // 设置Scaffold的背景色
        body: Center(
          ///正在下载或安装
          child: downloading || downloadSuccess || installing
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 250,
                      width: 250,
                      child: CircularPercentIndicator(
                        radius: 60.0,
                        lineWidth: 5.0,
                        percent: downloading 
                            ? (downloadedBytes ?? 0) / (totalBytes ?? 1024)
                            : installing 
                                ? 1.0 
                                : 1.0,
                        center: downloading
                            ? Text(
                                "${((downloadedBytes ?? 0) / 1024).round()}k\n${((totalBytes ?? 1024) / 1024).round()}k",
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
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
                                    style: TextStyle(fontSize: 14),
                                  ),
                        progressColor: downloading ? Colors.green : installing ? Colors.blue : Colors.green,
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

              /// 发现新版本
              : newVersionFound && !newVersionIgnored
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          "assets/images/logo.png",
                          width: 64,
                          height: 64,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("发现新版本 $newVersionName"),
                              for (String change in newVersionChanges!) Text('• $change'),
                              const Text('\n是否升级？'),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 32, 0, 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.red, // foreground
                                ),
                                child: const Text('否'),
                                onPressed: () {
                                  setState(() {
                                    newVersionIgnored = true;
                                    tryAutoLogin();
                                  });
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(32, 0, 0, 0),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.green, // foreground
                                  ),
                                  child: const Text('是'),
                                  onPressed: () {
                                    if (PlatformUtils.isAndroid) {
                                      downloadApkAndUpgrade();
                                    } else if (PlatformUtils.isWindows) {
                                      // Windows 平台直接执行静默安装
                                      downloadWindowsAndUpgrade(useSilent: true);
                                    } else if (PlatformUtils.isLinux) {
                                      // Linux 平台直接执行自动升级
                                      downloadLinuxAndUpgrade();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    )
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
                              colors: [Color(0xFF4A90E2), Color(0xFF357ABD), Color(0xFF2E5F8A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
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
                                      textScaler: const TextScaler.linear(1.0),
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: 4,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    // 版本号显示
                                    Text(
                                      _buildNumber != null 
                                          ? '版本 ${Global.version} ($_buildNumber)'
                                          : '版本 ${Global.version}',
                                      textScaler: const TextScaler.linear(1.0),
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // 轻量的进度提示
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _preparingMessage,
                                          textScaler: const TextScaler.linear(1.0),
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.9),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
    setState(() {
      _preparingMessage = '正在同步数据…';
    });
    
    var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
    if (user != null && user.email != null) {
      setState(() {
        _preparingMessage = '正在验证登录…';
      });
      
      var result = await UserBo().checkUser(CheckBy.email, user.email!, null, user.password!, getClientType().name, Global.version);
      if (result.success) {
        setState(() {
          _preparingMessage = '正在加载用户信息…';
        });
        
        var result2 = await UserBo().getLoggedInUser();
        if (result2.success) {
          await Global.setLoggedInUser(result2.data!);
          // 注意：由于改为延迟连接，此处不再主动上报用户信息
          // 用户信息会在进入需要socket的页面（如me、russia）时自动上报
          // SocketIoClient.instance.tryReportUserToSocketServer();

          Get.offNamed("/index", arguments: IndexPageArgs(4));
        } else {
          Get.offNamed("/email_login");
        }
      } else {
        Get.offNamed("/email_login");
      }
    } else {
      Get.offNamed("/email_login");
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
