import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// 订阅页面
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  List<ProductDetails> _products = [];
  bool _isLoading = true;
  String? _purchasingProductId; // 记录当前正在购买的产品ID
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

      // 获取产品列表并排序（确保顺序固定：月度在前，年度在后）
      final products = await SubscriptionUtil.getProducts();
      products.sort((a, b) {
        // 定义顺序：monthly 优先于 yearly/annual
        bool aIsMonthly = a.id.contains('monthly');
        bool bIsMonthly = b.id.contains('monthly');

        if (aIsMonthly && !bIsMonthly) return 1;
        if (!aIsMonthly && bIsMonthly) return -1;
        return a.id.compareTo(b.id);
      });

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
    if (_purchasingProductId != null) {
      return;
    }

    // 检查是否已有有效订阅
    final isPremium = SubscriptionUtil.isPremium();
    final currentType = SubscriptionUtil.getSubscriptionType();
    final expireDate = SubscriptionUtil.getExpireDate();

    // 判断产品类型
    final isMonthly = product.id.contains('monthly');
    final isAnnual = product.id.contains('yearly') || product.id.contains('annual');

    if (isPremium && expireDate != null) {
      final formatter = DateFormat('yyyy年MM月dd日');

      // 购买相同类型订阅时，显示确认对话框
      if ((currentType == 'annual' && isAnnual) || (currentType == 'monthly' && isMonthly)) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认订阅'),
            content: Text('您已经是${isAnnual ? "年度" : "月度"}会员\n'
                '有效期至：${formatter.format(expireDate)}\n\n'
                '重复订阅相同类型可能会在当前订阅到期后续订，或根据 Apple 的订阅政策处理。\n\n'
                '建议：如需续订，请等待当前订阅快到期时再操作。\n\n'
                '确定要继续吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          return;
        }
      }

      // 从年度降级到月度时，给出明确说明
      else if (currentType == 'annual' && isMonthly) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('降级订阅'),
            content: Text('您当前是年度会员（有效期至 ${formatter.format(expireDate)}）\n\n'
                '如果订阅月度会员：\n'
                '• 您的年度会员将继续有效至到期日\n'
                '• 年度会员到期后，将自动切换为月度会员\n'
                '• 不会立即生效，也不会获得退款\n\n'
                '您确定要降级吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认降级'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          return;
        }
      }

      // 从月度升级到年度时，强调立即生效和退款
      else if (currentType == 'monthly' && isAnnual) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('升级到年度会员'),
            content: Text('您当前是月度会员（有效期至 ${formatter.format(expireDate)}）\n\n'
                '如果升级到年度会员：\n'
                '• 立即生效，享受年度会员权益\n'
                '• Apple 会自动退还月度订阅未使用部分的费用\n'
                '• 年度会员价格更优惠！\n\n'
                '确定要升级吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('立即升级'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          return;
        }
      }
    }

    setState(() {
      _purchasingProductId = product.id;
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
        _purchasingProductId = null;
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
        
        // 检查恢复后是否为会员状态，如果不是则给出提示
        if (!SubscriptionUtil.isPremium()) {
          ToastUtil.info('未找到有效的订阅记录。');
        }
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
    } else if (subscriptionType == 'annual' ||
        subscriptionType == 'yearly' ||
        subscriptionType.contains('yearly') ||
        subscriptionType.contains('annual')) {
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
        return '$typeText会员\n有效期至：${formatter.format(expireDate)}';
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
                  Container(
                    decoration: BoxDecoration(
                      gradient: isPremium
                          ? LinearGradient(
                              colors: [Colors.green.shade400, Colors.green.shade600],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : LinearGradient(
                              colors: [Colors.grey.shade300, Colors.grey.shade400],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: isPremium ? Colors.green.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isPremium ? Icons.workspace_premium : Icons.person_outline,
                                color: Colors.white,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '会员状态',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _getSubscriptionStatusText(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• 订阅周期：1个月（月度订阅）或1年（年度订阅）。\n'
                            '• 付款：用户确认购买并付款后计入iTunes账户。\n'
                            '• 续订：苹果iTunes账户会在到期前24小时内扣费，扣费成功后订阅周期顺延一个订阅周期。\n'
                            '• 取消续订：如需取消续订，请在当前订阅周期到期前24小时以前，手动在iTunes/Apple ID设置管理中关闭自动续订功能。\n'
                            '• 恢复购买：如果您之前已购买过，可以点击右上角的“恢复购买”按钮。',
                            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '购买即视为您同意以下条款：',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(context, '/privacy');
                                },
                                child: Text(
                                  '隐私政策',
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    decoration: TextDecoration.underline,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(context, '/protocol');
                                },
                                child: Text(
                                  '用户协议',
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    decoration: TextDecoration.underline,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  final url = Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
                                  if (await canLaunchUrl(url)) {
                                    await launchUrl(url);
                                  }
                                },
                                child: Text(
                                  '标准EULA',
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    decoration: TextDecoration.underline,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
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

    // 检查当前订阅状态
    final isPremium = SubscriptionUtil.isPremium();
    final currentType = SubscriptionUtil.getSubscriptionType();
    final isCurrentSubscription = isPremium && ((currentType == 'annual' && isAnnual) || (currentType == 'monthly' && isMonthly));

    return Card(
      elevation: isRecommended ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      // 当前订阅使用绿色背景
      color: isCurrentSubscription ? Colors.green.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrentSubscription
            ? BorderSide(color: Colors.green, width: 2)
            : (isRecommended ? BorderSide(color: Theme.of(context).primaryColor, width: 2) : BorderSide.none),
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
                            isMonthly ? '月度订阅 (1个月)' : '年度订阅 (1年)',
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

            // 显示当前订阅标识
            if (isCurrentSubscription) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '当前订阅',
                      style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            // 会员权益说明
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '会员权益:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '• 解除每日20的单词上限, 上限提升至500\n'
                    '• 可自定义单词书\n',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _purchasingProductId != null ? null : () => _purchaseProduct(product),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _purchasingProductId == product.id
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(isCurrentSubscription ? '续订' : '立即订阅'),
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
