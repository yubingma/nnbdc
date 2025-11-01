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

class _FeatureRequestWallPageState extends State<FeatureRequestWallPage> {
  List<FeatureRequestVo> _requests = [];
  bool _isLoading = true;
  final Map<String, bool> _votedStatus = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
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

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setState) => AlertDialog(
          backgroundColor: backgroundColor,
          title: Text(
            '提需求',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w400),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      labelText: '标题',
                      labelStyle: TextStyle(color: textColor),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    style: TextStyle(color: textColor),
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: '详细描述',
                      labelStyle: TextStyle(color: textColor),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('取消', style: TextStyle(color: textColor)),
            ),
            TextButton(
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
              child: const Text('提交'),
            ),
          ],
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
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
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final request = _requests[index];
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

