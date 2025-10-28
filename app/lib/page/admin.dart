import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/page/admin/feedback_management.dart';
import 'package:nnbdc/page/admin/dictionary_management.dart';
import 'package:nnbdc/page/admin/system_health_check.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool _isLoading = true;
  UserVo? _currentUser;

  @override
  void initState() {
    super.initState();
    _checkAdminPermission();
  }

  Future<void> _checkAdminPermission() async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null || !user.isAdmin) {
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
                fontWeight: FontWeight.bold,
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
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
        children: [
          _buildManagementCard(
            title: '意见建议',
            icon: Icons.feedback,
            color: const Color(0xFF4CAF50),
            onTap: () => _navigateToFeedback(),
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
            onTap: () => _showComingSoon('用户管理'),
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
        ],
      ),
    );
  }

  Widget _buildManagementCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
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
            Icon(
              icon,
              size: 44,
              color: color,
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

  void _navigateToFeedback() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FeedbackManagementWidget(),
      ),
    );
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
