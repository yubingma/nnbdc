import 'package:flutter/material.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/excel_import_parser.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/word_util.dart';

/// 添加单词弹窗。
///
/// 通用词典已收录的词直接加入当前词表；查不到时展开释义输入，
/// 按 Excel 导入同一条路径自建私有单词（`newSpell`），
/// 用户不必为了一个生词先去整理表格。
class AddWordDialog extends StatefulWidget {
  final WordModifier wordModifier;

  /// 添加成功后的刷新回调（由词表页负责重算分页并重查列表）。
  final Future<void> Function() onAdded;

  const AddWordDialog({
    super.key,
    required this.wordModifier,
    required this.onAdded,
  });

  @override
  State<AddWordDialog> createState() => _AddWordDialogState();
}

class _AddWordDialogState extends State<AddWordDialog> {
  final TextEditingController _spellController = TextEditingController();
  final TextEditingController _meaningController = TextEditingController();

  String _pos = 'n.';

  /// 通用词典查不到该词时置为 true，展开释义输入区。
  bool _needMeaning = false;

  bool _submitting = false;

  @override
  void dispose() {
    _spellController.dispose();
    _meaningController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final rawSpell = _spellController.text.trim();
    if (rawSpell.isEmpty) {
      ToastUtil.error('请输入单词拼写');
      return;
    }

    setState(() => _submitting = true);
    try {
      // 与原来的手动添加保持一致：先按通用词典口径查（含大小写与词形变体）。
      final hit = await WordBo().searchWordLocalOnly(rawSpell);
      if (hit.word != null) {
        final added = await widget.wordModifier.addWord(hit.word!.id!);
        if (added) await _finish();
        return;
      }

      // 通用词典没有这个词：先展开释义输入，让用户补齐后再建词。
      if (!_needMeaning) {
        setState(() => _needMeaning = true);
        return;
      }

      final spell = rawSpell.replaceAll(RegExp(r'\s+'), ' ');
      if (!englishSpellPattern.hasMatch(spell)) {
        ToastUtil.error('拼写只能包含英文字母、空格、撇号、连字符或句点');
        return;
      }

      final meaning = _meaningController.text.trim().replaceAll(RegExp(r'[\r\n；]+'), ';');
      if (meaning.isEmpty) {
        ToastUtil.error('请填写释义后再加入词表');
        return;
      }

      final ciXing = _pos == '无' ? '' : _pos;
      if (ciXing.length > maxCiXingLength) {
        ToastUtil.error('词性最多 $maxCiXingLength 个字符');
        return;
      }

      final stats = await widget.wordModifier.addWords([
        DictWordImportItem(
          wordId: Util.uuid(),
          newSpell: spell,
          meaning: meaning,
          partOfSpeech: ciXing,
        ),
      ]);
      // 写入失败时 addWords 已提示原因，这里只需保持在弹窗里让用户修改。
      if (stats.inserted == 0) return;

      ToastUtil.success('已新建「$spell」并加入词表');
      await _finish();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _finish() async {
    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final hintColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return AlertDialog(
      title: const Text('添加单词'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _spellController,
                autocorrect: false,
                autofocus: !_needMeaning,
                decoration: const InputDecoration(
                  hintText: '输入单词拼写',
                  labelText: '单词',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_needMeaning) ...[
                const SizedBox(height: 16),
                Text(
                  '通用词典中没有这个词。补充释义后可直接建词，加入当前词表。',
                  style: TextStyle(fontSize: 12, color: hintColor),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _pos,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '词性',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  items: wordPosOptions
                      .map((value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _pos = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _meaningController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '多个释义用分号隔开，例如：脸;脸面',
                    labelText: '释义',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? '处理中…' : (_needMeaning ? '加入词表' : '添加')),
        ),
      ],
    );
  }
}
