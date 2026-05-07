import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';

class DictGroupManagementPage extends StatefulWidget {
  const DictGroupManagementPage({super.key});

  @override
  State<DictGroupManagementPage> createState() => _DictGroupManagementPageState();
}

class _DictGroupManagementPageState extends State<DictGroupManagementPage> {
  bool _isLoading = true;
  List<DictGroupVo> _allGroups = [];
  List<DictVo> _allDicts = [];
  Map<String, List<DictVo>> _groupDictMap = {};
  
  // 树形结构
  List<_TreeNode> _rootNodes = [];
  String? _rootGroupId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      // 直接从服务端获取最新的数据，不经过本地数据库
      final groupsResult = await Api.client.getAllDictGroups();
      final dictsResult = await Api.client.getAllDicts();

      if (groupsResult.success && dictsResult.success) {
        _allGroups = groupsResult.data!;
        _allDicts = dictsResult.data!;
        
        // 建立分组与词书的映射
        _groupDictMap = {};
        for (var group in _allGroups) {
          if (group.dicts != null) {
            _groupDictMap[group.id] = group.dicts!;
          }
        }

        _buildTree();
      } else {
        ToastUtil.error("获取数据失败: ${groupsResult.msg ?? dictsResult.msg}");
      }
    } catch (e) {
      Global.logger.e("同步分组数据失败: $e");
      ToastUtil.error("加载数据失败: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _buildTree() {
    _rootNodes = [];
    final rootGroup = _allGroups.cast<DictGroupVo?>().firstWhere(
      (g) => g?.name == 'root',
      orElse: () => _allGroups.cast<DictGroupVo?>().firstWhere((g) => g?.parentId == null, orElse: () => null),
    );

    if (rootGroup == null) return;
    _rootGroupId = rootGroup.id;

    // 寻找根节点的直接子节点作为顶级分类
    final topLevelGroups = _allGroups.where((g) => g.parentId == rootGroup.id).toList();
    topLevelGroups.sort((a, b) => (a.displayIndex ?? 0).compareTo(b.displayIndex ?? 0));

    for (var group in topLevelGroups) {
      _rootNodes.add(_buildNode(group));
    }
  }

  _TreeNode _buildNode(DictGroupVo group) {
    final children = _allGroups.where((g) => g.parentId == group.id).toList();
    children.sort((a, b) => (a.displayIndex ?? 0).compareTo(b.displayIndex ?? 0));
    
    final dicts = _groupDictMap[group.id] ?? [];
    dicts.sort((a, b) => (b.createTime ?? DateTime(0)).compareTo(a.createTime ?? DateTime(0)));
    
    return _TreeNode(
      group: group,
      children: children.map((c) => _buildNode(c)).toList(),
      dicts: dicts,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    
    return Scaffold(
      appBar: AppTheme.createGradientAppBar(
        title: '词书与分组管理',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.add_box, color: Colors.white),
            tooltip: '添加根分组',
            onPressed: () => _showGroupEditDialog(_rootGroupId),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: _rootNodes.map((node) => _buildTreeItem(node, 0, isDarkMode)).toList(),
          ),
    );
  }

  Widget _buildTreeItem(_TreeNode node, int depth, bool isDarkMode) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.only(left: 16.0 + (depth * 20.0), right: 16.0),
        leading: Icon(
          node.children.isEmpty && node.dicts.isEmpty ? Icons.folder_open : Icons.folder,
          color: node.children.isEmpty && node.dicts.isEmpty ? Colors.grey : Colors.orange,
        ),
        initiallyExpanded: depth < 1, // 默认展开第一层
        title: Text(
          "${node.group.name} (${node.dicts.length} 词书)",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              onSelected: (value) => _handleAction(value, node),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'add_child', child: Text('添加子分组')),
                const PopupMenuItem(value: 'edit', child: Text('编辑名称')),
                const PopupMenuItem(value: 'delete', child: Text('删除分组')),
                const PopupMenuItem(value: 'manage_dicts', child: Text('管理词书')),
              ],
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          // 子分组
          ...node.children.map((child) => _buildTreeItem(child, depth + 1, isDarkMode)),
          // 该分组下的词书
          ...node.dicts.map((dict) => ListTile(
                contentPadding: EdgeInsets.only(left: 16.0 + ((depth + 1) * 20.0), right: 16.0),
                leading: const Icon(Icons.book, size: 18, color: Colors.blueGrey),
                title: Text(dict.shortName ?? dict.name ?? '未命名', style: const TextStyle(fontSize: 14)),
                subtitle: Text("${dict.wordCount ?? 0} 词", style: const TextStyle(fontSize: 12)),
                onTap: () {
                  // 这里以后可以添加点击词书的逻辑，比如查看详情
                },
              )),
        ],
      ),
    );
  }

  void _handleAction(String action, _TreeNode node) {
    switch (action) {
      case 'add_child':
        _showGroupEditDialog(node.group.id);
        break;
      case 'edit':
        _showGroupEditDialog(node.group.parentId, existingGroup: node.group);
        break;
      case 'delete':
        _confirmDeleteGroup(node);
        break;
      case 'manage_dicts':
        _showDictManagementDialog(node);
        break;
    }
  }

  Future<void> _showGroupEditDialog(String? parentId, {DictGroupVo? existingGroup}) async {
    final nameController = TextEditingController(text: existingGroup?.name ?? "");
    final indexController = TextEditingController(text: existingGroup?.displayIndex.toString() ?? "0");
    bool isSaving = false;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingGroup == null ? '添加分组' : '编辑分组'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController, 
                decoration: const InputDecoration(labelText: '分组名称'),
                enabled: !isSaving,
              ),
              TextField(
                controller: indexController, 
                decoration: const InputDecoration(labelText: '排序索引'), 
                keyboardType: TextInputType.number,
                enabled: !isSaving,
              ),
              if (isSaving)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context), 
              child: const Text('取消')
            ),
            TextButton(
              onPressed: isSaving ? null : () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ToastUtil.error("请输入分组名称");
                  return;
                }
                final index = int.tryParse(indexController.text) ?? 0;
                
                setDialogState(() => isSaving = true);
                try {
                  final result = await Api.client.saveDictGroup(
                    existingGroup?.id,
                    name,
                    parentId,
                    index,
                  );
                  
                  if (result.success) {
                    ToastUtil.success("保存成功");
                    if (context.mounted) Navigator.pop(context);
                    _loadData(showLoading: false);
                  } else {
                    ToastUtil.error("保存失败: ${result.msg}");
                  }
                } catch (e) {
                  ToastUtil.error("网络请求失败: $e");
                } finally {
                  if (context.mounted) setDialogState(() => isSaving = false);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteGroup(_TreeNode node) async {
    final hasContent = node.children.isNotEmpty || node.dicts.isNotEmpty;
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasContent ? '级联删除确认' : '确认删除'),
        content: Text(hasContent 
            ? '警告：该分组 "${node.group.name}" 下仍有子分组或词书。级联删除将删除所有子分组，并解除这些分组与词书的关联。确定要继续吗？'
            : '确定要删除分组 "${node.group.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await Api.client.deleteDictGroup(node.group.id);
              if (result.success) {
                ToastUtil.success("删除成功");
                _loadData(showLoading: false);
              } else {
                ToastUtil.error("删除失败: ${result.msg}");
              }
            },
            child: Text(hasContent ? '级联删除' : '确认删除', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDictManagementDialog(_TreeNode node) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // 背景透明，以便使用自定义圆角卡片
      builder: (context) => _DictAssignmentSheet(
        group: node.group,
        currentDicts: node.dicts,
        allDicts: _allDicts,
        onChanged: () => _loadData(showLoading: false),
      ),
    );
  }
}

class _TreeNode {
  final DictGroupVo group;
  final List<_TreeNode> children;
  final List<DictVo> dicts;

  _TreeNode({required this.group, required this.children, required this.dicts});
}

class _DictAssignmentSheet extends StatefulWidget {
  final DictGroupVo group;
  final List<DictVo> currentDicts;
  final List<DictVo> allDicts;
  final VoidCallback onChanged;

  const _DictAssignmentSheet({
    required this.group,
    required this.currentDicts,
    required this.allDicts,
    required this.onChanged,
  });

  @override
  State<_DictAssignmentSheet> createState() => _DictAssignmentSheetState();
}

class _DictAssignmentSheetState extends State<_DictAssignmentSheet> {
  late List<DictVo> _availableDicts;
  late List<DictVo> _currentDicts;
  String _searchQuery = "";
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _currentDicts = List.from(widget.currentDicts);
    _currentDicts.sort((a, b) => (b.createTime ?? DateTime(0)).compareTo(a.createTime ?? DateTime(0)));
    _availableDicts = widget.allDicts.where((d) => !_currentDicts.any((cd) => cd.id == d.id)).toList();
    // 按照创建时间倒序排序
    _availableDicts.sort((a, b) => (b.createTime ?? DateTime(0)).compareTo(a.createTime ?? DateTime(0)));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _availableDicts.where((d) => (d.shortName ?? d.name ?? '').toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12), // 增加外边距，使其看起来像悬浮卡片
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("管理分组: ${widget.group.name}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),
              if (_currentDicts.isNotEmpty) ...[
                const Text("当前词书:", style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 8,
                  children: _currentDicts.map((d) => Chip(
                    label: Text(d.shortName ?? d.name ?? '未命名'),
                    onDeleted: _isUpdating ? null : () => _updateDictGroup(d, null),
                  )).toList(),
                ),
                const Divider(),
              ],
              const Text("添加词书:", style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(
                decoration: const InputDecoration(hintText: '搜索词书...', prefixIcon: Icon(Icons.search)),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              const SizedBox(height: 8),
              if (_isUpdating) const LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final d = filtered[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.shortName ?? d.name ?? '未命名'),
                      subtitle: Text("${d.wordCount ?? 0} 词"),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                        onPressed: _isUpdating ? null : () => _updateDictGroup(d, widget.group.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateDictGroup(DictVo dict, String? groupId) async {
    setState(() => _isUpdating = true);
    try {
      final result = await Api.client.updateSystemDict(
        dict.id,
        dict.name ?? '',
        dict.isReady ?? true,
        dict.visible ?? true,
        dict.popularityLimit,
        groupId,
        null, // gameHallIds
      );

      if (result.success) {
        setState(() {
          if (groupId == null) {
            // 从当前移除
            _currentDicts.removeWhere((d) => d.id == dict.id);
            _availableDicts.add(dict);
            _availableDicts.sort((a, b) => (b.createTime ?? DateTime(0)).compareTo(a.createTime ?? DateTime(0)));
          } else {
            // 添加到当前
            _currentDicts.add(dict);
            _currentDicts.sort((a, b) => (b.createTime ?? DateTime(0)).compareTo(a.createTime ?? DateTime(0)));
            _availableDicts.removeWhere((d) => d.id == dict.id);
          }
        });
        widget.onChanged(); // 后台刷新父页面数据
      } else {
        ToastUtil.error("更新失败: ${result.msg}");
      }
    } catch (e) {
      ToastUtil.error("网络错误: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }
}
