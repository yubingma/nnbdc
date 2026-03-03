import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config.dart';
import '../global.dart';
import '../socket_io.dart';
import '../util/client_type.dart';
import 'package:fluwx/fluwx.dart';
import 'package:nnbdc/util/wechat_util.dart';
import 'package:nnbdc/util/platform_util.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  bool _approved = false;
  bool _isWechatLoading = false;
  DateTime? _lastTapTime;
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  loadData() async {
    var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
    if (user != null) {
      setState(() {
        _approved = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isWechatLoading) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isWechatLoading) {
          setState(() {
            _isWechatLoading = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Column(
          children: [
            const Spacer(flex: 3),
            // Logo & Title Section
            GestureDetector(
              onDoubleTap: _showVersionAndProfileDialog,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Image.asset('assets/images/logo.png', width: 72, height: 72),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '泡泡单词',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Progress, not perfection',
                    style: TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 4),
            // Action Section
            Padding(
              padding: EdgeInsets.only(
                left: 48,
                right: 48,
                bottom: MediaQuery.of(context).viewPadding.bottom + 40,
              ),
              child: Column(
                children: [
                  if (PlatformUtils.isIOS || PlatformUtils.isAndroid)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isWechatLoading ? null : wechatLoginPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5F5F5),
                          foregroundColor: const Color(0xFF1A1A1A),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.wechat, color: Color(0xFF07C160), size: 24),
                        label: Text(
                          _isWechatLoading ? '正在连接...' : '微信一键登录',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMinorButton('邮箱登录', () => Navigator.of(context).pushNamed('/email_login')),
                      _buildDivider(),
                      _buildMinorButton('先去逛逛', () async {
                        await Global.loginAsGuest();
                        await SubscriptionUtil.restorePurchases(showToast: false);
                        Get.offAllNamed('/index');
                      }),
                    ],
                  ),
                  const SizedBox(height: 48),
                  // Agreement Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: _approved,
                          onChanged: (v) => setState(() => _approved = v ?? false),
                          activeColor: const Color(0xFF1A1A1A),
                          shape: const CircleBorder(),
                          side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('同意 ', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11)),
                      _buildLink('《用户协议》', showProtocolPage),
                      const Text(' 与 ', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11)),
                      _buildLink('《隐私政策》', showPrivacyPage),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinorButton(String text, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      child: Text(text, style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontWeight: FontWeight.w400)),
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 12, color: Colors.grey.withValues(alpha: 0.2));
  }

  Widget _buildLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(text, style: const TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  void showPrivacyPage() => Navigator.pushNamed(context, "/privacy");
  void showProtocolPage() => Navigator.pushNamed(context, "/protocol");

  void wechatLoginPressed() async {
    if (!_approved) {
      ToastUtil.error("请先同意[使用协议]和[隐私政策]");
      return;
    }
    setState(() => _isWechatLoading = true);
    try {
      bool handled = false;
      late final FluwxCancelable cancelable;
      cancelable = WechatUtil.addSubscriber((response) async {
        if (handled || response is! WeChatAuthResponse) return;
        handled = true;
        cancelable.cancel();
        if (response.code != null) {
          try {
            final result = await Api.client.loginByWechat(response.code!, getClientType().name, Global.version);
            if (result.success && result.data != null) {
              final userVo = UserVo.fromJson(result.data as Map<String, dynamic>);
              userVo.lastLoginTime = AppClock.now();
              await MyDatabase.instance.usersDao.saveUser(userVo2User(userVo), false);
              await Global.setLoggedInUser(userVo);
              SubscriptionUtil.restorePurchases(showToast: false);
              Get.offAllNamed('/index');
              return;
            }
            ToastUtil.error(result.msg ?? '微信登录失败');
          } catch (e, stackTrace) {
            ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByWechat');
          }
        } else {
          ToastUtil.error('微信授权失败');
        }
        if (mounted) setState(() => _isWechatLoading = false);
      });
      if (!await WechatUtil.login()) {
        handled = true;
        cancelable.cancel();
        setState(() => _isWechatLoading = false);
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByWechat');
      setState(() => _isWechatLoading = false);
    }
  }

  Future<void> _showVersionAndProfileDialog() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int dbVersion = MyDatabase.instance.schemaVersion;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('应用信息'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('版本: ${packageInfo.version} (${packageInfo.buildNumber})'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('环境: ${Config.profileName}'),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        Config.profileName = (Config.profileName == 'dev' ? 'prod' : 'dev');
                        Api.useProdUrl = (Config.profileName == 'prod');
                      });
                      Api.resetClient();
                      SocketIoClient.instance.reset();
                      Navigator.pop(context);
                      ToastUtil.success('已切换到 ${Config.profileName}');
                    },
                    child: const Text('切换'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('数据库版本: $dbVersion'),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
        ),
      );
    } catch (e) {
      if (mounted) ToastUtil.error('获取信息失败');
    }
  }
}
