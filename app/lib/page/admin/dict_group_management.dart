import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';

class DictGroupManagementPage extends StatefulWidget {
  const DictGroupManagementPage({super.key});

  @override
  State<DictGroupManagementPage> createState() => _DictGroupManagementPageState();
}

class _DictGroupManagementPageState extends State<DictGroupManagementPage> {
  bool _isLoading = true;
  List<DictGroup> _allGroups = [];
  List<Dict> _allDicts = [];
  Map<String, List<Dict>> _groupDictMap = {};
  
  // 树形结构
  List<_TreeNode> _rootNodes = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = MyDatabase.instance;
      _allGroups = await db.select(db.dictGroups).get();
      _allDicts = await db.select(db.dicts).get();
      
      final links = await db.select(db.groupAndDictLinks).get();
      _groupDictMap = {};
      for (var link in links) {
        final dict = _allDicts.cast<Dict?>().firstWhere((d) => d?.id == link.dictId, orElse: () => null);
        if (dict != null) {
          _groupDictMap[link.groupId] ??= [];
          _groupDictMap[link.groupId]!.add(dict);
        }
      }

      _buildTree();
    } catch (e) {
      ToastUtil.error("加载数据失败: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _buildTree() {
    _rootNodes = [];
    final rootGroup = _allGroups.cast<DictGroup?>().firstWhere(
      (g) => g?.name == 'root',
      orElse: () => _allGroups.cast<DictGroup?>().firstWhere((g) => g?.parentId == null, orElse: () => null),
    );

    if (rootGroup == null) return;

    // 寻找根节点的直接子节点作为顶级分类
    final topLevelGroups = _allGroups.where((g) => g.parentId == rootGroup.id).toList();
    topLevelGroups.sort((a, b) => a.displayIndex.compareTo(b.displayIndex));

    for (var group in topLevelGroups) {
      _rootNodes.add(_buildNode(group));
    }
  }

  _TreeNode _buildNode(DictGroup group) {
    final children = _allGroups.where((g) => g.parentId == group.id).toList();
    children.sort((a, b) => a.displayIndex.compareTo(b.displayIndex));
    
    return _TreeNode(
      group: group,
      children: children.map((c) => _buildNode(c)).toList(),
      dicts: _groupDictMap[group.id] ?? [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('词书与分组管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.add_box),
            tooltip: '添加根分组',
            onPressed: () => _showGroupEditDialog(null),
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
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + (depth * 20.0), right: 16.0),
          leading: Icon(
            node.children.isEmpty ? Icons.folder_open : Icons.folder,
            color: node.children.isEmpty ? Colors.grey : Colors.orange,
          ),
          title: Text(
            "${node.group.name} (${node.dicts.length} 词书)",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => _handleAction(value, node),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'add_child', child: Text('添加子分组')),
              const PopupMenuItem(value: 'edit', child: Text('编辑名称')),
              const PopupMenuItem(value: 'delete', child: Text('删除分组')),
              const PopupMenuItem(value: 'manage_dicts', child: Text('管理词书')),
            ],
          ),
        ),
        if (node.children.isNotEmpty)
          ...node.children.map((child) => _buildTreeItem(child, depth + 1, isDarkMode)),
        const Divider(height: 1),
      ],
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

  Future<void> _showGroupEditDialog(String? parentId, {DictGroup? existingGroup}) async {
    final nameController = TextEditingController(text: existingGroup?.name ?? "");
    final indexController = TextEditingController(text: existingGroup?.displayIndex.toString() ?? "0");

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingGroup == null ? '添加分组' : '编辑分组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '分组名称')),
            TextField(controller: indexController, decoration: const InputDecoration(labelText: '排序索引'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final index = int.tryParse(indexController.text) ?? 0;
              
              Navigator.pop(context);
              final result = await Api.client.saveDictGroup(
                existingGroup?.id,
                name,
                parentId,
                index,
              );
              
              if (result.success) {
                ToastUtil.success("保存成功");
                _loadData();
              } else {
                ToastUtil.error("保存失败: ${result.msg}");
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteGroup(_TreeNode node) async {
    if (node.children.isNotEmpty || node.dicts.isNotEmpty) {
      return showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('无法删除'),
          content: const Text('该分组下仍有子分组或词书，请先清空后再删除。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
        ),
      );
    }

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除分组 "${node.group.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await Api.client.deleteDictGroup(node.group.id);
              if (result.success) {
                ToastUtil.success("删除成功");
                _loadData();
              } else {
                ToastUtil.error("删除失败: ${result.msg}");
              }
            },
            child: const Text('确认删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDictManagementDialog(_TreeNode node) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DictAssignmentSheet(
        group: node.group,
        currentDicts: node.dicts,
        allDicts: _allDicts,
        onChanged: _loadData,
      ),
    );
  }
}

class _TreeNode {
  final DictGroup group;
  final List<_TreeNode> children;
  final List<Dict> dicts;

  _TreeNode({required this.group, required this.children, required this.dicts});
}

class _DictAssignmentSheet extends StatefulWidget {
  final DictGroup group;
  final List<Dict> currentDicts;
  final List<Dict> allDicts;
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
  late List<Dict> _availableDicts;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _availableDicts = widget.allDicts.where((d) => !widget.currentDicts.any((cd) => cd.id == d.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _availableDicts.where((d) => d.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("管理分组: ${widget.group.name}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text("当前词书:", style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: widget.currentDicts.map((d) => Chip(
              label: Text(d.name),
              onDeleted: () => _updateDictGroup(d, null),
            )).toList(),
          ),
          const Divider(),
          const Text("添加词书:", style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(
            decoration: const InputDecoration(hintText: '搜索词书...', prefixIcon: Icon(Icons.search)),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final d = filtered[index];
                return ListTile(
                  title: Text(d.name),
                  subtitle: Text("${d.wordCount} 词"),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                    onPressed: () => _updateDictGroup(d, widget.group.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateDictGroup(Dict dict, String? groupId) async {
    final result = await Api.client.updateSystemDict(
      dict.id,
      dict.name,
      dict.isReady,
      dict.visible,
      dict.popularityLimit,
      groupId,
      null, // gameHallIds
    );

    if (result.success) {
      ToastUtil.success("更新成功");
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } else {
      ToastUtil.error("更新失败: ${result.msg}");
    }
  }
}
