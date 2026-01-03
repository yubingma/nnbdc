import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:intl/intl.dart';

/// 订阅页面
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  List<ProductDetails> _products = [];
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _initSubscription();
  }

  /// 初始化订阅服务
  Future<void> _initSubscription() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 初始化订阅服务
      final available = await SubscriptionUtil.init();
      if (!available) {
        ToastUtil.error('应用内购买不可用');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 获取产品列表
      final products = await SubscriptionUtil.getProducts();
      setState(() {
        _products = products;
        _isLoading = false;
      });

      if (products.isEmpty) {
        // 错误提示已在 SubscriptionUtil.getProducts() 中显示
        // 这里不再重复提示
      }
    } catch (e) {
      Global.logger.e('初始化订阅失败', error: e);
      ToastUtil.error('加载订阅信息失败');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 购买订阅
  Future<void> _purchaseProduct(ProductDetails product) async {
    if (_isPurchasing) {
      return;
    }

    setState(() {
      _isPurchasing = true;
    });

    try {
      final success = await SubscriptionUtil.purchase(product);
      if (success) {
        // 购买流程已启动，结果会在_subscriptionUtil中处理
        // 等待一段时间后刷新用户信息
        await Future.delayed(const Duration(seconds: 2));
        await _refreshUserInfo();
      } else {
        ToastUtil.error('购买失败，请重试');
      }
    } catch (e) {
      Global.logger.e('购买异常', error: e);
      ToastUtil.error('购买失败，请重试');
    } finally {
      setState(() {
        _isPurchasing = false;
      });
    }
  }

  /// 恢复购买
  Future<void> _restorePurchases() async {
    if (_isRestoring) {
      return;
    }

    setState(() {
      _isRestoring = true;
    });

    try {
      final success = await SubscriptionUtil.restorePurchases();
      if (success) {
        // 恢复购买流程已启动
        // 等待一段时间后刷新用户信息
        await Future.delayed(const Duration(seconds: 2));
        await _refreshUserInfo();
      }
    } catch (e) {
      Global.logger.e('恢复购买异常', error: e);
      ToastUtil.error('恢复购买失败，请重试');
    } finally {
      setState(() {
        _isRestoring = false;
      });
    }
  }

  /// 刷新用户信息
  Future<void> _refreshUserInfo() async {
    try {
      // 重新从数据库加载用户信息
      await Global.loadUserFromDb();
      final result = await UserBo().getLoggedInUser();
      if (result.success && mounted) {
        setState(() {});
        Global.logger.i('订阅页面：用户信息已刷新');
      }
    } catch (e) {
      Global.logger.e('刷新用户信息失败', error: e);
    }
  }

  /// 获取订阅类型文本
  String _getSubscriptionTypeText(String? subscriptionType) {
    if (subscriptionType == null) {
      return '未知';
    }
    if (subscriptionType == 'monthly' || subscriptionType.contains('monthly')) {
      return '月度订阅';
    } else if (subscriptionType == 'annual' || subscriptionType == 'yearly' || subscriptionType.contains('yearly') || subscriptionType.contains('annual')) {
      return '年度订阅';
    } else {
      return '订阅';
    }
  }

  /// 获取订阅状态文本
  String _getSubscriptionStatusText() {
    final user = Global.getLoggedInUser();
    if (user == null) {
      return '未登录';
    }

    final isPremium = SubscriptionUtil.isPremium();
    if (isPremium) {
      final expireDate = SubscriptionUtil.getExpireDate();
      final subscriptionType = SubscriptionUtil.getSubscriptionType();
      
      if (expireDate != null) {
        final formatter = DateFormat('yyyy年MM月dd日');
        final typeText = _getSubscriptionTypeText(subscriptionType).replaceAll('订阅', '');
        return 'iOS $typeText会员，有效期至：${formatter.format(expireDate)}';
      } else {
        return 'iOS 会员（永久）';
      }
    } else {
      return '非会员';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = SubscriptionUtil.isPremium();

    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅会员'),
        actions: [
          TextButton(
            onPressed: _isRestoring ? null : _restorePurchases,
            child: _isRestoring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('恢复购买'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 当前订阅状态
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前状态',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getSubscriptionStatusText(),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: isPremium ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (isPremium) ...[
                            const SizedBox(height: 8),
                            Text(
                              '订阅类型：${_getSubscriptionTypeText(SubscriptionUtil.getSubscriptionType())}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 订阅产品列表
                  if (_products.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('暂无可用订阅产品'),
                      ),
                    )
                  else
                    ..._products.map((product) => _buildProductCard(product)),

                  const SizedBox(height: 24),

                  // 说明文字
                  Card(
                    color: Colors.grey[100],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '订阅说明',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• 订阅将自动续费，除非在到期前至少24小时取消\n'
                            '• 订阅费用将在确认购买时从您的Apple ID账户中扣除\n'
                            '• 您可以在App Store的账户设置中管理订阅和关闭自动续费\n'
                            '• 恢复购买功能可以帮助您在更换设备后恢复订阅',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 构建产品卡片
  Widget _buildProductCard(ProductDetails product) {
    final isMonthly = product.id.contains('monthly');
    final isAnnual = product.id.contains('yearly') || product.id.contains('annual');
    final isRecommended = isAnnual; // 推荐年度订阅

    return Card(
      elevation: isRecommended ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRecommended
            ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isMonthly ? '月度订阅' : '年度订阅',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (isRecommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '推荐',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.price,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (isAnnual) ...[
                        const SizedBox(height: 4),
                        Text(
                          '平均每月仅需 ${_calculateMonthlyPrice(product.price)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.green,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isPurchasing
                    ? null
                    : () => _purchaseProduct(product),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isPurchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('立即订阅'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 计算年度订阅的月均价格（简单示例，实际需要解析价格字符串）
  String _calculateMonthlyPrice(String annualPrice) {
    // 这里只是示例，实际需要根据价格字符串解析
    // 例如：如果年度价格是 ¥98，则月均价格约为 ¥8.17
    try {
      // 尝试提取数字
      final priceStr = annualPrice.replaceAll(RegExp(r'[^\d.]'), '');
      final price = double.tryParse(priceStr);
      if (price != null) {
        final monthlyPrice = price / 12;
        return '¥${monthlyPrice.toStringAsFixed(2)}';
      }
    } catch (e) {
      // 忽略解析错误
    }
    return '更优惠';
  }
}

