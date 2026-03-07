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
      // 重置登录状态，防止死锁
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isWechatLoading) {
          setState(() => _isWechatLoading = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8FAFC),
              const Color(0xFFF1F5F9),
              Colors.white,
              const Color(0xFFECFEFF), // Cyan-50 hint
            ],
            stops: const [0.0, 0.4, 0.8, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background elements
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF22D3EE).withValues(alpha: 0.08),
                      const Color(0xFF22D3EE).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0EA5E9).withValues(alpha: 0.05),
                      const Color(0xFF0EA5E9).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            
            // Main Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    
                    // Logo & Title Section
                    GestureDetector(
                      onDoubleTap: _showVersionAndProfileDialog,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF22D3EE).withValues(alpha: 0.15),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Image.asset('assets/images/logo.png', width: 84, height: 84),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            '泡泡单词',
                            style: TextStyle(
                              color: Color(0xFF0F172A), // Slate-900
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.0,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0EA5E9).withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Progress, not perfection',
                              style: TextStyle(
                                color: Color(0xFF0EA5E9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Spacer(flex: 4),
                    
                    // Action Section
                    Column(
                      children: [
                        if (PlatformUtils.isIOS || PlatformUtils.isAndroid)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF07C160), Color(0xFF06AD56)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF07C160).withValues(alpha: 0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _isWechatLoading ? null : wechatLoginPressed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                splashFactory: InkSparkle.splashFactory,
                              ),
                              icon: const Icon(Icons.wechat, color: Colors.white, size: 26),
                              label: Text(
                                _isWechatLoading ? '正在连接...' : '微信一键登录',
                                style: const TextStyle(
                                  fontSize: 16, 
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMinorButton('邮箱登录', () => Navigator.of(context).pushNamed('/email_login')),
                            Container(
                              width: 1,
                              height: 14,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: const Color(0xFFCBD5E1),
                            ),
                            _buildMinorButton('先去逛逛', () async {
                              await Global.loginAsGuest();
                              await SubscriptionUtil.restorePurchases(showToast: false);
                              Get.offAllNamed('/index');
                            }),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Agreement Section
                        GestureDetector(
                          onTap: () => setState(() => _approved = !_approved),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            color: Colors.transparent, // Expand tap area
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _approved ? const Color(0xFF0EA5E9) : Colors.transparent,
                                    border: Border.all(
                                      color: _approved ? const Color(0xFF0EA5E9) : const Color(0xFFCBD5E1),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: _approved 
                                    ? const Icon(Icons.check, color: Colors.white, size: 12) 
                                    : null,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  '同意 ', 
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500)
                                ),
                                _buildLink('《用户协议》', showProtocolPage),
                                const Text(
                                  ' 与 ', 
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500)
                                ),
                                _buildLink('《隐私政策》', showPrivacyPage),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
                      ],
                    ),
                  ],
                ),
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

  Widget _buildLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0EA5E9),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFamily: 'NotoSansSC',
        ),
      ),
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
              StatefulBuilder(builder: (context, setState) {
                return Row(
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
                );
              }),
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
