import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/page/admin/feedback_management.dart';
import 'package:nnbdc/page/admin/dictionary_management.dart';

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
        title: '管理页面',
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
        title: const Text('管理页面'),
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
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0,
        children: [
          _buildManagementCard(
            title: '意见建议',
            subtitle: '查看用户反馈',
            icon: Icons.feedback,
            color: const Color(0xFF4CAF50),
            onTap: () => _navigateToFeedback(),
          ),
          _buildManagementCard(
            title: '系统词典',
            subtitle: '管理词典资源',
            icon: Icons.book,
            color: const Color(0xFF2196F3),
            onTap: () => _navigateToDictionary(),
          ),
          _buildManagementCard(
            title: '用户管理',
            subtitle: '管理用户账户',
            icon: Icons.people,
            color: const Color(0xFFFF9800),
            onTap: () => _showComingSoon('用户管理'),
          ),
          _buildManagementCard(
            title: '系统设置',
            subtitle: '配置系统参数',
            icon: Icons.settings,
            color: const Color(0xFF9C27B0),
            onTap: () => _showComingSoon('系统设置'),
          ),
          _buildManagementCard(
            title: '数据统计',
            subtitle: '查看使用统计',
            icon: Icons.analytics,
            color: const Color(0xFF00BCD4),
            onTap: () => _showComingSoon('数据统计'),
          ),
          _buildManagementCard(
            title: '日志管理',
            subtitle: '查看系统日志',
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
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Card(
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textScaler: const TextScaler.linear(1.0),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textScaler: const TextScaler.linear(1.0),
                style: TextStyle(
                  fontSize: 11,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontFamily: 'NotoSansSC',
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
