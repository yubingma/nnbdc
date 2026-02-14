import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/toast_util.dart';

/// 改进的编辑释义对话框
/// 显示所有词性的完整释义，每个词性有独立的下拉选择框和编辑框
class EditMeaningDialog extends StatefulWidget {
  final WordWrapper word;
  final WordModifier wordModifier;
  final VoidCallback onSuccess;

  const EditMeaningDialog({
    super.key,
    required this.word,
    required this.wordModifier,
    required this.onSuccess,
  });

  @override
  State<EditMeaningDialog> createState() => _EditMeaningDialogState();
}

class _EditMeaningDialogState extends State<EditMeaningDialog> {
  late List<MeaningItemController> controllers;
  bool _hasDiffFromDefault = false;
  
  List<String> get availablePosList {
    // 返回所有词性选项
    return posList;
  }
  
  final List<String> posList = [
    'n.',
    'v.',
    'vt.',
    'vi.',
    'adj.',
    'adv.',
    'prep.',
    'conj.',
    'pron.',
    'art.',
    'num.',
    'int.',
    'phrase.',
    'abbr.',
    '无'
  ];

  @override
  void initState() {
    super.initState();

    // 为每个释义项创建控制器
    List<MeaningItemVo>? meaningItems = widget.word.word.meaningItems;
    controllers = [];

    if (meaningItems != null && meaningItems.isNotEmpty) {
      // 1. 按词性分组
      Map<String, List<MeaningItemVo>> groupedItems = {};
      for (var item in meaningItems) {
        String cx = item.ciXing ?? '';
        groupedItems.putIfAbsent(cx, () => []).add(item);
      }

      // 2. 为每个词性创建一个控制器，合并释义
      groupedItems.forEach((cx, items) {
        // 合并释义内容，使用分号分隔
        String mergedMeaning = items
            .map((e) => e.meaning ?? '')
            .where((s) => s.isNotEmpty)
            .join('；');
        
        // 只要有一个是自定义的，就标记为自定义
        bool isCustom = items.any((e) => (e.id?.length ?? 0) > 10);
        
        // 确定下拉框选中的值
        String selectedPos = posList.contains(cx) ? cx : '无';

        controllers.add(MeaningItemController(
          selectedPos: selectedPos,
          cixingController: TextEditingController(text: selectedPos == '无' ? '' : cx),
          meaningController: TextEditingController(text: mergedMeaning),
          isCustom: isCustom,
        ));
      });
    }

    // 如果没有释义，添加一个空的编辑框
    if (controllers.isEmpty) {
      _addMeaningItem();
    }

    // 异步比较当前内容与默认释义
    _checkDiffFromDefault(meaningItems);
  }

  Future<void> _checkDiffFromDefault(List<MeaningItemVo>? currentItems) async {
    try {
      // 获取默认释义（从通用词典 dictId = "0"）
      final db = MyDatabase.instance;
      final defaultQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.equals(widget.word.word.id!) & mi.dictId.equals(Global.commonDictId))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final defaultItems = await defaultQuery.get();
      
      if (defaultItems.isEmpty) return;
      
      // 将默认释义按词性分组并合并
      Map<String, List<dynamic>> defaultGrouped = {};
      for (var item in defaultItems) {
        String cx = item.ciXing ?? '';
        defaultGrouped.putIfAbsent(cx, () => []).add(item);
      }
      
      String defaultStr = '';
      defaultGrouped.forEach((cx, items) {
        String merged = items.map((e) => e.meaning ?? '').where((s) => s.isNotEmpty).join('；');
        defaultStr += '${cx.isNotEmpty ? cx : "无"}:$merged;';
      });
      
      // 将当前编辑内容转为字符串比较
      String currentStr = '';
      for (var c in controllers) {
        currentStr += '${c.selectedPos}:${c.meaningController.text};';
      }
      
      // 比较是否不同
      if (mounted) {
        setState(() {
          _hasDiffFromDefault = currentStr.trim() != defaultStr.trim();
        });
      }
    } catch (e) {
      // 忽略错误，默认不显示按钮
    }
  }

  void _addMeaningItem() {
    // 获取已使用的词性
    final usedPos = controllers.map((c) => c.selectedPos).toSet();
    
    // 找出可用的词性（未使用的）
    String defaultPos = 'n.';
    for (final pos in posList) {
      if (!usedPos.contains(pos)) {
        defaultPos = pos;
        break;
      }
    }
    
    setState(() {
      controllers.add(MeaningItemController(
        selectedPos: defaultPos,
        cixingController: TextEditingController(text: defaultPos == '无' ? '' : defaultPos),
        meaningController: TextEditingController(),
        isCustom: false,
      ));
    });
  }

  void _removeMeaningItem(int index) {
    setState(() {
      if (controllers.length > 1) {
        controllers[index].dispose();
        controllers.removeAt(index);
      } else {
        ToastUtil.error("至少需要保留一个释义");
      }
    });
  }

  @override
  void dispose() {
    for (var controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text('编辑释义: ${widget.word.word.spell}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              ...controllers.asMap().entries.map((entry) {
                int index = entry.key;
                var controller = entry.value;
                return _buildMeaningItemEditor(index, controller, availablePosListForIndex(index));
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addMeaningItem,
                icon: const Icon(Icons.add),
                label: const Text('添加词性/释义'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _handleSave,
          child: const Text('保存'),
        ),
        if (_hasDiffFromDefault)
          TextButton(
            onPressed: _handleRestoreDefault,
            child: const Text('恢复默认', style: TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  List<String> availablePosListForIndex(int excludeIndex) {
    final usedPos = controllers
        .asMap()
        .entries
        .where((e) => e.key != excludeIndex)
        .map((e) => e.value.selectedPos)
        .toSet();
    // 始终包含当前控制器已选的值（即使被其他控制器使用），否则下拉框会报错
    final currentPos = controllers[excludeIndex].selectedPos;
    final result = posList.where((pos) => !usedPos.contains(pos) || pos == currentPos).toList();
    return result;
  }
  
  Widget _buildMeaningItemEditor(int index, MeaningItemController controller, List<String> availablePos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: controller.isCustom ? Colors.blue.shade50 : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 词性行：下拉框 + 自定义词性输入框 + 删除按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: controller.selectedPos,
                  decoration: const InputDecoration(
                    labelText: '词性',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  items: availablePos.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      controller.selectedPos = newValue!;
                      if (newValue != '无') {
                        controller.cixingController.text = newValue;
                      } else {
                        controller.cixingController.text = '';
                      }
                    });
                    // 词性变化时也触发差异检测
                    _checkDiffFromDefault(null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: controller.selectedPos == '无'
                    ? TextField(
                        controller: controller.cixingController,
                        decoration: const InputDecoration(
                          hintText: '输入词性',
                          labelText: '无词性',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                        onChanged: (_) => _checkDiffFromDefault(null),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => _removeMeaningItem(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 释义内容行
          TextField(
            controller: controller.meaningController,
            decoration: const InputDecoration(
              hintText: '输入释义 (例如: 脸;脸面)',
              labelText: '释义内容',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => _checkDiffFromDefault(null),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    // 收集所有非空的释义，并按词性合并
    Map<String, List<String>> mergedMeanings = {};
    
    for (var controller in controllers) {
      final meaning = controller.meaningController.text.trim();
      final cixing = controller.cixingController.text.trim();
      
      if (meaning.isNotEmpty) {
        mergedMeanings.putIfAbsent(cixing, () => []);
        mergedMeanings[cixing]!.add(meaning);
      }
    }
    
    List<MeaningUpdateItem> newMeanings = [];
    mergedMeanings.forEach((cixing, meaningParts) {
      // 同一词性的多个编辑框内容也用分号连接，且把内容中的换行也替换为分号
      newMeanings.add(MeaningUpdateItem(
        ciXing: cixing, 
        meaning: meaningParts.map((e) => e.replaceAll('\n', '；')).join('；')
      ));
    });

    if (newMeanings.isEmpty) {
      ToastUtil.error("至少需要一个释义");
      return;
    }

    final success = await widget.wordModifier.updateMeanings(
      widget.word.word.id!,
      newMeanings,
    );

    if (success) {
      // 立即更新内存中的数据，以便 UI 立刻显示最新内容
      widget.word.word.meaningItems = newMeanings.map((e) => MeaningItemVo(
        'custom_meaning_placeholder', // 设置一个足够长的 ID 以便被识别为自定义
        e.ciXing, 
        e.meaning,
        null, // dict
        null, // synonyms
        null  // sentences
      )).toList();

      // 同时也更新 shortDesc 以便页面列表立刻显示最新内容
      widget.word.word.shortDesc = newMeanings.map((e) {
        String cx = e.ciXing;
        // 确保没有换行符
        String m = e.meaning.replaceAll('\n', '；');
        return cx.isNotEmpty ? "$cx $m" : m;
      }).join("; ");

      Get.back();
      ToastUtil.info('更新成功');
      widget.onSuccess();
    }
  }

  Future<void> _handleRestoreDefault() async {
    final success = await widget.wordModifier.deleteMeaning(widget.word.word.id!);
    if (success) {
      // 重新加载默认释义 - 从数据库获取该词的默认释义
      final userId = Global.getLoggedInUser()?.id;
      if (userId != null) {
        final defaultMeaningItems = await WordBo().getMeaningItemsForWord(widget.word.word.id!, userId);
        // 更新WordWrapper中的meaningItems
        widget.word.word.meaningItems = defaultMeaningItems;
      }
      // 重新初始化控制器
      setState(() {
        // 销毁旧的控制器
        for (var controller in controllers) {
          controller.dispose();
        }
        
        // 重新创建控制器
        List<MeaningItemVo>? meaningItems = widget.word.word.meaningItems;
        controllers = [];

        if (meaningItems != null && meaningItems.isNotEmpty) {
          // 1. 按词性分组
          Map<String, List<MeaningItemVo>> groupedItems = {};
          for (var item in meaningItems) {
            String cx = item.ciXing ?? '';
            groupedItems.putIfAbsent(cx, () => []).add(item);
          }

          // 2. 为每个词性创建一个控制器，合并释义
          groupedItems.forEach((cx, items) {
            // 合并释义内容，使用分号分隔
            String mergedMeaning = items
                .map((e) => e.meaning ?? '')
                .where((s) => s.isNotEmpty)
                .join('；');
            
            // 标记为非自定义
            bool isCustom = false;
            
            // 确定下拉框选中的值
            String selectedPos = posList.contains(cx) ? cx : '无';

            controllers.add(MeaningItemController(
              selectedPos: selectedPos,
              cixingController: TextEditingController(text: selectedPos == '无' ? '' : cx),
              meaningController: TextEditingController(text: mergedMeaning),
              isCustom: isCustom,
            ));
          });
        }

        // 如果没有释义，添加一个空的编辑框
        if (controllers.isEmpty) {
          _addMeaningItem();
        }
        
        // 恢复默认后，内容与默认相同
        _hasDiffFromDefault = false;
      });
      ToastUtil.info('已恢复默认释义');
    }
  }
}

class MeaningItemController {
  String selectedPos;
  final TextEditingController cixingController;
  final TextEditingController meaningController;
  final bool isCustom;
  VoidCallback? onMeaningChanged;

  MeaningItemController({
    required this.selectedPos,
    required this.cixingController,
    required this.meaningController,
    required this.isCustom,
  }) {
    // 添加文本变化监听，实时触发差异检测
    meaningController.addListener(_onTextChanged);
    cixingController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    onMeaningChanged?.call();
  }

  void dispose() {
    cixingController.removeListener(_onTextChanged);
    cixingController.dispose();
    meaningController.removeListener(_onTextChanged);
    meaningController.dispose();
  }
}
