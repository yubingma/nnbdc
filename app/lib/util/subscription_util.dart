import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:flutter/foundation.dart';

/// 订阅工具类
/// 用于处理iOS应用内购买订阅功能（仅支持iOS平台）
class SubscriptionUtil {
  static final InAppPurchase _iap = InAppPurchase.instance;
  static final StreamController<List<PurchaseDetails>> _purchaseUpdatedController =
      StreamController<List<PurchaseDetails>>.broadcast();
  
  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  static bool _isAvailable = false;
  static bool _initialized = false;
  
  /// 订阅产品ID列表
  static const Set<String> _productIds = {
    'ppdc.monthly',  // 月度订阅产品ID
    'ppdc.yearly',   // 年度订阅产品ID
  };

  /// 初始化订阅服务
  static Future<bool> init() async {
    if (_initialized) {
      return _isAvailable;
    }

    try {
      // 检查是否支持应用内购买（iOS/Android）
      _isAvailable = await _iap.isAvailable();
      
      if (!_isAvailable) {
        Global.logger.w('应用内购买不可用');
        _initialized = true;
        return false;
      }

      // 监听购买更新
      _purchaseSubscription = _iap.purchaseStream.listen(
        _onPurchaseUpdated,
        onDone: () => _purchaseSubscription?.cancel(),
        onError: (error) {
          Global.logger.e('购买流错误', error: error);
          ToastUtil.error('购买处理出错，请重试');
        },
      );

      _initialized = true;
      Global.logger.i('订阅服务初始化成功');
      return true;
    } catch (e, stackTrace) {
      Global.logger.e('订阅服务初始化失败', error: e, stackTrace: stackTrace);
      _initialized = true;
      return false;
    }
  }

  /// 获取可用的订阅产品
  static Future<List<ProductDetails>> getProducts() async {
    if (!_isAvailable) {
      await init();
      if (!_isAvailable) {
        return [];
      }
    }

    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(_productIds);
      
      // 记录查询结果详情
      Global.logger.i('产品查询结果: 找到 ${response.productDetails.length} 个产品, '
          '未找到 ${response.notFoundIDs.length} 个产品, '
          '错误: ${response.error?.code ?? "无"}');
      
      // 检查是否有未找到的产品
      if (response.notFoundIDs.isNotEmpty) {
        Global.logger.w('未找到产品: ${response.notFoundIDs}');
        
        // 如果所有产品都未找到，提供详细提示
        if (response.notFoundIDs.length == _productIds.length && response.productDetails.isEmpty) {
          String missingProducts = response.notFoundIDs.join(', ');
          ToastUtil.error(
            '订阅产品未找到：$missingProducts\n\n'
            '可能原因：\n'
            '1. App Store Connect 中产品状态为"元数据丢失"\n'
            '2. 产品未关联到 App 版本并提交审核\n'
            '3. 需要在真实设备上测试（模拟器不支持）\n\n'
            '请检查 App Store Connect 中的产品配置'
          );
        } else if (response.productDetails.isNotEmpty) {
          // 部分产品未找到，但已找到部分产品，只记录警告不弹窗
          String missingProducts = response.notFoundIDs.join(', ');
          Global.logger.w('部分产品未找到（已找到 ${response.productDetails.length} 个）: $missingProducts');
        } else {
          // 部分产品未找到，但没有找到任何产品
          String missingProducts = response.notFoundIDs.join(', ');
          ToastUtil.info('部分产品未找到：$missingProducts');
        }
      }
      
      // 检查是否有错误
      if (response.error != null) {
        final error = response.error!;
        Global.logger.e('查询产品失败', error: error);
        
        // 即使有错误，如果找到了部分产品，也返回找到的产品
        if (response.productDetails.isNotEmpty) {
          Global.logger.w('虽然有错误，但已找到 ${response.productDetails.length} 个产品，将返回这些产品');
          // 针对常见错误提供提示，但不阻止返回已找到的产品
          if (error.code == 'storekit_no_response') {
            ToastUtil.info('部分产品加载失败，请检查网络连接和 App Store Connect 配置');
          }
          return response.productDetails;
        }
        
        // 如果没有找到任何产品，才显示错误提示
        String errorMessage = '获取订阅信息失败';
        if (error.code == 'storekit_no_response') {
          // storekit_no_response 错误在开发测试阶段很常见，特别是当产品未在 App Store Connect 中配置时
          // 提供更详细的说明，包括开发和生产环境的区别
          errorMessage = '无法连接到 App Store\n\n'
              '开发测试说明：\n'
              '1. 此错误在开发测试阶段很常见\n'
              '2. 真机测试需要使用 TestFlight 或发布版本\n'
              '3. 模拟器无法使用应用内购买功能\n'
              '4. 首次发布前产品在 App Store Connect 中不可用\n\n'
              '请检查：\n'
              '• 使用真实设备测试（模拟器不支持）\n'
              '• 设备已登录有效的 Apple ID\n'
              '• 网络连接正常\n'
              '• 产品ID已在 App Store Connect 中创建';
        } else if (error.code == 'storekit_product_not_available') {
          errorMessage = '订阅产品暂不可用\n\n'
              '请检查 App Store Connect：\n'
              '1. 产品状态是否为"准备提交"或"已批准"\n'
              '2. 产品元数据是否完整\n'
              '3. 产品是否已关联到 App 版本';
        } else {
          final message = error.message.isNotEmpty ? error.message : error.code;
          errorMessage = '获取订阅信息失败：$message';
        }
        
        ToastUtil.error(errorMessage);
        return [];
      }

      // 返回找到的产品（可能为空，也可能部分找到）
      return response.productDetails;
    } catch (e, stackTrace) {
      Global.logger.e('查询产品异常', error: e, stackTrace: stackTrace);
      ToastUtil.error('获取订阅信息失败，请重试');
      return [];
    }
  }

  /// 购买订阅
  static Future<bool> purchase(ProductDetails productDetails) async {
    if (!_isAvailable) {
      await init();
      if (!_isAvailable) {
        ToastUtil.error('应用内购买不可用');
        return false;
      }
    }

    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      final bool success = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      
      if (!success) {
        ToastUtil.error('购买失败，请重试');
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      Global.logger.e('购买异常', error: e, stackTrace: stackTrace);
      ToastUtil.error('购买失败，请重试');
      return false;
    }
  }

  /// 恢复购买
  static Future<bool> restorePurchases() async {
    if (!_isAvailable) {
      await init();
      if (!_isAvailable) {
        ToastUtil.error('应用内购买不可用');
        return false;
      }
    }

    try {
      await _iap.restorePurchases();
      ToastUtil.info('正在恢复购买...');
      return true;
    } catch (e, stackTrace) {
      Global.logger.e('恢复购买异常', error: e, stackTrace: stackTrace);
      ToastUtil.error('恢复购买失败，请重试');
      return false;
    }
  }

  /// 处理购买更新
  static void _onPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      _handlePurchase(purchaseDetails);
    }
  }

  /// 处理单个购买
  static Future<void> _handlePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.status == PurchaseStatus.pending) {
      Global.logger.i('购买待处理: ${purchaseDetails.productID}');
      ToastUtil.info('购买处理中...');
      return;
    }

    if (purchaseDetails.status == PurchaseStatus.error) {
      Global.logger.e('购买失败: ${purchaseDetails.error}');
      ToastUtil.error('购买失败: ${purchaseDetails.error?.message ?? "未知错误"}');
      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
      return;
    }

    if (purchaseDetails.status == PurchaseStatus.purchased ||
        purchaseDetails.status == PurchaseStatus.restored) {
      Global.logger.i('购买成功: ${purchaseDetails.productID}');
      
      // 验证收据
      final bool verified = await _verifyReceipt(purchaseDetails);
      
      if (verified) {
        ToastUtil.success('订阅成功！');
        // 刷新用户信息
        await _refreshUserInfo();
      } else {
        ToastUtil.error('订阅验证失败，请联系客服');
      }

      // 完成购买
      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
    }

    if (purchaseDetails.status == PurchaseStatus.canceled) {
      Global.logger.i('购买已取消: ${purchaseDetails.productID}');
      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
    }
  }

  /// 验证收据
  static Future<bool> _verifyReceipt(PurchaseDetails purchaseDetails) async {
    try {
      // 获取收据数据
      String receiptData = '';
      
      if (Platform.isIOS) {
        // iOS使用transactionReceipt
        receiptData = purchaseDetails.verificationData.serverVerificationData;
      } else {
        // Android使用purchaseToken
        receiptData = purchaseDetails.verificationData.serverVerificationData;
      }

      if (receiptData.isEmpty) {
        Global.logger.w('收据数据为空');
        return false;
      }

      // 获取当前用户ID
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.w('用户未登录');
        ToastUtil.error('请先登录');
        return false;
      }

      // 只支持iOS平台
      if (!PlatformUtils.isIOS) {
        Global.logger.w('当前平台不支持订阅功能');
        ToastUtil.error('订阅功能仅支持iOS平台');
        return false;
      }
      
      final platform = 'ios';

      // 调用后端验证接口
      final userId = user.id;
      
      final Result result = await Api.client.verifySubscription(
        userId,
        receiptData,
        purchaseDetails.productID,
        purchaseDetails.purchaseID ?? '',
        platform,
      );

      if (result.success) {
        Global.logger.i('收据验证成功');
        return true;
      } else {
        Global.logger.w('收据验证失败: ${result.msg}');
        return false;
      }
    } catch (e, stackTrace) {
      Global.logger.e('验证收据异常', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 刷新用户信息
  static Future<void> _refreshUserInfo() async {
    try {
      final result = await UserBo().getLoggedInUser();
      if (result.success && result.data != null) {
        // 用户信息已更新，可以通过Global.getLoggedInUser()获取最新信息
        Global.logger.i('用户信息已刷新');
      }
    } catch (e, stackTrace) {
      Global.logger.e('刷新用户信息失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 检查用户是否为会员（仅支持iOS平台）
  static bool isPremium() {
    final user = Global.getLoggedInUser();
    if (user == null) {
      return false;
    }

    // 只支持iOS平台订阅
    if (PlatformUtils.isIOS) {
      // 检查iOS订阅
      if (user.isPremiumIos == true) {
        // 检查订阅是否过期
        if (user.subscriptionExpireDateIos != null) {
          final now = DateTime.now();
          final expireDate = user.subscriptionExpireDateIos!;
          if (expireDate.isAfter(now)) {
            return true;
          }
        } else {
          // 如果没有过期时间，但isPremiumIos为true，也认为是会员
          return true;
        }
      }
    }

    return false;
  }

  /// 获取订阅到期时间（仅支持iOS平台）
  static DateTime? getExpireDate() {
    final user = Global.getLoggedInUser();
    if (user == null) {
      return null;
    }

    if (PlatformUtils.isIOS) {
      return user.subscriptionExpireDateIos;
    }

    return null;
  }

  /// 获取订阅类型（仅支持iOS平台）
  static String? getSubscriptionType() {
    final user = Global.getLoggedInUser();
    if (user == null) {
      return null;
    }

    if (PlatformUtils.isIOS) {
      return user.subscriptionTypeIos;
    }

    return null;
  }

  /// 清理资源
  static void dispose() {
    _purchaseSubscription?.cancel();
    _purchaseUpdatedController.close();
    _initialized = false;
  }
}

