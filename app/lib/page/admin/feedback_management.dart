import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

// 意见建议管理组件
class FeedbackManagementWidget extends StatefulWidget {
  const FeedbackManagementWidget({super.key});

  @override
  State<FeedbackManagementWidget> createState() => _FeedbackManagementWidgetState();
}

class _FeedbackManagementWidgetState extends State<FeedbackManagementWidget> {
  List<MsgVo> _messages = [];
  bool _isLoading = true;
  Map<String, int> _clientTypeStats = {};

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      // 禁用API的自动loading，使用页面自己的loading
      final messages = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getAllAdviceMessages();
      });
      
      final stats = <String, int>{};
      
      // 统计客户端类型分布
      for (final message in messages) {
        if (message.clientType != null) {
          stats[message.clientType!] = (stats[message.clientType!] ?? 0) + 1;
        }
      }
      
      setState(() {
        _messages = messages;
        _clientTypeStats = stats;
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

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('意见建议管理'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _loadMessages,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _messages.isEmpty
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
              : Column(
                  children: [
                    // 客户端类型统计
                    if (_clientTypeStats.isNotEmpty) _buildClientTypeStats(),
                    // 消息列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return _buildMessageCard(message);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMessageCard(MsgVo message) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primaryColor,
                child: Text(
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
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(message.createTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        if (message.clientType != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _getClientTypeColor(message.clientType!).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _getClientTypeColor(message.clientType!).withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              _getClientTypeIcon(message.clientType!),
                              size: 14,
                              color: _getClientTypeColor(message.clientType!),
                            ),
                          ),
                        ],
                      ],
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

  Widget _buildClientTypeStats() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.all(16),
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
                Icons.analytics,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '客户端类型统计',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _clientTypeStats.entries.map((entry) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getClientTypeColor(entry.key).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getClientTypeColor(entry.key).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getClientTypeIcon(entry.key),
                      size: 14,
                      color: _getClientTypeColor(entry.key),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getClientTypeDisplayName(entry.key),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getClientTypeColor(entry.key),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getClientTypeColor(entry.key),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${entry.value}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
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

  String _getClientTypeDisplayName(String clientType) {
    switch (clientType) {
      case 'browser':
        return '浏览器';
      case 'android':
        return '安卓';
      case 'ios':
        return 'iOS';
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      case 'jmeter':
        return 'JMeter';
      default:
        return clientType;
    }
  }

  Color _getClientTypeColor(String clientType) {
    switch (clientType) {
      case 'browser':
        return const Color(0xFF4CAF50); // 绿色 - 浏览器
      case 'android':
        return const Color(0xFF3DDC84); // 安卓绿
      case 'ios':
        return const Color(0xFF007AFF); // iOS蓝
      case 'windows':
        return const Color(0xFF0078D4); // Windows蓝
      case 'macos':
        return const Color(0xFF8E8E93); // macOS灰
      case 'linux':
        return const Color(0xFFFF6B35); // Linux橙
      case 'jmeter':
        return const Color(0xFF9C27B0); // 紫色
      default:
        return AppTheme.primaryColor;
    }
  }

  IconData _getClientTypeIcon(String clientType) {
    switch (clientType) {
      case 'browser':
        return Icons.web;
      case 'android':
        return Icons.android;
      case 'ios':
        return Icons.phone_iphone;
      case 'windows':
        return Icons.laptop_windows;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.terminal;
      case 'jmeter':
        return Icons.speed;
      default:
        return Icons.device_unknown;
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
  List<MsgVo> _conversationHistory = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadConversationHistory();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadConversationHistory() async {
    try {
      // 获取该用户与系统的所有消息历史
      final messages = await Api.client.getLastestMsgsBetweenUserAndSys(
        widget.message.fromUser.id ?? '', 
        50  // 获取最近50条消息
      );
      
      setState(() {
        _conversationHistory = messages;
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
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Row(
          children: [
            const Icon(Icons.chat_bubble_outline),
            const SizedBox(width: 8),
            Text(
              '与 ${widget.message.fromUser.nickName ?? widget.message.fromUser.userName} 的对话',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 聊天记录区域
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse: false, // 最新的消息在顶部
                    padding: const EdgeInsets.all(16),
                    itemCount: _conversationHistory.length,
                    itemBuilder: (context, index) {
                      final msg = _conversationHistory[index];
                      // 判断是否为管理员消息：消息类型为adviceReply（管理员回复）
                      final isAdminMessage = msg.msgType == 'AdviceReply';
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: isAdminMessage 
                              ? MainAxisAlignment.end 
                              : MainAxisAlignment.start,
                          children: [
                            if (!isAdminMessage) ...[
                              // 用户头像
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.primaryColor,
                                child: Text(
                                  _getUserInitial(msg),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 用户消息气泡
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        msg.content,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('yyyy-MM-dd HH:mm').format(msg.createTime),
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ] else ...[
                              // 管理员消息气泡
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        msg.content,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('yyyy-MM-dd HH:mm').format(msg.createTime),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 管理员头像
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.grey[600],
                                child: const Icon(
                                  Icons.admin_panel_settings,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // 输入区域
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: '输入回复内容...',
                      hintStyle: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppTheme.gradientStartColor,
                        AppTheme.gradientEndColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _isSending ? null : _sendReply,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        _replyController.clear();
        // 重新加载对话历史
        await _loadConversationHistory();
        // 通知父组件刷新
        if (mounted) {
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
