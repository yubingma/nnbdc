import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/loading_utils.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

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

  void _showCreateDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final isDarkMode = Provider.of<DarkMode>(context, listen: false).isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final cardColor = isDarkMode ? const Color(0xFF3D3D3D) : const Color(0xFFF8F9FA);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            margin: const EdgeInsets.symmetric(horizontal: 0),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: isDarkMode ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.8)],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.rate_review,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '提需求',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // 表单内容
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                                width: 1,
                              ),
                            ),
                            child: TextField(
                              controller: titleController,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                labelText: '需求标题',
                                labelStyle: TextStyle(
                                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                  fontSize: 14,
                                ),
                                prefixIcon: Icon(
                                  Icons.title,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                                width: 1,
                              ),
                            ),
                            child: TextField(
                              controller: contentController,
                              style: TextStyle(color: textColor),
                              maxLines: 6,
                              decoration: InputDecoration(
                                labelText: '详细描述',
                                labelStyle: TextStyle(
                                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                  fontSize: 14,
                                ),
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.only(bottom: 120),
                                  child: Icon(
                                    Icons.description_outlined,
                                    color: AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 操作按钮
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        ),
                        child: Text(
                          '取消',
                          style: TextStyle(
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
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
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('提交', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
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
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final filteredRequests = _getFilteredRequests();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          '需求墙',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _loadRequests,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '刷新',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '投票中'),
            Tab(text: '开发中'),
            Tab(text: '已拒绝'),
            Tab(text: '已完成'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredRequests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 64,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无需求',
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
                  itemCount: filteredRequests.length,
                  itemBuilder: (context, index) {
                    final request = filteredRequests[index];
                    return _buildRequestCard(request);
                  },
                ),
    );
  }

  Widget _buildRequestCard(FeatureRequestVo request) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    final status = FeatureRequestStatusExt.fromString(request.status ?? 'VOTING');

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case FeatureRequestStatus.voting:
        statusColor = Colors.blue;
        statusIcon = Icons.how_to_vote;
        break;
      case FeatureRequestStatus.inProgress:
        statusColor = Colors.orange;
        statusIcon = Icons.build;
        break;
      case FeatureRequestStatus.rejected:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case FeatureRequestStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
    }

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.title ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        status.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              request.content ?? '',
              style: TextStyle(
                fontSize: 14,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                  child: Text(
                    _getUserInitial(request.creator),
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  request.creator?.nickName ?? '匿名用户',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('yyyy-MM-dd').format(request.createTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _voteRequest(request);
                    },
                    icon: const Icon(Icons.thumb_up_outlined),
                    label: Text('${request.voteCount ?? 0}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                      foregroundColor: AppTheme.primaryColor,
                      elevation: 0,
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

