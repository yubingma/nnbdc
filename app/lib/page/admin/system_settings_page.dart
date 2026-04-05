import 'package:flutter/material.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/state.dart';
import 'package:provider/provider.dart';

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  bool _isLoading = true;
  List<SysParamVo> _params = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  Future<void> _loadParams() async {
    try {
      final result = await Api.client.getAllSysParams();
      if (result.success && result.data != null) {
        setState(() {
          _params = result.data!;
          _isLoading = false;
        });
      } else {
        ToastUtil.error(result.msg ?? '获取配置失败');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveParam(String name, String value, String? comment) async {
    try {
      final result = await Api.client.saveSysParam(name, value, comment);
      if (result.success) {
        ToastUtil.success('保存成功');
        _loadParams();
      } else {
        ToastUtil.error(result.msg ?? '保存失败');
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
    }
  }

  Future<void> _deleteParam(String name) async {
    try {
      final result = await Api.client.deleteSysParam(name);
      if (result.success) {
        ToastUtil.success('删除成功');
        _loadParams();
      } else {
        ToastUtil.error(result.msg ?? '删除失败');
      }
    } catch (e) {
      ToastUtil.error('报错: $e');
    }
  }

  void _showEditDialog([SysParamVo? param]) {
    final nameController = TextEditingController(text: param?.paramName ?? '');
    final valueController = TextEditingController(text: param?.paramValue ?? '');
    final commentController = TextEditingController(text: param?.comment ?? '');
    final isEdit = param != null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? '编辑参数' : '新增参数'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                enabled: !isEdit,
                decoration: const InputDecoration(labelText: '参数名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: valueController,
                decoration: const InputDecoration(labelText: '参数值'),
                maxLines: null,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(labelText: '备注'),
                maxLines: null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (isEdit)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmDelete(param.paramName);
              },
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isEmpty || valueController.text.isEmpty) {
                ToastUtil.error('名称和值不能为空');
                return;
              }
              _saveParam(nameController.text, valueController.text, commentController.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除参数 "$name" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteParam(name);
            },
            child: const Text('确认', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    final filteredParams = _params
        .where((p) =>
            p.paramName.toLowerCase().contains(_searchQuery.toLowerCase()) || (p.comment?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false))
        .toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: '系统参数管理',
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showEditDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索参数...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: filteredParams.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final param = filteredParams[index];
                      return Card(
                        color: cardColor,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title: Text(param.paramName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('值: ${param.paramValue}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              if (param.comment != null && param.comment!.isNotEmpty)
                                Text('备注: ${param.comment}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          isThreeLine: param.comment != null && param.comment!.isNotEmpty,
                          trailing: const Icon(Icons.edit, size: 20),
                          onTap: () => _showEditDialog(param),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
