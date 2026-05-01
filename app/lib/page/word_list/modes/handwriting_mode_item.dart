import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/utils.dart';
import '../word_list_actions.dart';
import 'word_list_item_layout.dart';
import 'mode_components.dart';

/// 手写模式：用户通过全屏手写面板输入单词拼写
class HandwritingModeItem extends StatelessWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final bool isBookmarked;
  final bool isDarkMode;
  final bool? learningStatus;
  final bool showWordProgress;
  final WordListActionHandler actions;
  final List<Widget> slidableActions;

  const HandwritingModeItem({
    super.key,
    required this.word,
    required this.index,
    required this.baseIndex,
    required this.isBookmarked,
    required this.isDarkMode,
    required this.learningStatus,
    required this.showWordProgress,
    required this.actions,
    required this.slidableActions,
  });

  @override
  Widget build(BuildContext context) {
    return WordListItemLayout(
      word: word,
      index: index,
      baseIndex: baseIndex,
      studyMode: WordListStudyMode.dictationHandwriting,
      isBookmarked: isBookmarked,
      isDarkMode: isDarkMode,
      learningStatus: learningStatus,
      showWordProgress: showWordProgress,
      actions: actions,
      slidableActions: slidableActions,
      centerContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onWordTap(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          child: ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0),
        ),
      ),
      rightContent: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildReadOnlyTextField(),
                if (word.hintLetterCount > 0)
                  _buildHint(),
              ],
            ),
          ),
          _buildHandwritingButton(),
        ],
      ),
    );
  }

  Widget _buildReadOnlyTextField() {
    return TextField(
      readOnly: true,
      enableInteractiveSelection: false,
      controller: word.spellController,
      decoration: InputDecoration(
        isCollapsed: true,
        border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        contentPadding: EdgeInsets.zero,
        hintText: '请在屏幕手写拼写',
        hintStyle: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white24 : Colors.black26),
      ),
      onTap: () => actions.onWordTap(word, index),
      style: TextStyle(
        fontSize: 16,
        color: Util.equalsIgnoreCase(word.word.spell, word.spellController.text)
            ? word.isAnswerProvidedBySystem
                ? (isDarkMode ? Colors.white : const Color(0xFF1F2937))
                : Colors.green
            : Colors.red,
      ),
    );
  }

  Widget _buildHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Text(
        word.word.spell.substring(0, word.hintLetterCount),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  Widget _buildHandwritingButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => actions.onHandwritingPressed(word, index),
      child: Container(
        width: 60,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Icon(
            Icons.edit_rounded,
            size: 20,
            color: isBookmarked
                ? const Color(0xFF0097A7)
                : (isDarkMode ? Colors.white38 : Colors.black38),
          ),
        ),
      ),
    );
  }
}
