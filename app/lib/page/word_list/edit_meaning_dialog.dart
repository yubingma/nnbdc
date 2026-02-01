import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/vo.dart';
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
    '其他'
  ];

  @override
  void initState() {
    super.initState();

    // 为每个释义项创建控制器
    List<MeaningItemVo>? meaningItems = widget.word.word.meaningItems;
    controllers = [];

    if (meaningItems != null && meaningItems.isNotEmpty) {
      for (var item in meaningItems) {
        String ciXing = item.ciXing ?? '';
        // 如果不在预设列表中，设为"其他"
        String selectedPos = posList.contains(ciXing) ? ciXing : '其他';

        controllers.add(MeaningItemController(
          selectedPos: selectedPos,
          cixingController: TextEditingController(text: ciXing),
          meaningController: TextEditingController(text: item.meaning ?? ''),
          isCustom: (item.id?.length ?? 0) > 10,
        ));
      }
    }

    // 如果没有释义，添加一个空的编辑框
    if (controllers.isEmpty) {
      _addMeaningItem();
    }
  }

  void _addMeaningItem() {
    setState(() {
      controllers.add(MeaningItemController(
        selectedPos: 'n.',
        cixingController: TextEditingController(text: 'n.'),
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
      title: Text('编辑释义: ${widget.word.word.spell}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '提示：编辑后将保存为自定义释义',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ...controllers.asMap().entries.map((entry) {
                int index = entry.key;
                var controller = entry.value;
                return _buildMeaningItemEditor(index, controller);
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
        if (controllers.any((c) => c.isCustom))
          TextButton(
            onPressed: _handleRestoreDefault,
            child: const Text('恢复默认', style: TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Widget _buildMeaningItemEditor(int index, MeaningItemController controller) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: controller.isCustom ? Colors.blue.shade50 : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '释义 ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (controller.isCustom)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '自定义',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => _removeMeaningItem(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: controller.selectedPos,
                  decoration: const InputDecoration(
                    labelText: '词性',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  items: posList.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      controller.selectedPos = newValue!;
                      if (newValue != '其他') {
                        controller.cixingController.text = newValue;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (controller.selectedPos == '其他')
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: controller.cixingController,
                    decoration: const InputDecoration(
                      hintText: '输入词性',
                      labelText: '其他词性',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller.meaningController,
            decoration: const InputDecoration(
              hintText: '输入释义 (例如: 脸;脸面)',
              labelText: '释义内容',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: null,
            minLines: 1,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    // 收集所有非空的释义
    List<Map<String, String>> newMeanings = [];
    for (var controller in controllers) {
      final meaning = controller.meaningController.text.trim();
      final cixing = controller.cixingController.text.trim();
      if (meaning.isNotEmpty) {
        newMeanings.add({'cixing': cixing, 'meaning': meaning});
      }
    }

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
      widget.word.word.meaningItems = newMeanings.map((e) => MeaningItemVo.from(e['cixing']!, e['meaning']!)).toList();

      // 同时也更新 shortDesc 以便页面列表立刻显示最新内容
      widget.word.word.shortDesc = newMeanings.map((e) {
        String cx = e['cixing'] ?? '';
        String m = e['meaning'] ?? '';
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
      Get.back();
      ToastUtil.info('已恢复默认释义');
      widget.onSuccess();
    }
  }
}

class MeaningItemController {
  String selectedPos;
  final TextEditingController cixingController;
  final TextEditingController meaningController;
  final bool isCustom;

  MeaningItemController({
    required this.selectedPos,
    required this.cixingController,
    required this.meaningController,
    required this.isCustom,
  });

  void dispose() {
    cixingController.dispose();
    meaningController.dispose();
  }
}
