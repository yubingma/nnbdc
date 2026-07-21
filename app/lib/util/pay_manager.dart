import 'dart:io';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/wechat_util.dart';

/// 支付渠道枚举
enum PaymentChannelEnum {
  wechat('WECHAT', '微信支付'),
  alipay('ALIPAY', '支付宝'),
  huaweiIap('HUAWEI_IAP', '华为支付'),
  xiaomiIap('XIAOMI_IAP', '小米支付'),
  appleIap('APPLE_IAP', 'Apple App Store');

  final String code;
  final String label;

  const PaymentChannelEnum(this.code, this.label);
}

/// 统一支付适配器接口
abstract class PayAdapter {
  PaymentChannelEnum get channel;
  Future<bool> isAvailable();
  Future<bool> pay({required String productId, required double amount});
}

/// 微信支付适配器
class WeChatPayAdapter implements PayAdapter {
  @override
  PaymentChannelEnum get channel => PaymentChannelEnum.wechat;

  @override
  Future<bool> isAvailable() async {
    return await WechatUtil.isWechatInstalled();
  }

  @override
  Future<bool> pay({required String productId, required double amount}) async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        ToastUtil.error('请先登录');
        return false;
      }
      final preOrderRes = await Api.client.createPreOrder(
        userId: user.id,
        productId: productId,
        amount: amount,
        channel: channel.code,
      );

      if (preOrderRes.success && preOrderRes.data != null) {
        ToastUtil.info('调起微信支付中...');
        return true;
      } else {
        ToastUtil.error(preOrderRes.msg ?? '预下单失败');
        return false;
      }
    } catch (e) {
      Global.logger.e('微信支付异常', error: e);
      ToastUtil.error('支付拉起失败');
      return false;
    }
  }
}

/// 支付宝支付适配器
class AlipayPayAdapter implements PayAdapter {
  @override
  PaymentChannelEnum get channel => PaymentChannelEnum.alipay;

  @override
  Future<bool> isAvailable() async {
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  Future<bool> pay({required String productId, required double amount}) async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        ToastUtil.error('请先登录');
        return false;
      }
      final preOrderRes = await Api.client.createPreOrder(
        userId: user.id,
        productId: productId,
        amount: amount,
        channel: channel.code,
      );

      if (preOrderRes.success && preOrderRes.data != null) {
        ToastUtil.info('调起支付宝支付中...');
        return true;
      } else {
        ToastUtil.error(preOrderRes.msg ?? '预下单失败');
        return false;
      }
    } catch (e) {
      Global.logger.e('支付宝支付异常', error: e);
      ToastUtil.error('支付拉起失败');
      return false;
    }
  }
}

/// Apple 内购适配器
class ApplePayAdapter implements PayAdapter {
  @override
  PaymentChannelEnum get channel => PaymentChannelEnum.appleIap;

  @override
  Future<bool> isAvailable() async {
    return Platform.isIOS;
  }

  @override
  Future<bool> pay({required String productId, required double amount}) async {
    if (!Platform.isIOS) return false;
    final products = await SubscriptionUtil.getProducts();
    if (products.isEmpty) {
      ToastUtil.error('未找到可用内购商品');
      return false;
    }
    final targetProduct = products.firstWhere(
      (p) => p.id == productId,
      orElse: () => products.first,
    );
    return await SubscriptionUtil.purchase(targetProduct);
  }
}

/// 统一支付管理
class PayManager {
  static final List<PayAdapter> _adapters = [
    WeChatPayAdapter(),
    AlipayPayAdapter(),
    ApplePayAdapter(),
  ];

  /// 获取当前环境可用的支付方式列表
  static Future<List<PaymentChannelEnum>> getAvailableChannels() async {
    final List<PaymentChannelEnum> available = [];
    for (final adapter in _adapters) {
      if (await adapter.isAvailable()) {
        available.add(adapter.channel);
      }
    }
    return available;
  }

  /// 发起支付
  static Future<bool> pay({
    required PaymentChannelEnum channel,
    required String productId,
    required double amount,
  }) async {
    final adapter = _adapters.firstWhere(
      (a) => a.channel == channel,
      orElse: () => throw Exception('未找该支付渠道适配器: $channel'),
    );
    return await adapter.pay(productId: productId, amount: amount);
  }
}
