import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

String _resolveImgUrl(String path) {
  if (path.contains('/')) return '${Config.imgBaseUrl}$path';
  return '${Config.imgBaseUrl}word/$path';
}

// 意见建议管理组件
class FeedbackManagementWidget extends StatefulWidget {
  const FeedbackManagementWidget({super.key});

  @override
  State<FeedbackManagementWidget> createState() => _FeedbackManagementWidgetState();
}

class _FeedbackManagementWidgetState extends State<FeedbackManagementWidget> {
  List<MsgVo> _messages = [];
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  Map<String, int> _clientTypeStats = {};
  bool _isMarkingViewed = false;
  bool _isSearching = false;
  String _membershipFilter = "all"; // all, premium, normal

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  List<String> _parseImageFiles(String content) {
    const marker = '【报错图片】';
    final idx = content.indexOf(marker);
    if (idx == -1) return const [];
    final jsonPart = content.substring(idx + marker.length).trim();
    try {
      final parsed = jsonDecode(jsonPart);
      if (parsed is List) {
        return parsed.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 从内容中提取文本部分和图片列表。
  /// 支持两种标记：
  ///   【报错图片】["a.jpg"] — 新格式，直接解析图片
  ///   【报错ID】uuid — 旧格式，只剥离标记，不解析图片
  (String, List<String>) _extractContentAndImages(String content) {
    const imgMarker = '【报错图片】';
    final imgIdx = content.indexOf(imgMarker);
    if (imgIdx != -1) {
      return (
        content.substring(0, imgIdx).trim(),
        _parseImageFiles(content),
      );
    }
    const idMarker = '【报错ID】';
    final idIdx = content.indexOf(idMarker);
    if (idIdx != -1) {
      return (content.substring(0, idIdx).trim(), const <String>[]);
    }
    return (content, const <String>[]);
  }

  Widget _buildMessageContent(String content, Color textColor) {
    final (textPart, imageFiles) = _extractContentAndImages(content);
    if (textPart == content && imageFiles.isEmpty) {
      return Text(content, style: TextStyle(color: textColor, fontSize: 16));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (textPart.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(textPart, style: TextStyle(color: textColor, fontSize: 16)),
          ),
        if (imageFiles.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('截图 (${imageFiles.length}张):',
                    style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.6))),
                const SizedBox(height: 6),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: imageFiles.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () => _showImagePreview(context,
                            _resolveImgUrl(imageFiles[index])),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _resolveImgUrl(imageFiles[index]),
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 120,
                              height: 120,
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey[100],
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cleanupOldAdvice() async {
    final TextEditingController daysController = TextEditingController(text: "30");
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理旧反馈'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要删除指定天数以前的意见建议吗？此操作不可撤销。'),
            const SizedBox(height: 16),
            TextField(
              controller: daysController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '删除多少天以前的？',
                suffixText: '天',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final int? days = int.tryParse(daysController.text);
      if (days == null || days <= 0) {
        ToastUtil.error('请输入有效的正整数');
        return;
      }

      try {
        final userId = Global.getLoggedInUser()?.id ?? "";
        final result = await Api.client.cleanupOldAdvice(days, userId);

        if (result.success) {
          ToastUtil.success('成功清理了 ${result.data} 条旧反馈');
          _loadMessages();
        } else {
          ToastUtil.error(result.msg ?? '清理失败');
        }
      } catch (e) {
        ToastUtil.error('清理过程中出现错误: $e');
      }
    }
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

      // 未读优先，其次按时间倒序
      messages.sort((a, b) {
        if (a.viewed != b.viewed) {
          return a.viewed ? 1 : -1; // 未读在前
        }
        return b.createTime.compareTo(a.createTime); // 新的在前
      });

      setState(() {
        _messages = messages;
        _clientTypeStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markMsgsAsViewed(List<String> msgIds) async {
    if (msgIds.isEmpty) return;
    if (_isMarkingViewed) return;

    setState(() {
      _isMarkingViewed = true;
    });

    try {
      // advice 消息通常是发给系统用户（Global.sysUserId）
      await Api.client.setMsgsAsViewed(msgIds, Global.sysUserId);

      // 本地立即更新状态，避免刷新前 UI 不一致
      final idSet = msgIds.toSet();
      setState(() {
        _messages = _messages
            .map((m) => idSet.contains(m.id)
                ? MsgVo(
                    m.id,
                    m.fromUserName,
                    m.fromUserNickName,
                    m.toUserName,
                    m.toUserNickName,
                    m.content,
                    m.createTimeForDisplay,
                    m.msgType,
                    m.clientType,
                    m.fromUser,
                    m.toUser,
                    m.createTime,
                    true,
                  )
                : m)
            .toList();
      });
    } catch (e) {
      // 标记已读失败不阻塞主流程，避免打断管理员处理
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingViewed = false;
        });
      }
    }
  }

  Widget _buildViewedBadge(MsgVo message) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final bool isViewed = message.viewed;
    final Color bg = isViewed ? (isDarkMode ? Colors.grey[700]! : Colors.grey[200]!) : const Color(0xFFFFEBEE);
    final Color fg = isViewed ? (isDarkMode ? Colors.white70 : Colors.black54) : const Color(0xFFD32F2F);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isViewed ? (isDarkMode ? Colors.grey[600]! : Colors.grey[300]!) : const Color(0xFFFFCDD2),
        ),
      ),
      child: Text(
        isViewed ? '已读' : '未读',
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = "";
                  _searchController.clear();
                }
              });
            },
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
            tooltip: '搜索',
          ),
          IconButton(
            onPressed: _cleanupOldAdvice,
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            tooltip: '清理旧反馈',
          ),
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
              : SelectionArea(
                  child: Column(
                    children: [
                      // 搜索栏
                      if (_isSearching) _buildSearchBar(),
                      // 筛选栏（会员/非会员）
                      _buildFilterTabs(),
                      // 客户端类型统计
                      if (_clientTypeStats.isNotEmpty && !_isSearching && _membershipFilter == "all") _buildClientTypeStats(),
                      // 消息列表
                      Expanded(
                        child: _buildMessageList(),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFilterTabs() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      width: double.infinity,
      color: backgroundColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildFilterChip('全部', 'all'),
            const SizedBox(width: 8),
            _buildFilterChip('永久会员', 'premium'),
            const SizedBox(width: 8),
            _buildFilterChip('普通用户', 'normal'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _membershipFilter == value;
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black87),
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _membershipFilter = value;
        });
      },
      selectedColor: AppTheme.primaryColor,
      backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppTheme.primaryColor : (isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
          width: 0.5,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.primaryColor.withValues(alpha: 0.1),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: '搜索昵称、用户、内容...',
          hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
          prefixIcon: Icon(Icons.search, color: AppTheme.primaryColor),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = "";
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  Widget _buildMessageList() {
    final filtered = _messages.where((m) {
      // 1. 会员状态筛选
      if (_membershipFilter != 'all') {
        final bool isPremium = m.fromUser.premiumOverrideEnabled == true;
        if (_membershipFilter == 'premium' && !isPremium) return false;
        if (_membershipFilter == 'normal' && isPremium) return false;
      }

      // 2. 全文搜索筛选
      if (_searchQuery.isEmpty) return true;

      // 准备所有可见字段的搜索字符串
      final visibleStrings = <String>[];
      visibleStrings.add(m.content);
      visibleStrings.add(m.fromUser.nickName ?? "");
      visibleStrings.add(m.fromUser.userName ?? "");
      visibleStrings.add(m.fromUser.email ?? "");
      visibleStrings.add(m.fromUserNickName ?? "");
      visibleStrings.add(m.fromUserName ?? "");

      // 加上可见的客户端类型名
      if (m.clientType != null) {
        visibleStrings.add(_getClientTypeDisplayName(m.clientType!));
      }

      // 加上可见的状态名
      visibleStrings.add(m.viewed ? '已读' : '未读');

      // 加上日期字符串
      visibleStrings.add(DateFormat('yyyy-MM-dd HH:mm').format(m.createTime.toLocal()));

      // 拼接成一个大字符串，检查是否包含搜索词
      final fullText = visibleStrings.join(' ').toLowerCase();

      return fullText.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Text(
          '未找到匹配的内容',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final message = filtered[index];
        return _buildMessageCard(message);
      },
    );
  }

  Widget _buildMessageCard(MsgVo message) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        // 点开即视为管理员已读（先标记，再打开对话）
        if (!message.viewed) {
          await _markMsgsAsViewed([message.id]);
        }
        if (mounted) {
          _replyToMessage(message);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.15),
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
                        Row(
                          children: [
                            Text(
                              message.fromUser.nickName ?? message.fromUserNickName ?? message.fromUserName ?? '未知用户',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            if (message.fromUser.premiumOverrideEnabled == true) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified, size: 16, color: Color(0xFF2196F3)),
                            ],
                          ],
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
                              DateFormat('yyyy-MM-dd HH:mm').format(message.createTime.toLocal()),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildViewedBadge(message),
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
              _buildMessageContent(message.content, textColor),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _deleteMessage(message),
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                      label: const Text(
                        '删除',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _setAsPermanentMemberForUser(message.fromUser),
                      icon: Icon(
                        message.fromUser.premiumOverrideEnabled == true ? Icons.star : Icons.star_border,
                        size: 16,
                        color: message.fromUser.premiumOverrideEnabled == true ? const Color(0xFF2196F3) : Colors.grey[600],
                      ),
                      label: Text(
                        message.fromUser.premiumOverrideEnabled == true ? '已是会员' : '设为会员',
                        style: TextStyle(
                          color: message.fromUser.premiumOverrideEnabled == true ? const Color(0xFF2196F3) : Colors.grey[600],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        if (!message.viewed) {
                          await _markMsgsAsViewed([message.id]);
                        }
                        if (mounted) {
                          _replyToMessage(message);
                        }
                      },
                      icon: const Icon(Icons.reply, size: 16),
                      label: const Text('回复'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMessage(MsgVo message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除该条反馈消息吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userId = Global.getLoggedInUser()?.id ?? "";
      final result = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.deleteMsg(message.id, userId);
      });

      if (result.success) {
        ToastUtil.success('删除成功');
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
          if (message.clientType != null && _clientTypeStats.containsKey(message.clientType)) {
            final current = _clientTypeStats[message.clientType!] ?? 0;
            if (current <= 1) {
              _clientTypeStats.remove(message.clientType!);
            } else {
              _clientTypeStats[message.clientType!] = current - 1;
            }
          }
        });
      } else {
        ToastUtil.error(result.msg ?? '删除失败');
      }
    } catch (e) {
      ToastUtil.error('删除失败: $e');
    }
  }

  void _showImagePreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _replyToMessage(MsgVo message) async {
    await showDialog(
      context: context,
      builder: (context) => _ReplyDialog(
        message: message,
        onMessageDeleted: () => _loadMessages(),
      ),
    );
    if (mounted) {
      _loadMessages();
    }
  }

  Future<void> _setAsPermanentMemberForUser(UserVo user) async {
    final bool isAlreadyPremium = user.premiumOverrideEnabled == true;

    try {
      final result = await Api.client.updatePremiumOverride(
        user.id ?? '',
        !isAlreadyPremium,
        '管理员在意见反馈页手动设置',
        null, // null 表示永久
      );

      if (result.success && mounted) {
        ToastUtil.success('操作成功');
        setState(() {
          user.premiumOverrideEnabled = !isAlreadyPremium;
          user.premiumOverrideDuration = null;
        });
      } else {
        ToastUtil.error(result.msg ?? '操作失败');
      }
    } catch (e) {
      ToastUtil.error('操作失败: $e');
    }
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
            color: isDarkMode ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1),
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

    if (nickName != null && nickName.trim().isNotEmpty) {
      return Util.getInitial(nickName);
    } else if (userNickName != null && userNickName.trim().isNotEmpty) {
      return Util.getInitial(userNickName);
    } else if (userName != null && userName.trim().isNotEmpty) {
      return Util.getInitial(userName);
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
  final VoidCallback? onMessageDeleted;

  const _ReplyDialog({required this.message, this.onMessageDeleted});

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final TextEditingController _replyController = TextEditingController();
  List<MsgVo> _conversationHistory = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isSettingPremium = false;
  bool _isMarkingViewed = false;

  @override
  void initState() {
    super.initState();
    _loadConversationHistory();
  }

  List<String> _dialogParseImageFiles(String content) {
    const marker = '【报错图片】';
    final idx = content.indexOf(marker);
    if (idx == -1) return const [];
    final jsonPart = content.substring(idx + marker.length).trim();
    try {
      final parsed = jsonDecode(jsonPart);
      if (parsed is List) {
        return parsed.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  Widget _buildDialogContent(String content, Color textColor, bool isAdmin) {
    String textPart;
    List<String> imageFiles;

    const imgMarker = '【报错图片】';
    final imgIdx = content.indexOf(imgMarker);
    if (imgIdx != -1) {
      textPart = content.substring(0, imgIdx).trim();
      imageFiles = _dialogParseImageFiles(content);
    } else {
      const idMarker = '【报错ID】';
      final idIdx = content.indexOf(idMarker);
      if (idIdx != -1) {
        textPart = content.substring(0, idIdx).trim();
        imageFiles = const [];
      } else {
        return Text(content, style: TextStyle(color: textColor, fontSize: 14));
      }
    }

    return Column(
      crossAxisAlignment: isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (textPart.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(textPart, style: TextStyle(color: textColor, fontSize: 14)),
          ),
        if (imageFiles.isNotEmpty) ...[
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imageFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final url = _resolveImgUrl(imageFiles[index]);
                return GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: InteractiveViewer(
                          child: Image.network(url, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 100,
                      height: 100,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey[100],
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    },
                  ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadConversationHistory() async {
    try {
      // 获取该用户与系统的所有消息历史
      final messages = await Api.client.getLastestMsgsBetweenUserAndSys(widget.message.fromUser.id ?? '', 50);

      if (mounted) {
        setState(() {
          _conversationHistory = messages;
          _isLoading = false;
        });
      }

      await _markConversationAdviceAsViewed(messages);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markConversationAdviceAsViewed(List<MsgVo> messages) async {
    if (_isMarkingViewed) return;
    
    // 找出所有发给系统的未读消息
    final ids = messages
        .where((m) => m.toUser.id == Global.sysUserId && !m.viewed)
        .map((m) => m.id)
        .toList();
        
    if (ids.isEmpty) return;

    setState(() {
      _isMarkingViewed = true;
    });

    try {
      await Api.client.setMsgsAsViewed(ids, Global.sysUserId);
      if (mounted) {
        setState(() {
          _conversationHistory = _conversationHistory.map((m) {
            if (ids.contains(m.id)) {
              return MsgVo(
                m.id,
                m.fromUserName,
                m.fromUserNickName,
                m.toUserName,
                m.toUserNickName,
                m.content,
                m.createTimeForDisplay,
                m.msgType,
                m.clientType,
                m.fromUser,
                m.toUser,
                m.createTime,
                true,
              );
            }
            return m;
          }).toList();
        });
      }
    } catch (_) {
      // 忽略：不影响对话展示
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingViewed = false;
        });
      }
    }
  }

  Future<void> _setAsPermanentMember() async {
    final user = widget.message.fromUser;
    final bool isAlreadyPremium = user.premiumOverrideEnabled == true;

    setState(() {
      _isSettingPremium = true;
    });

    try {
      final result = await Api.client.updatePremiumOverride(
        user.id ?? '',
        !isAlreadyPremium,
        '管理员在意见反馈页手动设置',
        null, // null 表示永久
      );

      if (result.success && mounted) {
        ToastUtil.success('操作成功');
        setState(() {
          user.premiumOverrideEnabled = !isAlreadyPremium;
          user.premiumOverrideDuration = null;
        });
        // 刷新父页面消息列表，确保同步状态
        final parentState = context.findAncestorStateOfType<_FeedbackManagementWidgetState>();
        parentState?._loadMessages();
      } else {
        ToastUtil.error(result.msg ?? '操作失败');
      }
    } catch (e) {
      ToastUtil.error('操作失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSettingPremium = false;
        });
      }
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
            Expanded(
              child: Text(
                '与 ${widget.message.fromUser.nickName ?? widget.message.fromUser.userName} 的对话',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_isSettingPremium)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              onPressed: _setAsPermanentMember,
              icon: Icon(
                widget.message.fromUser.premiumOverrideEnabled == true ? Icons.verified : Icons.verified_outlined,
                color: widget.message.fromUser.premiumOverrideEnabled == true ? const Color(0xFF2196F3) : null,
              ),
              tooltip: widget.message.fromUser.premiumOverrideEnabled == true ? '已是永久会员' : '设为永久会员',
            ),
        ],
      ),
      body: SelectionArea(
        child: Column(
          children: [
            // 聊天记录区域
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _conversationHistory.length,
                      itemBuilder: (context, index) {
                        final msg = _conversationHistory[index];
                        final isAdminMessage = msg.msgType == 'AdviceReply';

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: isAdminMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildDialogContent(msg.content, textColor, false),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              DateFormat('yyyy-MM-dd HH:mm').format(msg.createTime.toLocal()),
                                              style: TextStyle(
                                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                                fontSize: 10,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap: () => _deleteConversationMessage(msg),
                                              borderRadius: BorderRadius.circular(8),
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(
                                                  Icons.delete_outline,
                                                  size: 13,
                                                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ] else ...[
                                // 管理员消息气泡
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        _buildDialogContent(msg.content, Colors.white, true),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () => _deleteConversationMessage(msg),
                                              borderRadius: BorderRadius.circular(8),
                                              child: const Padding(
                                                padding: EdgeInsets.all(2),
                                                child: Icon(
                                                  Icons.delete_outline,
                                                  size: 13,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              DateFormat('yyyy-MM-dd HH:mm').format(msg.createTime.toLocal()),
                                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                                            ),
                                          ],
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
                                  child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 16),
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
                        hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _isSending
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.gradientStartColor, AppTheme.gradientEndColor],
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: _sendReply,
                              child: Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final result = await Api.client.replyAdvice(
        text,
        widget.message.fromUser.id ?? '',
        Global.getLoggedInUser()?.id ?? '',
      );

      if (result.success && mounted) {
        _replyController.clear();
        await _loadConversationHistory();
        if (mounted) {
          final parentState = context.findAncestorStateOfType<_FeedbackManagementWidgetState>();
          parentState?._loadMessages();
        }
      } else {
        ToastUtil.error(result.msg ?? '回复失败');
      }
    } catch (e) {
      ToastUtil.error('回复失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _deleteConversationMessage(MsgVo msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除此条消息吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userId = Global.getLoggedInUser()?.id ?? "";
      final result = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.deleteMsg(msg.id, userId);
      });

      if (result.success) {
        ToastUtil.success('删除成功');
        setState(() {
          _conversationHistory.removeWhere((m) => m.id == msg.id);
        });
        widget.onMessageDeleted?.call();
      } else {
        ToastUtil.error(result.msg ?? '删除失败');
      }
    } catch (e) {
      ToastUtil.error('删除失败: $e');
    }
  }

  String _getUserInitial(MsgVo message) {
    final nickName = message.fromUser.nickName;
    final userNickName = message.fromUserNickName;
    final userName = message.fromUserName;

    if (nickName != null && nickName.trim().isNotEmpty) {
      return Util.getInitial(nickName);
    } else if (userNickName != null && userNickName.trim().isNotEmpty) {
      return Util.getInitial(userNickName);
    } else if (userName != null && userName.trim().isNotEmpty) {
      return Util.getInitial(userName);
    } else {
      return 'U';
    }
  }
}
