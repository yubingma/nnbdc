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
import '../global.dart';
import '../util/client_type.dart';

class EmailLoginPage extends StatefulWidget {
  const EmailLoginPage({super.key});

  @override
  EmailLoginPageState createState() => EmailLoginPageState();
}

class EmailLoginPageState extends State<EmailLoginPage> {
  final email = TextEditingController();
  final verificationCode = TextEditingController();
  final FocusNode _verificationCodeFocusNode = FocusNode();
  bool _approved = false;
  bool _isLoading = false;
  bool _isSendingCode = false; // 是否正在发送验证码
  int _countdown = 0; // 倒计时秒数
  Timer? _countdownTimer; // 倒计时定时器
  bool? _emailExistsInLocal; // 本地是否存在该邮箱，null表示未检查
  bool _isCheckingLocal = false; // 是否正在检查本地
  List<String> _localEmails = []; // 本地保存的邮箱列表

  @override
  void dispose() {
    _countdownTimer?.cancel();
    email.dispose();
    verificationCode.dispose();
    _verificationCodeFocusNode.dispose();
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
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
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
                child: const Icon(
                  Icons.email_outlined,
                  size: 56,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '邮箱登录',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
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
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        color: Colors.transparent,
        padding: EdgeInsets.only(bottom: bottomPadding + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 返回按钮 (左上角浮动感)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2D2D2D), size: 20),
                  ),
                ],
              ),
            ),
            
            // 输入区域容器
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 邮箱输入
                  TextFormField(
                    key: const Key('email_login_email_field'),
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 16),
                    decoration: InputDecoration(
                      labelText: '电子邮箱',
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                      suffixIcon: _isCheckingLocal
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(14.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (_localEmails.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.unfold_more_rounded, color: Colors.grey),
                                  onPressed: _showEmailPicker,
                                )
                              : null),
                    ),
                  ),
                  
                  // 验证码输入（分行或保持现状，但优化样式）
                  if (_emailExistsInLocal != true) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('email_login_verification_code_field'),
                            controller: verificationCode,
                            focusNode: _verificationCodeFocusNode,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 16, letterSpacing: 4),
                            decoration: const InputDecoration(
                              labelText: '验证码',
                              prefixIcon: Icon(Icons.shield_outlined, size: 20),
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: (_countdown > 0 || _isSendingCode) ? null : sendVerificationCode,
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            _isSendingCode ? '发送中...' : (_countdown > 0 ? '$_countdown s' : '获取验证码'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  const SizedBox(height: 24),

                  // 登录按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : loginBtnPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _isLoading ? '登录中…' : '登录',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 游客按钮 (轻量级)
            TextButton(
              onPressed: () async {
                await Global.loginAsGuest();
                await SubscriptionUtil.restorePurchases(showToast: false);
                Get.offAllNamed('/index');
              },
              child: Text(
                '暂不登录，先去逛逛',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ),

            const SizedBox(height: 16),

            // 隐私政策
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      key: const Key('email_login_agree_checkbox'),
                      value: _approved,
                      onChanged: (value) => setState(() => _approved = value ?? false),
                      activeColor: const Color(0xFF1A1A1A),
                      shape: const CircleBorder(),
                      side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('同意 ', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11)),
                  GestureDetector(
                    onTap: showProtocolPage,
                    child: const Text('《用户协议》', style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w500)),
                  ),
                  const Text(' 与 ', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11)),
                  GestureDetector(
                    onTap: showPrivacyPage,
                    child: const Text('《隐私政策》', style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w500)),
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
        // 自动聚焦到验证码输入框
        _verificationCodeFocusNode.requestFocus();
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
}
