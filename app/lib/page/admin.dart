import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/page/admin/feedback_management.dart';
import 'package:nnbdc/page/admin/dictionary_management.dart';
import 'package:nnbdc/page/admin/system_health_check.dart';
import 'package:nnbdc/page/admin/user_management.dart';
import 'package:nnbdc/page/admin/cdn_management.dart';
import 'package:nnbdc/page/admin/aliyun_resource_management.dart';
import 'package:nnbdc/page/admin/feature_request_management.dart';
import 'package:nnbdc/page/admin/feature_request_report_management.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool _isLoading = true;
  UserVo? _currentUser;
  int _adviceUnreadCount = 0;

  List<Widget> _buildManagementItems() {
    return [
      _buildManagementCard(
        title: '意见建议',
        icon: Icons.feedback,
        color: const Color(0xFF4CAF50),
        badgeCount: _adviceUnreadCount,
        onTap: () => _navigateToFeedback(),
      ),
      _buildManagementCard(
        title: '需求管理',
        icon: Icons.rate_review,
        color: const Color(0xFFE53935),
        onTap: () => _navigateToFeatureRequestManagement(),
      ),
      _buildManagementCard(
        title: '需求举报',
        icon: Icons.flag,
        color: Colors.red,
        onTap: () => _navigateToFeatureRequestReportManagement(),
      ),
      _buildManagementCard(
        title: '系统词典',
        icon: Icons.book,
        color: const Color(0xFF2196F3),
        onTap: () => _navigateToDictionary(),
      ),
      _buildManagementCard(
        title: '系统健康检查',
        icon: Icons.health_and_safety,
        color: const Color(0xFFE91E63),
        onTap: () => _navigateToSystemHealthCheck(),
      ),
      _buildManagementCard(
        title: '用户管理',
        icon: Icons.people,
        color: const Color(0xFFFF9800),
        onTap: () => _navigateToUserManagement(),
      ),
      _buildManagementCard(
        title: '系统设置',
        icon: Icons.settings,
        color: const Color(0xFF9C27B0),
        onTap: () => _showComingSoon('系统设置'),
      ),
      _buildManagementCard(
        title: '数据统计',
        icon: Icons.analytics,
        color: const Color(0xFF00BCD4),
        onTap: () => _showComingSoon('数据统计'),
      ),
      _buildManagementCard(
        title: '日志管理',
        icon: Icons.description,
        color: const Color(0xFF795548),
        onTap: () => _showComingSoon('日志管理'),
      ),
      _buildManagementCard(
        title: 'CDN管理',
        icon: Icons.cloud_sync,
        color: const Color(0xFF009688),
        onTap: () => _navigateToCdnManagement(),
      ),
      _buildManagementCard(
        title: '阿里云资源',
        icon: Icons.cloud,
        color: const Color(0xFFFF6B00),
        onTap: () => _navigateToAliyunResourceManagement(),
      ),
      _buildManagementCard(
        title: '制作黄金母版',
        icon: Icons.auto_fix_high,
        color: Colors.redAccent,
        onTap: () => Navigator.pushNamed(context, '/golden_master'),
      ),
      _buildManagementCard(
        title: 'AI 功能管理',
        icon: Icons.psychology,
        color: const Color(0xFF6A1B9A),
        onTap: () => Navigator.pushNamed(context, '/ai_activation'),
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _checkAdminPermission();
  }

  Future<void> _checkAdminPermission() async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null || !(user.isAdmin ?? false)) {
        // 非管理员用户，显示无权限页面
        setState(() {
          _isLoading = false;
        });
        return;
      }
      // 将User转换为UserVo
      _currentUser = UserVo.c2(user.id)
        ..userName = user.userName
        ..nickName = user.nickName
        ..isAdmin = user.isAdmin;
    } catch (e) {
      // 获取用户信息失败
    }
    
    setState(() {
      _isLoading = false;
    });

    // 异步加载“意见建议”未读数量（不阻塞主 UI）
    _loadAdviceMsgCounts();
  }

  Future<void> _loadAdviceMsgCounts() async {
    try {
      final res = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getMsgCounts(Global.sysUserId);
      });
      if (!mounted) return;
      if (res.success) {
        setState(() {
          _adviceUnreadCount = res.data?.second ?? 0;
        });
      }
    } catch (_) {
      // 获取失败不影响主功能
    }
  }

  Widget _buildNoPermissionPage() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: '系统管理',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock,
              size: 64,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              '无权限访问',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '此页面仅对管理员可见',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminContent() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          '系统管理',
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
      ),
      body: _buildManagementGrid(),
    );
  }

  Widget _buildManagementGrid() {
    final items = _buildManagementItems();

    return LayoutBuilder(
      builder: (context, constraints) {
        // macOS/桌面端窗口通常更宽：限制内容最大宽度并居中，避免按钮过度分散
        final maxWidth = constraints.maxWidth;
        final contentMaxWidth = maxWidth >= 900 ? 780.0 : maxWidth;
        final maxCrossAxisExtent = maxWidth >= 900 ? 180.0 : 160.0;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxCrossAxisExtent,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => items[index],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildManagementCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 44,
                  color: color,
                ),
                if ((badgeCount ?? 0) > 0)
                  Positioned(
                    // 绑定在图标右上角，略微外扩，视觉更贴近
                    right: -10,
                    top: -10,
                    child: _buildBadge(badgeCount!),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(int count) {
    final display = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        display,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _navigateToFeedback() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeedbackManagementWidget(),
      ),
    ).then((_) {
      // 从意见建议页面返回后刷新未读数量
      _loadAdviceMsgCounts();
    });
  }

  void _navigateToDictionary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DictionaryManagementWidget(),
      ),
    );
  }

  void _navigateToSystemHealthCheck() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SystemHealthCheckPage(),
      ),
    );
  }

  void _navigateToUserManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UserManagementWidget(),
      ),
    );
  }

  void _navigateToCdnManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CdnManagementPage(),
      ),
    );
  }

  void _navigateToAliyunResourceManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AliyunResourceManagementPage(),
      ),
    );
  }

  void _navigateToFeatureRequestManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeatureRequestManagementWidget(),
      ),
    );
  }

  void _navigateToFeatureRequestReportManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeatureRequestReportManagementWidget(),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 功能开发中...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.watch<DarkMode>().isDarkMode 
            ? const Color(0xFF121212) 
            : const Color(0xFFF8F9FA),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_currentUser == null || _currentUser!.isAdmin != true) {
      return _buildNoPermissionPage();
    }

    return _buildAdminContent();
  }
}
