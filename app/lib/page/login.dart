import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/theme/app_theme.dart';
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
  // 双击检测相关
  DateTime? _lastTapTime;
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 从本地数据库读取用户名和邮箱列表
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
      // 这里的逻辑是：如果用户从微信授权页切换回 APP，但没有触发回调（比如手动切回），
      // 我们需要重置加载状态。为了不干扰正常的回调处理，稍作延迟再重置。
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
      resizeToAvoidBottomInset: true, // 输入法从底部弹出时，重新调整屏幕大小
      body: SizedBox(
        height: double.infinity,
        child: Stack(
          children: [
            // 背景层
            backgroundLayer(),

            //输入层
            inputLayer(),
          ],
        ),
      ),
    );
  }

  Widget backgroundLayer() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.gradientStartColor,
            AppTheme.gradientEndColor,
          ],
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
          Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Global.logger.d('Logo area tapped');
                  final now = DateTime.now();
                  if (_lastTapTime != null && now.difference(_lastTapTime!) < _doubleTapTimeout) {
                    // 检测到双击
                    Global.logger.d('Logo double tapped detected!');
                    _lastTapTime = null;
                    _showVersionAndProfileDialog();
                  } else {
                    _lastTapTime = now;
                  }
                },
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '泡泡单词',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MediaQuery.of(context).size.width > 600 ? 24 : 18,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Align inputLayer() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        color: Colors.transparent,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.width > 600 ? 10 : 5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 占据一点空间
            SizedBox(height: MediaQuery.of(context).size.height * 0.05),

            // 微信登录按钮 (仅手机端插件支持)
            if (PlatformUtils.isIOS || PlatformUtils.isAndroid)
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              child: ElevatedButton.icon(
                onPressed: _isWechatLoading ? null : wechatLoginPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09BB07), // 微信绿色
                  padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.of(context).size.width > 600 ? 15 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.wechat, color: Colors.white, size: 24),
                label: Text(
                  _isWechatLoading ? '登录中…' : '微信登录',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // 作为游客体验
            Container(
              margin: EdgeInsets.only(
                top: MediaQuery.of(context).size.width > 600 ? 10 : 5,
                bottom: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              child: ElevatedButton(
                onPressed: () async {
                  await Global.loginAsGuest();
                  // 游客身份进入时也尝试恢复之前的购买状态
                  await SubscriptionUtil.restorePurchases(showToast: false);
                  Get.offAllNamed('/index');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDarkColor,
                  padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.of(context).size.width > 600 ? 8 : 6,
                    horizontal: MediaQuery.of(context).size.width > 600 ? 32 : 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  '我是游客',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: MediaQuery.of(context).size.width > 600 ? 14 : 12,
                  ),
                ),
              ),
            ),
            // 其他登录方式：邮箱登录
            TextButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/email_login');
              },
              child: Text(
                '使用邮箱登录',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: MediaQuery.of(context).size.width > 600 ? 14 : 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.width > 600 ? 10 : 5),
            // 隐私政策
            Container(
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              child: Row(
                children: [
                  Checkbox(
                    key: const Key('login_agree_checkbox'),
                    value: _approved,
                    onChanged: (value) {
                      setState(() {
                        _approved = value ?? false;
                      });
                    },
                    activeColor: Colors.white,
                    checkColor: AppTheme.primaryColor,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                  ),
                  Text(
                    '我已阅读并同意',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: MediaQuery.of(context).size.width > 600 ? 12 : 10,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      showProtocolPage();
                    },
                    child: Text(
                      ' 用户协议',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width > 600 ? 12 : 10,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    ' 和 ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: MediaQuery.of(context).size.width > 600 ? 12 : 10,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      showPrivacyPage();
                    },
                    child: Text(
                      '隐私政策',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width > 600 ? 12 : 10,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.width > 600 ? 10 : 5),
          ],
        ),
      ),
    );
  }

  void showPrivacyPage() {
    Navigator.pushNamed(context, "/privacy");
  }

  void showProtocolPage() {
    Navigator.pushNamed(context, "/protocol");
  }


  // 微信登录
  void wechatLoginPressed() async {
    if (!_approved) {
      ToastUtil.error("请先同意[使用协议]和[隐私政策]");
      return;
    }

    setState(() {
      _isWechatLoading = true;
    });

    try {
      // 1. 先注册一次性监听器，再发起授权（避免回调丢失）
      bool handled = false;
      late final FluwxCancelable cancelable;

      cancelable = WechatUtil.addSubscriber((response) async {
        // 防止重复处理
        if (handled) return;
        if (response is! WeChatAuthResponse) return;
        handled = true;
        cancelable.cancel(); // 移除此监听器

        if (response.code != null) {
          try {
            // 2. 使用code调用后端API登录
            final result = await Api.client.loginByWechat(
              response.code!,
              getClientType().name,
              Global.version,
            );

            if (result.success) {
              // 3. 登录成功，保存用户信息到本地数据库
              if (result.data != null) {
                final userVo = UserVo.fromJson(result.data as Map<String, dynamic>);
                userVo.lastLoginTime = AppClock.now();

                // 保存到本地数据库
                final db = MyDatabase.instance;
                await db.usersDao.saveUser(userVo2User(userVo), false);

                // 设置全局用户
                await Global.setLoggedInUser(userVo);
              }
              // 登录成功后自动触发静默恢复购买
              SubscriptionUtil.restorePurchases(showToast: false);
              Get.offAllNamed('/index');
              return;
            } else {
              ToastUtil.error(result.msg ?? '微信登录失败');
            }
          } catch (e, stackTrace) {
            ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByWechat');
          }
        } else {
          Global.logger.e('微信授权失败，errCode: ${response.errCode}, errStr: ${response.errStr}');
          ToastUtil.error('微信授权失败: ${response.errCode} - ${response.errStr ?? "未知错误"}');
        }

        if (mounted) {
          setState(() {
            _isWechatLoading = false;
          });
        }
      });

      // 4. 发起微信授权
      bool success = await WechatUtil.login();
      if (!success) {
        handled = true;
        cancelable.cancel();
        setState(() {
          _isWechatLoading = false;
        });
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByWechat');
      setState(() {
        _isWechatLoading = false;
      });
    }
  }

  /// 显示版本号和Profile信息的对话框
  Future<void> _showVersionAndProfileDialog() async {
    try {
      // 获取版本信息
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String version = packageInfo.version;
      String buildNumber = packageInfo.buildNumber;

      // 获取数据库版本号
      int dbVersion = MyDatabase.instance.schemaVersion;

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('应用信息'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('版本号: $version'),
                const SizedBox(height: 8),
                Text('构建号: $buildNumber'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Profile: ${Config.profileName}'),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (Config.profileName == 'dev') {
                            Config.profileName = 'prod';
                            Api.useProdUrl = true;
                          } else {
                            Config.profileName = 'dev';
                            Api.useProdUrl = false;
                          }
                        });
                        Api.resetClient();
                        SocketIoClient.instance.reset();
                        Navigator.of(context).pop();
                        ToastUtil.success('已切换到 ${Config.profileName} 环境');
                      },
                      child: const Text('切换'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('数据库版本: $dbVersion'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      Global.logger.e('获取版本信息失败: $e');
      if (mounted) {
        ToastUtil.error('获取版本信息失败');
      }
    }
  }
}
