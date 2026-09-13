import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../widget/app_scaffold.dart';
import '../widget/frosted_glass_card.dart';

/// 订阅页面（会员中心）
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  List<ProductDetails> _products = [];
  ProductDetails? _selectedProduct;
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

      // 获取产品列表并排序（确保顺序：年度优先展示，其次月度）
      final products = await SubscriptionUtil.getProducts();
      products.sort((a, b) {
        bool aIsAnnual = a.id.contains('yearly') || a.id.contains('annual');
        bool bIsAnnual = b.id.contains('yearly') || b.id.contains('annual');
        if (aIsAnnual && !bIsAnnual) return -1;
        if (!aIsAnnual && bIsAnnual) return 1;
        return a.id.compareTo(b.id);
      });

      ProductDetails? defaultProduct;
      for (final p in products) {
        if (p.id.contains('yearly') || p.id.contains('annual')) {
          defaultProduct = p;
          break;
        }
      }
      defaultProduct ??= products.isNotEmpty ? products.first : null;

      setState(() {
        _products = products;
        _selectedProduct = defaultProduct;
        _isLoading = false;
      });
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
        await Future.delayed(const Duration(seconds: 2));
        await _refreshUserInfo();
      } else {
        ToastUtil.error('购买失败，请重试');
      }
    } catch (e) {
      Global.logger.e('购买异常', error: e);
      ToastUtil.error('购买失败，请重试');
    } finally {
      if (mounted) {
        setState(() {
          _purchasingProductId = null;
        });
      }
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
        await Future.delayed(const Duration(seconds: 2));
        await _refreshUserInfo();

        if (!SubscriptionUtil.isPremium()) {
          ToastUtil.info('未找到有效的订阅记录');
        } else {
          ToastUtil.success('已成功恢复会员身份');
        }
      }
    } catch (e) {
      Global.logger.e('恢复购买异常', error: e);
      ToastUtil.error('恢复购买失败，请重试');
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  /// 刷新用户信息
  Future<void> _refreshUserInfo() async {
    try {
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

  /// 获取订阅类型纯文本
  String _getSubscriptionTypeTitle() {
    final subscriptionType = SubscriptionUtil.getSubscriptionType();
    if (subscriptionType == null) return '会员';
    if (subscriptionType.contains('monthly')) return '月度会员';
    if (subscriptionType.contains('yearly') || subscriptionType.contains('annual')) return '年度会员';
    return '尊享会员';
  }

  /// 计算年度订阅的月均价格（自动保持货币符号一致）
  String _calculateMonthlyPrice(String annualPrice) {
    try {
      final currencyMatch = RegExp(r'^[^\d.]+').firstMatch(annualPrice.trim());
      String currency = currencyMatch?.group(0) ?? '';
      if (currency.isEmpty) {
        if (annualPrice.contains('¥')) {
          currency = '¥';
        } else if (annualPrice.contains('\$')) {
          currency = '\$';
        }
      }

      final priceStr = annualPrice.replaceAll(RegExp(r'[^\d.]'), '');
      final price = double.tryParse(priceStr);
      if (price != null) {
        final monthlyPrice = price / 12;
        return '$currency${monthlyPrice.toStringAsFixed(2)}';
      }
    } catch (_) {}
    return '更超值';
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = SubscriptionUtil.isPremium();
    final expireDate = SubscriptionUtil.getExpireDate();

    return AppScaffold(
      appBar: AppBar(
        title: const Text(
          '会员中心',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isRestoring ? null : _restorePurchases,
            style: TextButton.styleFrom(
              foregroundColor: context.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: _isRestoring
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(context.textSecondary),
                    ),
                  )
                : Text(
                    '恢复购买',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. 会员状态尊享卡片
                        _buildMemberStatusCard(isPremium, expireDate),
                        const SizedBox(height: 20),

                        // 2. 会员专属特权矩阵（统一展示，不重复堆叠）
                        _buildPrivilegesSection(),
                        const SizedBox(height: 20),

                        // 3. 订阅方案选择区（并排/对比卡片）
                        if (_products.isNotEmpty) ...[
                          _buildPlanSelectorHeader(),
                          const SizedBox(height: 12),
                          _buildPlanCardsGrid(),
                          const SizedBox(height: 20),
                        ],

                        // 4. 说明与条款
                        _buildTermsAndDisclaimers(),
                      ],
                    ),
                  ),
                ),

                // 底部常驻购买行动栏
                if (_products.isNotEmpty) _buildStickyActionBar(),
              ],
            ),
    );
  }

  /// 1. 会员状态卡片
  Widget _buildMemberStatusCard(bool isPremium, DateTime? expireDate) {
    final primaryColor = context.primaryColor;
    final formatter = DateFormat('yyyy年MM月dd日');

    if (isPremium) {
      // 会员生效态：黑曜石深空尊享质感卡片
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: const Color(0xFFFBBF24).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFF451A03),
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _getSubscriptionTypeTitle(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'PRO VIP',
                          style: TextStyle(
                            color: Color(0xFFFDE68A),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    expireDate != null ? '有效期至：${formatter.format(expireDate)}' : '永久会员权益生效中',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12.5,
                      fontFamily: 'Roboto',
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // 非会员态：柔和通透的升级指引卡片
      return FrostedGlassCard(
        borderRadius: 20,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.diamond_rounded,
                color: primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '开通 NBDC 会员',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '解锁全库词书畅学与 AI 助教记忆解析',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  /// 2. 会员专属特权矩阵（聚合式排版，零多余框）
  Widget _buildPrivilegesSection() {
    return FrostedGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '会员特权',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· 专享高效背词服务',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 2x2 特权项
          Row(
            children: [
              Expanded(
                child: _buildPrivilegeItem(
                  icon: Icons.all_inclusive_rounded,
                  iconColor: const Color(0xFF0EA5E9), // 明快天蓝
                  title: '无上限学词',
                  desc: '解除每日20词限制',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPrivilegeItem(
                  icon: Icons.bolt_rounded,
                  iconColor: const Color(0xFFF59E0B), // 暖金
                  title: '自由加量学习',
                  desc: '打卡后随时随心追加',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildPrivilegeItem(
                  icon: Icons.menu_book_rounded,
                  iconColor: const Color(0xFF10B981), // 翠绿
                  title: '全库词书畅学',
                  desc: '全库解锁与自定义导入',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPrivilegeItem(
                  icon: Icons.psychology_rounded,
                  iconColor: const Color(0xFF8B5CF6), // 典雅紫
                  title: 'AI 深度助教',
                  desc: '语境联想与记忆溯源',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 单个权益元素
  Widget _buildPrivilegeItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondary,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 3.1 方案选择器标题
  Widget _buildPlanSelectorHeader() {
    return Text(
      '选择订阅方案',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: context.textPrimary,
        letterSpacing: -0.2,
      ),
    );
  }

  /// 3.2 方案选择器（并排卡片）
  Widget _buildPlanCardsGrid() {
    if (_products.length >= 2) {
      return Row(
        children: _products.map((product) {
          final isSelected = _selectedProduct?.id == product.id;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: product == _products.first ? 6 : 0,
                left: product == _products.last ? 6 : 0,
              ),
              child: _buildPlanCard(product, isSelected),
            ),
          );
        }).toList(),
      );
    } else {
      return Column(
        children: _products.map((p) => _buildPlanCard(p, _selectedProduct?.id == p.id)).toList(),
      );
    }
  }

  /// 单个订阅计划卡片
  Widget _buildPlanCard(ProductDetails product, bool isSelected) {
    final primaryColor = context.primaryColor;
    final isAnnual = product.id.contains('yearly') || product.id.contains('annual');
    final isMonthly = product.id.contains('monthly');

    // 检查是否为当前正在生效的订阅类型
    final isPremium = SubscriptionUtil.isPremium();
    final currentType = SubscriptionUtil.getSubscriptionType();
    final isCurrentSubscription = isPremium &&
        ((currentType == 'annual' && isAnnual) || (currentType == 'monthly' && isMonthly));

    final title = isAnnual ? '年度订阅' : (isMonthly ? '月度订阅' : product.title);
    final periodSubtitle = isAnnual ? '12个月' : '1个月';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedProduct = product;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: isSelected
              ? primaryColor.withValues(alpha: 0.08)
              : context.cardBg,
          border: Border.all(
            color: isSelected
                ? primaryColor
                : context.cardBorder,
            width: isSelected ? 1.8 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [context.cardShadow],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 方案名
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  periodSubtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.textMuted,
                  ),
                ),
                const SizedBox(height: 12),

                // 挺拔修长的主价格展示 (Roboto)
                Text(
                  product.price,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Roboto',
                    letterSpacing: -0.5,
                    color: isSelected ? primaryColor : context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),

                // 月均折算文案 / 灵活按月
                if (isAnnual) ...[
                  Text(
                    '折合 ${_calculateMonthlyPrice(product.price)}/月',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? primaryColor : context.textSecondary,
                    ),
                  ),
                ] else ...[
                  Text(
                    '灵活按月畅学',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 10),

                // 当前订阅状态标签或选中状态标记
                if (isCurrentSubscription)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 12, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          '当前生效',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 18,
                    child: Center(
                      child: Text(
                        isSelected ? '已选定' : '轻触选择',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isSelected ? primaryColor : context.textMuted,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // 顶部推荐徽标（仅年度）
            if (isAnnual)
              Positioned(
                top: -24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      '超值推荐',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 4. 说明与条款
  Widget _buildTermsAndDisclaimers() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '• 付款与续订：确认购买后将由 iTunes 账户扣款。到期前24小时内苹果会自动扣款续订。\n'
            '• 取消续订：如需取消，请在当前周期结束前至少24小时在 Apple ID 订阅管理中关闭。\n'
            '• 恢复权益：如曾在其他 iOS 设备购买过，可轻触右上角“恢复购买”。',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => context.push('/protocol'),
                child: Text(
                  '用户协议',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                '  ·  ',
                style: TextStyle(fontSize: 11, color: context.textMuted),
              ),
              GestureDetector(
                onTap: () => context.push('/privacy'),
                child: Text(
                  '隐私政策',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                '  ·  ',
                style: TextStyle(fontSize: 11, color: context.textMuted),
              ),
              GestureDetector(
                onTap: () async {
                  final url = Uri.parse(
                      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  }
                },
                child: Text(
                  'Apple EULA',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 5. 底部常驻购买行动栏
  Widget _buildStickyActionBar() {
    final selectedProduct = _selectedProduct;
    if (selectedProduct == null) return const SizedBox.shrink();

    final primaryColor = context.primaryColor;
    final isPremium = SubscriptionUtil.isPremium();
    final currentType = SubscriptionUtil.getSubscriptionType();
    final isAnnual = selectedProduct.id.contains('yearly') || selectedProduct.id.contains('annual');
    final isMonthly = selectedProduct.id.contains('monthly');

    final isSameType = (currentType == 'annual' && isAnnual) || (currentType == 'monthly' && isMonthly);

    String buttonLabel;
    if (isPremium) {
      if (isSameType) {
        buttonLabel = '续订${isAnnual ? "年度" : "月度"}会员 (${selectedProduct.price})';
      } else if (currentType == 'monthly' && isAnnual) {
        buttonLabel = '升级为年度会员 (${selectedProduct.price})';
      } else {
        buttonLabel = '变更订阅 (${selectedProduct.price})';
      }
    } else {
      buttonLabel = '立即开通 ${isAnnual ? "年度会员" : "月度会员"} (${selectedProduct.price})';
    }

    final isProcessing = _purchasingProductId == selectedProduct.id;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? const Color(0xE618202F)
            : const Color(0xE6FFFFFF),
        border: Border(
          top: BorderSide(
            color: context.cardBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: (isProcessing || _purchasingProductId != null)
                  ? null
                  : () => _purchaseProduct(selectedProduct),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '自动续期可随时取消 · 支持跨设备通用',
            style: TextStyle(
              fontSize: 11,
              color: context.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

