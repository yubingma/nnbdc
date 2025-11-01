import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

// 用户管理组件
class UserManagementWidget extends StatefulWidget {
  const UserManagementWidget({super.key});

  @override
  State<UserManagementWidget> createState() => _UserManagementWidgetState();
}

class _UserManagementWidgetState extends State<UserManagementWidget> {
  bool _isLoading = true;
  List<UserVo> _users = [];
  int _currentPage = 1;
  final int _pageSize = 20;
  int _total = 0;
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilter = 0; // 0: 全部, 1: 管理员, 2: 超级管理员, 3: 录入员

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool resetPage = false}) async {
    if (resetPage) {
      setState(() {
        _currentPage = 1;
      });
    }

    try {
      // 禁用API的自动loading，使用页面自己的loading
      final result = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.searchUsers(
          _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          _currentPage,
          _pageSize,
          _selectedFilter,
        );
      });

      if (result.success && result.data != null) {
        setState(() {
          _users = result.data!.rows;
          _total = result.data!.total;
          _isLoading = false;
        });
      } else {
        setState(() {
          _users = [];
          _total = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _users = [];
        _total = 0;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    // 搜索防抖处理，实际项目中可以使用debounce
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _searchController.text == _searchController.text) {
        _loadUsers(resetPage: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          '用户管理',
          textScaler: TextScaler.linear(1.0),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选选项卡
          Container(
            height: 50,
            color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: _buildFilterTab('全部', 0),
                ),
                Expanded(
                  child: _buildFilterTab('管理员', 1),
                ),
                Expanded(
                  child: _buildFilterTab('超级管理员', 2),
                ),
                Expanded(
                  child: _buildFilterTab('录入员', 3),
                ),
              ],
            ),
          ),
          // 搜索框
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
              decoration: InputDecoration(
                hintText: '搜索用户（用户名、昵称、邮箱）...',
                hintStyle: TextStyle(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontFamily: 'NotoSansSC',
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[50],
              ),
            ),
          ),
          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _total == 0 ? '暂无用户数据' : '未找到匹配的用户',
                              textScaler: const TextScaler.linear(1.0),
                              style: TextStyle(
                                fontSize: 18,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // 用户列表
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _users.length,
                              itemBuilder: (context, index) {
                                final user = _users[index];
                                return _buildUserCard(user);
                              },
                            ),
                          ),
                          // 分页控制器
                          _buildPagination(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(UserVo user) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.15),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
          child: Text(
            user.nickName?.substring(0, 1).toUpperCase() ?? user.userName?.substring(0, 1).toUpperCase() ?? 'U',
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          user.nickName ?? user.userName ?? '未知用户',
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: textColor,
            fontFamily: 'NotoSansSC',
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '用户名: ${user.userName ?? "N/A"}',
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                fontFamily: 'NotoSansSC',
              ),
            ),
            if (user.email != null && user.email!.isNotEmpty)
              Text(
                '邮箱: ${user.email}',
                textScaler: const TextScaler.linear(1.0),
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontFamily: 'NotoSansSC',
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (user.isAdmin == true)
                  _buildBadge('管理员', Colors.blue),
                if (user.isSuperAdmin == true)
                  _buildBadge('超级管理员', Colors.purple),
                if (user.isInputor == true)
                  _buildBadge('录入员', Colors.green),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          onPressed: () => _editUserPermission(user),
          icon: Icon(
            Icons.settings,
            size: 24,
            color: AppTheme.primaryColor,
          ),
          tooltip: '设置权限',
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'NotoSansSC',
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, int filterIndex) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final isSelected = _selectedFilter == filterIndex;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = filterIndex;
        });
        _loadUsers(resetPage: true);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            color: isSelected
                ? AppTheme.primaryColor
                : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final totalPages = (_total / _pageSize).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1 ? () => _loadPage(_currentPage - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '第 $_currentPage 页 / 共 $totalPages 页',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontFamily: 'NotoSansSC',
            ),
          ),
          IconButton(
            onPressed: _currentPage < totalPages ? () => _loadPage(_currentPage + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _loadPage(int page) {
    setState(() {
      _currentPage = page;
    });
    _loadUsers();
  }

  void _editUserPermission(UserVo user) {
    showDialog(
      context: context,
      builder: (context) => _EditPermissionDialog(
        user: user,
        onPermissionUpdated: () {
          _loadUsers(); // 重新加载用户列表
        },
      ),
    );
  }
}

// 编辑权限对话框
class _EditPermissionDialog extends StatefulWidget {
  final UserVo user;
  final VoidCallback onPermissionUpdated;

  const _EditPermissionDialog({
    required this.user,
    required this.onPermissionUpdated,
  });

  @override
  State<_EditPermissionDialog> createState() => _EditPermissionDialogState();
}

class _EditPermissionDialogState extends State<_EditPermissionDialog> {
  late bool _isAdmin;
  late bool _isSuperAdmin;
  late bool _isInputor;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isAdmin = widget.user.isAdmin ?? false;
    _isSuperAdmin = widget.user.isSuperAdmin ?? false;
    _isInputor = widget.user.isInputor ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return AlertDialog(
      backgroundColor: backgroundColor,
      title: Text(
        '设置用户权限',
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          color: textColor,
          fontFamily: 'NotoSansSC',
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '用户: ${widget.user.nickName ?? widget.user.userName ?? "未知"}',
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text(
                '管理员',
                textScaler: TextScaler.linear(1.0),
              ),
              subtitle: const Text(
                '具有管理员权限，可以管理系统',
                textScaler: TextScaler.linear(1.0),
              ),
              value: _isAdmin,
              onChanged: (value) {
                setState(() {
                  _isAdmin = value;
                });
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text(
                '超级管理员',
                textScaler: TextScaler.linear(1.0),
              ),
              subtitle: const Text(
                '具有超级管理员权限',
                textScaler: TextScaler.linear(1.0),
              ),
              value: _isSuperAdmin,
              onChanged: (value) {
                setState(() {
                  _isSuperAdmin = value;
                });
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text(
                '录入员',
                textScaler: TextScaler.linear(1.0),
              ),
              subtitle: const Text(
                '具有录入员权限，可以录入数据',
                textScaler: TextScaler.linear(1.0),
              ),
              value: _isInputor,
              onChanged: (value) {
                setState(() {
                  _isInputor = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text(
            '取消',
            textScaler: TextScaler.linear(1.0),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _savePermission,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  '保存',
                  textScaler: TextScaler.linear(1.0),
                ),
        ),
      ],
    );
  }

  Future<void> _savePermission() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 调用更新权限的API
      final result = await Api.client.updateAdminPermission(
        widget.user.id!,
        _isAdmin,
        _isSuperAdmin,
        _isInputor,
      );

      if (result.success) {
        if (mounted) {
          Navigator.pop(context);
          widget.onPermissionUpdated();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              '权限更新成功',
              textScaler: TextScaler.linear(1.0),
            )),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              '更新失败: ${result.msg ?? "未知错误"}',
              textScaler: const TextScaler.linear(1.0),
            )),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            '更新失败: $e',
            textScaler: const TextScaler.linear(1.0),
          )),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

