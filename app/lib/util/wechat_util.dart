import 'dart:io';

import 'package:fluwx/fluwx.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';

/// 微信工具类
class WechatUtil {
  static bool _initialized = false;
  static final Fluwx _fluwx = Fluwx();

  /// 微信AppID - 需要在微信开放平台申请
  static const String appId = 'wx42e6014d1927e5f0';

  /// iOS通用链接 - 用于iOS微信登录回调
  static const String universalLink = 'https://back.nnbdc.com/wxlink/';

  /// 初始化微信SDK
  static Future<void> init() async {
    if (_initialized) return;

    try {
      // 检查配置
      if (appId.isEmpty) {
        Global.logger.w('微信AppID未配置，微信登录功能将不可用');
        return;
      }

      // 注册微信SDK
      await _fluwx.registerApi(
        appId: appId,
        doOnAndroid: true,
        doOnIOS: true,
        universalLink: universalLink,
      );

      _initialized = true;
      Global.logger.i('微信SDK初始化成功');
    } catch (e, stackTrace) {
      Global.logger.e('微信SDK初始化失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 检查微信是否已安装
  static Future<bool> isWechatInstalled() async {
    try {
      return await _fluwx.isWeChatInstalled;
    } catch (e) {
      return false;
    }
  }

  /// 发起微信登录
  static Future<bool> login() async {
    try {
      // 检查SDK是否初始化
      if (!_initialized) {
        await init();
        if (!_initialized) {
          ToastUtil.error('微信登录功能未配置');
          return false;
        }
      }

      // 检查微信是否安装
      bool installed = await isWechatInstalled();
      if (!installed) {
        ToastUtil.error('请先安装微信客户端');
        return false;
      }

      // 发起微信授权
      await _fluwx.authBy(
        which: NormalAuth(
          scope: 'snsapi_userinfo',
          state: 'wechat_login',
        ),
      );

      return true;
    } catch (e, stackTrace) {
      Global.logger.e('微信登录失败', error: e, stackTrace: stackTrace);
      ToastUtil.error('微信登录失败，请重试');
      return false;
    }
  }

  /// 分享图片到微信（好友或朋友圈）
  static Future<bool> shareImage({
    required File imageFile,
    required WeChatScene scene,
  }) async {
    try {
      if (!_initialized) {
        await init();
      }

      bool installed = await isWechatInstalled();
      if (!installed) {
        ToastUtil.error('请先安装微信客户端');
        return false;
      }

      final bytes = await imageFile.readAsBytes();
      return await _fluwx.share(
        WeChatShareImageModel(
          WeChatImageToShare(
            uint8List: bytes,
            localImagePath: imageFile.path,
          ),
          scene: scene,
        ),
      );
    } catch (e, stackTrace) {
      Global.logger.e('微信分享失败', error: e, stackTrace: stackTrace);
      ToastUtil.error('微信分享失败，请重试');
      return false;
    }
  }

  /// 订阅微信授权响应
  /// 使用addSubscriber方法添加监听器
  static FluwxCancelable addSubscriber(WeChatResponseSubscriber listener) {
    return _fluwx.addSubscriber(listener);
  }

  /// 移除订阅
  static void removeSubscriber(WeChatResponseSubscriber listener) {
    _fluwx.removeSubscriber(listener);
  }
}
