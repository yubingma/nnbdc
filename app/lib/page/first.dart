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

  bool newVersionFound = false;
  bool newVersionIgnored = false;
  String? newVersionName;
  List<dynamic>? newVersionChanges;

  // 动态闪屏：动画控制与数据
  late AnimationController _splashController;
  late List<_Bubble> _bubbles;
  final String _splashText = "听说读写玩，背词不再难";

  void checkNewVersion() async {
    // 检查新版本/自动升级
    if (PlatformUtils.isAndroid || PlatformUtils.isWindows) {
      // 获取程序版本信息
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int buildNumber = int.parse(packageInfo.buildNumber);
      Global.version = packageInfo.version;

      // 从服务端获取最新版本信息，如果发现新版本，则下载并升级
      try {
        var response =
            await Dio(BaseOptions(connectTimeout: Duration(seconds: 5), sendTimeout: Duration(seconds: 5), receiveTimeout: Duration(seconds: 5))).get(
          Config.updateUrl,
        );

        if (response.statusCode == 200) {
          int verCode = response.data![0]['verCode'];
          var verName = response.data![0]['verName'];
          var changes = response.data![0]['changes'];
          if (verCode > buildNumber) {
            setState(() {
              newVersionFound = true;
              newVersionName = verName;
              newVersionChanges = changes;
            });
          } else {
            /// 已经是最新版本
            tryAutoLogin();
          }
        } else {
          ToastUtil.error('获取版本信息失败');
          tryAutoLogin();
        }
      } on DioException {
        ToastUtil.error('获取版本信息失败!');
        tryAutoLogin();
      }
    } else {
      /// 非android/windows
      tryAutoLogin();
    }
  }

  Future<void> showUpgradeConfirmDlg(verName, changes) async {
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
      if (PlatformUtils.isAndroid) {
        downloadApkAndUpgrade();
      } else if (PlatformUtils.isWindows) {
        downloadWindowsAndUpgrade();
      }
    } else {
      tryAutoLogin();
    }
  }

  Future downloadApkAndUpgrade() async {
    try {
      Dio dio = Dio();

      String fileName = Config.apkUrl.substring(Config.apkUrl.lastIndexOf("/") + 1);

      savePath = await getFilePath(fileName);
      downloadStarted = true;
      downloading = true;
      var resp = await dio.download(Config.apkUrl, savePath, deleteOnError: true, onReceiveProgress: (rec, total) {
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
    if (!await Permission.requestInstallPackages.request().isGranted) {
      ToastUtil.error("未获得安装权限，仍使用旧版本");
      tryAutoLogin();
    }

    var result = await OpenFile.open(savePath, type: "application/vnd.android.package-archive");
    if (result.type == ResultType.done) {
      // 开始安装新版本，当前程序可以退出了
      SystemNavigator.pop();
    } else {
      ToastUtil.error("${result.message}，仍使用旧版本");
      tryAutoLogin();
    }
  }

  Future downloadWindowsAndUpgrade() async {
    try {
      Dio dio = Dio();

      String fileName = Config.windowsUrl.substring(Config.windowsUrl.lastIndexOf("/") + 1);

      savePath = await getFilePath(fileName);
      downloadStarted = true;
      downloading = true;
      var resp = await dio.download(Config.windowsUrl, savePath, deleteOnError: true, onReceiveProgress: (rec, total) {
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
        });
        installWindowsApp();
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

  Future<void> installWindowsApp() async {
    try {
      var result = await OpenFile.open(savePath);
      if (result.type == ResultType.done) {
        // 提示用户安装新版本
        ToastUtil.success("安装包已下载，请按照提示安装新版本");
        // 延迟退出，让用户看到提示
        Future.delayed(Duration(seconds: 2), () {
          SystemNavigator.pop();
        });
      } else {
        ToastUtil.error("打开安装包失败：${result.message}，仍使用旧版本");
        tryAutoLogin();
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleError(e, stackTrace, logPrefix: '打开Windows安装包失败', showToast: true);
      tryAutoLogin();
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
          ///正在下载
          child: downloading || downloadSuccess
              ? SizedBox(
                  height: 250,
                  width: 250,
                  child: CircularPercentIndicator(
                    radius: 60.0,
                    lineWidth: 5.0,
                    percent: (downloadedBytes ?? 0) / (totalBytes ?? 1024),
                    center: Text(
                      "${((downloadedBytes ?? 0) / 1024).round()}k\n${((totalBytes ?? 1024) / 1024).round()}k",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                    progressColor: Colors.green,
                  ),
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
                                    downloadApkAndUpgrade();
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
                                          '正在准备学习环境…',
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
    var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
    if (user != null && user.email != null) {
      var result = await UserBo().checkUser(CheckBy.email, user.email!, null, user.password!, getClientType().json, Global.version);
      if (result.success) {
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
