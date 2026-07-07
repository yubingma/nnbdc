import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';

import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

class PromoActivityManagementPage extends StatefulWidget {
  const PromoActivityManagementPage({super.key});

  @override
  State<PromoActivityManagementPage> createState() => _PromoActivityManagementPageState();
}

class _PromoActivityManagementPageState extends State<PromoActivityManagementPage> {
  bool _isLoading = true;
  List<PromoActivityVo> _activities = [];

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    try {
      final result = await Api.client.listPromoActivities(user.id);
      if (result.success && result.data != null) {
        setState(() {
          _activities = result.data!;
          _isLoading = false;
        });
      } else {
        ToastUtil.error(result.msg ?? '获取活动列表失败');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createActivity(String name, String code, String? duration, int? maxRedemptions) async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    try {
      final result = await Api.client.createPromoActivity(
        user.id,
        name,
        code,
        duration,
        maxRedemptions,
      );
      if (result.success) {
        ToastUtil.success('创建活动成功');
        _loadActivities();
      } else {
        ToastUtil.error(result.msg ?? '创建活动失败');
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
    }
  }

  Future<void> _deleteActivity(String activityId) async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    try {
      final result = await Api.client.deletePromoActivity(user.id, activityId);
      if (result.success) {
        ToastUtil.success('删除成功');
        _loadActivities();
      } else {
        ToastUtil.error(result.msg ?? '删除失败');
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
    }
  }

  void _showCreateDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final durationController = TextEditingController(text: '30天');
    final maxRedemptionsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建运营活动'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '活动名称',
                  hintText: '例如：小红书种子用户赠送',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: '活动兑换码',
                  hintText: '例如：XHS666',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: durationController,
                decoration: const InputDecoration(
                  labelText: '会员时长',
                  hintText: '例如：30天、365天，留空表示永久',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: maxRedemptionsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '最大兑换次数限制',
                  hintText: '留空表示无限制',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final code = codeController.text.trim();
              final duration = durationController.text.trim();
              final maxRedemptionsStr = maxRedemptionsController.text.trim();

              if (name.isEmpty || code.isEmpty) {
                ToastUtil.error('活动名称与活动码不能为空');
                return;
              }

              final maxRedemptions = maxRedemptionsStr.isEmpty ? null : int.tryParse(maxRedemptionsStr);

              Navigator.pop(context);
              _createActivity(name, code, duration.isEmpty ? null : duration, maxRedemptions);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('运营推广活动管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
              ? const Center(
                  child: Text('暂无推广活动'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _activities.length,
                  itemBuilder: (context, index) {
                    final activity = _activities[index];
                    final durationText = activity.duration ?? '永久';
                    final maxRedemptionsText = activity.maxRedemptions == null || activity.maxRedemptions == 0
                        ? '无限制'
                        : '${activity.maxRedemptions} 次';
                    final progress = '${activity.redemptionCount} / $maxRedemptionsText';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    activity.name ?? '',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('删除活动'),
                                        content: Text('你确定要删除活动“${activity.name}”吗？此操作不可撤销。'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              if (activity.id != null) {
                                                _deleteActivity(activity.id!);
                                              }
                                            },
                                            child: const Text('确定', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildInfoColumn('活动兑换码', activity.activityCode ?? '', isDarkMode),
                                _buildInfoColumn('赠送时长', durationText, isDarkMode),
                                _buildInfoColumn('已兑换次数', progress, isDarkMode),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildInfoColumn(String label, String value, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }
}
