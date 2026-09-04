import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';
import '../../../../state.dart';
import '../../../../theme/app_theme.dart';

import '../word_list_actions.dart';
import 'mode_components.dart';
import 'word_list_item_layout.dart';

/// 遮挡模式：包含“遮挡中文”或“遮挡英文”，用户点击后才会揭晓答案
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
  final List<Widget> slidableActions;
  final GroupCardPosition groupPosition;

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
    this.groupPosition = GroupCardPosition.single,
  });

  @override
  Widget build(BuildContext context) {
    final bool isHideEnglish = studyMode == WordListStudyMode.hideEnglish;
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

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
      groupPosition: groupPosition,
      centerContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onWordTap(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          child: isHideEnglish
              ? ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0, themeConfig: themeConfig)
              : ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode, themeConfig: themeConfig),
        ),
      ),
      rightContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onToggleAnswer(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: _buildHiddenAnswerArea(isHideEnglish, themeConfig),
        ),
      ),
    );
  }

  Widget _buildHiddenAnswerArea(bool isEnglish, AppThemeConfig themeConfig) {
    final Widget answerContent = isEnglish
        ? ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode, themeConfig: themeConfig)
        : ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0, themeConfig: themeConfig);

    if (word.isAnswerRevealed) {
      return answerContent;
    }

    final accentColor = themeConfig.primaryColor;
    final hintColor = isBookmarked
        ? accentColor
        : themeConfig.textMuted.withValues(alpha: 0.6);

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Opacity(
          opacity: 0.0,
          child: answerContent,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 13.5,
                color: hintColor,
              ),
              const SizedBox(width: 4.5),
              Text(
                isEnglish ? '查看英文' : '查看释义',
                style: TextStyle(
                  fontSize: 12,
                  color: hintColor,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
