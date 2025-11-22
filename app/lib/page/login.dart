import 'dart:async';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/page/get_pwd.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config.dart';
import '../global.dart';
import '../util/client_type.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final verificationCode = TextEditingController();
  bool _approved = false;
  bool _isLoading = false;
  bool _obscure = true;
  bool _isSendingCode = false; // 是否正在发送验证码
  int _countdown = 0; // 倒计时秒数
  Timer? _countdownTimer; // 倒计时定时器
  bool? _emailExists; // 邮箱是否存在，null表示未检查
  bool _isCheckingEmail = false; // 是否正在检查邮箱
  
  // 双击检测相关
  DateTime? _lastTapTime;
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);

  @override
  void dispose() {
    _countdownTimer?.cancel();
    email.dispose();
    password.dispose();
    verificationCode.dispose();
    super.dispose();
  }

  // 从本地数据库读取用户名、密码
  loadData() async {
    var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
    if (user != null && user.email != null) {
      setState(() {
        email.text = user.email!;
        password.text = user.password!;
        _approved = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    loadData();
    // 监听邮箱输入变化，检查邮箱是否存在
    email.addListener(_checkEmailExists);
  }

  // 检查邮箱是否存在
  Future<void> _checkEmailExists() async {
    if (email.text.isEmpty || !EmailValidator.validate(email.text)) {
      setState(() {
        _emailExists = null;
        verificationCode.clear();
      });
      return;
    }

    // 防抖：延迟500ms后检查
    await Future.delayed(const Duration(milliseconds: 500));
    if (email.text.isEmpty || !EmailValidator.validate(email.text)) {
      return;
    }

    setState(() {
      _isCheckingEmail = true;
    });

    try {
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserByEmail(email.text);
      
      setState(() {
        _emailExists = user != null;
        if (user != null) {
          // 如果邮箱存在，清空验证码
          verificationCode.clear();
        }
      });
    } catch (e) {
      // 检查失败，保持当前状态
    } finally {
      setState(() {
        _isCheckingEmail = false;
      });
    }
  }

  // 开始倒计时
  void _startCountdown() {
    _countdown = 60;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
      }
    });
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
                  if (_lastTapTime != null && 
                      now.difference(_lastTapTime!) < _doubleTapTimeout) {
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
              const SizedBox(height: 10),
              Text(
                _emailExists == false 
                    ? '请输入验证码登录'
                    : '使用邮箱和密码登录',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 12,
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
            // 邮箱登录表单
            Container(
              width: double.infinity,
              constraints: BoxConstraints(
                minHeight: (_emailExists == false) 
                    ? (MediaQuery.of(context).size.width > 600 ? 280 : 200)
                    : (MediaQuery.of(context).size.width > 600 ? 200 : 140),
              ),
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 20 : 10,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 邮箱输入
                  TextFormField(
                    key: const Key('email_login_email_field'),
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 14,
                    ),
                    validator: (value) => EmailValidator.validate(value!) ? null : "请输入有效的 email",
                    decoration: InputDecoration(
                      labelText: '邮箱',
                      labelStyle: const TextStyle(color: Colors.grey),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email, color: Colors.grey),
                      suffixIcon: _isCheckingEmail 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.width > 600 ? 15 : 10),
                  // 密码输入
                  TextFormField(
                    key: const Key('email_login_password_field'),
                    controller: password,
                    obscureText: _obscure,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 14,
                    ),
                    decoration: InputDecoration(
                      labelText: '密码',
                      labelStyle: const TextStyle(color: Colors.grey),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                      ),
                    ),
                  ),
                  // 验证码输入（仅在邮箱不存在时显示）
                  if (_emailExists == false) ...[
                    SizedBox(height: MediaQuery.of(context).size.width > 600 ? 15 : 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('email_login_verification_code_field'),
                            controller: verificationCode,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 14,
                            ),
                            decoration: InputDecoration(
                              labelText: '验证码',
                              labelStyle: const TextStyle(color: Colors.grey),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.verified_user, color: Colors.grey),
                              counterText: '',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 100,
                          child: ElevatedButton(
                            onPressed: (_countdown > 0 || _isSendingCode) ? null : sendVerificationCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryDarkColor,
                              padding: EdgeInsets.symmetric(
                                vertical: MediaQuery.of(context).size.width > 600 ? 12 : 8,
                              ),
                            ),
                            child: Text(
                              _isSendingCode 
                                  ? '发送中...'
                                  : (_countdown > 0 ? '$_countdown秒' : '发送验证码'),
                              style: TextStyle(
                                fontSize: MediaQuery.of(context).size.width > 600 ? 12 : 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // 登录按钮
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : loginBtnPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDarkColor,
                  padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.of(context).size.width > 600 ? 15 : 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  _isLoading 
                      ? '登录中…' 
                      : '登录',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // 找回密码
            Container(
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 5 : 3,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      showGetPasswordPage();
                    },
                    child: Text(
                      "找回密码",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width > 600 ? 14 : 12,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 微信登录按钮（暂时隐藏）
            // Container(
            //   width: double.infinity,
            //   margin: EdgeInsets.symmetric(
            //     horizontal: 20,
            //     vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
            //   ),
            //   child: ElevatedButton.icon(
            //     onPressed: _isLoading ? null : wechatLoginPressed,
            //     style: ElevatedButton.styleFrom(
            //       backgroundColor: const Color(0xFF09BB07), // 微信绿色
            //       padding: EdgeInsets.symmetric(
            //         vertical: MediaQuery.of(context).size.width > 600 ? 15 : 12,
            //       ),
            //       shape: RoundedRectangleBorder(
            //         borderRadius: BorderRadius.circular(20),
            //       ),
            //     ),
            //     icon: const Icon(Icons.wechat, color: Colors.white, size: 24),
            //     label: Text(
            //       '微信登录',
            //       style: TextStyle(
            //         fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 14,
            //         color: Colors.white,
            //       ),
            //     ),
            //   ),
            // ),
            // 隐私政策
            Container(
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              child: Row(
                children: [
                  Checkbox(
                    key: const Key('email_login_agree_checkbox'),
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

  void showGetPasswordPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GetPwdPage(defaultEmail: email.text),
      ),
    );
  }

  // 发送验证码
  Future<void> sendVerificationCode() async {
    if (email.text.isEmpty) {
      ToastUtil.error('请输入邮箱');
      return;
    }

    if (!EmailValidator.validate(email.text)) {
      ToastUtil.error('请输入有效的邮箱地址');
      return;
    }

    setState(() {
      _isSendingCode = true;
    });

    try {
      final result = await Api.client.sendEmailCode(email.text, 'LOGIN');
      if (result.success) {
        ToastUtil.success('验证码已发送到您的邮箱');
        _startCountdown();
      } else {
        ToastUtil.error(result.msg ?? '发送验证码失败');
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'sendEmailCode');
    } finally {
      setState(() {
        _isSendingCode = false;
      });
    }
  }

  void loginBtnPressed() async {
    // 隐藏软键盘
    FocusScope.of(context).requestFocus(FocusNode());

    if (!_approved) {
      ToastUtil.error("请先同意[使用协议]和[隐私政策]");
      return;
    }

    // 统一使用验证码登录流程
    await doLogin();
  }

  // 登录
  Future<void> doLogin() async {
    if (email.text.isEmpty) {
      ToastUtil.error('请输入邮箱');
      return;
    }
    if (password.text.isEmpty) {
      ToastUtil.error('请输入密码');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 如果显示了验证码输入框（本地检查显示邮箱不存在）且用户输入了验证码，必须使用验证码登录流程
      if (_emailExists == false && verificationCode.text.isNotEmpty) {
        // 使用验证码登录（会验证验证码，然后进行登录或注册）
        final codeResult = await Api.client.loginByEmailCode(
          email.text,
          password.text,
          verificationCode.text,
          getClientType().name,
          Global.version,
        );

        if (codeResult.success) {
          // 验证码登录成功（自动注册或登录）
          if (codeResult.data != null) {
            final userVo = UserVo.fromJson(codeResult.data as Map<String, dynamic>);
            userVo.lastLoginTime = AppClock.now();
            userVo.password = password.text;
            
            // 保存到本地数据库
            final db = MyDatabase.instance;
            await db.usersDao.saveUser(userVo2User(userVo), false);
            
            // 设置全局用户
            await Global.setLoggedInUser(userVo);
          }
          Get.offAllNamed('/index');
        } else {
          ToastUtil.error(codeResult.msg ?? '登录失败');
        }
      } else if (_emailExists == false && verificationCode.text.isEmpty) {
        // 本地检查显示邮箱不存在，但没有输入验证码
        ToastUtil.error('请输入验证码');
      } else {
        // 本地检查显示邮箱存在，使用密码登录
        var result = await UserBo().checkUser(
          CheckBy.email,
          email.text,
          null,
          password.text,
          getClientType().name,
          Global.version,
        );

        if (result.success) {
          // 密码登录成功
          if (result.data != null) {
            await Global.setLoggedInUser(result.data!);
          }
          Get.offAllNamed('/index');
        } else {
          ToastUtil.error(result.msg ?? '登录失败');
        }
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'doLogin');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 微信登录（暂时隐藏，保留代码以便将来恢复）
  // void wechatLoginPressed() async {
  //   if (!_approved) {
  //     ToastUtil.error("请先同意[使用协议]和[隐私政策]");
  //     return;
  //   }
  //
  //   // 注意：微信登录需要先配置微信开放平台
  //   // 详见项目根目录的 WECHAT_LOGIN_SETUP.md 文档
  //   
  //   setState(() {
  //     _isLoading = true;
  //   });
  //
  //   try {
  //     // 1. 发起微信授权（需要先配置WechatUtil中的AppID）
  //     // bool success = await WechatUtil.login();
  //     // 
  //     // if (!success) {
  //     //   setState(() {
  //     //     _isLoading = false;
  //     //   });
  //     //   return;
  //     // }
  //     //
  //     // // 2. 监听微信授权结果
  //     // WechatUtil.responseStream.listen((response) async {
  //     //   if (response is WeChatAuthResponse) {
  //     //     if (response.code != null) {
  //     //       // 3. 使用code调用后端API登录
  //     //       Result result = await Api.client.loginByWechat(
  //     //         response.code!,
  //     //         getClientType().json,
  //     //         Global.version,
  //     //       );
  //     //
  //     //       if (result.success) {
  //     //         // 4. 登录成功，保存用户信息
  //     //         final userResult = await UserBo().getLoggedInUser();
  //     //         if (userResult.success && userResult.data != null) {
  //     //           await Global.setLoggedInUser(userResult.data!);
  //     //         }
  //     //         Get.offAllNamed('/index');
  //     //       } else {
  //     //         ToastUtil.error(result.msg ?? '微信登录失败');
  //     //       }
  //     //     } else {
  //     //       ToastUtil.error('微信授权失败');
  //     //     }
  //     //   }
  //     //   
  //     //   setState(() {
  //     //     _isLoading = false;
  //     //   });
  //     // });
  //
  //     // 临时提示：微信登录功能需要先配置
  //     ToastUtil.error('微信登录功能需要先配置，详见 WECHAT_LOGIN_SETUP.md');
  //     setState(() {
  //       _isLoading = false;
  //     });
  //
  //   } catch (e, stackTrace) {
  //     ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByWechat');
  //     setState(() {
  //       _isLoading = false;
  //     });
  //   }
  // }

  /// 显示版本号和Profile信息的对话框
  Future<void> _showVersionAndProfileDialog() async {
    try {
      // 获取版本信息
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String version = packageInfo.version;
      String buildNumber = packageInfo.buildNumber;
      String profile = Config.profileName;

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
                Text('Profile: $profile'),
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
