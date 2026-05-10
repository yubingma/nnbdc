import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluwx/fluwx.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/wechat_util.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../config.dart';
import '../global.dart';
import '../socket_io.dart';
import '../util/client_type.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _bubbleController;
  bool _approved = false;
  bool _isWechatLoading = false;
  bool _isAppleLoading = false;
  bool _isGuestLoading = false;
  bool _isWechatInstalled = true; // 默认显示，后续异步检测

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bubbleController.dispose();
    super.dispose();
  }

  loadData() async {
    var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
    if (user != null) {
      // 检查隐私政策版本
      const int currentPrivacyVersion = 20260310;
      int acceptedVersion =
          Prefs.read<int>('accepted_privacy_version') ?? 0;
      if (acceptedVersion >= currentPrivacyVersion) {
        setState(() {
          _approved = true;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bubbleController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    loadData();
    _checkWechatInstallation();
    _requestTrackingPermission();
  }

  Future<void> _checkWechatInstallation() async {
    if (PlatformUtils.isIOS) {
      bool installed = await WechatUtil.isWechatInstalled();
      if (mounted) {
        setState(() {
          _isWechatInstalled = installed;
        });
      }
    }
  }

  Future<void> _requestTrackingPermission() async {
    if (PlatformUtils.isIOS) {
      try {
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          // 等待一秒钟，确保页面已经渲染
          await Future.delayed(const Duration(milliseconds: 1000));
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      } catch (e) {
        debugPrint('Error requesting tracking permission: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_isWechatLoading || _isAppleLoading)) {
      // 重置登录状态，防止死锁
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          if (_isWechatLoading) setState(() => _isWechatLoading = false);
          if (_isAppleLoading) setState(() => _isAppleLoading = false);
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
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0EA5E9), // Sky-500
              const Color(0xFF0284C7), // Sky-600
              const Color(0xFF0369A1), // Sky-700
              const Color(0xFF075985), // Sky-800
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background elements
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

            // Animated Bubbles
            AnimatedBuilder(
              animation: _bubbleController,
              builder: (context, child) {
                return Stack(
                  children: [
                    _buildFloatingBubble(0.2, 0.8, 40, 0.08, offset: 0.1),
                    _buildFloatingBubble(0.7, 0.6, 24, 0.05, offset: 0.4),
                    _buildFloatingBubble(0.1, 0.2, 32, 0.04, offset: 0.7),
                    _buildFloatingBubble(0.8, 0.1, 16, 0.06, offset: 0.2),
                    _buildFloatingBubble(0.5, 0.5, 20, 0.03, offset: 0.9),
                    _buildFloatingBubble(0.3, 0.9, 28, 0.05, offset: 0.5),
                  ],
                );
              },
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
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 15,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Image.asset('assets/images/logo.png',
                                width: 76, height: 76),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            Global.appName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4.0,
                              fontFamily: 'NotoSansSC',
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  offset: Offset(0, 4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '进步而非完美',
                            style: TextStyle(
                              color: Color(0xFFBAE6FD), // Sky-200
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2.0,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 4),

                    // Action Section
                    Column(
                      children: [
                        if (PlatformUtils.isIOS)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: (_isWechatLoading ||
                                      _isAppleLoading ||
                                      _isGuestLoading)
                                  ? null
                                  : appleLoginPressed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                splashFactory: InkSparkle.splashFactory,
                              ),
                              icon: const Icon(Icons.apple,
                                  color: Colors.white, size: 26),
                              label: Text(
                                _isAppleLoading ? '正在连接...' : '通过 Apple 登录',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                            ),
                          ),
                        if (PlatformUtils.isIOS || PlatformUtils.isAndroid)
                          if (!PlatformUtils.isIOS || _isWechatInstalled)
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
                                  color: const Color(0xFF07C160)
                                      .withValues(alpha: 0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: (_isWechatLoading ||
                                      _isAppleLoading ||
                                      _isGuestLoading)
                                  ? null
                                  : wechatLoginPressed,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                splashFactory: InkSparkle.splashFactory,
                              ),
                              icon: const Icon(Icons.wechat,
                                  color: Colors.white, size: 26),
                              label: Text(
                                _isWechatLoading ? '正在连接...' : '微信一键登录',
                                style: const TextStyle(
                                  color: Colors.white,
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
                            _buildMinorButton('邮箱登录', () {
                              if (!_approved) {
                                ToastUtil.error("请先同意[使用协议]和[隐私政策]");
                                return;
                              }
                              context.push('/email_login',
                                  extra: {'approved': _approved});
                            }),
                            Container(
                              width: 1,
                              height: 14,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: Colors.white24,
                            ),
                            _buildMinorButton(
                                _isGuestLoading ? '正在登录...' : '先去逛逛', () async {
                              if (_isGuestLoading) return;
                              if (!_approved) {
                                ToastUtil.error("请先同意[使用协议]和[隐私政策]");
                                return;
                              }
                              setState(() => _isGuestLoading = true);
                              try {
                                await Global.loginAsGuest();
                                // 访客也尝试同步（虽然目前 Global.isGuest 为真时 syncUserDb 会跳过，但 syncSysDb 仍有用）
                                ThrottledDbSyncService()
                                    .requestSync(immediate: true);
                                // 记录同意了当前隐私政策版本
                                Prefs.write(
                                    'accepted_privacy_version', 20260310);

                                // 访客登录后初始化统计 SDK (如果是 Android/iOS)
                                if (PlatformUtils.isAndroid ||
                                    PlatformUtils.isIOS) {
                                  try {
                                    UmengCommonSdk.initCommon(
                                        Config.umengAndroidAppKey,
                                        Config.umengIosAppKey,
                                        Config.umengChannel);
                                  } catch (e) {
                                    debugPrint('Umeng init error: $e');
                                  }
                                }

                                await SubscriptionUtil.restorePurchases(
                                    showToast: false);
                                if (context.mounted) context.go('/index');
                              } catch (e, stackTrace) {
                                ErrorHandler.handleNetworkError(e, stackTrace,
                                    api: 'loginAsGuest');
                                if (mounted) {
                                  setState(() => _isGuestLoading = false);
                                }
                              }
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
                                    color: _approved
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: _approved
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: _approved
                                      ? const Icon(Icons.check,
                                          color: Color(0xFF0284C7), size: 12)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                const Text('同意 ',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                                _buildLink('《用户协议》', showProtocolPage),
                                const Text(' 与 ',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                                _buildLink('《隐私政策》', showPrivacyPage),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                            height: MediaQuery.of(context).padding.bottom + 20),
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
      style: TextButton.styleFrom(
          minimumSize: Size.zero,
          foregroundColor: const Color(0xFFE0F2FE),
          disabledForegroundColor: const Color(0xFFE0F2FE).withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildFloatingBubble(double leftPercent, double startBottomPercent,
      double size, double opacity,
      {required double offset}) {
    double progress = (_bubbleController.value + offset) % 1.0;
    double bottom =
        (startBottomPercent + (1.0 - startBottomPercent) * progress) *
            MediaQuery.of(context).size.height;

    // Fade out as it goes up
    double currentOpacity = opacity * (1.0 - progress * 0.5);

    return Positioned(
      left: leftPercent * MediaQuery.of(context).size.width,
      bottom: bottom,
      child: _buildBubble(size, currentOpacity),
    );
  }

  Widget _buildBubble(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
        border: Border.all(
          color: Colors.white.withValues(alpha: opacity * 1.5),
          width: 0.8,
        ),
      ),
    );
  }

  Widget _buildLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF7DD3FC), // Sky-300
          fontSize: 12,
          fontWeight: FontWeight.w800,
          fontFamily: 'NotoSansSC',
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF7DD3FC),
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
            final result = await Api.client.loginByWechat(
                response.code!, getClientType().name, Global.version);
            if (result.success && result.data != null) {
              final userVo =
                  UserVo.fromJson(result.data as Map<String, dynamic>);
              userVo.lastLoginTime = AppClock.now();
              await MyDatabase.instance.usersDao
                  .saveUser(userVo2User(userVo), true); // 开启同步信号
              await Global.setLoggedInUser(userVo);

              // 记录登录操作日志
              await MyDatabase.instance.userOpersDao.recordLogin(userVo.id!, remark: "微信登录");

              // 微信登录成功后立即触发同步
              ThrottledDbSyncService().requestSync(immediate: true);

              // 记录同意了当前隐私政策版本
              Prefs.write('accepted_privacy_version', 20260310);

              // 登录成功后初始化统计 SDK (如果是 Android/iOS)
              if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
                try {
                  UmengCommonSdk.initCommon(Config.umengAndroidAppKey,
                      Config.umengIosAppKey, Config.umengChannel);
                } catch (e) {
                  debugPrint('Umeng init error: $e');
                }
              }

              SubscriptionUtil.restorePurchases(showToast: false);
              if (mounted) context.go('/index');
              return;
            }
            ToastUtil.error(result.msg ?? '微信登录失败');
          } catch (e, stackTrace) {
            ErrorHandler.handleNetworkError(e, stackTrace,
                api: 'loginByWechat');
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

  void appleLoginPressed() async {
    if (!_approved) {
      ToastUtil.error("请先同意[使用协议]和[隐私政策]");
      return;
    }
    setState(() => _isAppleLoading = true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      String? nickname;
      if (credential.givenName != null || credential.familyName != null) {
        nickname =
            '${credential.givenName ?? ""} ${credential.familyName ?? ""}'
                .trim();
      }

      final result = await Api.client.loginByApple(credential.userIdentifier!,
          credential.email, nickname, getClientType().name, Global.version);

      if (result.success && result.data != null) {
        final userVo = UserVo.fromJson(result.data as Map<String, dynamic>);
        userVo.lastLoginTime = AppClock.now();
        await MyDatabase.instance.usersDao.saveUser(userVo2User(userVo), true); // 开启同步信号
        await Global.setLoggedInUser(userVo);

        // 记录登录操作日志
        await MyDatabase.instance.userOpersDao.recordLogin(userVo.id!, remark: "Apple登录");

        ThrottledDbSyncService().requestSync(immediate: true);

        Prefs.write('accepted_privacy_version', 20260310);

        if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
          try {
            UmengCommonSdk.initCommon(Config.umengAndroidAppKey,
                Config.umengIosAppKey, Config.umengChannel);
          } catch (e) {
            debugPrint('Umeng init error: $e');
          }
        }

        SubscriptionUtil.restorePurchases(showToast: false);
        if (mounted) context.go('/index');
        return;
      }
      ToastUtil.error(result.msg ?? '苹果登录失败');
    } catch (e, stackTrace) {
      if (e is SignInWithAppleAuthorizationException &&
          e.code == AuthorizationErrorCode.canceled) {
        // User canceled
      } else {
        ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByApple');
      }
    } finally {
      if (mounted) {
        setState(() => _isAppleLoading = false);
      }
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
                          Config.profileName =
                              (Config.profileName == 'dev' ? 'prod' : 'dev');
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
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'))
          ],
        ),
      );
    } catch (e) {
      if (mounted) ToastUtil.error('获取信息失败');
    }
  }
}
