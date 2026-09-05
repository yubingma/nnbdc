import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/prefs.dart';
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

  String? _getVotedPrefsKey() {
    final user = Global.getLoggedInUser();
    if (user == null || user.id.isEmpty) return null;
    return 'voted_feature_requests_${user.id}';
  }

  void _loadCachedVotedStatus() {
    final key = _getVotedPrefsKey();
    if (key == null) return;
    final cached = Prefs.read<List<String>>(key);
    if (cached != null && cached.isNotEmpty) {
      for (final id in cached) {
        _votedStatus[id] = true;
      }
    }
  }

  Future<void> _saveVotedStatus(String requestId) async {
    _votedStatus[requestId] = true;
    final key = _getVotedPrefsKey();
    if (key == null) return;
    final cached = Prefs.read<List<String>>(key) ?? <String>[];
    if (!cached.contains(requestId)) {
      final updated = List<String>.from(cached)..add(requestId);
      await Prefs.write(key, updated);
    }
  }

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
    _loadCachedVotedStatus();
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
    final user = Global.getLoggedInUser();
    if (user == null) {
      ToastUtil.info('请先登录');
      return;
    }

    // 若本地已知已投票，直接给轻量提示，不再发起网络请求，避免大红错误弹窗
    if (_votedStatus[request.id] == true) {
      ToastUtil.info('您已经为此需求投过票了');
      return;
    }

    try {
      final result = await Api.client.voteFeatureRequest(request.id, user.id);
      if (result.success) {
        setState(() {
          request.voteCount = (request.voteCount ?? 0) + 1;
        });
        await _saveVotedStatus(request.id);
        if (mounted) setState(() {});
        ToastUtil.success('投票成功');
      } else {
        final msg = result.msg ?? '';
        if (msg.contains('已经') || msg.contains('投过票')) {
          await _saveVotedStatus(request.id);
          if (mounted) setState(() {});
          ToastUtil.info('您已经为此需求投过票了');
        } else {
          ToastUtil.error(msg.isNotEmpty ? msg : '投票失败');
        }
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
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xD91E242C) // 85% 曜石深灰通透磨砂
                          : const Color(0xE0FFFFFF), // 88% 凝润通透乳白磨砂
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? const Color(0x33FFFFFF) : const Color(0xD9FFFFFF),
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.16 : 0.10),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.flag_rounded,
                                color: Color(0xFFEF4444),
                                size: 19,
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
                        // 需求摘要指示标签：轻透温润，告别厚重死蓝色块
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x1FFFFFFF) : const Color(0x40FFFFFF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? const Color(0x14FFFFFF) : const Color(0x52FFFFFF),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '需求',
                                style: TextStyle(
                                  color: theme.textMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  request.title ?? '',
                                  style: TextStyle(
                                    color: theme.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 举报原因输入框：通透半透明材质 + 细腻圆角微边框
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x14FFFFFF) : const Color(0x4AFFFFFF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? const Color(0x1FFFFFFF) : const Color(0x66FFFFFF),
                              width: 0.8,
                            ),
                          ),
                          child: TextField(
                            controller: contentController,
                            style: TextStyle(color: theme.textPrimary, fontSize: 13.5),
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: '请详细填写举报原因...',
                              hintStyle: TextStyle(
                                color: theme.textMuted.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(13),
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
                                      side: BorderSide(
                                        color: isDark ? const Color(0x2BFFFFFF) : const Color(0x40000000),
                                        width: 0.6,
                                      ),
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
                                    backgroundColor: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.20 : 0.12),
                                    foregroundColor: const Color(0xFFEF4444),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    side: BorderSide(
                                      color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.35 : 0.22),
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
            constraints: const BoxConstraints(maxWidth: 390),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xD91E242C) // 85% 曜石深灰通透磨砂
                          : const Color(0xE0FFFFFF), // 88% 凝润通透乳白磨砂
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? const Color(0x33FFFFFF) : const Color(0xD9FFFFFF),
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.10),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                Icons.edit_note_rounded,
                                color: theme.primaryColor,
                                size: 21,
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
                        // 需求标题输入框
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x14FFFFFF) : const Color(0x4AFFFFFF),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: isDark ? const Color(0x1FFFFFFF) : const Color(0x66FFFFFF),
                              width: 0.8,
                            ),
                          ),
                          child: TextField(
                            controller: titleController,
                            style: TextStyle(color: theme.textPrimary, fontSize: 13.5),
                            decoration: InputDecoration(
                              hintText: '需求标题，如：单词列表支持乱序播放',
                              hintStyle: TextStyle(
                                color: theme.textMuted.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 需求详情描述框
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x14FFFFFF) : const Color(0x4AFFFFFF),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: isDark ? const Color(0x1FFFFFFF) : const Color(0x66FFFFFF),
                              width: 0.8,
                            ),
                          ),
                          child: TextField(
                            controller: contentController,
                            style: TextStyle(color: theme.textPrimary, fontSize: 13.5),
                            maxLines: 5,
                            decoration: InputDecoration(
                              hintText: '详细描述这个功能的使用场景和你的具体构想...',
                              hintStyle: TextStyle(
                                color: theme.textMuted.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(13),
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
                                      side: BorderSide(
                                        color: isDark ? const Color(0x2BFFFFFF) : const Color(0x40000000),
                                        width: 0.6,
                                      ),
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

                                    if (title.isEmpty) {
                                      ToastUtil.info('请填写需求标题');
                                      return;
                                    }
                                    if (content.isEmpty) {
                                      ToastUtil.info('请填写需求描述');
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
                                      if (result.success) {
                                        ToastUtil.success('提交成功，感谢你的建议！');
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
                                  child: const Text('立即提交', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x401C222A) : const Color(0x8CFFFFFF), // 温润晨雾白微底，杜绝深蓝大底座
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isDark ? const Color(0x2BFFFFFF) : const Color(0xB3FFFFFF),
                  width: 0.8,
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: isDark ? const Color(0xFF2C323C) : Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: theme.primaryColor,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                // 高对比度未选中字色，彻底解决字迹发暗看不清问题
                unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
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
      // 现代化纯正毛玻璃（Frosted Glass）微光悬浮胶囊：通透磨砂 + 朦胧墨水色块晕染
      floatingActionButton: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: theme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            // 黄金参数 sigma=7，精准抹去底层锐利轮廓，形成高级温润的朦胧磨砂晕染
            filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showCreateDialog,
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    // 严格遵循规范：浅色使用 45% 凝润通透乳白磨砂，杜绝 90%+ 实心白
                    color: isDark
                        ? const Color(0xB81C2127) // 72% 曜石深灰磨砂
                        : const Color(0x73FFFFFF), // 45% 凝润乳白通透磨砂
                    borderRadius: BorderRadius.circular(100),
                    // 晶莹高光切边与微主题色光相辉映
                    border: Border.all(
                      color: isDark
                          ? const Color(0x33FFFFFF)
                          : const Color(0xB3FFFFFF),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: theme.primaryColor, size: 19),
                      const SizedBox(width: 5),
                      Text(
                        '提需求',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.14 : 0.07),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: statusColor.withValues(alpha: isDark ? 0.28 : 0.16),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 11.5, color: statusColor),
                      const SizedBox(width: 3.5),
                      Text(
                        status.description,
                        style: TextStyle(
                          fontSize: 10.5,
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
                // 投票支持胶囊按钮（自适应紧凑高级胶囊，已投态高光微光反馈，清晰易辨）
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _voteRequest(request),
                    borderRadius: BorderRadius.circular(100),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: hasVoted
                            ? theme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.14)
                            : theme.primaryColor.withValues(alpha: isDark ? 0.08 : 0.04),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: hasVoted
                              ? theme.primaryColor.withValues(alpha: isDark ? 0.70 : 0.55)
                              : theme.primaryColor.withValues(alpha: isDark ? 0.24 : 0.14),
                          width: hasVoted ? 1.0 : 0.8,
                        ),
                        boxShadow: hasVoted
                            ? [
                                BoxShadow(
                                  color: theme.primaryColor.withValues(alpha: isDark ? 0.25 : 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 1.5),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasVoted ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                            size: 14,
                            color: theme.primaryColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            hasVoted ? '已投' : '投票',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: hasVoted ? FontWeight.w700 : FontWeight.w600,
                              color: theme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${request.voteCount ?? 0}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Roboto',
                              color: theme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // 举报辅助操作：克制低调的浅灰幽灵微按钮，彻底消除满屏刺眼粉红大色块
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showReportDialog(request),
                    borderRadius: BorderRadius.circular(100),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 13.5,
                            color: theme.textMuted.withValues(alpha: isDark ? 0.6 : 0.65),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '举报',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                              color: theme.textMuted.withValues(alpha: isDark ? 0.6 : 0.65),
                            ),
                          ),
                        ],
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
