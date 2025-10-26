import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
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
  List<DictStatsVo> _dictionaries = [];
  List<DictStatsVo> _filteredDictionaries = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDictionaryData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDictionaryData() async {
    try {
      final result = await Api.client.getSystemDictsWithStats();
      if (result.success && result.data != null) {
        // 按选择率从高到低排序
        final sortedDictionaries = List<DictStatsVo>.from(result.data!);
        sortedDictionaries.sort((a, b) => b.selectionRate.compareTo(a.selectionRate));
        
        setState(() {
          _dictionaries = sortedDictionaries;
          _filteredDictionaries = sortedDictionaries;
          _isLoading = false;
        });
      } else {
        setState(() {
          _dictionaries = [];
          _filteredDictionaries = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _dictionaries = [];
        _filteredDictionaries = [];
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredDictionaries = _dictionaries;
      });
    } else {
      setState(() {
        _filteredDictionaries = _dictionaries.where((dict) {
          return _fuzzyMatch(dict.name.toLowerCase(), query);
        }).toList();
      });
    }
  }

  bool _fuzzyMatch(String text, String query) {
    // 直接包含匹配
    if (text.contains(query)) {
      return true;
    }
    
    // 模糊匹配：检查查询字符串的每个字符是否在文本中按顺序出现
    int textIndex = 0;
    for (int i = 0; i < query.length; i++) {
      final char = query[i];
      bool found = false;
      
      // 从当前位置开始查找字符
      while (textIndex < text.length) {
        if (text[textIndex] == char) {
          found = true;
          textIndex++;
          break;
        }
        textIndex++;
      }
      
      if (!found) {
        return false;
      }
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          '系统词典管理',
          textScaler: TextScaler.linear(1.0),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _loadDictionaryData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
              decoration: InputDecoration(
                hintText: '搜索词典名称...',
                hintStyle: TextStyle(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontFamily: 'NotoSansSC',
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[50],
              ),
            ),
          ),
          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _filteredDictionaries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _dictionaries.isEmpty ? '暂无系统词典' : '未找到匹配的词典',
                            textScaler: const TextScaler.linear(1.0),
                            style: TextStyle(
                              fontSize: 18,
                              color: textColor,
                            ),
                          ),
                          if (_dictionaries.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '系统词典管理功能开发中...',
                              textScaler: const TextScaler.linear(1.0),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredDictionaries.length,
                        itemBuilder: (context, index) {
                          final dict = _filteredDictionaries[index];
                          return _buildDictionaryCard(dict);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDictionaryCard(DictStatsVo dict) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
                      textScaler: const TextScaler.linear(1.0),
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 16,
                        color: textColor,
                        fontFamily: 'NotoSansSC',
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
                  textScaler: const TextScaler.linear(1.0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'NotoSansSC',
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
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _editDictionary(dict),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text(
                  '编辑',
                  textScaler: TextScaler.linear(1.0),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _viewDictionaryDetails(dict),
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text(
                  '详情',
                  textScaler: TextScaler.linear(1.0),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
        ),
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
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: textColor,
            fontFamily: 'NotoSansSC',
          ),
        ),
        Text(
          label,
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            fontFamily: 'NotoSansSC',
          ),
        ),
      ],
    );
  }

  void _editDictionary(DictStatsVo dict) {
    // 实现编辑词典功能 - 使用全屏展示
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _EditDictionaryDialog(dict: dict),
        fullscreenDialog: true,
      ),
    );
  }

  void _viewDictionaryDetails(DictStatsVo dict) {
    // 实现查看词典详情功能
    showDialog(
      context: context,
      builder: (context) => _DictionaryDetailsDialog(dict: dict),
    );
  }
}

// 编辑词典对话框
class _EditDictionaryDialog extends StatefulWidget {
  final DictStatsVo dict;

  const _EditDictionaryDialog({required this.dict});

  @override
  State<_EditDictionaryDialog> createState() => _EditDictionaryDialogState();
}

class _EditDictionaryDialogState extends State<_EditDictionaryDialog> {
  late TextEditingController _nameController;
  late TextEditingController _popularityLimitController;
  late bool _isReady;
  late bool _visible;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.dict.name);
    _popularityLimitController = TextEditingController(
      text: widget.dict.popularityLimit?.toString() ?? ''
    );
    _isReady = widget.dict.isReady;
    _visible = widget.dict.visible;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _popularityLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Row(
          children: [
            const Icon(Icons.edit),
            const SizedBox(width: 8),
            Text(
              '编辑词典',
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: Text(
              '取消',
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isLoading ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    '保存',
                    textScaler: TextScaler.linear(1.0),
                  ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
              child: TabBar(
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                indicatorColor: AppTheme.primaryColor,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.settings),
                    text: '词典设置',
                  ),
                  Tab(
                    icon: Icon(Icons.list),
                    text: '单词管理',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // 词典设置标签页
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
            // 词典名称输入框
            Card(
              color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '词典名称',
                      textScaler: const TextScaler.linear(1.0),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: textColor,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      style: TextStyle(
                        color: textColor,
                        fontFamily: 'NotoSansSC',
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                      decoration: InputDecoration(
                        hintText: '请输入词典名称',
                        hintStyle: TextStyle(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontFamily: 'NotoSansSC',
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 词典设置卡片
            Card(
              color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '词典设置',
                      textScaler: const TextScaler.linear(1.0),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: textColor,
                        fontFamily: 'NotoSansSC',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // 词典就绪开关
                    SwitchListTile(
                      title: Text(
                        '词典就绪',
                        textScaler: const TextScaler.linear(1.0),
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      subtitle: Text(
                        _isReady ? '用户可以选择此词典' : '词典正在编辑中',
                        textScaler: const TextScaler.linear(1.0),
                        style: TextStyle(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      value: _isReady,
                      onChanged: (value) {
                        setState(() {
                          _isReady = value;
                        });
                      },
                    ),
                    
                    const Divider(),
                    
                    // 词典可见开关
                    SwitchListTile(
                      title: Text(
                        '词典可见',
                        textScaler: const TextScaler.linear(1.0),
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      subtitle: Text(
                        _visible ? '用户可以看到此词典' : '词典对用户隐藏',
                        textScaler: const TextScaler.linear(1.0),
                        style: TextStyle(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                      value: _visible,
                      onChanged: (value) {
                        setState(() {
                          _visible = value;
                        });
                      },
                    ),
                    
                    const Divider(),
                    
                    // 流行度限制输入
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '流行度限制',
                            textScaler: const TextScaler.linear(1.0),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: textColor,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '限制通用词典释义的流行度阈值（留空表示不限制）',
                            textScaler: const TextScaler.linear(1.0),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _popularityLimitController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              color: textColor,
                              fontFamily: 'NotoSansSC',
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: InputDecoration(
                              hintText: '请输入流行度限制值（如：1000）',
                              hintStyle: TextStyle(
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                fontFamily: 'NotoSansSC',
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
                      ],
                    ),
                  ),
                  // 单词管理标签页
                  _WordManagementTab(dict: widget.dict),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          '词典名称不能为空',
          textScaler: TextScaler.linear(1.0),
        )),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 解析popularityLimit
      int? popularityLimit;
      if (_popularityLimitController.text.trim().isNotEmpty) {
        popularityLimit = int.tryParse(_popularityLimitController.text.trim());
        if (popularityLimit == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              '流行度限制必须是有效的数字',
              textScaler: TextScaler.linear(1.0),
            )),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      // 调用更新词典的API
      final result = await Api.client.updateSystemDict(
        widget.dict.id,
        _nameController.text.trim(),
        _isReady,
        _visible,
        popularityLimit,
      );
      
      if (result.success) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              '词典信息更新成功',
              textScaler: TextScaler.linear(1.0),
            )),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              '更新失败: ${result.msg ?? "未知错误"}',
              textScaler: const TextScaler.linear(1.0),
            )),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            '更新失败: $e',
            textScaler: const TextScaler.linear(1.0),
          )),
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
  final DictStatsVo dict;

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
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          color: textColor,
          fontFamily: 'NotoSansSC',
        ),
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
          child: const Text(
            '关闭',
            textScaler: TextScaler.linear(1.0),
          ),
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
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
              ),
              Expanded(
                child: Text(
                  value,
                  textScaler: const TextScaler.linear(1.0),
                  style: TextStyle(
                    color: textColor,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// 单词管理标签页
class _WordManagementTab extends StatefulWidget {
  final DictStatsVo dict;

  const _WordManagementTab({required this.dict});

  @override
  State<_WordManagementTab> createState() => _WordManagementTabState();
}

class _WordManagementTabState extends State<_WordManagementTab> {
  bool _isLoading = true;
  List<DictWordVo> _words = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWords();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWords() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 使用本地方法获取词典单词
      final result = await WordBo().getDictWordsForAPage(widget.dict.id, 0, 1000);
      
      setState(() {
        _words = result.rows;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _words = [];
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
    });
  }

  List<DictWordVo> get _filteredWords {
    if (_searchQuery.isEmpty) {
      return _words;
    }
    return _words.where((word) {
      return word.word.spell.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          // 搜索栏
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: textColor,
                fontFamily: 'NotoSansSC',
              ),
              decoration: InputDecoration(
                hintText: '搜索单词...',
                hintStyle: TextStyle(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontFamily: 'NotoSansSC',
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          
          // 单词列表
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  )
                : _filteredWords.isEmpty
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
                              _words.isEmpty ? '词典中没有单词' : '未找到匹配的单词',
                              textScaler: const TextScaler.linear(1.0),
                              style: TextStyle(
                                fontSize: 18,
                                color: textColor,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredWords.length,
                        itemBuilder: (context, index) {
                          final dictWord = _filteredWords[index];
                          return _buildWordCard(dictWord);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordCard(DictWordVo dictWord) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final cardColor = isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDarkMode 
                ? Colors.black.withValues(alpha: 0.3) 
                : Colors.grey.withValues(alpha: 0.15),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
          child: Text(
            '${dictWord.seq}',
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          dictWord.word.spell,
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: textColor,
            fontFamily: 'NotoSansSC',
          ),
        ),
        subtitle: (dictWord.word.meaningItems?.isNotEmpty ?? false)
            ? Text(
                dictWord.word.meaningItems?.first.meaning ?? '',
                textScaler: const TextScaler.linear(1.0),
                style: TextStyle(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontFamily: 'NotoSansSC',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _editWord(dictWord),
              icon: Icon(
                Icons.edit,
                size: 20,
                color: AppTheme.primaryColor,
              ),
              tooltip: '编辑单词',
            ),
            IconButton(
              onPressed: () => _deleteWord(dictWord),
              icon: Icon(
                Icons.delete,
                size: 20,
                color: Colors.red,
              ),
              tooltip: '删除单词',
            ),
          ],
        ),
      ),
    );
  }

  void _editWord(DictWordVo dictWord) {
    showDialog(
      context: context,
      builder: (context) => _EditWordDialog(
        dictWord: dictWord,
        onWordUpdated: () {
          _loadWords(); // 重新加载单词列表
        },
      ),
    );
  }

  void _deleteWord(DictWordVo dictWord) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '确认删除',
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontFamily: 'NotoSansSC',
          ),
        ),
        content: Text(
          '确定要删除单词 "${dictWord.word.spell}" 吗？\n\n此操作不可撤销。',
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontFamily: 'NotoSansSC',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '取消',
              textScaler: TextScaler.linear(1.0),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteWord(dictWord);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text(
              '删除',
              textScaler: TextScaler.linear(1.0),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteWord(DictWordVo dictWord) async {
    try {
      // 调用删除单词的API
      final result = await Api.client.removeWordFromDict(
        widget.dict.id,
        dictWord.word.id ?? '',
      );
      
      if (result.success) {
        // 重新加载单词列表
        _loadWords();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              '单词删除成功',
              textScaler: TextScaler.linear(1.0),
            )),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              '删除失败: ${result.msg ?? "未知错误"}',
              textScaler: const TextScaler.linear(1.0),
            )),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            '删除失败: $e',
            textScaler: const TextScaler.linear(1.0),
          )),
        );
      }
    }
  }
}

// 编辑单词对话框
class _EditWordDialog extends StatefulWidget {
  final DictWordVo dictWord;
  final VoidCallback onWordUpdated;

  const _EditWordDialog({
    required this.dictWord,
    required this.onWordUpdated,
  });

  @override
  State<_EditWordDialog> createState() => _EditWordDialogState();
}

class _EditWordDialogState extends State<_EditWordDialog> {
  late TextEditingController _spellController;
  late TextEditingController _shortDescController;
  late TextEditingController _longDescController;
  late TextEditingController _pronounceController;
  late TextEditingController _americaPronounceController;
  late TextEditingController _britishPronounceController;
  late TextEditingController _popularityController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _spellController = TextEditingController(text: widget.dictWord.word.spell);
    _shortDescController = TextEditingController(text: widget.dictWord.word.shortDesc ?? '');
    _longDescController = TextEditingController(text: widget.dictWord.word.longDesc ?? '');
    _pronounceController = TextEditingController(text: widget.dictWord.word.pronounce ?? '');
    _americaPronounceController = TextEditingController(text: widget.dictWord.word.americaPronounce ?? '');
    _britishPronounceController = TextEditingController(text: widget.dictWord.word.britishPronounce ?? '');
    _popularityController = TextEditingController(text: widget.dictWord.word.popularity?.toString() ?? '');
  }

  @override
  void dispose() {
    _spellController.dispose();
    _shortDescController.dispose();
    _longDescController.dispose();
    _pronounceController.dispose();
    _americaPronounceController.dispose();
    _britishPronounceController.dispose();
    _popularityController.dispose();
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
        '编辑单词',
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          color: textColor,
          fontFamily: 'NotoSansSC',
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 单词拼写
            _buildTextField(
              controller: _spellController,
              label: '单词拼写',
              hint: '请输入单词拼写',
              isRequired: true,
            ),
            
            const SizedBox(height: 16),
            
            // 简短描述
            _buildTextField(
              controller: _shortDescController,
              label: '简短描述',
              hint: '请输入简短描述',
              maxLines: 2,
            ),
            
            const SizedBox(height: 16),
            
            // 详细描述
            _buildTextField(
              controller: _longDescController,
              label: '详细描述',
              hint: '请输入详细描述',
              maxLines: 3,
            ),
            
            const SizedBox(height: 16),
            
            // 发音
            _buildTextField(
              controller: _pronounceController,
              label: '发音',
              hint: '请输入发音',
            ),
            
            const SizedBox(height: 16),
            
            // 美式发音
            _buildTextField(
              controller: _americaPronounceController,
              label: '美式发音',
              hint: '请输入美式发音',
            ),
            
            const SizedBox(height: 16),
            
            // 英式发音
            _buildTextField(
              controller: _britishPronounceController,
              label: '英式发音',
              hint: '请输入英式发音',
            ),
            
            const SizedBox(height: 16),
            
            // 流行度
            _buildTextField(
              controller: _popularityController,
              label: '流行度',
              hint: '请输入流行度数值',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text(
            '取消',
            textScaler: TextScaler.linear(1.0),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  '保存',
                  textScaler: TextScaler.linear(1.0),
                ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label${isRequired ? ' *' : ''}',
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textColor,
            fontFamily: 'NotoSansSC',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: TextStyle(
            color: textColor,
            fontFamily: 'NotoSansSC',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              fontFamily: 'NotoSansSC',
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveChanges() async {
    if (_spellController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          '单词拼写不能为空',
          textScaler: TextScaler.linear(1.0),
        )),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 解析流行度
      int? popularity;
      if (_popularityController.text.trim().isNotEmpty) {
        popularity = int.tryParse(_popularityController.text.trim());
        if (popularity == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              '流行度必须是有效的数字',
              textScaler: TextScaler.linear(1.0),
            )),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      // 调用更新单词的API
      final result = await Api.client.updateDictWord(
        widget.dictWord.word.id ?? '',
        _spellController.text.trim(),
        _shortDescController.text.trim().isEmpty ? null : _shortDescController.text.trim(),
        _longDescController.text.trim().isEmpty ? null : _longDescController.text.trim(),
        _pronounceController.text.trim().isEmpty ? null : _pronounceController.text.trim(),
        _americaPronounceController.text.trim().isEmpty ? null : _americaPronounceController.text.trim(),
        _britishPronounceController.text.trim().isEmpty ? null : _britishPronounceController.text.trim(),
        popularity,
      );
      
      if (result.success) {
        if (mounted) {
          Navigator.pop(context);
          widget.onWordUpdated();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              '单词修改成功',
              textScaler: TextScaler.linear(1.0),
            )),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              '修改失败: ${result.msg ?? "未知错误"}',
              textScaler: const TextScaler.linear(1.0),
            )),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            '修改失败: $e',
            textScaler: const TextScaler.linear(1.0),
          )),
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
