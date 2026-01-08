import 'dart:async';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:drift/drift.dart' as drift hide Column;
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
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
  final verificationCode = TextEditingController();
  bool _approved = false;
  bool _isLoading = false;
  bool _isSendingCode = false; // 是否正在发送验证码
  int _countdown = 0; // 倒计时秒数
  Timer? _countdownTimer; // 倒计时定时器
  bool? _emailExistsInLocal; // 本地是否存在该邮箱，null表示未检查
  bool _isCheckingLocal = false; // 是否正在检查本地
  List<String> _localEmails = []; // 本地保存的邮箱列表
  
  // 双击检测相关
  DateTime? _lastTapTime;
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);

  @override
  void dispose() {
    _countdownTimer?.cancel();
    email.dispose();
    verificationCode.dispose();
    super.dispose();
  }

  // 从本地数据库读取用户名和邮箱列表
  loadData() async {
    var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
    if (user != null && user.email != null) {
      setState(() {
        email.text = user.email!;
        _approved = true;
      });
    }
    
    // 加载本地所有用户的邮箱
    _loadLocalEmails();
  }

  // 加载本地所有邮箱
  Future<void> _loadLocalEmails() async {
    try {
      final db = MyDatabase.instance;
      final users = await db.usersDao.allUsers;
      final emails = users
          .where((user) => user.email != null && user.email!.isNotEmpty)
          .map((user) => user.email!)
          .toSet() // 去重
          .toList();
      
      setState(() {
        _localEmails = emails;
      });
    } catch (e) {
      // 加载失败，保持空列表
      setState(() {
        _localEmails = [];
      });
    }
  }

  @override
  void initState() {
    super.initState();
    loadData();
    // 监听邮箱输入变化，检查本地是否有该邮箱
    email.addListener(_checkLocalEmail);
  }

  // 显示邮箱选择下拉菜单
  Future<void> _showEmailPicker() async {
    if (_localEmails.isEmpty) {
      ToastUtil.info('本地暂无保存的邮箱');
      return;
    }

    // 使用底部弹出菜单
    final selectedEmail = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '选择邮箱',
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _localEmails.length,
                  itemBuilder: (BuildContext context, int index) {
                    final emailItem = _localEmails[index];
                    return ListTile(
                      leading: const Icon(Icons.email),
                      title: Text(emailItem),
                      onTap: () {
                        Navigator.pop(context, emailItem);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selectedEmail != null) {
      setState(() {
        email.text = selectedEmail;
      });
      // 选择邮箱后触发检查
      _checkLocalEmail();
    }
  }

  // 检查本地是否有该邮箱
  Future<void> _checkLocalEmail() async {
    final trimmedEmail = email.text.trim();
    if (trimmedEmail.isEmpty || !EmailValidator.validate(trimmedEmail)) {
      setState(() {
        _emailExistsInLocal = null;
        verificationCode.clear();
      });
      return;
    }

    // 防抖：延迟500ms后检查
    await Future.delayed(const Duration(milliseconds: 500));
    final trimmedEmailAfterDelay = email.text.trim();
    if (trimmedEmailAfterDelay.isEmpty || !EmailValidator.validate(trimmedEmailAfterDelay)) {
      return;
    }

    setState(() {
      _isCheckingLocal = true;
    });

    try {
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserByEmail(trimmedEmailAfterDelay);
      
      setState(() {
        _emailExistsInLocal = user != null;
        if (user != null) {
          // 如果本地有该邮箱，清空验证码，准备自动登录
          verificationCode.clear();
        }
      });
    } catch (e) {
      // 检查失败，保持当前状态
      setState(() {
        _emailExistsInLocal = null;
      });
    } finally {
      setState(() {
        _isCheckingLocal = false;
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
                minHeight: (_emailExistsInLocal == true)
                    ? (MediaQuery.of(context).size.width > 600 ? 100 : 80)
                    : (MediaQuery.of(context).size.width > 600 ? 200 : 160),
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
                    validator: (value) => EmailValidator.validate(value!.trim()) ? null : "请输入有效的 email",
                    decoration: InputDecoration(
                      labelText: '邮箱',
                      labelStyle: const TextStyle(color: Colors.grey),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email, color: Colors.grey),
                      suffixIcon: _isCheckingLocal 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (_localEmails.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                  onPressed: _showEmailPicker,
                                  tooltip: '选择已保存的邮箱',
                                )
                              : null),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                      ),
                    ),
                  ),
                  // 验证码输入（仅在本地没有该邮箱时显示）
                  if (_emailExistsInLocal != true) ...[
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

            // 作为游客体验
            Container(
              margin: EdgeInsets.only(
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


  // 发送验证码
  Future<void> sendVerificationCode() async {
    final trimmedEmail = email.text.trim();
    if (trimmedEmail.isEmpty) {
      ToastUtil.error('请输入邮箱');
      return;
    }

    if (!EmailValidator.validate(trimmedEmail)) {
      ToastUtil.error('请输入有效的邮箱地址');
      return;
    }

    setState(() {
      _isSendingCode = true;
    });

    try {
      final result = await Api.client.sendEmailCode(trimmedEmail, 'LOGIN');
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
    final trimmedEmail = email.text.trim();
    if (trimmedEmail.isEmpty) {
      ToastUtil.error('请输入邮箱');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 如果本地有该邮箱，直接使用本地用户信息登录
      if (_emailExistsInLocal == true) {
        final db = MyDatabase.instance;
        final user = await db.usersDao.getUserByEmail(trimmedEmail);
        
        if (user != null) {
          // 更新最后登录时间
          final now = AppClock.now();
          await db.usersDao.saveUser(user.copyWith(lastLoginTime: drift.Value(now)), true);
          Global.currentUserId = user.id;
          
          // 从服务器获取最新的用户信息
          final result = await UserBo().getLoggedInUser();
          if (result.success && result.data != null) {
            await Global.setLoggedInUser(result.data!);
            // 登录成功后自动触发静默恢复购买
            SubscriptionUtil.restorePurchases(showToast: false);
            Get.offAllNamed('/index');
          } else {
            // 如果服务器验证失败，可能需要重新验证码登录
            ToastUtil.error('登录验证失败，请使用验证码登录');
            setState(() {
              _emailExistsInLocal = false;
            });
          }
        } else {
          // 本地检查结果可能过期，使用验证码登录
          setState(() {
            _emailExistsInLocal = false;
          });
          if (verificationCode.text.isEmpty) {
            ToastUtil.error('请输入验证码');
            return;
          }
          await _doCodeLogin();
        }
      } else {
        // 本地没有该邮箱，使用验证码登录
        if (verificationCode.text.isEmpty) {
          ToastUtil.error('请输入验证码');
          setState(() {
            _isLoading = false;
          });
          return;
        }
        await _doCodeLogin();
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'doLogin');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 验证码登录
  Future<void> _doCodeLogin() async {
    // 使用验证码登录（会验证验证码，然后进行登录或注册）
    final trimmedEmail = email.text.trim();
    final codeResult = await Api.client.loginByEmailCode(
      trimmedEmail,
      verificationCode.text,
      getClientType().name,
      Global.version,
    );

    if (codeResult.success) {
      // 验证码登录成功（自动注册或登录）
      if (codeResult.data != null) {
        final userVo = UserVo.fromJson(codeResult.data as Map<String, dynamic>);
        userVo.lastLoginTime = AppClock.now();
        
        // 保存到本地数据库（保证第一次验证码登录成功后保存到本地）
        final db = MyDatabase.instance;
        await db.usersDao.saveUser(userVo2User(userVo), false);
        
        // 设置全局用户
        await Global.setLoggedInUser(userVo);
        
        // 更新本地检查状态
        setState(() {
          _emailExistsInLocal = true;
        });
      }
      // 登录成功后自动触发静默恢复购买
      SubscriptionUtil.restorePurchases(showToast: false);
      Get.offAllNamed('/index');
    } else {
      ToastUtil.error(codeResult.msg ?? '登录失败');
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
                Text('Profile: $profile'),
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
