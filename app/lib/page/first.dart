import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../api/api.dart';
import '../api/bo/user_bo.dart';
import '../config.dart';
import '../global.dart';
import '../db/db.dart';
import '../services/update_service.dart';
import '../util/subscription_util.dart';
import '../page/index.dart';

class FirstPage extends ConsumerStatefulWidget {
  const FirstPage({super.key});

  @override
  FirstPageState createState() => FirstPageState();
}

class FirstPageState extends ConsumerState<FirstPage> with SingleTickerProviderStateMixin {
  // 版本状态
  String? _buildNumber;
  String? _versionName;

  // 提示文案
  String _preparingMessage = '正在准备学习环境…';
  String? _autoLoginError;

  // 轻微呼吸动画
  late AnimationController _splashController;

  @override
  void initState() {
    super.initState();
    Api.setLoadingDisabled(true);

    _splashController = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPrivacyAndProceed());
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
    int acceptedVersion = Prefs.read<int>('accepted_privacy_version') ?? 0;

    if (acceptedVersion < currentPrivacyVersion) {
      _showPrivacyDialog();
    } else {
      _initVersion().then((_) => checkNewVersion());
    }
  }

  Future<void> _initVersion() async {
    final pi = await PackageInfo.fromPlatform();
    Global.version = pi.version;
    Global.buildNumber = pi.buildNumber;
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
      final updateNotifier = ref.read(updateServiceProvider.notifier);

      // 重新获取一次 buildNumber，确保最准确
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      
      final info = await updateNotifier.checkForUpdateOnStartup(currentBuild);

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
        await updateNotifier.downloadUpdate(updateInfo);
        
        // 如果是强制更新，则不继续执行自动登录进入主页
        if (updateInfo.isForce) {
          debugPrint('强制更新模式，停止自动登录流程');
          return;
        }
        
        tryAutoLogin();
      } else {
        tryAutoLogin();
      }
    } catch (e, stack) {
      debugPrint('检查更新发生异常: $e\n$stack');
      tryAutoLogin();
    }
  }

  Future<void> tryAutoLogin() async {
    _setPreparingMessage('正在自动登录…');
    try {
      final user = await MyDatabase.instance.usersDao.getLastLoggedInUser();

      // 如果是游客账号，不自动登录，清除会话后直接进入登录页
      if (user != null && user.id != Global.guestId) {
        // 自动登录逻辑...
        final result = await UserBo().getLoggedInUser();
        if (result.success && result.data != null) {
          await Global.setLoggedInUser(result.data!);
          SubscriptionUtil.restorePurchases(showToast: false);
          if (mounted) context.go("/index", extra: IndexPageArgs(0));
        } else {
          if (mounted) context.go("/login");
        }
      } else {
        if (user?.id == Global.guestId) {
          await Global.logout();
        }
        if (mounted) context.go("/login");
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '服务协议与隐私政策',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'NotoSansSC'),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请阅读并接受：', style: TextStyle(fontSize: 14, fontFamily: 'NotoSansSC')),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push('/protocol'),
                  child: const Text(
                    '《用户协议》',
                    style: TextStyle(color: Color(0xFF18BA7C), fontWeight: FontWeight.bold, fontFamily: 'NotoSansSC'),
                  ),
                ),
                const Text(' 与 '),
                GestureDetector(
                  onTap: () => context.push('/privacy'),
                  child: const Text(
                    '《隐私政策》',
                    style: TextStyle(color: Color(0xFF18BA7C), fontWeight: FontWeight.bold, fontFamily: 'NotoSansSC'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '点击“同意并继续”即表示您已阅读并接受上述协议。',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'NotoSansSC'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => exit(0),
            child: const Text('不同意', style: TextStyle(color: Colors.grey, fontFamily: 'NotoSansSC')),
          ),
          ElevatedButton(
            onPressed: () async {
              await Prefs.write('accepted_privacy_version', 20260310);
              if (context.mounted) Navigator.of(context).pop();
              _initVersion().then((_) => checkNewVersion());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF18BA7C),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('同意并继续', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'NotoSansSC')),
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
    // 纯白极简体系（与原生启动屏无缝融合）
    const textMainColor = Color(0xFF152724);
    const textSubColor = Color(0xFF5A7570);
    const textMutedColor = Color(0xFF8EA8A3);
    const accentGreen = Color(0xFF18BA7C);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _splashController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + 0.03 * math.sin(_splashController.value * math.pi),
                    child: child,
                  );
                },
                child: Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0x1818BA7C),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentGreen.withValues(alpha: 0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      "assets/images/logo.png",
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '泡泡单词',
                style: TextStyle(
                  color: textMainColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'PROGRESS OVER PERFECTION',
                style: TextStyle(
                  color: textSubColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 44),
              _buildStatusIndicator(),
              const SizedBox(height: 24),
              Text(
                '版本 ${_versionName ?? ''}(${_buildNumber ?? ''})',
                style: const TextStyle(
                  color: textMutedColor,
                  fontSize: 11,
                  fontFamily: 'Roboto',
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    const textSubColor = Color(0xFF5A7570);
    const accentGreen = Color(0xFF18BA7C);
    final err = Global.startupError.value ?? _autoLoginError;

    return Column(
      children: [
        if (err == null)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(accentGreen),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          err ?? _preparingMessage,
          style: TextStyle(
            color: err == null ? textSubColor : Colors.redAccent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSansSC',
          ),
        ),
        if (err != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton(
              onPressed: () => _checkPrivacyAndProceed(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: accentGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              ),
              child: const Text('重试', style: TextStyle(fontFamily: 'NotoSansSC', fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}


