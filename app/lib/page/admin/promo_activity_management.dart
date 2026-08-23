import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';

import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

import 'package:nnbdc/theme/app_theme.dart';

import 'package:flutter/services.dart';

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

  Future<void> _createActivity(String name, String code, String? duration, DateTime? endTime, int? maxRedemptions) async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    try {
      final result = await Api.client.createPromoActivity(
        user.id,
        name,
        code,
        duration,
        endTime?.millisecondsSinceEpoch,
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
    final daysController = TextEditingController(text: '30');
    final maxRedemptionsController = TextEditingController();
    bool isPermanent = false;
    bool hasDeadline = true;
    DateTime selectedDeadline = DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('创建运营活动'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '活动名称',
                      hintText: '例如：小红书种子用户活动',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: '活动兑换码',
                      hintText: '例如：XHS666',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 会员时长配置
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: daysController,
                          enabled: !isPermanent,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: '赠送会员时长',
                            hintText: isPermanent ? '永久有效' : '请输入天数',
                            suffixText: isPermanent ? null : '天',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: isPermanent,
                            onChanged: (val) {
                              setDialogState(() {
                                isPermanent = val ?? false;
                              });
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                isPermanent = !isPermanent;
                              });
                            },
                            child: const Text('永久'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 活动截止期配置
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: !hasDeadline
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDeadline,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      // 设定为选定日期的 23:59:59
                                      selectedDeadline = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
                                    });
                                  }
                                },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: '活动截止日期',
                              enabled: hasDeadline,
                              suffixIcon: const Icon(Icons.calendar_today, size: 18),
                            ),
                            child: Text(
                              hasDeadline
                                  ? '${selectedDeadline.year}-${selectedDeadline.month.toString().padLeft(2, '0')}-${selectedDeadline.day.toString().padLeft(2, '0')}'
                                  : '长期有效（无截止期）',
                              style: TextStyle(
                                fontSize: 13,
                                color: hasDeadline ? null : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: !hasDeadline,
                            onChanged: (val) {
                              setDialogState(() {
                                hasDeadline = !(val ?? false);
                              });
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                hasDeadline = !hasDeadline;
                              });
                            },
                            child: const Text('无截止期'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 限量兑换人数限制
                  TextField(
                    controller: maxRedemptionsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '限量兑换总人数',
                      hintText: '留空表示不限制总人数',
                      suffixText: '人',
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
                  final days = daysController.text.trim();
                  final maxRedemptionsStr = maxRedemptionsController.text.trim();

                  if (name.isEmpty || code.isEmpty) {
                    ToastUtil.error('活动名称与活动码不能为空');
                    return;
                  }

                  String? duration;
                  if (isPermanent) {
                    duration = null; // 永久会员
                  } else {
                    if (days.isEmpty || int.tryParse(days) == null || int.parse(days) <= 0) {
                      ToastUtil.error('请输入有效的会员天数');
                      return;
                    }
                    duration = '$days天';
                  }

                  final DateTime? endTime = hasDeadline ? selectedDeadline : null;
                  final maxRedemptions = maxRedemptionsStr.isEmpty ? null : int.tryParse(maxRedemptionsStr);

                  Navigator.pop(context);
                  _createActivity(name, code, duration, endTime, maxRedemptions);
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Scaffold(
      appBar: AppTheme.createGradientAppBar(
        title: '运营推广活动管理',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '刷新',
            onPressed: () {
              setState(() => _isLoading = true);
              _loadActivities();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: '创建活动',
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadActivities,
              child: _activities.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.campaign_rounded,
                                size: 64,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              '暂无运营推广活动',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '您可以创建专属活动兑换码，指定赠送会员时长与最大兑换次数，分发给用户进行推广获客。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDarkMode ? Colors.white60 : Colors.black54,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _showCreateDialog,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('创建首个推广活动'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final activity = _activities[index];
                        final durationText = activity.duration ?? '永久';
                        final maxRedemptions = activity.maxRedemptions;
                        final count = activity.redemptionCount ?? 0;
                        final maxRedemptionsText = maxRedemptions == null || maxRedemptions == 0
                            ? '不限人数'
                            : '$maxRedemptions 人';
                        final remainingSlotsText = maxRedemptions != null && maxRedemptions > 0
                            ? ' (剩 ${maxRedemptions - count} 人)'
                            : '';
                        final progress = '$count / $maxRedemptionsText$remainingSlotsText';

                        String deadlineText = '长期有效';
                        Color? deadlineColor;
                        if (activity.endTime != null) {
                          final now = DateTime.now();
                          final diff = activity.endTime!.difference(now);
                          final dateStr = '${activity.endTime!.year}-${activity.endTime!.month.toString().padLeft(2, '0')}-${activity.endTime!.day.toString().padLeft(2, '0')}';
                          if (diff.isNegative) {
                            deadlineText = '$dateStr (已截止)';
                            deadlineColor = Colors.red;
                          } else if (diff.inDays >= 1) {
                            deadlineText = '$dateStr (还剩 ${diff.inDays} 天)';
                            deadlineColor = Colors.orange.shade700;
                          } else if (diff.inHours >= 1) {
                            deadlineText = '$dateStr (还剩 ${diff.inHours} 小时)';
                            deadlineColor = Colors.orange.shade700;
                          } else {
                            deadlineText = '$dateStr (今日即将截止)';
                            deadlineColor = Colors.red;
                          }
                        }

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
                                    _buildInfoColumn('兑换进度', progress, isDarkMode),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Text(
                                      '活动截止期：',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkMode ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      deadlineText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: deadlineColor ?? (isDarkMode ? Colors.white70 : Colors.black87),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
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
