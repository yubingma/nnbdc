import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/advice_content.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/permission_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:permission_handler/permission_handler.dart';

/// 意见建议管理的三个视角。
///
/// 会话列表是「按用户组织」的导航页：一个用户一行，把同一个人的聊天内容收在一起；
/// 需求列表是消息级需求的待办页（需求贴在具体某条消息上，不贴在会话上）；
/// 会话详情才是聊天本身，长按任意一条消息可以引用回复或标为需求。
enum _AdviceView { sessions, requirements, detail }

/// 需求列表里的一张卡片。两个来源用同一个模型承载，靠 isFromWall 区分点击后去哪。
class _RequirementItem {
  final String id;
  final String title;
  final String body;
  final String statusKey;
  final int voteCount;

  /// true = 用户在需求墙发的需求（feature_request），去需求墙管理处理；
  /// false = 管理员在客服会话里标记的消息级需求，回到那条消息上看。
  final bool isFromWall;
  final String userId;
  final String nickName;
  final DateTime createTime;

  _RequirementItem({
    required this.id,
    required this.title,
    required this.body,
    required this.statusKey,
    required this.voteCount,
    required this.isFromWall,
    required this.userId,
    required this.nickName,
    required this.createTime,
  });

  /// 卡片上要显示的那段话：需求墙有用户自己写的标题，客服会话就是原话
  String get displayText => title.isNotEmpty ? title : AdviceContent.preview(body, maxLength: 80);
}

// 意见建议管理组件
class FeedbackManagementWidget extends StatefulWidget {
  const FeedbackManagementWidget({super.key});

  @override
  State<FeedbackManagementWidget> createState() => _FeedbackManagementWidgetState();
}

class _FeedbackManagementWidgetState extends State<FeedbackManagementWidget> {
  _AdviceView _view = _AdviceView.sessions;

  // ---- 会话列表 ----
  List<AdviceSessionVo> _sessions = [];
  bool _isLoadingSessions = true;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _membershipFilter = "all"; // all, premium, normal, requirement

  // ---- 需求列表 ----
  List<_RequirementItem> _requirements = [];
  bool _isLoadingRequirements = true;
  String _requirementStatusFilter = 'VOTING';

  // ---- 会话详情 ----
  AdviceSessionVo? _currentSession;
  List<MsgVo> _conversation = [];
  bool _isLoadingConversation = true;
  bool _isSending = false;
  MsgVo? _quotedMessage;
  MsgVo? _highlightMessage;
  ScrollController? _detailScrollController;
  final TextEditingController _replyController = TextEditingController();
  final Map<String, GlobalKey> _messageKeys = {};
  final List<AdviceImageAttachment> _pendingImages = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _replyController.dispose();
    _detailScrollController?.dispose();
    super.dispose();
  }

  String? get _adminUserId => Global.getLoggedInUser()?.id;

  bool get _isAdmin => Global.getLoggedInUser()?.isAdmin == true;

  // ==================== 取数 ====================

  Future<void> _loadSessions() async {
    if (mounted) setState(() => _isLoadingSessions = true);
    try {
      final sessions = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getAdviceSessions(limit: 200);
      });
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoadingSessions = false;
      });
    } catch (e) {
      Global.logger.e('加载客服会话失败', error: e);
      if (mounted) setState(() => _isLoadingSessions = false);
    }
  }

  Future<void> _loadRequirements() async {
    if (mounted) setState(() => _isLoadingRequirements = true);
    try {
      // 客服会话里被标记为需求的消息
      final result = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getAdviceRequirements();
      });
      // 需求墙上的需求，一屏看两边
      final wallRequests = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getAllFeatureRequests();
      });

      final items = <_RequirementItem>[];
      if (result.success && result.data != null) {
        for (final requirement in result.data!) {
          items.add(_RequirementItem(
            id: requirement.id,
            title: '',
            body: requirement.content,
            statusKey: requirement.reqStatus ?? 'VOTING',
            voteCount: 0,
            isFromWall: false,
            userId: requirement.userId,
            nickName: requirement.nickName ?? requirement.userName ?? '未知用户',
            createTime: requirement.createTime,
          ));
        }
      } else if (!result.success) {
        ToastUtil.error(result.msg ?? '加载会话需求失败');
      }

      for (final request in wallRequests) {
        items.add(_RequirementItem(
          id: request.id,
          title: request.title ?? '',
          body: request.content ?? '',
          statusKey: request.status ?? 'VOTING',
          voteCount: request.voteCount ?? 0,
          isFromWall: true,
          userId: request.creator?.id ?? '',
          nickName: request.creator?.nickName ?? request.creator?.userName ?? '未知用户',
          createTime: request.createTime,
        ));
      }

      items.sort((a, b) => b.createTime.compareTo(a.createTime));

      if (!mounted) return;
      setState(() {
        _requirements = items;
        _isLoadingRequirements = false;
      });
    } catch (e) {
      Global.logger.e('加载需求列表失败', error: e);
      if (mounted) setState(() => _isLoadingRequirements = false);
    }
  }

  /// 加载某条会话的聊天记录。
  ///
  /// [locateTo] 是要落到的目标消息（从需求待办点进来时用）：目标可能在 200 条里的较远处，
  /// 那时它还没被列表构建出来，找不到它的位置。所以先按它在列表里的序号估一个初始滚动位置，
  /// 等它渲染出来之后再精确对齐一次。
  Future<void> _loadConversation(AdviceSessionVo session, {String? locateTo}) async {
    if (mounted) {
      setState(() {
        _isLoadingConversation = true;
        _currentSession = session;
        _quotedMessage = null;
        _highlightMessage = null;
      });
    }

    try {
      // 一次多拉一些历史，从需求待办点回来时才有机会落到那条较早的消息上
      final messages = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getLastestMsgsBetweenUserAndSys(session.userId, 200);
      });
      messages.sort((a, b) => a.createTime.compareTo(b.createTime));

      final targetIndex = locateTo == null
          ? -1
          : messages.indexWhere((message) => message.id == locateTo);

      // 按序号估算初始位置，让目标项先被构建出来
      _detailScrollController?.dispose();
      _detailScrollController = ScrollController(
        initialScrollOffset: targetIndex <= 0 ? 0 : targetIndex * _estimatedMessageHeight,
      );

      if (!mounted) return;
      setState(() {
        _conversation = messages;
        _isLoadingConversation = false;
        _messageKeys.clear();
        _highlightMessage = targetIndex >= 0 ? messages[targetIndex] : null;
      });

      if (locateTo != null && targetIndex < 0) {
        ToastUtil.info('这条需求对应的是较早的消息，未在最近 200 条内，请向上翻找');
      }

      await _markConversationAsViewed();

      if (targetIndex >= 0) {
        _scrollToMessage(messageId: locateTo!);
        _clearHighlightLater();
      } else {
        _scrollToBottom();
      }
    } catch (e) {
      Global.logger.e('加载会话记录失败', error: e);
      if (mounted) setState(() => _isLoadingConversation = false);
    }
  }

  /// 一条消息在列表里的粗略高度，只用来估初始滚动位置
  static const double _estimatedMessageHeight = 76;

  /// 从会话列表进某个会话
  Future<void> _openConversation(AdviceSessionVo session) async {
    setState(() {
      _view = _AdviceView.detail;
      _pendingImages.clear();
    });
    await _loadConversation(session);
  }

  /// 从需求待办点回某条被标记为需求的消息
  Future<void> _locateMessage(String userId, String nickName, String messageId) async {
    final session = _sessions.firstWhere(
      (s) => s.userId == userId,
      // 会话列表可能因为筛选或条数上限没有这个人，用需求卡片上的信息兜一个最小会话
      orElse: () => AdviceSessionVo(userId, null, nickName, null, false, 0, 0, 1, null, null, null),
    );

    setState(() {
      _view = _AdviceView.detail;
      _pendingImages.clear();
    });
    await _loadConversation(session, locateTo: messageId);
  }

  void _clearHighlightLater() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightMessage = null);
    });
  }

  // ==================== 已读 ====================

  Future<void> _markConversationAsViewed() async {
    final ids = _conversation
        .where((m) => m.toUser.id == Global.sysUserId && !m.viewed)
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;

    try {
      await Api.client.setMsgsAsViewed(ids, Global.sysUserId);
      if (!mounted) return;
      // 只改本地状态：这次会话的未读已经清零，用户会话列表等返回列表时再统一刷新，
      // 免得每打开一次会话就重拉一遍整张列表，界面闪一下
      setState(() {
        for (final message in _conversation) {
          if (ids.contains(message.id)) message.viewed = true;
        }
        final session = _currentSession;
        if (session != null) session.unviewedCount = 0;
      });
    } catch (e) {
      // 标记已读失败不阻断对话展示，但要在日志里留痕
      Global.logger.e('标记会话已读失败', error: e);
    }
  }

  // ==================== 滚动定位 ====================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _detailScrollController;
      if (controller == null || !controller.hasClients) return;
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 把被定位的那条消息滚到屏幕可见处。此时它已经因为初始偏移量被构建出来了。
  void _scrollToMessage({required String messageId}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _detailScrollController;
      final keyContext = _messageKeys[messageId]?.currentContext;
      if (controller == null || keyContext == null || !controller.hasClients) return;

      final box = keyContext.findRenderObject() as RenderBox?;
      if (box == null) return;

      final target = controller.offset + box.localToGlobal(Offset.zero).dy - 120;
      controller.animateTo(
        target.clamp(0.0, controller.position.maxScrollExtent),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // ==================== 写操作 ====================

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if ((text.isEmpty && _pendingImages.isEmpty) || _isSending) return;

    final session = _currentSession;
    final adminUserId = _adminUserId;
    if (session == null || adminUserId == null) return;

    setState(() => _isSending = true);
    try {
      final imagePaths = _pendingImages
          .map((image) => image.uploadedPath)
          .whereType<String>()
          .toList();
      // 只发截图、没打字时给一句占位正文，服务端不允许空内容。
      // 图片标记由服务端统一拼装，客户端只把图片路径交上去。
      final content = text.isEmpty ? AdviceContent.screenshotOnlyText : text;

      final result = await Api.client.replyAdvice(
        content,
        session.userId,
        adminUserId,
        replyToId: _quotedMessage?.id,
        imageFiles: imagePaths.isEmpty ? null : jsonEncode(imagePaths),
      );

      if (!mounted) return;
      if (result.success) {
        _replyController.clear();
        setState(() {
          _pendingImages.clear();
          _quotedMessage = null;
        });
        await _loadConversation(session);
      } else {
        ToastUtil.error(result.msg ?? '回复失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('回复失败: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickReplyImages() async {
    final session = _currentSession;
    final userId = _adminUserId;
    if (session == null || userId == null || _isSending) return;

    final source = await AdviceImages.pickSource(context);
    if (source == null || !mounted) return;

    await PermissionUtil.requestWithRationale(
      permission: source == ImageSource.camera ? Permission.camera : Permission.photos,
      title: source == ImageSource.camera ? '相机权限' : '相册/存储权限',
      purpose: source == ImageSource.camera ? '用于拍下问题现场发给用户。' : '用于把手机里的截图发给用户。',
      icon: source == ImageSource.camera ? Icons.camera_alt_rounded : Icons.photo_library_rounded,
      onGranted: () => _uploadReplyImages(userId, source),
    );
  }

  Future<void> _uploadReplyImages(String userId, ImageSource source) async {
    try {
      final picked = await AdviceImages.pickAndUpload(
        context: context,
        userId: userId,
        source: source,
        baseline: _pendingImages,
      );
      if (picked.isEmpty || !mounted) return;
      setState(() => _pendingImages.addAll(picked));
    } catch (e) {
      if (mounted) ToastUtil.error(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _toggleRequirementTag(MsgVo message) async {
    if (!_isAdmin) {
      ToastUtil.error('权限不足');
      return;
    }
    final adminUserId = _adminUserId;
    if (adminUserId == null) return;

    final isRequirement = message.tag == '需求';
    try {
      final res = await Api.client.setMsgTag(message.id, isRequirement ? null : '需求', adminUserId);
      if (!mounted) return;
      if (res.success) {
        setState(() => message.tag = isRequirement ? null : '需求');
        ToastUtil.success(isRequirement ? '已取消需求标记' : '已标记为需求');
        await _loadRequirements();
      } else {
        ToastUtil.error(res.msg ?? '操作失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('打标失败: $e');
    }
  }

  Future<void> _updateRequirementStatus(MsgVo message, String status) async {
    final adminUserId = _adminUserId;
    if (adminUserId == null) return;

    try {
      final res = await Api.client.updateRequirementStatus(message.id, status, adminUserId);
      if (!mounted) return;
      if (res.success) {
        setState(() => message.reqStatus = status);
        ToastUtil.success('需求状态已更新');
        await _loadRequirements();
      } else {
        ToastUtil.error(res.msg ?? '更新失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('更新失败: $e');
    }
  }

  Future<void> _togglePremium(String userId, bool isPremium) async {
    try {
      final result = await Api.client.updatePremiumOverride(
        userId,
        !isPremium,
        '管理员在意见反馈页手动设置',
        null, // null 表示永久
      );
      if (!mounted) return;
      if (result.success) {
        ToastUtil.success('操作成功');
        final session = _currentSession;
        if (session != null && session.userId == userId) {
          setState(() => session.premium = !isPremium);
        }
        await _loadSessions();
      } else {
        ToastUtil.error(result.msg ?? '操作失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('操作失败: $e');
    }
  }

  Future<void> _deleteMessage(MsgVo message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除该条消息吗？此操作不可撤销。如果它已经被回复引用，需要先删除引用它的回复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final userId = _adminUserId ?? "";
    try {
      final result = await LoadingUtils.withApiLoading(operation: () async {
        return await Api.client.deleteMsg(message.id, userId);
      });
      if (!mounted) return;
      if (result.success) {
        ToastUtil.success('删除成功');
        final session = _currentSession;
        if (session == null) return;
        await _loadConversation(session);
        await _loadSessions();
      } else {
        ToastUtil.error(result.msg ?? '删除失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('删除失败: $e');
    }
  }

  Future<void> _cleanupOldAdvice() async {
    final daysController = TextEditingController(text: "30");
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理旧反馈'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要删除指定天数以前的意见建议吗？此操作不可撤销。'),
            const SizedBox(height: 8),
            Text(
              '（提示：被标记为「需求」的消息、以及已经被回复引用的消息都会自动保留）',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
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
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final days = int.tryParse(daysController.text);
    if (days == null || days <= 0) {
      ToastUtil.error('请输入有效的正整数');
      return;
    }

    try {
      final result = await Api.client.cleanupOldAdvice(days, _adminUserId ?? "");
      if (!mounted) return;
      if (result.success) {
        ToastUtil.success('成功清理了 ${result.data} 条旧反馈');
        await _loadSessions();
      } else {
        ToastUtil.error(result.msg ?? '清理失败');
      }
    } catch (e) {
      if (mounted) ToastUtil.error('清理过程中出现错误: $e');
    }
  }

  /// 长按某条消息弹出的操作菜单。引用回复、标为需求、改需求状态、删除都收在这里。
  Future<void> _showMessageActions(MsgVo message) async {
    final isFromUser = message.msgType == 'Advice';
    final theme = context.themeConfig;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isFromUser)
                ListTile(
                  leading: Icon(Icons.reply_rounded, color: context.primaryColor),
                  title: const Text('引用回复这条'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => _quotedMessage = message);
                  },
                ),
              if (isFromUser)
                ListTile(
                  leading: Icon(
                    message.tag == '需求' ? Icons.lightbulb : Icons.lightbulb_outline,
                    color: const Color(0xFFF59E0B),
                  ),
                  title: Text(message.tag == '需求' ? '取消需求标记' : '标为需求'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _toggleRequirementTag(message);
                  },
                ),
              if (message.tag == '需求')
                ListTile(
                  leading: const Icon(Icons.flag_rounded, color: Color(0xFF3B82F6)),
                  title: const Text('设置需求状态'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showRequirementStatusSheet(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('删除这条消息', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteMessage(message);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRequirementStatusSheet(MsgVo message) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('设置需求状态', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final status in FeatureRequestStatus.values)
              ListTile(
                title: Text(status.description),
                trailing: message.reqStatus == status.json
                    ? Icon(Icons.check_rounded, color: context.primaryColor)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _updateRequirementStatus(message, status.json);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ==================== 界面 ====================

  @override
  Widget build(BuildContext context) {
    if (_view == _AdviceView.detail) return _buildDetailPage();

    final isSessions = _view == _AdviceView.sessions;
    return AppScaffold(
      appBar: AppAppBar(
        title: isSessions ? '意见建议' : '需求',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: isSessions
            ? [
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
                  onPressed: _loadSessions,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: '刷新',
                ),
              ]
            : [
                IconButton(
                  onPressed: _loadRequirements,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: '刷新',
                ),
              ],
      ),
      body: Column(
        children: [
          _buildViewSwitcher(),
          if (isSessions && _isSearching) _buildSearchBar(),
          if (isSessions) _buildMembershipFilter() else _buildRequirementStatusFilter(),
          Expanded(child: isSessions ? _buildSessionList() : _buildRequirementList()),
        ],
      ),
    );
  }

  /// 「按用户会话」与「需求待办」两个视角的切换
  Widget _buildViewSwitcher() {
    final isDarkMode = context.isDarkMode;
    final segments = <(String, _AdviceView)>[
      ('按用户会话', _AdviceView.sessions),
      ('需求待办', _AdviceView.requirements),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: segments.map((segment) {
          final selected = _view == segment.$2;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: () {
                setState(() => _view = segment.$2);
                if (segment.$2 == _AdviceView.requirements && _requirements.isEmpty) {
                  _loadRequirements();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? context.primaryColor.withValues(alpha: isDarkMode ? 0.25 : 0.14)
                      : (isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected
                        ? context.primaryColor.withValues(alpha: 0.6)
                        : (isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
                  ),
                ),
                child: Text(
                  segment.$1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? context.primaryColor : (isDarkMode ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDarkMode = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: context.primaryColor.withValues(alpha: 0.1),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: '搜索昵称、账号、会话内容...',
          hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
          prefixIcon: Icon(Icons.search, color: context.primaryColor),
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          filled: true,
          fillColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
      ),
    );
  }

  Widget _buildMembershipFilter() {
    final isDarkMode = context.isDarkMode;
    final withRequirement = _sessions.where((s) => s.requirementCount > 0).length;

    return Container(
      width: double.infinity,
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _buildFilterChip('全部', 'all'),
            const SizedBox(width: 8),
            _buildFilterChip(withRequirement > 0 ? '💡 含需求 ($withRequirement)' : '💡 含需求', 'requirement'),
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
    final isDarkMode = context.isDarkMode;
    final activeColor = value == 'requirement' ? const Color(0xFFF59E0B) : context.primaryColor;

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
      onSelected: (_) => setState(() => _membershipFilter = value),
      selectedColor: activeColor,
      backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? activeColor : (isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
          width: 0.5,
        ),
      ),
    );
  }

  Widget _buildRequirementStatusFilter() {
    final statuses = <(String, String)>[
      ('VOTING', '投票中'),
      ('IN_PROGRESS', '开发中'),
      ('REJECTED', '已拒绝'),
      ('COMPLETED', '已完成'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: statuses.map((status) {
          final selected = _requirementStatusFilter == status.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: () => setState(() => _requirementStatusFilter = status.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: selected ? context.primaryColor.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected ? context.primaryColor.withValues(alpha: 0.5) : context.themeConfig.cardBorder,
                  ),
                ),
                child: Text(
                  status.$2,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? context.primaryColor : context.themeConfig.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ==================== 会话列表 ====================

  List<AdviceSessionVo> get _filteredSessions {
    return _sessions.where((session) {
      if (_membershipFilter == 'requirement' && session.requirementCount == 0) return false;
      if (_membershipFilter == 'premium' && session.premium != true) return false;
      if (_membershipFilter == 'normal' && session.premium == true) return false;

      if (_searchQuery.isEmpty) return true;
      final haystack = [
        session.nickName ?? '',
        session.userName ?? '',
        session.lastContent ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(_searchQuery);
    }).toList();
  }

  Widget _buildSessionList() {
    if (_isLoadingSessions) return const Center(child: CircularProgressIndicator());

    final sessions = _filteredSessions;
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: context.themeConfig.textMuted),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isEmpty ? '暂无用户反馈' : '未找到匹配的会话',
              style: TextStyle(fontSize: 15, color: context.themeConfig.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: sessions.length,
      itemBuilder: (context, index) => _buildSessionCard(sessions[index]),
    );
  }

  Widget _buildSessionCard(AdviceSessionVo session) {
    final isDarkMode = context.isDarkMode;
    final theme = context.themeConfig;
    final hasUnread = session.unviewedCount > 0;
    final preview = AdviceContent.preview(session.lastContent ?? '');
    final isAdminLast = session.lastMsgType == 'AdviceReply';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openConversation(session),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasUnread ? context.primaryColor.withValues(alpha: 0.45) : theme.cardBorder,
            width: hasUnread ? 1.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDarkMode ? Colors.black.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(session.wechatAvatar, session.nickName ?? session.userName ?? 'U', radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          session.nickName ?? session.userName ?? '未知用户',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: theme.textPrimary,
                          ),
                        ),
                      ),
                      if (session.premium == true) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 15, color: Color(0xFF2196F3)),
                      ],
                      if (session.requirementCount > 0) ...[
                        const SizedBox(width: 6),
                        _buildBadge('需求 ${session.requirementCount}', const Color(0xFFF59E0B)),
                      ],
                      const Spacer(),
                      if (session.lastCreateTime != null)
                        Text(
                          _formatTime(session.lastCreateTime!),
                          style: TextStyle(fontSize: 11.5, color: theme.textMuted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAdminLast ? '已回复：$preview' : (preview.isEmpty ? '（无内容）' : preview),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: theme.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (hasUnread) _buildUnreadBadge(session.unviewedCount),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '共 ${session.totalCount} 条',
                    style: TextStyle(fontSize: 11.5, color: theme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildUnreadBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
    return isToday ? DateFormat('HH:mm').format(local) : DateFormat('MM-dd HH:mm').format(local);
  }

  // ==================== 需求列表 ====================

  Widget _buildRequirementList() {
    if (_isLoadingRequirements) return const Center(child: CircularProgressIndicator());

    final items = _requirements.where((item) => item.statusKey == _requirementStatusFilter).toList();
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lightbulb_outline, size: 56, color: context.themeConfig.textMuted),
            const SizedBox(height: 12),
            Text('这个状态下没有需求', style: TextStyle(fontSize: 15, color: context.themeConfig.textMuted)),
            const SizedBox(height: 6),
            Text(
              '在会话详情里长按用户的消息即可标为需求',
              style: TextStyle(fontSize: 12.5, color: context.themeConfig.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildRequirementCard(items[index]),
    );
  }

  Widget _buildRequirementCard(_RequirementItem item) {
    final theme = context.themeConfig;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openRequirement(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildBadge(item.isFromWall ? '需求墙' : '客服会话', const Color(0xFF3B82F6)),
                const SizedBox(width: 6),
                _buildBadge(FeatureRequestStatusExt.fromString(item.statusKey).description, const Color(0xFF8B5CF6)),
                if (item.isFromWall && item.voteCount > 0) ...[
                  const SizedBox(width: 6),
                  _buildBadge('${item.voteCount} 票', const Color(0xFFF97316)),
                ],
                const Spacer(),
                Text(_formatTime(item.createTime), style: TextStyle(fontSize: 11.5, color: theme.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.displayText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.textPrimary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline, size: 13, color: theme.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.nickName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: theme.textMuted),
                  ),
                ),
                Text(
                  item.isFromWall ? '去需求墙处理 ›' : '回到那条消息 ›',
                  style: TextStyle(fontSize: 12, color: context.primaryColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRequirement(_RequirementItem item) async {
    if (item.isFromWall) {
      // 需求墙的需求有自己的状态流转页面，这里只看一眼，不改它的状态
      _showFeatureRequestDetail(item);
      return;
    }
    await _locateMessage(item.userId, item.nickName, item.id);
  }

  void _showFeatureRequestDetail(_RequirementItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.title.isEmpty ? '需求' : item.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.body.isEmpty ? '（无详细描述）' : item.body),
              const SizedBox(height: 12),
              Text(
                '这条来自需求墙，请在「需求墙管理」里改状态与查看投票。',
                style: TextStyle(fontSize: 12, color: context.themeConfig.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('知道了')),
        ],
      ),
    );
  }

  // ==================== 会话详情 ====================

  Widget _buildDetailPage() {
    final theme = context.themeConfig;

    return AppScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: theme.textPrimary,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            setState(() {
              _view = _AdviceView.sessions;
              _quotedMessage = null;
              _highlightMessage = null;
              _pendingImages.clear();
            });
            _loadSessions();
          },
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: theme.textPrimary),
        ),
        title: Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: theme.textPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '与 ${_currentSession?.nickName ?? _currentSession?.userName ?? '用户'} 的对话',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.textPrimary),
              ),
            ),
          ],
        ),
        actions: [
          if (_currentSession != null)
            IconButton(
              onPressed: () => _togglePremium(_currentSession!.userId, _currentSession!.premium),
              icon: Icon(
                _currentSession!.premium == true ? Icons.verified : Icons.verified_outlined,
                color: _currentSession!.premium == true ? const Color(0xFF2196F3) : null,
              ),
              tooltip: _currentSession!.premium == true ? '已是永久会员' : '设为永久会员',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingConversation
                ? const Center(child: CircularProgressIndicator())
                : _buildConversationList(),
          ),
          _buildReplyInput(),
        ],
      ),
    );
  }

  Widget _buildConversationList() {
    if (_conversation.isEmpty) {
      return Center(child: Text('暂无聊天记录', style: TextStyle(color: context.themeConfig.textMuted)));
    }

    return ListView.builder(
      controller: _detailScrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _conversation.length,
      itemBuilder: (context, index) {
        final message = _conversation[index];
        _messageKeys.putIfAbsent(message.id, () => GlobalKey());
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(MsgVo message) {
    final theme = context.themeConfig;
    final isDarkMode = context.isDarkMode;
    final isAdminMessage = message.msgType == 'AdviceReply';
    final isHighlighted = _highlightMessage?.id == message.id;

    return Container(
      key: _messageKeys[message.id],
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(4),
      decoration: isHighlighted
          ? BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
            )
          : null,
      child: Row(
        mainAxisAlignment: isAdminMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isAdminMessage) ...[
            _buildAvatar(message.fromUser.wechatAvatar, message.fromUser.nickName ?? 'U', radius: 16),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showMessageActions(message),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isAdminMessage ? context.primaryColor : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.quotedMsgId != null) _buildQuoteBlock(message, isAdminMessage: isAdminMessage),
                    _buildMessageContent(message, isAdminMessage: isAdminMessage),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.tag == '需求') ...[
                          _buildBadge(
                            FeatureRequestStatusExt.fromString(message.reqStatus ?? 'VOTING').description,
                            const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(message.createTime.toLocal()),
                          style: TextStyle(
                            fontSize: 10,
                            color: isAdminMessage ? Colors.white70 : theme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isAdminMessage) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey,
              child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageContent(MsgVo message, {required bool isAdminMessage}) {
    final textColor = isAdminMessage ? Colors.white : context.themeConfig.textPrimary;
    final text = AdviceContent.text(message.content);
    final images = AdviceContent.imageFiles(message.content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (text.isNotEmpty) Text(text, style: TextStyle(color: textColor, fontSize: 14, height: 1.4)),
        if (images.isNotEmpty) ...[
          if (text.isNotEmpty) const SizedBox(height: 6),
          _buildMessageImages(images),
        ],
      ],
    );
  }

  Widget _buildQuoteBlock(MsgVo message, {required bool isAdminMessage}) {
    final quoted = AdviceContent.preview(message.quotedContent ?? '', maxLength: 60);
    final color = isAdminMessage ? Colors.white : context.themeConfig.textPrimary;
    final speaker = message.quotedMsgType == 'AdviceReply' ? '客服' : '用户';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color.withValues(alpha: 0.4), width: 2)),
      ),
      child: Text(
        quoted.isEmpty ? '原消息已删除' : '$speaker：$quoted',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
      ),
    );
  }

  Widget _buildMessageImages(List<String> imageFiles) {
    final isDarkMode = context.isDarkMode;
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: imageFiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final url = AdviceContent.imageUrl(imageFiles[index]);
          return GestureDetector(
            onTap: () => _showImagePreview(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 140,
                color: isDarkMode ? const Color(0xFF2A333D) : Colors.white.withValues(alpha: 0.5),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 18),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  Widget _buildReplyInput() {
    final theme = context.themeConfig;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: theme.cardBg,
        border: Border(top: BorderSide(color: theme.cardBorder, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImages.isNotEmpty) ...[
              _buildPendingImagesRow(),
              const SizedBox(height: 6),
            ],
            if (_quotedMessage != null) _buildQuotedReplyBar(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: _isSending ? null : _pickReplyImages,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.cardBorder),
                    ),
                    child: Icon(Icons.add_photo_alternate_outlined, size: 20, color: theme.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(color: theme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _quotedMessage == null ? '回复这个用户...' : '回复选中的那条消息...',
                      hintStyle: TextStyle(color: theme.textMuted, fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: theme.cardBorder),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending
                    ? const SizedBox(
                        width: 42,
                        height: 42,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : GestureDetector(
                        onTap: _sendReply,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: context.primaryColor, shape: BoxShape.circle),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotedReplyBar() {
    final quoted = AdviceContent.preview(_quotedMessage?.content ?? '', maxLength: 50);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 15, color: context.primaryColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '正在回复：$quoted',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: context.themeConfig.textSecondary),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _quotedMessage = null),
            child: Icon(Icons.close_rounded, size: 16, color: context.themeConfig.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingImagesRow() {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = _pendingImages[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(image.bytes, width: 60, height: 60, fit: BoxFit.cover),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(index)),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(Icons.close_rounded, size: 11, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAvatar(String? url, String name, {required double radius}) {
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: CachedNetworkImageProvider(url));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.primaryColor,
      child: Text(
        Util.getInitial(name),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
