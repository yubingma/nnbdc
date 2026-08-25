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

  Future<void> _createActivity(String name, String code, String? duration, DateTime? endTime, int? maxRedemptions, bool showCodeToUser) async {
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
        showCodeToUser,
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

  Future<void> _updateActivity(String activityId, String name, String code, String? duration, DateTime? endTime, int? maxRedemptions, bool showCodeToUser) async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    try {
      final result = await Api.client.updatePromoActivity(
        user.id,
        activityId,
        name,
        code,
        duration,
        endTime?.millisecondsSinceEpoch,
        maxRedemptions,
        showCodeToUser,
        true,
      );
      if (result.success) {
        ToastUtil.success('修改活动成功');
        _loadActivities();
      } else {
        ToastUtil.error(result.msg ?? '修改活动失败');
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
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _CreateOrEditPromoActivityPage(
          onSave: (name, code, duration, endTime, maxRedemptions, showCodeToUser) {
            _createActivity(name, code, duration, endTime, maxRedemptions, showCodeToUser);
          },
        ),
      ),
    );
  }

  void _showEditDialog(PromoActivityVo activity) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _CreateOrEditPromoActivityPage(
          initialActivity: activity,
          onSave: (name, code, duration, endTime, maxRedemptions, showCodeToUser) {
            if (activity.id != null) {
              _updateActivity(activity.id!, name, code, duration, endTime, maxRedemptions, showCodeToUser);
            }
          },
        ),
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
                                      child: Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Text(
                                            activity.name ?? '',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: isDarkMode ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(4),
                                              color: activity.showCodeToUser == true
                                                  ? Colors.green.withValues(alpha: 0.15)
                                                  : Colors.grey.withValues(alpha: 0.15),
                                            ),
                                            child: Text(
                                              activity.showCodeToUser == true ? '直接显示活动码' : '隐藏活动码',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: activity.showCodeToUser == true
                                                    ? Colors.green.shade700
                                                    : (isDarkMode ? Colors.white60 : Colors.black54),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                          tooltip: '修改活动',
                                          onPressed: () => _showEditDialog(activity),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                          tooltip: '删除活动',
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

class _CreateOrEditPromoActivityPage extends StatefulWidget {
  final PromoActivityVo? initialActivity;
  final void Function(String name, String code, String? duration, DateTime? endTime, int? maxRedemptions, bool showCodeToUser) onSave;

  const _CreateOrEditPromoActivityPage({
    this.initialActivity,
    required this.onSave,
  });

  @override
  State<_CreateOrEditPromoActivityPage> createState() => _CreateOrEditPromoActivityPageState();
}

class _CreateOrEditPromoActivityPageState extends State<_CreateOrEditPromoActivityPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _daysController = TextEditingController(text: '30');
  final TextEditingController _maxRedemptionsController = TextEditingController();
  final TextEditingController _deadlineController = TextEditingController();
  bool _isPermanent = false;
  bool _hasDeadline = true;
  bool _showCodeToUser = false;
  DateTime _selectedDeadline = DateTime.now().add(const Duration(days: 7));

  bool get _isEditing => widget.initialActivity != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialActivity;
    if (init != null) {
      _nameController.text = init.name ?? '';
      _codeController.text = init.activityCode ?? '';
      if (init.duration == null || init.duration!.isEmpty) {
        _isPermanent = true;
      } else {
        _isPermanent = false;
        _daysController.text = init.duration!.replaceAll('天', '').replaceAll('d', '').trim();
      }
      if (init.endTime != null) {
        _hasDeadline = true;
        _selectedDeadline = init.endTime!;
      } else {
        _hasDeadline = false;
      }
      if (init.maxRedemptions != null && init.maxRedemptions! > 0) {
        _maxRedemptionsController.text = init.maxRedemptions.toString();
      }
      _showCodeToUser = init.showCodeToUser == true;
    }
    _updateDeadlineText();
  }

  void _updateDeadlineText() {
    if (_hasDeadline) {
      _deadlineController.text = '${_selectedDeadline.year}-${_selectedDeadline.month.toString().padLeft(2, '0')}-${_selectedDeadline.day.toString().padLeft(2, '0')}';
    } else {
      _deadlineController.text = '长期有效（无截止期）';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _daysController.dispose();
    _maxRedemptionsController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim();
    final days = _daysController.text.trim();
    final maxRedemptionsStr = _maxRedemptionsController.text.trim();

    if (name.isEmpty || code.isEmpty) {
      ToastUtil.error('活动名称与活动码不能为空');
      return;
    }

    String? duration;
    if (_isPermanent) {
      duration = null; // 永久会员
    } else {
      if (days.isEmpty || int.tryParse(days) == null || int.parse(days) <= 0) {
        ToastUtil.error('请输入有效的会员天数');
        return;
      }
      duration = '$days天';
    }

    final DateTime? endTime = _hasDeadline ? _selectedDeadline : null;
    final maxRedemptions = maxRedemptionsStr.isEmpty ? null : int.tryParse(maxRedemptionsStr);

    Navigator.pop(context);
    widget.onSave(name, code, duration, endTime, maxRedemptions, _showCodeToUser);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    return Scaffold(
      appBar: AppTheme.createGradientAppBar(
        title: _isEditing ? '修改运营活动' : '创建运营活动',
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _submit,
            child: Text(
              _isEditing ? '保存' : '创建',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                elevation: isDarkMode ? 0 : 1,
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '基本信息',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '活动名称',
                          hintText: '例如：小红书种子用户活动',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: '活动兑换码',
                          hintText: '例如：XHS666',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('直接向用户展示活动码', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          _showCodeToUser
                              ? '已开启：普通用户在“我的”页面可以直接看到活动码并一键兑换（适合全员公开福利）'
                              : '已关闭：普通用户需手动输入活动码（适合小红书/公众号私域引流）',
                          style: TextStyle(
                            fontSize: 12,
                            color: _showCodeToUser ? Colors.green.shade700 : (isDarkMode ? Colors.white60 : Colors.black54),
                          ),
                        ),
                        value: _showCodeToUser,
                        activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                        activeThumbColor: AppTheme.primaryColor,
                        onChanged: (val) {
                          setState(() {
                            _showCodeToUser = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: isDarkMode ? 0 : 1,
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '限制与规模',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _deadlineController,
                              readOnly: true,
                              enabled: _hasDeadline,
                              onTap: !_hasDeadline
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _selectedDeadline,
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                                      );
                                      if (picked != null && mounted) {
                                        setState(() {
                                          _selectedDeadline = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
                                          _updateDeadlineText();
                                        });
                                      }
                                    },
                              decoration: const InputDecoration(
                                labelText: '活动截止日期',
                                suffixIcon: Icon(Icons.calendar_today, size: 18),
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: !_hasDeadline,
                                onChanged: (val) {
                                  setState(() {
                                    _hasDeadline = !(val ?? false);
                                    _updateDeadlineText();
                                  });
                                },
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _hasDeadline = !_hasDeadline;
                                    _updateDeadlineText();
                                  });
                                },
                                child: const Text('无截止期'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _maxRedemptionsController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: '限量兑换总人数',
                          hintText: '留空表示不限制总人数',
                          suffixText: '人',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: isDarkMode ? 0 : 1,
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '活动奖励内容',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _daysController,
                              enabled: !_isPermanent,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: '赠送会员时长',
                                hintText: _isPermanent ? '永久有效' : '请输入天数',
                                suffixText: _isPermanent ? null : '天',
                                floatingLabelBehavior: FloatingLabelBehavior.always,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _isPermanent,
                                onChanged: (val) {
                                  setState(() {
                                    _isPermanent = val ?? false;
                                  });
                                },
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isPermanent = !_isPermanent;
                                  });
                                },
                                child: const Text('永久'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_isEditing ? '保存修改' : '立即创建活动', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
