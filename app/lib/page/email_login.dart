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
import '../global.dart';
import '../util/client_type.dart';

class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key});

  @override
  EmailLoginPageState createState() => EmailLoginPageState();
}

class EmailLoginPageState extends State<EmailLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final verificationCode = TextEditingController();
  bool _approved = false;
  bool _isLoading = false;
  bool _obscure = true;
  bool _showVerificationCode = false; // 是否显示验证码输入框
  bool _isSendingCode = false; // 是否正在发送验证码
  int _countdown = 0; // 倒计时秒数
  Timer? _countdownTimer; // 倒计时定时器

  @override
  void dispose() {
    _countdownTimer?.cancel();
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
      resizeToAvoidBottomInset: true,
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
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Column(
            children: [
              const Icon(
                Icons.email,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 20),
              Text(
                '邮箱登录',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MediaQuery.of(context).size.width > 600 ? 24 : 18,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _showVerificationCode ? '请输入验证码完成注册' : '使用邮箱和密码登录',
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
            // 返回按钮
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (_showVerificationCode) {
                        // 如果正在验证码流程，返回密码登录
                        setState(() {
                          _showVerificationCode = false;
                          verificationCode.clear();
                        });
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ],
              ),
            ),
            // 输入框
            Container(
              width: double.infinity,
              height: _showVerificationCode 
                  ? (MediaQuery.of(context).size.width > 600 ? 180 : 120)
                  : (MediaQuery.of(context).size.width > 600 ? 200 : 140),
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
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 邮箱输入
                  TextFormField(
                    key: const Key('email_login_email_field'),
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_showVerificationCode, // 验证码流程中禁用邮箱输入
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).size.width > 600 ? 15 : 10),
                  // 密码输入或验证码输入
                  if (!_showVerificationCode)
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
                    )
                  else
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
                      : (_showVerificationCode ? '完成注册' : '登录'),
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // 找回密码（仅在密码登录时显示）
            if (!_showVerificationCode)
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

    if (_showVerificationCode) {
      // 验证码登录流程
      await doLoginByCode();
    } else {
      // 密码登录流程
      await doLogin();
    }
  }

  // 密码登录
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
      // 先检查邮箱是否存在
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserByEmail(email.text);
      
      if (user != null) {
        // 邮箱存在，验证密码
        if (user.password != password.text) {
          ToastUtil.error('密码错误');
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // 密码正确，登录成功
        var result = await UserBo().checkUser(
          CheckBy.email,
          email.text,
          null,
          password.text,
          getClientType().name,
          Global.version,
        );

        if (result.success) {
          if (result.data != null) {
            await Global.setLoggedInUser(result.data!);
          }
          Get.offAllNamed('/index');
        } else {
          ToastUtil.error(result.msg ?? '登录失败');
        }
      } else {
        // 邮箱不存在，发送验证码
        await sendVerificationCode();
        setState(() {
          _showVerificationCode = true;
        });
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'checkUser');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 验证码登录
  Future<void> doLoginByCode() async {
    if (email.text.isEmpty) {
      ToastUtil.error('请输入邮箱');
      return;
    }
    if (verificationCode.text.isEmpty) {
      ToastUtil.error('请输入验证码');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await Api.client.loginByEmailCode(
        email.text,
        verificationCode.text,
        getClientType().name,
        Global.version,
      );

      if (result.success) {
        // 登录成功，保存用户信息
        if (result.data != null) {
          final userVo = UserVo.fromJson(result.data as Map<String, dynamic>);
          userVo.lastLoginTime = AppClock.now();
          
          // 保存到本地数据库
          final db = MyDatabase.instance;
          await db.usersDao.saveUser(userVo2User(userVo), false);
          
          // 设置全局用户
          await Global.setLoggedInUser(userVo);
        }
        Get.offAllNamed('/index');
      } else {
        ToastUtil.error(result.msg ?? '登录失败');
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByEmailCode');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
