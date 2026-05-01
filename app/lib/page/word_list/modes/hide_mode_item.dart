import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import '../word_list_actions.dart';
import 'word_list_item_layout.dart';
import 'mode_components.dart';

class HideModeItem extends StatelessWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final bool isBookmarked;
  final bool isDarkMode;
  final bool? learningStatus;
  final bool showWordProgress;
  final WordListStudyMode studyMode;
  final WordListActionHandler actions;
  final List<SlidableAction> slidableActions;

  const HideModeItem({
    super.key,
    required this.word,
    required this.index,
    required this.baseIndex,
    required this.isBookmarked,
    required this.isDarkMode,
    required this.learningStatus,
    required this.showWordProgress,
    required this.studyMode,
    required this.actions,
    required this.slidableActions,
  });

  @override
  Widget build(BuildContext context) {
    final bool isHideEnglish = studyMode == WordListStudyMode.hideEnglish;

    return WordListItemLayout(
      word: word,
      index: index,
      baseIndex: baseIndex,
      studyMode: studyMode,
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
          child: isHideEnglish
              ? ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0)
              : ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode),
        ),
      ),
      rightContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onToggleAnswer(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: _buildHiddenAnswerArea(isHideEnglish),
        ),
      ),
    );
  }

  Widget _buildHiddenAnswerArea(bool isEnglish) {
    final Widget answerContent = isEnglish
        ? ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode)
        : ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0);

    if (word.isAnswerRevealed) {
      return answerContent;
    }

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Opacity(
          opacity: 0.0,
          child: answerContent,
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDarkMode ? Colors.white10 : Colors.black12,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 14,
                color: isDarkMode ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 6),
              Text(
                isEnglish ? '点击显示英文' : '点击显示中文',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
