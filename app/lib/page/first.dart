import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../api/api.dart';
import '../api/bo/user_bo.dart';
import '../config.dart';
import '../global.dart';
import '../db/db.dart';
import '../services/update_service.dart';
import '../util/subscription_util.dart';
import '../page/index.dart';

class FirstPage extends StatefulWidget {
  const FirstPage({super.key});

  @override
  FirstPageState createState() => FirstPageState();
}

class FirstPageState extends State<FirstPage> with SingleTickerProviderStateMixin {
  // 版本状态
  String? _buildNumber;
  String? _versionName;

  // 提示文案
  String _preparingMessage = '正在准备学习环境…';
  String? _autoLoginError;

  // 动画背景
  late AnimationController _splashController;
  late List<_Bubble> _bubbles;
  final String _splashText = "Progress, not perfection\n进步而非完美";

  @override
  void initState() {
    super.initState();
    Api.setLoadingDisabled(true);

    _initBubbles();
    _splashController = AnimationController(vsync: this, duration: const Duration(seconds: 20))
      ..addListener(() => _updateBubbles())
      ..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPrivacyAndProceed());
  }

  void _initBubbles() {
    final rnd = math.Random();
    _bubbles = List.generate(24, (i) {
      return _Bubble(
        rnd.nextDouble(),
        rnd.nextDouble(),
        6 + rnd.nextDouble() * 18,
        0.0006 + rnd.nextDouble() * 0.0016,
        Colors.white.withValues(alpha: 0.05 + rnd.nextDouble() * 0.10),
      );
    });
  }

  void _updateBubbles() {
    for (final b in _bubbles) {
      b.y -= b.speed * 16 / 1000 * 60;
      if (b.y < -0.05) {
        b.y = 1.1;
        b.x = math.Random().nextDouble();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Api.setLoadingDisabled(false);
    _splashController.dispose();
    super.dispose();
  }

  // --- 启动流程 ---

  void _checkPrivacyAndProceed() async {
    const int currentPrivacyVersion = 20260310;
    int acceptedVersion = GetStorage().read<int>('accepted_privacy_version') ?? 0;

    if (acceptedVersion < currentPrivacyVersion) {
      _showPrivacyDialog();
    } else {
      _initVersion().then((_) => checkNewVersion());
    }
  }

  Future<void> _initVersion() async {
    final pi = await PackageInfo.fromPlatform();
    Global.version = pi.version;
    if (mounted) {
      setState(() {
        _buildNumber = pi.buildNumber;
        _versionName = pi.version;
      });
    }
  }

  void checkNewVersion() async {
    _setPreparingMessage('正在检查更新…');
    try {
      final updateService = Get.find<UpdateService>();
      final currentBuild = int.tryParse(_buildNumber ?? '0') ?? 0;
      final info = await updateService.checkForUpdateOnStartup(currentBuild);

      if (info != null) {
        String downloadUrl = Config.apkUrl;
        if (Platform.isWindows) {
          downloadUrl = Config.windowsUrl;
        } else if (Platform.isLinux) {
          downloadUrl = Config.linuxUrl;
        }

        final updateInfo = UpdateInfo(
          version: info['verCode'].toString(),
          buildNumber: info['verCode'].toString(),
          downloadUrl: '$downloadUrl?ver=${info['verCode']}',
          size: '0',
          releaseNotes: (info['changes'] as List).join('\n'),
          isForce: info['belowMinVersion'] ?? false,
        );
        await updateService.downloadUpdate(updateInfo);
      } else {
        tryAutoLogin();
      }
    } catch (e) {
      tryAutoLogin();
    }
  }

  Future<void> tryAutoLogin() async {
    _setPreparingMessage('正在自动登录…');
    try {
      final user = await MyDatabase.instance.usersDao.getLastLoggedInUser();

      if (user != null) {
        // 自动登录逻辑...
        final result = await UserBo().getLoggedInUser();
        if (result.success && result.data != null) {
          await Global.setLoggedInUser(result.data!);
          SubscriptionUtil.restorePurchases(showToast: false);
          Get.offNamed("/index", arguments: IndexPageArgs(0));
        } else {
          Get.offNamed("/login");
        }
      } else {
        Get.offNamed("/login");
      }
    } catch (e) {
      _setAutoLoginError('登录失败: $e');
    }
  }

  // --- UI 构建 ---

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('服务协议与隐私政策', style: TextStyle(fontSize: 16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('使用前请先阅读并同意：', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => Get.toNamed('/protocol'),
                  child: const Text('《用户协议》', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                ),
                const Text(' 与 '),
                GestureDetector(
                  onTap: () => Get.toNamed('/privacy'),
                  child: const Text('《隐私政策》', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('点击“同意”即表示您已接受上述协议。', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => exit(0), child: const Text('不同意', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              await GetStorage().write('accepted_privacy_version', 20260310);
              Get.back();
              _initVersion().then((_) => checkNewVersion());
            },
            style: ElevatedButton.styleFrom(elevation: 0),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
  }

  void _setPreparingMessage(String msg) {
    if (mounted) setState(() => _preparingMessage = msg);
  }

  void _setAutoLoginError(String? msg) {
    if (mounted) setState(() => _autoLoginError = msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0EA5E9),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0EA5E9), Color(0xFF075985)],
              ),
            ),
          ),
          CustomPaint(painter: _BubblesPainter(_bubbles), size: Size.infinite),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 1.0 + 0.04 * math.sin(_splashController.value * 2 * math.pi),
                  child: Image.asset("assets/images/logo.png", width: 90),
                ),
                const SizedBox(height: 20),
                Text(_splashText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 40),
                _buildStatusIndicator(),
                const SizedBox(height: 20),
                Text('版本 ${_versionName ?? ''}(${_buildNumber ?? ''})', style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final err = Global.startupError.value ?? _autoLoginError;
    return Column(
      children: [
        if (err == null)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white))),
        const SizedBox(height: 10),
        Text(err ?? _preparingMessage, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        if (err != null) TextButton(onPressed: () => _checkPrivacyAndProceed(), child: const Text('重试', style: TextStyle(color: Colors.white))),
      ],
    );
  }
}

class _Bubble {
  double x, y, radius, speed;
  Color color;
  _Bubble(this.x, this.y, this.radius, this.speed, this.color);
}

class _BubblesPainter extends CustomPainter {
  final List<_Bubble> bubbles;
  _BubblesPainter(this.bubbles);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    for (var b in bubbles) {
      paint.color = b.color;
      canvas.drawCircle(Offset(b.x * size.width, b.y * size.height), b.radius, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;
}
