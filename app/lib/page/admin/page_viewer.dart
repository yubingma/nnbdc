import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

/// 页面查看器 - 方便开发时快速跳转到指定页面
class PageViewerPage extends StatefulWidget {
  const PageViewerPage({super.key});

  @override
  State<PageViewerPage> createState() => _PageViewerPageState();
}

class _PageViewerPageState extends State<PageViewerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 定义所有可用的页面路由和描述
  final List<PageRouteInfo> _routes = [
    PageRouteInfo('/test', '测试页面', Icons.bug_report),
    PageRouteInfo('/first', '首次启动页', Icons.first_page),
    PageRouteInfo('/login', '登录页', Icons.login),
    PageRouteInfo('/email_login', '邮箱登录页', Icons.mail_outline),
    PageRouteInfo('/index', '主页（词表）', Icons.home),
    PageRouteInfo('/protocol', '用户协议', Icons.description),
    PageRouteInfo('/privacy', '隐私政策', Icons.privacy_tip),
    PageRouteInfo('/pic_search', '图片搜索', Icons.image_search),
    PageRouteInfo('/select_book', '选择词书', Icons.menu_book),
    PageRouteInfo('/word_list', '单词列表', Icons.list),
    PageRouteInfo('/walkman', '随身听', Icons.headphones),
    PageRouteInfo('/game', '游戏', Icons.games),
    PageRouteInfo('/russia', '俄罗斯方块', Icons.grid_on),
    PageRouteInfo('/word_detail', '单词详情', Icons.info),
    PageRouteInfo('/bdc', '背单词页', Icons.book),
    PageRouteInfo('/finish', '完成页', Icons.check_circle),
    PageRouteInfo('/farm', '我的小天地', Icons.eco),
    PageRouteInfo('/word_lists', '单词列表集合', Icons.view_list),
    PageRouteInfo('/msg', '消息页', Icons.message),
    PageRouteInfo('/search', '搜索页', Icons.search),
    PageRouteInfo('/ai_activation', 'AI 助教', Icons.psychology),
    PageRouteInfo('/ai_diagnostic', 'AI 诊断', Icons.healing),
    PageRouteInfo('/study_stats', '学习统计', Icons.analytics),
    PageRouteInfo('/reminder_settings', '学习提醒设置', Icons.notifications_active),
    PageRouteInfo('/golden_master', '黄金母版工具', Icons.auto_fix_high),
    PageRouteInfo('/admin', '系统管理', Icons.admin_panel_settings),
  ];

  List<PageRouteInfo> get _filteredRoutes {
    if (_searchQuery.isEmpty) {
      return _routes;
    }
    return _routes
        .where((route) =>
            route.route.toLowerCase().contains(_searchQuery.toLowerCase()) || route.description.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToPage(String route) {
    try {
      // 如果是finish页面，传递标志表示从页面查看器进入，避免触发打卡
      if (route == '/finish') {
        context.push(route, extra: {'fromPageViewer': true});
      } else {
        context.push(route);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('跳转失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          '页面查看器',
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
      body: Column(
        children: [
          // 搜索框
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索页面...',
                hintStyle: TextStyle(
                  color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
              ),
              style: TextStyle(color: textColor),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          // 页面列表
          Expanded(
            child: _filteredRoutes.isEmpty
                ? Center(
                    child: Text(
                      '未找到匹配的页面',
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredRoutes.length,
                    itemBuilder: (context, index) {
                      final route = _filteredRoutes[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: cardColor,
                        elevation: isDarkMode ? 0 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              route.icon,
                              color: AppTheme.primaryColor,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            route.description,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          subtitle: Text(
                            route.route,
                            style: TextStyle(
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                          onTap: () => _navigateToPage(route.route),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class PageRouteInfo {
  final String route;
  final String description;
  final IconData icon;

  PageRouteInfo(this.route, this.description, this.icon);
}
