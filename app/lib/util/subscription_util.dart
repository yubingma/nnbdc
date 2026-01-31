import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';

/// 订阅工具类
/// 用于处理iOS应用内购买订阅功能（仅支持iOS平台）
class SubscriptionUtil {
  static final InAppPurchase _iap = InAppPurchase.instance;
  static final StreamController<List<PurchaseDetails>> _purchaseUpdatedController = StreamController<List<PurchaseDetails>>.broadcast();

  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  static bool _isAvailable = false;
  static bool _initialized = false;
  static bool _showToasts = true; // 控制是否显示 Toast 提示

  /// 订阅更新流，用于通知UI刷新
  static Stream<List<PurchaseDetails>> get purchaseUpdatedStream => _purchaseUpdatedController.stream;

  /// 订阅产品ID列表
  static const Set<String> _productIds = {
    'ppdc.monthly', // 月度订阅产品ID
    'ppdc.yearly', // 年度订阅产品ID
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
          ToastUtil.error('订阅产品未找到：$missingProducts\n\n'
              '可能原因：\n'
              '1. App Store Connect 中产品状态为"元数据丢失"\n'
              '2. 产品未关联到 App 版本并提交审核\n'
              '3. 需要在真实设备上测试（模拟器不支持）\n\n'
              '请检查 App Store Connect 中的产品配置');
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
    _showToasts = true; // 手动购买必须显示提示
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
    } on PlatformException catch (e, stackTrace) {
      // 捕获 PlatformException 并提供详细错误信息
      Global.logger.e('购买异常 (PlatformException)', error: e, stackTrace: stackTrace);

      String errorMessage = '购买失败';

      // 解析常见的 StoreKit 错误
      if (e.code == 'storekit_duplicate_product_object') {
        errorMessage = '订阅已存在，请勿重复购买';
      } else if (e.code == 'storekit_invalid_payment') {
        errorMessage = '支付信息无效，请重试';
      } else if (e.code == 'storekit_invalid_product') {
        errorMessage = '订阅产品不可用，请联系客服';
      } else if (e.code == 'user_cancelled') {
        errorMessage = '您已取消购买';
        Global.logger.i('用户取消购买');
      } else if (e.message != null && e.message!.contains('StoreKitError')) {
        // StoreKit 原生错误
        errorMessage = '购买失败：${e.message}\n\n'
            '可能原因：\n'
            '1. 网络连接问题\n'
            '2. Apple ID 未登录或被锁定\n'
            '3. 设备不支持应用内购买\n'
            '4. App Store 服务器问题\n\n'
            '请稍后重试或检查 Apple ID 设置';
      } else {
        // 其他错误
        final details = e.message ?? e.code;
        errorMessage = '购买失败：$details';
      }

      ToastUtil.error(errorMessage);
      return false;
    } catch (e, stackTrace) {
      Global.logger.e('购买异常', error: e, stackTrace: stackTrace);
      ToastUtil.error('购买失败，请重试');
      return false;
    }
  }

  /// 恢复购买
  static Future<bool> restorePurchases({bool showToast = true}) async {
    if (!_isAvailable) {
      await init();
      if (!_isAvailable) {
        if (showToast) ToastUtil.error('应用内购买不可用');
        return false;
      }
    }

    try {
      _showToasts = showToast;
      await _iap.restorePurchases();
      if (showToast) ToastUtil.info('正在恢复购买...');
      return true;
    } catch (e, stackTrace) {
      Global.logger.e('恢复购买异常', error: e, stackTrace: stackTrace);
      if (showToast) ToastUtil.error('恢复购买失败，请重试');
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
      if (_showToasts) ToastUtil.info('购买处理中...');
      return;
    }

    if (purchaseDetails.status == PurchaseStatus.error) {
      Global.logger.e('购买失败: ${purchaseDetails.error}');
      if (_showToasts) ToastUtil.error('购买失败: ${purchaseDetails.error?.message ?? "未知错误"}');
      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
      }
      return;
    }

    if (purchaseDetails.status == PurchaseStatus.purchased || purchaseDetails.status == PurchaseStatus.restored) {
      Global.logger.i('购买成功: ${purchaseDetails.productID}');

      // 验证收据(后端验证)
      final bool verified = await _verifyReceipt(purchaseDetails);

      if (verified) {
        if (_showToasts) {
          // 区分是新订阅还是恢复订阅
          if (purchaseDetails.status == PurchaseStatus.restored) {
            ToastUtil.success('恢复订阅成功！');
          } else {
            ToastUtil.success('订阅成功！');
          }
        }
        // 刷新用户信息
        await _refreshUserInfo();
        // 发送订阅更新事件，通知页面刷新
        _purchaseUpdatedController.add([purchaseDetails]);
      } else {
        if (_showToasts) {
          ToastUtil.error('订阅验证失败，请联系客服');
        }
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
        Global.logger.i('iOS收据数据长度: ${receiptData.length}');
        Global.logger.i('iOS收据数据前100字符: ${receiptData.length > 100 ? receiptData.substring(0, 100) : receiptData}');
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
        Global.logger.w('验证收据失败：当前未获取到用户信息');
        return false;
      }

      final userId = user.id;

      // 只支持iOS平台
      if (!PlatformUtils.isIOS) {
        Global.logger.w('当前平台不支持订阅功能');
        return false;
      }

      final platform = 'ios';

      // 调用后端验证接口 (游客模式也会发送 userId='guest' 给后端进行收据校验)

      final Result<SubscriptionVo> result = await Api.client.verifySubscription(
        userId,
        receiptData,
        purchaseDetails.productID,
        purchaseDetails.purchaseID ?? '',
        platform,
        !Global.isGuest, // updateBackend: 为访客时不更新后端
      );

      if (result.success && result.data != null) {
        Global.logger.i('收据验证成功，立即更新本地数据库');

        // 从返回的订阅信息中提取数据
        final subscriptionData = result.data!;
        final isPremiumIos = subscriptionData.isPremiumIos ?? false;
        final subscriptionTypeIos = subscriptionData.subscriptionTypeIos;
        final subscriptionStatusIos = subscriptionData.subscriptionStatusIos;
        final subscriptionExpireDateIos = subscriptionData.subscriptionExpireDateIos;

        // 立即更新本地数据库（不写同步日志，因为服务端已经更新了）
        final db = MyDatabase.instance;
        final currentUser = await db.usersDao.getUserById(userId);
        if (currentUser != null) {
          final updatedUser = currentUser.copyWith(
            isPremiumIos: Value<bool?>(isPremiumIos),
            subscriptionExpireDateIos: Value<DateTime?>(subscriptionExpireDateIos),
            subscriptionTypeIos: Value<String?>(subscriptionTypeIos),
            subscriptionStatusIos: Value<String?>(subscriptionStatusIos),
            lastReceiptDataIos: Value<String?>(receiptData),
          );

          // 直接更新数据库，不生成同步日志
          await (db.update(db.users)..where((t) => t.id.equals(userId))).write(updatedUser);

          // 立即更新内存缓存
          Global.updateUserCache(updatedUser);

          Global.logger.i('订阅状态已更新到本地数据库和缓存: isPremium=$isPremiumIos, expireDate=$subscriptionExpireDateIos');
        }

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

  /// 刷新用户信息（订阅验证成功后立即更新本地数据库，这里用于更新缓存和触发UI刷新）
  static Future<void> _refreshUserInfo() async {
    try {
      // 重新从数据库加载用户信息到缓存，确保UI能获取到最新订阅状态
      await Global.loadUserFromDb();

      // 触发一次同步（不等待结果）
      ThrottledDbSyncService().requestSync();
      Global.logger.i('订阅验证成功，本地数据已更新，缓存已刷新，后台同步已触发');
    } catch (e, stackTrace) {
      Global.logger.e('刷新用户信息失败', error: e, stackTrace: stackTrace);
    }
  }

  /// 检查用户是否为会员（优先使用本地用户字段判定）
  static bool isPremium() {
    final user = Global.getLoggedInUser();
    if (user == null) {
      return false;
    }

    return _isPremiumEffective(user);
  }

  /// 检查并强制执行会员限制（例如：非会员每日单词限额为 20）
  static Future<void> checkAndEnforceMemberLimits() async {
    final user = Global.getLoggedInUser();
    if (user == null || Global.isGuest) {
      return;
    }

    if (!isPremium()) {
      if (user.wordsPerDay > 20) {
        Global.logger.i('用户非会员，强制执行每日单词限额 20（原设为 ${user.wordsPerDay}）');

        // 更新本地数据库
        await MyDatabase.instance.usersDao.updateWordsPerDay(user.id, 20);

        // 更新内存缓存
        final updatedUser = user.copyWith(wordsPerDay: 20);
        Global.updateUserCache(updatedUser);

        // 触发同步到云端
        ThrottledDbSyncService().requestSync();
      }
    }
  }

  /// 有效会员判定（包含“强制视为会员”逻辑；边界情况偏向会员）
  static bool _isPremiumEffective(User user) {
    final now = DateTime.now();

    // 非ios平台, 暂时都视为会员
    if (!Platform.isIOS) {
      return true;
    }

    // 1) iOS订阅
    try {
      if (user.isPremiumIos == true) {
        final expireDate = user.subscriptionExpireDateIos;
        if (expireDate == null) {
          return true;
        }
        if (expireDate.isAfter(now)) {
          return true;
        }
      }
    } catch (_) {
      return true;
    }

    // 2) 强制视为会员
    try {
      if (user.premiumOverrideEnabled != true) {
        return false;
      }
      if (user.premiumOverrideDuration == null) {
        return true; // 永久
      }
      final updateTime = user.premiumOverrideUpdateTime;
      if (updateTime == null) {
        return true; // 元数据缺失，偏向会员
      }

      final durationMs = _parseDurationMillis(user.premiumOverrideDuration!);
      if (durationMs == null) {
        return true; // 无法解析，偏向会员
      }
      if (durationMs <= 0) {
        return false;
      }
      final expireTime = updateTime.add(Duration(milliseconds: durationMs));
      return expireTime.isAfter(now);
    } catch (_) {
      return true;
    }
  }

  static int? _parseDurationMillis(String duration) {
    final s = duration.trim();
    if (s.isEmpty) return null;
    final reg = RegExp(r'^(\d+)\s*(毫秒|ms|秒|s|分钟|分|m|小时|时|h|天|日|d)$', caseSensitive: false);
    final m = reg.firstMatch(s);
    if (m == null) return null;
    final value = int.tryParse(m.group(1)!);
    if (value == null) return null;
    final unit = (m.group(2) ?? '').toLowerCase();
    switch (unit) {
      case '毫秒':
      case 'ms':
        return value;
      case '秒':
      case 's':
        return value * 1000;
      case '分钟':
      case '分':
      case 'm':
        return value * 60 * 1000;
      case '小时':
      case '时':
      case 'h':
        return value * 60 * 60 * 1000;
      case '天':
      case '日':
      case 'd':
        return value * 24 * 60 * 60 * 1000;
      default:
        return null;
    }
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
