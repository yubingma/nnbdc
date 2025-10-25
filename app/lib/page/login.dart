import 'package:flutter/material.dart';
import 'package:nnbdc/page/email_login.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/error_handler.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  bool _approved = false;
  bool _isLoading = false;

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
              Image.asset(
                'assets/images/logo.png',
                width: 80,
                height: 80,
                fit: BoxFit.contain,
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
                '听说读写玩，背词不再难',
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
            // 微信登录按钮（主要登录方式）
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 10 : 5,
              ),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : wechatLoginPressed,
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
                  '微信登录',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // 其他登录方式链接
            Container(
              margin: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.width > 600 ? 15 : 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      showEmailLoginPage();
                    },
                    child: Text(
                      "邮箱登录",
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
                    key: const Key('wechat_login_agree_checkbox'),
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

  void showEmailLoginPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const EmailLoginPage(),
      ),
    );
  }

  // 微信登录
  void wechatLoginPressed() async {
    if (!_approved) {
      ToastUtil.error("请先同意[使用协议]和[隐私政策]");
      return;
    }

    // 注意：微信登录需要先配置微信开放平台
    // 详见项目根目录的 WECHAT_LOGIN_SETUP.md 文档
    
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 发起微信授权（需要先配置WechatUtil中的AppID）
      // bool success = await WechatUtil.login();
      // 
      // if (!success) {
      //   setState(() {
      //     _isLoading = false;
      //   });
      //   return;
      // }
      //
      // // 2. 监听微信授权结果
      // WechatUtil.responseStream.listen((response) async {
      //   if (response is WeChatAuthResponse) {
      //     if (response.code != null) {
      //       // 3. 使用code调用后端API登录
      //       Result result = await Api.client.loginByWechat(
      //         response.code!,
      //         getClientType().json,
      //         Global.version,
      //       );
      //
      //       if (result.success) {
      //         // 4. 登录成功，保存用户信息
      //         final userResult = await UserBo().getLoggedInUser();
      //         if (userResult.success && userResult.data != null) {
      //           await Global.setLoggedInUser(userResult.data!);
      //         }
      //         Get.offAllNamed('/index');
      //       } else {
      //         ToastUtil.error(result.msg ?? '微信登录失败');
      //       }
      //     } else {
      //       ToastUtil.error('微信授权失败');
      //     }
      //   }
      //   
      //   setState(() {
      //     _isLoading = false;
      //   });
      // });

      // 临时提示：微信登录功能需要先配置
      ToastUtil.error('微信登录功能需要先配置，详见 WECHAT_LOGIN_SETUP.md');
      setState(() {
        _isLoading = false;
      });

    } catch (e, stackTrace) {
      ErrorHandler.handleNetworkError(e, stackTrace, api: 'loginByWechat');
      setState(() {
        _isLoading = false;
      });
    }
  }
}
