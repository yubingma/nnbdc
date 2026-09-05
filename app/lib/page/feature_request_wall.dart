import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/app_scaffold.dart';

class FeatureRequestWallPage extends StatefulWidget {
  const FeatureRequestWallPage({super.key});

  @override
  State<StatefulWidget> createState() => _FeatureRequestWallPageState();
}

class _FeatureRequestWallPageState extends State<FeatureRequestWallPage> with SingleTickerProviderStateMixin {
  List<FeatureRequestVo> _requests = [];
  bool _isLoading = true;
  final Map<String, bool> _votedStatus = {};
  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    try {
      final requests = await LoadingUtils.withoutApiLoading(() async {
        return await Api.client.getAllFeatureRequests();
      });

      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      Global.logger.e('加载需求列表失败', error: e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _voteRequest(FeatureRequestVo request) async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        ToastUtil.info('请先登录');
        return;
      }

      final result = await Api.client.voteFeatureRequest(request.id, user.id);
      if (result.success) {
        setState(() {
          request.voteCount = (request.voteCount ?? 0) + 1;
          _votedStatus[request.id] = true;
        });
        ToastUtil.success('投票成功');
      } else {
        ToastUtil.error(result.msg ?? '投票失败');
      }
    } catch (e) {
      ToastUtil.error('投票失败');
    }
  }

  void _showReportDialog(FeatureRequestVo request) {
    final contentController = TextEditingController();
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              decoration: BoxDecoration(
                color: theme.cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.cardBorder, width: 0.8),
                boxShadow: theme.cardShadows,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.flag_rounded,
                          color: Color(0xFFEF4444),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '举报需求',
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '若内容涉嫌违规或广告，请向我们反馈',
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.subtleBg.withValues(alpha: isDark ? 0.3 : 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.cardBorder, width: 0.6),
                    ),
                    child: Text(
                      '需求：${request.title ?? ''}',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.subtleBg.withValues(alpha: isDark ? 0.35 : 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.cardBorder, width: 0.8),
                    ),
                    child: TextField(
                      controller: contentController,
                      style: TextStyle(color: theme.textPrimary, fontSize: 13.5),
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: '请详细填写举报原因...',
                        hintStyle: TextStyle(
                          color: theme.textMuted,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                                side: BorderSide(color: theme.cardBorder, width: 0.8),
                              ),
                            ),
                            child: const Text('取消', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: ElevatedButton(
                            onPressed: () async {
                              final content = contentController.text.trim();
                              if (content.isEmpty) {
                                ToastUtil.info('请填写举报原因');
                                return;
                              }

                              final user = Global.getLoggedInUser();
                              if (user == null) {
                                ToastUtil.info('请先登录');
                                return;
                              }

                              try {
                                final result = await Api.client.saveFeatureRequestReport(request.id, content, user.id);
                                if (!context.mounted) return;
                                if (result.success) {
                                  ToastUtil.success('举报成功');
                                  Navigator.pop(dialogContext);
                                } else {
                                  ToastUtil.error(result.msg ?? '举报失败');
                                }
                              } catch (e) {
                                if (!context.mounted) return;
                                ToastUtil.error('举报失败');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.22 : 0.12),
                              foregroundColor: const Color(0xFFEF4444),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              side: BorderSide(
                                color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.40 : 0.25),
                                width: 0.8,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                            ),
                            child: const Text('确认举报', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              decoration: BoxDecoration(
                color: theme.cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.cardBorder, width: 0.8),
                boxShadow: theme.cardShadows,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: theme.primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '提交新需求',
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '分享你的构想，获高赞需求将优先开发',
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.subtleBg.withValues(alpha: isDark ? 0.35 : 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.cardBorder, width: 0.8),
                    ),
                    child: TextField(
                      controller: titleController,
                      style: TextStyle(color: theme.textPrimary, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: '需求标题，如：单词列表支持乱序播放',
                        hintStyle: TextStyle(
                          color: theme.textMuted,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.subtleBg.withValues(alpha: isDark ? 0.35 : 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.cardBorder, width: 0.8),
                    ),
                    child: TextField(
                      controller: contentController,
                      style: TextStyle(color: theme.textPrimary, fontSize: 13.5),
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: '详细描述这个功能的使用场景和你的具体构想...',
                        hintStyle: TextStyle(
                          color: theme.textMuted,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.textSecondary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                                side: BorderSide(color: theme.cardBorder, width: 0.8),
                              ),
                            ),
                            child: const Text('取消', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: ElevatedButton(
                            onPressed: () async {
                              final title = titleController.text.trim();
                              final content = contentController.text.trim();
                              if (title.isEmpty || content.isEmpty) {
                                ToastUtil.info('请填写完整信息');
                                return;
                              }

                              final user = Global.getLoggedInUser();
                              if (user == null) {
                                ToastUtil.info('请先登录');
                                return;
                              }

                              try {
                                final result = await Api.client.createFeatureRequest(title, content, user.id);
                                if (!context.mounted) return;
                                if (result.success && result.data != null) {
                                  ToastUtil.success('提交成功');
                                  Navigator.pop(dialogContext);
                                  _loadRequests();
                                } else {
                                  ToastUtil.error(result.msg ?? '提交失败');
                                }
                              } catch (e) {
                                if (!context.mounted) return;
                                ToastUtil.error('提交失败');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                            ),
                            child: const Text('提交需求', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<FeatureRequestVo> _getFilteredRequests() {
    String targetStatus;
    switch (_currentTabIndex) {
      case 0:
        targetStatus = 'VOTING';
        break;
      case 1:
        targetStatus = 'IN_PROGRESS';
        break;
      case 2:
        targetStatus = 'REJECTED';
        break;
      case 3:
        targetStatus = 'COMPLETED';
        break;
      default:
        return _requests;
    }
    return _requests.where((req) => req.status == targetStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;
    final filteredRequests = _getFilteredRequests();

    return AppScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '需求墙',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.textPrimary, size: 20),
          splashRadius: 22,
          tooltip: '返回',
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadRequests,
            icon: Icon(Icons.refresh_rounded, color: theme.textPrimary, size: 22),
            tooltip: '刷新',
            splashRadius: 22,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: theme.subtleBg.withValues(alpha: isDark ? 0.45 : 0.65),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: theme.cardBorder, width: 0.8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: isDark ? const Color(0xFF2E3440) : Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: theme.primaryColor,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelColor: theme.textMuted,
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: '投票中'),
                  Tab(text: '开发中'),
                  Tab(text: '已拒绝'),
                  Tab(text: '已完成'),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: theme.primaryColor.withValues(alpha: isDark ? 0.40 : 0.28),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _showCreateDialog,
          backgroundColor: theme.primaryColor,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          label: const Text(
            '提需求',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
      body: SelectionArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: theme.primaryColor,
                ),
              )
            : filteredRequests.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: theme.subtleBg.withValues(alpha: isDark ? 0.3 : 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.rate_review_outlined,
                            size: 32,
                            color: theme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '当前分类暂无需求',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: filteredRequests.length,
                    itemBuilder: (context, index) {
                      final request = filteredRequests[index];
                      return _buildRequestCard(request);
                    },
                  ),
      ),
    );
  }

  Widget _buildRequestCard(FeatureRequestVo request) {
    final theme = context.themeConfig;
    final isDark = context.isDarkMode;

    final status = FeatureRequestStatusExt.fromString(request.status ?? 'VOTING');

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case FeatureRequestStatus.voting:
        statusColor = theme.primaryColor;
        statusIcon = Icons.how_to_vote_rounded;
        break;
      case FeatureRequestStatus.inProgress:
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.engineering_rounded;
        break;
      case FeatureRequestStatus.rejected:
        statusColor = const Color(0xFF94A3B8);
        statusIcon = Icons.remove_circle_outline_rounded;
        break;
      case FeatureRequestStatus.completed:
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_rounded;
        break;
    }

    final hasVoted = _votedStatus[request.id] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: theme.cardShadows,
        border: Border.all(
          color: theme.cardBorder,
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    request.title ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16.5,
                      color: theme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: statusColor.withValues(alpha: isDark ? 0.35 : 0.22),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12.5, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        status.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (request.content != null && request.content!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                request.content!,
                style: TextStyle(
                  fontSize: 13.5,
                  color: theme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: theme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                  child: Text(
                    _getUserInitial(request.creator),
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  request.creator?.nickName ?? '匿名用户',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('yyyy-MM-dd').format(request.createTime),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.textMuted,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // 投票支持胶囊按钮（最新美学：薄雾微光底 + 精细描边）
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: () => _voteRequest(request),
                      icon: Icon(
                        hasVoted ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                        size: 15,
                      ),
                      label: Text(
                        '${request.voteCount ?? 0}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor.withValues(
                          alpha: hasVoted ? (isDark ? 0.25 : 0.16) : (isDark ? 0.14 : 0.07),
                        ),
                        foregroundColor: theme.primaryColor,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        side: BorderSide(
                          color: theme.primaryColor.withValues(
                            alpha: hasVoted ? 0.6 : (isDark ? 0.32 : 0.20),
                          ),
                          width: 0.8,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 举报幽灵微按钮
                SizedBox(
                  height: 36,
                  child: TextButton.icon(
                    onPressed: () => _showReportDialog(request),
                    icon: const Icon(Icons.flag_outlined, size: 14, color: Color(0xFFEF4444)),
                    label: const Text(
                      '举报',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.10 : 0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                        side: BorderSide(
                          color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.25 : 0.15),
                          width: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  String _getUserInitial(UserVo? user) {
    if (user == null) return '?';
    final nickName = user.nickName;
    if (nickName == null || nickName.isEmpty) return '?';
    return nickName[0].toUpperCase();
  }
}
