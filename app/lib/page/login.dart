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
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/wechat_util.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../theme/app_theme.dart';
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
    if (PlatformUtils.isZhuoyiTong) {
      if (mounted) {
        setState(() {
          _isWechatInstalled = false;
        });
      }
      return;
    }
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
      TrackingStatus status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
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
    final isDarkMode = context.isDarkMode;
    final themeConfig = context.themeConfig;

    final textMainColor = themeConfig.textPrimary;
    final textSubColor = themeConfig.textSecondary;
    final textMutedColor = isDarkMode ? Colors.white38 : const Color(0xFF475569);
    final accentColor = themeConfig.primaryColor;
    final appleBgColor = isDarkMode ? const Color(0xFF192A26) : const Color(0xFF111827);
    final dividerColor = themeConfig.cardBorder;

    return AppScaffold(
      body: Stack(
        children: [
          // 1. 顶部与底部柔和环境微光
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentColor.withValues(alpha: isDarkMode ? 0.15 : 0.09),
                    accentColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -100,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentColor.withValues(alpha: isDarkMode ? 0.09 : 0.06),
                    accentColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          // 2. 呼吸浮动泡泡
          AnimatedBuilder(
            animation: _bubbleController,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildFloatingBubble(0.15, 0.75, 44, isDarkMode ? 0.04 : 0.06, offset: 0.1, isDark: isDarkMode, color: accentColor),
                  _buildFloatingBubble(0.78, 0.60, 26, isDarkMode ? 0.03 : 0.05, offset: 0.4, isDark: isDarkMode, color: accentColor),
                  _buildFloatingBubble(0.10, 0.25, 34, isDarkMode ? 0.03 : 0.04, offset: 0.7, isDark: isDarkMode, color: accentColor),
                  _buildFloatingBubble(0.85, 0.18, 18, isDarkMode ? 0.04 : 0.06, offset: 0.2, isDark: isDarkMode, color: accentColor),
                  _buildFloatingBubble(0.52, 0.48, 22, isDarkMode ? 0.02 : 0.04, offset: 0.9, isDark: isDarkMode, color: accentColor),
                ],
              );
            },
          ),

          // 3. 核心内容
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Brand Hero & Logo
                  GestureDetector(
                    onDoubleTap: _showVersionAndProfileDialog,
                    child: Column(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF13201D) : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDarkMode ? Colors.white12 : const Color(0x1418BA7C),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDarkMode ? Colors.black45 : const Color(0x1818BA7C),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          Global.appName,
                          style: TextStyle(
                            color: textMainColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.0,
                            fontFamily: 'NotoSansSC',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'PROGRESS OVER PERFECTION',
                          style: TextStyle(
                            color: textSubColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 4),

                  // 登录操作区
                  Column(
                    children: [
                      // 微信登录主按钮
                      if ((PlatformUtils.isIOS || PlatformUtils.isAndroid) &&
                          !PlatformUtils.isZhuoyiTong &&
                          (!PlatformUtils.isIOS || _isWechatInstalled))
                        Container(
                          width: double.infinity,
                          height: 52,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: LinearGradient(
                              colors: context.appBarGradient,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: isDarkMode ? 0.35 : 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: (_isWechatLoading || _isAppleLoading || _isGuestLoading)
                                ? null
                                : wechatLoginPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                            icon: _isWechatLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.wechat, color: Colors.white, size: 24),
                            label: Text(
                              _isWechatLoading ? '正在连接微信...' : '微信一键登录',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                          ),
                        ),

                      // Apple 登录按钮
                      if (PlatformUtils.isIOS)
                        Container(
                          width: double.infinity,
                          height: 52,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: appleBgColor,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: isDarkMode ? Colors.white12 : Colors.transparent,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: (_isWechatLoading || _isAppleLoading || _isGuestLoading)
                                ? null
                                : appleLoginPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                            icon: _isAppleLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.apple, color: Colors.white, size: 24),
                            label: Text(
                              _isAppleLoading ? '正在连接 Apple...' : '通过 Apple 登录',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                          ),
                        ),

                      // 卓易通 / 无微信环境下的邮箱主按钮
                      if (!PlatformUtils.isIOS && (PlatformUtils.isZhuoyiTong || !_isWechatInstalled))
                        Container(
                          width: double.infinity,
                          height: 52,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: LinearGradient(
                              colors: context.appBarGradient,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: isDarkMode ? 0.35 : 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: (_isWechatLoading || _isAppleLoading || _isGuestLoading)
                                ? null
                                : _onEmailLoginPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                            icon: const Icon(Icons.email_outlined, color: Colors.white, size: 22),
                            label: const Text(
                              '邮箱验证码登录',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                          ),
                        ),

                      // 次级小入口（邮箱 / 游客）
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!(!PlatformUtils.isIOS && (PlatformUtils.isZhuoyiTong || !_isWechatInstalled))) ...[
                              _buildMinorButton('邮箱登录', _onEmailLoginPressed, textSubColor),
                              Container(
                                width: 1,
                                height: 12,
                                margin: const EdgeInsets.symmetric(horizontal: 10),
                                color: dividerColor,
                              ),
                            ],
                            _buildMinorButton(
                              _isGuestLoading ? '正在登录...' : '先去逛逛',
                              () async {
                                if (_isGuestLoading) return;
                                if (!_approved) {
                                  ToastUtil.error("请先同意[使用协议]和[隐私政策]");
                                  return;
                                }
                                setState(() => _isGuestLoading = true);
                                try {
                                  await Global.loginAsGuest();
                                  ThrottledDbSyncService().requestSync(immediate: true);
                                  Prefs.write('accepted_privacy_version', 20260310);

                                  if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
                                    try {
                                      UmengCommonSdk.initCommon(
                                        Config.umengAndroidAppKey,
                                        Config.umengIosAppKey,
                                        Config.umengChannel,
                                      );
                                    } catch (e) {
                                      debugPrint('Umeng init error: $e');
                                    }
                                  }

                                  await SubscriptionUtil.restorePurchases(showToast: false);
                                  if (context.mounted) context.go('/index');
                                } catch (e, stackTrace) {
                                  ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginAsGuest');
                                  if (mounted) {
                                    setState(() => _isGuestLoading = false);
                                  }
                                }
                              },
                              textSubColor,
                            ),
                          ],
                        ),
                      ),

                      if (PlatformUtils.isZhuoyiTong)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '卓易通兼容环境暂不支持微信登录，请使用邮箱登录',
                            style: TextStyle(
                              color: textMutedColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),

                      // 协议勾选行
                      GestureDetector(
                        onTap: () => setState(() => _approved = !_approved),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          color: Colors.transparent,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _approved ? accentColor : Colors.transparent,
                                  border: Border.all(
                                    color: _approved
                                        ? accentColor
                                        : (isDarkMode ? Colors.white38 : const Color(0xFFCBD5E1)),
                                    width: 1.5,
                                  ),
                                ),
                                child: _approved
                                    ? const Center(
                                        child: Icon(Icons.check, color: Colors.white, size: 11),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '已阅读并同意 ',
                                style: TextStyle(
                                  color: textMutedColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                              _buildLink('《用户协议》', showProtocolPage, textMainColor),
                              Text(
                                ' 与 ',
                                style: TextStyle(
                                  color: textMutedColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                              _buildLink('《隐私政策》', showPrivacyPage, textMainColor),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinorButton(String text, VoidCallback onTap, Color textColor) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        foregroundColor: textColor,
        disabledForegroundColor: textColor.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'NotoSansSC',
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildFloatingBubble(double leftPercent, double startBottomPercent, double size, double opacity,
      {required double offset, required bool isDark, required Color color}) {
    double progress = (_bubbleController.value + offset) % 1.0;
    double bottom = (startBottomPercent + (1.0 - startBottomPercent) * progress) * MediaQuery.of(context).size.height;
    double currentOpacity = opacity * (1.0 - progress * 0.5);

    return Positioned(
      left: leftPercent * MediaQuery.of(context).size.width,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: currentOpacity),
          border: Border.all(
            color: color.withValues(alpha: currentOpacity * 1.6),
            width: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildLink(String text, VoidCallback onTap, Color mainColor) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: mainColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          fontFamily: 'NotoSansSC',
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  void showPrivacyPage() => context.push("/privacy");
  void showProtocolPage() => context.push("/protocol");

  void _onEmailLoginPressed() {
    if (!_approved) {
      ToastUtil.error("请先同意[使用协议]和[隐私政策]");
      return;
    }
    context.push('/email_login', extra: {'approved': _approved});
  }

  void wechatLoginPressed() async {
    if (!_approved) {
      ToastUtil.error("请先同意[使用协议]和[隐私政策]");
      return;
    }
    if (PlatformUtils.isZhuoyiTong) {
      ToastUtil.info("卓易通兼容环境暂不支持微信登录，请使用邮箱登录");
      return;
    }
    setState(() => _isWechatLoading = true);
    try {
      bool handled = false;
      late final FluwxCancelable cancelable;
      Timer? timeoutTimer;
      cancelable = WechatUtil.addSubscriber((response) async {
        if (handled || response is! WeChatAuthResponse) return;
        handled = true;
        timeoutTimer?.cancel();
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
      // 设置超时保护，若微信未响应或被特殊环境拦截，8秒后自动取消并重置状态
      timeoutTimer = Timer(const Duration(seconds: 8), () {
        if (!handled) {
          handled = true;
          cancelable.cancel();
          if (mounted) {
            setState(() => _isWechatLoading = false);
          }
        }
      });
      if (!await WechatUtil.login()) {
        handled = true;
        timeoutTimer.cancel();
        cancelable.cancel();
        setState(() => _isWechatLoading = false);
        return;
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
      List<String> changes = await Util.getAppChanges();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('应用信息'),
          content: SingleChildScrollView(
            child: Column(
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
                if (changes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('版本更新说明:'),
                  const SizedBox(height: 4),
                  ...changes.map(
                    (change) => Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        '• $change',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
