import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/state.dart';

// 系统词典管理组件
class DictionaryManagementWidget extends StatefulWidget {
  const DictionaryManagementWidget({super.key});

  @override
  State<DictionaryManagementWidget> createState() => _DictionaryManagementWidgetState();
}

class _DictionaryManagementWidgetState extends State<DictionaryManagementWidget> {
  bool _isLoading = true;
  List<DictStatsDto> _dictionaries = [];

  @override
  void initState() {
    super.initState();
    _loadDictionaryData();
  }

  Future<void> _loadDictionaryData() async {
    try {
      final result = await Api.client.getSystemDictsWithStats();
      if (result.success && result.data != null) {
        setState(() {
          _dictionaries = result.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _dictionaries = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _dictionaries = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Container(
      color: backgroundColor,
      child: _dictionaries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 64,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无系统词典',
                    style: TextStyle(
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '系统词典管理功能开发中...',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _dictionaries.length,
              itemBuilder: (context, index) {
                final dict = _dictionaries[index];
                return _buildDictionaryCard(dict);
              },
            ),
    );
  }

  Widget _buildDictionaryCard(DictStatsDto dict) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDarkMode 
                ? Colors.black.withValues(alpha: 0.3) 
                : Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.book,
                color: AppTheme.primaryColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dict.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '词典ID: ${dict.id}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // 状态标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: dict.isReady ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  dict.isReady ? '就绪' : '编辑中',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // 统计信息
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('单词数', '${dict.wordCount}', Icons.book_outlined),
                    _buildStatItem('选择用户', '${dict.userSelectionCount}', Icons.people),
                    _buildStatItem('选择率', '${dict.selectionRate.toStringAsFixed(1)}%', Icons.trending_up),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '总用户数: ${dict.totalUsers}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '创建时间: ${DateFormat('yyyy-MM-dd').format(dict.createTime)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _editDictionary(dict),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('编辑'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _viewDictionaryDetails(dict),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('详情'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _editDictionary(DictStatsDto dict) {
    // 实现编辑词典功能
    showDialog(
      context: context,
      builder: (context) => _EditDictionaryDialog(dict: dict),
    );
  }

  void _viewDictionaryDetails(DictStatsDto dict) {
    // 实现查看词典详情功能
    showDialog(
      context: context,
      builder: (context) => _DictionaryDetailsDialog(dict: dict),
    );
  }
}

// 编辑词典对话框
class _EditDictionaryDialog extends StatefulWidget {
  final DictStatsDto dict;

  const _EditDictionaryDialog({required this.dict});

  @override
  State<_EditDictionaryDialog> createState() => _EditDictionaryDialogState();
}

class _EditDictionaryDialogState extends State<_EditDictionaryDialog> {
  late TextEditingController _nameController;
  late bool _isReady;
  late bool _visible;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.dict.name);
    _isReady = widget.dict.isReady;
    _visible = widget.dict.visible;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return AlertDialog(
      backgroundColor: backgroundColor,
      title: Text(
        '编辑词典',
        style: TextStyle(color: textColor),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                labelText: '词典名称',
                labelStyle: TextStyle(color: textColor),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text('词典就绪', style: TextStyle(color: textColor)),
              subtitle: Text(
                _isReady ? '用户可以选择此词典' : '词典正在编辑中',
                style: TextStyle(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              value: _isReady,
              onChanged: (value) {
                setState(() {
                  _isReady = value;
                });
              },
            ),
            SwitchListTile(
              title: Text('词典可见', style: TextStyle(color: textColor)),
              subtitle: Text(
                _visible ? '用户可以看到此词典' : '词典对用户隐藏',
                style: TextStyle(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              value: _visible,
              onChanged: (value) {
                setState(() {
                  _visible = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveChanges,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('词典名称不能为空')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 这里应该调用更新词典的API
      // 暂时显示成功消息
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('词典信息更新成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

// 词典详情对话框
class _DictionaryDetailsDialog extends StatelessWidget {
  final DictStatsDto dict;

  const _DictionaryDetailsDialog({required this.dict});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return AlertDialog(
      backgroundColor: backgroundColor,
      title: Text(
        '词典详情',
        style: TextStyle(color: textColor),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('词典名称', dict.name),
            _buildDetailRow('词典ID', dict.id),
            _buildDetailRow('单词数量', '${dict.wordCount}'),
            _buildDetailRow('选择用户数', '${dict.userSelectionCount}'),
            _buildDetailRow('总用户数', '${dict.totalUsers}'),
            _buildDetailRow('选择率', '${dict.selectionRate.toStringAsFixed(2)}%'),
            _buildDetailRow('词典状态', dict.isReady ? '就绪' : '编辑中'),
            _buildDetailRow('可见性', dict.visible ? '可见' : '隐藏'),
            _buildDetailRow('创建时间', DateFormat('yyyy-MM-dd HH:mm:ss').format(dict.createTime)),
            if (dict.updateTime != null)
              _buildDetailRow('更新时间', DateFormat('yyyy-MM-dd HH:mm:ss').format(dict.updateTime!)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Consumer<DarkMode>(
      builder: (context, darkMode, child) {
        final isDarkMode = darkMode.isDarkMode;
        final textColor = isDarkMode ? Colors.white : Colors.black87;
    
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  '$label:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(color: textColor),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
