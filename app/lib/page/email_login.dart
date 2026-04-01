import 'dart:async';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:drift/drift.dart' as drift hide Column;
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:get_storage/get_storage.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/analytics_util.dart';
import '../config.dart';
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

  loadData() async {
    var user = await MyDatabase.instance.usersDao.getLastLoggedInUser();
    if (user != null && user.email != null) {
      setState(() {
        email.text = user.email!;
        _approved = true;
      });
    }

    // 检查隐私政策版本
    const int currentPrivacyVersion = 20260310;
    int acceptedVersion = GetStorage().read<int>('accepted_privacy_version') ?? 0;
    if (acceptedVersion >= currentPrivacyVersion) {
      setState(() {
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

    // 尝试从路由参数中获取同意状态
    final args = Get.arguments;
    if (args is Map && args['approved'] == true) {
      _approved = true;
    }

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
    final trimmedEmail = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
    if (trimmedEmail.isEmpty || !EmailValidator.validate(trimmedEmail)) {
      setState(() {
        _emailExistsInLocal = null;
        verificationCode.clear();
      });
      return;
    }

    // 防抖：延迟500ms后检查
    await Future.delayed(const Duration(milliseconds: 500));
    final trimmedEmailAfterDelay = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF8FAFC),
            const Color(0xFFF1F5F9),
            Colors.white,
            const Color(0xFFECFEFF),
          ],
          stops: const [0.0, 0.4, 0.8, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF22D3EE).withValues(alpha: 0.1),
                    const Color(0xFF22D3EE).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF22D3EE).withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.email_rounded,
                        size: 48,
                        color: Color(0xFF0EA5E9),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '邮箱登录',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Align inputLayer() {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.only(bottom: bottomPadding + 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 输入区域容器
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 20), 
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  border: Border.all(color: Colors.black.withValues(alpha: 0.02), width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 邮箱输入
                    TextFormField(
                      key: const Key('email_login_email_field'),
                      controller: email,
                      keyboardType: TextInputType.visiblePassword,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'[\s\u2006\u200B]')),
                      ],
                      style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: '电子邮箱',
                        labelStyle: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20, color: Color(0xFF0EA5E9)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF0EA5E9), width: 1.5),
                        ),
                        suffixIcon: _isCheckingLocal
                            ? const UnconstrainedBox(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF0EA5E9))),
                                ),
                              )
                            : (_localEmails.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.expand_more_rounded, color: Color(0xFF94A3B8)),
                                    onPressed: _showEmailPicker,
                                  )
                                : null),
                      ),
                    ),
                    
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
                              style: const TextStyle(color: Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 8),
                              decoration: InputDecoration(
                                labelText: '验证码',
                                labelStyle: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500, letterSpacing: 0),
                                prefixIcon: const Icon(Icons.verified_user_outlined, size: 20, color: Color(0xFF0EA5E9)),
                                counterText: '',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: (_countdown > 0 || _isSendingCode) ? null : sendVerificationCode,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0EA5E9),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              backgroundColor: const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              _isSendingCode ? '...' : (_countdown > 0 ? '${_countdown}s' : '获取'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                    
                    const SizedBox(height: 32),

                    // 登录按钮
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0EA5E9), Color(0xFF22D3EE)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0EA5E9).withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : loginBtnPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: Text(
                          _isLoading ? '登录中...' : '登录',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2, fontFamily: 'NotoSansSC'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 返回
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('返回其他登录方式'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: 12),

              // 协议
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: GestureDetector(
                  onTap: () => setState(() => _approved = !_approved),
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _approved ? const Color(0xFF0EA5E9) : Colors.transparent,
                            border: Border.all(
                              color: _approved ? const Color(0xFF0EA5E9) : const Color(0xFFCBD5E1),
                              width: 1.5,
                            ),
                          ),
                          child: _approved 
                            ? const Icon(Icons.check, color: Colors.white, size: 11) 
                            : null,
                        ),
                        const SizedBox(width: 8),
                        const Text('同意 ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        _buildLinkText('《用户协议》', showProtocolPage),
                        const Text(' 与 ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        _buildLinkText('《隐私政策》', showPrivacyPage),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkText(String text, VoidCallback onTap) {
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

  void showPrivacyPage() {
    Navigator.pushNamed(context, "/privacy");
  }

  void showProtocolPage() {
    Navigator.pushNamed(context, "/protocol");
  }

  // 发送验证码
  Future<void> sendVerificationCode() async {
    final trimmedEmail = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
    if (trimmedEmail.isEmpty) {
      ToastUtil.error('请输入邮箱');
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(trimmedEmail)) {
      ToastUtil.error('邮箱格式不正确，请检查');
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
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'sendEmailCode', showToast: true);
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
    final trimmedEmail = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
    if (trimmedEmail.isEmpty) {
      ToastUtil.error('请输入邮箱');
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(trimmedEmail)) {
      ToastUtil.error('邮箱格式不正确，请检查');
      return;
    }

    if (!EmailValidator.validate(trimmedEmail)) {
      ToastUtil.error('请输入有效的邮箱地址');
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
            
            // 登录成功后立即触发同步，确保老用户在新设备上的数据（词书、进度）能尽快加载 
            await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
            // 登录成功后更新隐私版本并初始化统计 SDK
            GetStorage().write('accepted_privacy_version', 20260310);
            if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
              try {
                UmengCommonSdk.initCommon(Config.umengAndroidAppKey, Config.umengIosAppKey, Config.umengChannel);
              } catch (e) {
                debugPrint('Umeng init error: $e');
              }
            }

            // 登录成功后自动触发静默恢复购买
            SubscriptionUtil.restorePurchases(showToast: false);
            
            // 漏斗：无痛登入（邮箱登录完成）
            AnalyticsUtil.trackLogin('email', false);
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
    final trimmedEmail = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
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

        // 登录成功后立即触发同步，确保老用户在新设备上的数据（词书、进度）能尽快加载
        await ThrottledDbSyncService().requestSyncAndWait(immediate: true);

        // 更新本地检查状态
        setState(() {
          _emailExistsInLocal = true;
        });
      }
      // 登录成功后更新隐私版本并初始化统计 SDK
      GetStorage().write('accepted_privacy_version', 20260310);
      if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        try {
          UmengCommonSdk.initCommon(Config.umengAndroidAppKey, Config.umengIosAppKey, Config.umengChannel);
        } catch (e) {
          debugPrint('Umeng init error: $e');
        }
      }

      // 登录成功后自动触发静默恢复购买
      SubscriptionUtil.restorePurchases(showToast: false);
      
      // 漏斗：无痛登入（验证码登录完成）
      AnalyticsUtil.trackLogin('email', false);
      Get.offAllNamed('/index');
    } else {
      ToastUtil.error(codeResult.msg ?? '登录失败');
    }
  }
}
