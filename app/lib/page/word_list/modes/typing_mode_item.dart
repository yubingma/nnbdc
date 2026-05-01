import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/utils.dart';
import '../word_list_actions.dart';
import 'word_list_item_layout.dart';
import 'mode_components.dart';

/// 键盘拼写模式：用户通过虚拟键盘输入单词拼写
class TypingModeItem extends StatelessWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final bool isBookmarked;
  final bool isDarkMode;
  final bool? learningStatus;
  final bool showWordProgress;
  final WordListActionHandler actions;
  final List<Widget> slidableActions;

  const TypingModeItem({
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
      studyMode: WordListStudyMode.dictation,
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
      rightContent: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTextField(),
            if (word.hintLetterCount > 0)
              _buildHint(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return AnimatedBuilder(
      animation: word.focusNode,
      builder: (context, child) {
        return TextField(
          readOnly: false,
          enableInteractiveSelection: true,
          controller: word.spellController,
          focusNode: word.focusNode,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            isCollapsed: true,
            border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0097A7))),
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => actions.onWordTap(word, index),
          onChanged: (value) => actions.onSpellChanged(word, index, value),
          style: TextStyle(
            fontSize: 16,
            color: Util.equalsIgnoreCase(word.word.spell, word.spellController.text)
                ? word.isAnswerProvidedBySystem
                    ? (isDarkMode ? Colors.white : const Color(0xFF1F2937))
                    : Colors.green
                : Colors.red,
          ),
        );
      },
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
}
