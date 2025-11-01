import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

/// 阿里云资源管理页面
class AliyunResourceManagementPage extends StatefulWidget {
  const AliyunResourceManagementPage({super.key});

  @override
  State<AliyunResourceManagementPage> createState() => _AliyunResourceManagementPageState();
}

class _AliyunResourceManagementPageState extends State<AliyunResourceManagementPage> {
  Map<String, dynamic>? _balanceInfo;
  List<dynamic>? _resourcePackages;
  final bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    await Future.wait([
      _refreshBalance(),
      _refreshResourcePackages(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          '阿里云资源管理',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            fontFamily: 'NotoSansSC',
          ),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBalanceCard(isDarkMode),
                  const SizedBox(height: 16),
                  _buildResourcePackagesCard(isDarkMode),
                  const SizedBox(height: 16),
                  _buildInfoCard(isDarkMode),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard(bool isDarkMode) {
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '账户余额',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_balanceInfo == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '点击右上角刷新按钮查询余额',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor.withValues(alpha: 0.6),
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              )
            else
              Column(
                children: [
                  _buildBalanceRow(
                    '可用余额',
                    _balanceInfo!['availableAmount'] ?? '-',
                    _balanceInfo!['currency'] ?? 'CNY',
                    isDarkMode,
                    textColor,
                  ),
                  const Divider(height: 24),
                  _buildBalanceRow(
                    '可用现金',
                    _balanceInfo!['availableCashAmount'] ?? '-',
                    _balanceInfo!['currency'] ?? 'CNY',
                    isDarkMode,
                    textColor,
                  ),
                  const Divider(height: 24),
                  _buildBalanceRow(
                    '信用额度',
                    _balanceInfo!['creditAmount'] ?? '-',
                    _balanceInfo!['currency'] ?? 'CNY',
                    isDarkMode,
                    textColor,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceRow(
    String label,
    String amount,
    String currency,
    bool isDarkMode,
    Color textColor,
  ) {
    final isPositive = amount != '-' && (double.tryParse(amount) ?? 0) >= 0;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: textColor.withValues(alpha: 0.8),
            fontFamily: 'NotoSansSC',
          ),
        ),
        Row(
          children: [
            Text(
              amount,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isPositive ? Colors.green : Colors.red,
                fontFamily: 'NotoSansSC',
              ),
            ),
            const SizedBox(width: 4),
            Text(
              currency,
              style: TextStyle(
                fontSize: 14,
                color: textColor.withValues(alpha: 0.6),
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResourcePackagesCard(bool isDarkMode) {
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '资源包使用情况',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_resourcePackages == null)
              Text(
                '正在加载资源包信息...',
                style: TextStyle(
                  fontSize: 14,
                  color: textColor.withValues(alpha: 0.6),
                  fontFamily: 'NotoSansSC',
                ),
              )
            else if (_resourcePackages!.isEmpty)
              Text(
                '暂无资源包',
                style: TextStyle(
                  fontSize: 14,
                  color: textColor.withValues(alpha: 0.6),
                  fontFamily: 'NotoSansSC',
                ),
              )
            else
              Column(
                children: _resourcePackages!.map((package) {
                  return _buildResourcePackageItem(package, isDarkMode, textColor);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourcePackageItem(Map<String, dynamic> package, bool isDarkMode, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package['InstanceName'] ?? '未知资源包',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '有效期至: ${package['ExpiryTime'] ?? '-'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.6),
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ],
            ),
          ),
          Text(
            package['Status'] ?? '-',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _getStatusColor(package['Status'] ?? ''),
              fontFamily: 'NotoSansSC',
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (status.contains('有效') || status.contains('Active')) {
      return Colors.green;
    } else if (status.contains('过期') || status.contains('Expired')) {
      return Colors.red;
    } else {
      return Colors.orange;
    }
  }

  Widget _buildInfoCard(bool isDarkMode) {
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '说明',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '1. 此功能用于查询阿里云账户的余额和资源使用情况。\n'
              '2. 余额信息需要配置正确的阿里云AccessKey。\n'
              '3. 点击右上角刷新按钮可以实时查询最新余额。\n'
              '4. 信用额度显示为负数表示透支额度。',
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: textColor.withValues(alpha: 0.8),
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 刷新余额信息
  Future<void> _refreshBalance() async {
    try {
      final result = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.queryAliyunBalance();
      });

      if (result.success && result.data != null) {
        setState(() {
          _balanceInfo = result.data!.data;
        });
      } else {
        ToastUtil.error('查询失败: ${result.msg ?? "未知错误"}');
      }
    } catch (e) {
      Global.logger.e('查询余额失败', error: e);
      ToastUtil.error('查询失败: $e');
    }
  }

  /// 刷新资源包信息
  Future<void> _refreshResourcePackages() async {
    try {
      final result = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.queryAliyunResourcePackages();
      });

      if (result.success && result.data != null) {
        setState(() {
          _resourcePackages = result.data!.data['Instances'] as List<dynamic>?;
        });
      } else {
        // 资源包查询失败不显示错误，因为可能没有资源包
        Global.logger.w('资源包查询失败: ${result.msg ?? "未知错误"}');
      }
    } catch (e) {
      Global.logger.e('查询资源包失败', error: e);
    }
  }
}

