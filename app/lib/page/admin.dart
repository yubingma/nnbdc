import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  UserVo? _currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkAdminPermission();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.feedback),
              text: '意见建议',
            ),
            Tab(
              icon: Icon(Icons.book),
              text: '系统词典',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeedbackManagementTab(),
          _buildDictionaryManagementTab(),
        ],
      ),
    );
  }

  Widget _buildFeedbackManagementTab() {
    return const FeedbackManagementWidget();
  }

  Widget _buildDictionaryManagementTab() {
    return const DictionaryManagementWidget();
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

// 意见建议管理组件
class FeedbackManagementWidget extends StatefulWidget {
  const FeedbackManagementWidget({super.key});

  @override
  State<FeedbackManagementWidget> createState() => _FeedbackManagementWidgetState();
}

class _FeedbackManagementWidgetState extends State<FeedbackManagementWidget> {
  List<MsgVo> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await Api.client.getAllAdviceMessages();
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Container(
      color: backgroundColor,
      child: _messages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.feedback_outlined,
                    size: 64,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无意见建议',
                    style: TextStyle(
                      fontSize: 18,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageCard(message);
              },
            ),
    );
  }

  Widget _buildMessageCard(MsgVo message) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDarkMode 
                ? Colors.black.withValues(alpha: 0.3) 
                : Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primaryColor,
                child:                     Text(
                      _getUserInitial(message),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.fromUser.nickName ?? 
                      message.fromUserNickName ?? 
                      message.fromUserName ?? 
                      '未知用户',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      message.createTime.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message.content,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _replyToMessage(message),
                icon: const Icon(Icons.reply, size: 16),
                label: const Text('回复'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _replyToMessage(MsgVo message) {
    // 实现回复功能
    showDialog(
      context: context,
      builder: (context) => _ReplyDialog(message: message),
    );
  }

  String _getUserInitial(MsgVo message) {
    final nickName = message.fromUser.nickName;
    final userNickName = message.fromUserNickName;
    final userName = message.fromUserName;
    
    if (nickName != null && nickName.isNotEmpty) {
      return nickName.substring(0, 1).toUpperCase();
    } else if (userNickName != null && userNickName.isNotEmpty) {
      return userNickName.substring(0, 1).toUpperCase();
    } else if (userName != null && userName.isNotEmpty) {
      return userName.substring(0, 1).toUpperCase();
    } else {
      return 'U';
    }
  }
}

// 回复对话框
class _ReplyDialog extends StatefulWidget {
  final MsgVo message;

  const _ReplyDialog({required this.message});

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return AlertDialog(
      backgroundColor: backgroundColor,
      title: Text(
        '回复用户',
        style: TextStyle(color: textColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '原消息：',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.message.content,
              style: TextStyle(color: textColor),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '回复内容：',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _replyController,
            maxLines: 4,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: '请输入回复内容...',
              hintStyle: TextStyle(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _isSending ? null : _sendReply,
          child: _isSending 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发送'),
        ),
      ],
    );
  }

  Future<void> _sendReply() async {
    if (_replyController.text.trim().isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final result = await Api.client.replyAdvice(
        _replyController.text.trim(),
        widget.message.fromUser.id ?? '',
        Global.getLoggedInUser()?.id ?? '',
      );
      
      if (result.success && mounted) {
        Navigator.pop(context);
        // 刷新消息列表
        if (context.mounted) {
          // 通知父组件刷新
          final parentState = context.findAncestorStateOfType<_FeedbackManagementWidgetState>();
          parentState?._loadMessages();
        }
      }
    } catch (e) {
      // 处理错误
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('回复失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }
}

// 系统词典管理组件
class DictionaryManagementWidget extends StatefulWidget {
  const DictionaryManagementWidget({super.key});

  @override
  State<DictionaryManagementWidget> createState() => _DictionaryManagementWidgetState();
}

class _DictionaryManagementWidgetState extends State<DictionaryManagementWidget> {
  bool _isLoading = true;
  List<DictVo> _dictionaries = [];

  @override
  void initState() {
    super.initState();
    _loadDictionaryData();
  }

  Future<void> _loadDictionaryData() async {
    try {
      // 这里需要实现获取系统词典列表的API
      // 暂时使用空列表
      setState(() {
        _dictionaries = [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Container(
      color: backgroundColor,
      child: _dictionaries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 64,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无系统词典',
                    style: TextStyle(
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '系统词典管理功能开发中...',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _dictionaries.length,
              itemBuilder: (context, index) {
                final dict = _dictionaries[index];
                return _buildDictionaryCard(dict);
              },
            ),
    );
  }

  Widget _buildDictionaryCard(DictVo dict) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDarkMode 
                ? Colors.black.withValues(alpha: 0.3) 
                : Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.book,
                color: AppTheme.primaryColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dict.name ?? '未知词典',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: textColor,
                      ),
                    ),
                    if (dict.name != null && dict.name!.isNotEmpty)
                      Text(
                        '词典ID: ${dict.id}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ID: ${dict.id}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _editDictionary(dict),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('编辑'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _viewDictionaryDetails(dict),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('查看'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _editDictionary(DictVo dict) {
    // 实现编辑词典功能
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('编辑词典: ${dict.name}')),
    );
  }

  void _viewDictionaryDetails(DictVo dict) {
    // 实现查看词典详情功能
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('查看词典详情: ${dict.name}')),
    );
  }
}
