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

class FeatureRequestManagementWidget extends StatefulWidget {
  const FeatureRequestManagementWidget({super.key});

  @override
  State<StatefulWidget> createState() => _FeatureRequestManagementWidgetState();
}

class _FeatureRequestManagementWidgetState extends State<FeatureRequestManagementWidget> {
  List<FeatureRequestVo> _requests = [];
  bool _isLoading = true;

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
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStatus(FeatureRequestVo request, FeatureRequestStatus status) async {
    try {
      final adminUser = Global.getLoggedInUser();
      if (adminUser == null || adminUser.isAdmin != true) {
        ToastUtil.error('权限不足');
        return;
      }

      final result = await Api.client.updateFeatureRequestStatus(
        request.id,
        status.json,
        adminUser.id,
      );

      if (!mounted) return;
      if (result.success) {
        setState(() {
          request.status = status.json;
        });
        ToastUtil.success('状态已更新');
      } else {
        ToastUtil.error(result.msg ?? '更新失败');
      }
    } catch (e) {
      if (!mounted) return;
      ToastUtil.error('更新失败');
    }
  }

  void _showStatusDialog(FeatureRequestVo request) {
    final isDarkMode = Provider.of<DarkMode>(context, listen: false).isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: backgroundColor,
        title: Text(
          '更改状态',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w400),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusOption(
              FeatureRequestStatus.voting,
              request,
              textColor,
              dialogContext,
            ),
            _buildStatusOption(
              FeatureRequestStatus.inProgress,
              request,
              textColor,
              dialogContext,
            ),
            _buildStatusOption(
              FeatureRequestStatus.rejected,
              request,
              textColor,
              dialogContext,
            ),
            _buildStatusOption(
              FeatureRequestStatus.completed,
              request,
              textColor,
              dialogContext,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('取消', style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOption(
    FeatureRequestStatus status,
    FeatureRequestVo request,
    Color textColor,
    BuildContext dialogContext,
  ) {
    final isSelected = FeatureRequestStatusExt.fromString(request.status ?? 'VOTING') == status;
    
    return ListTile(
      leading: Icon(
        _getStatusIcon(status),
        color: _getStatusColor(status),
      ),
      title: Text(
        status.description,
        style: TextStyle(color: textColor),
      ),
      trailing: isSelected ? Icon(Icons.check, color: AppTheme.primaryColor) : null,
      onTap: () async {
        Navigator.pop(dialogContext);
        await _updateStatus(request, status);
      },
    );
  }

  IconData _getStatusIcon(FeatureRequestStatus status) {
    switch (status) {
      case FeatureRequestStatus.voting:
        return Icons.how_to_vote;
      case FeatureRequestStatus.inProgress:
        return Icons.build;
      case FeatureRequestStatus.rejected:
        return Icons.cancel;
      case FeatureRequestStatus.completed:
        return Icons.check_circle;
    }
  }

  Color _getStatusColor(FeatureRequestStatus status) {
    switch (status) {
      case FeatureRequestStatus.voting:
        return Colors.blue;
      case FeatureRequestStatus.inProgress:
        return Colors.orange;
      case FeatureRequestStatus.rejected:
        return Colors.red;
      case FeatureRequestStatus.completed:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('需求管理'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
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
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

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
                InkWell(
                  onTap: () => _showStatusDialog(request),
                  child: Container(
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
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 12),
                      ],
                    ),
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
                const SizedBox(width: 16),
                Icon(
                  Icons.thumb_up_outlined,
                  size: 16,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  '${request.voteCount ?? 0}',
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

