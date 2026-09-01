import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';
import '../../../../state.dart';
import '../../../../theme/app_theme.dart';

import '../word_list_actions.dart';
import 'mode_components.dart';
import 'word_list_item_layout.dart';

/// 隐藏模式：包含“隐藏中文”或“隐藏英文”，用户点击后才会揭晓答案
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
      centerContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onWordTap(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          child: isHideEnglish
              ? ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0)
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
        : ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0);

    if (word.isAnswerRevealed) {
      return answerContent;
    }

    final accentColor = themeConfig.primaryColor;
    final btnBg = isDarkMode
        ? accentColor.withValues(alpha: 0.15)
        : themeConfig.subtleBg;
    final btnBorder = isDarkMode
        ? accentColor.withValues(alpha: 0.3)
        : themeConfig.cardBorder;
    final btnTextColor = accentColor;

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Opacity(
          opacity: 0.0,
          child: answerContent,
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          decoration: BoxDecoration(
            color: btnBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: btnBorder,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 13,
                color: btnTextColor,
              ),
              const SizedBox(width: 5),
              Text(
                isEnglish ? '点击显示英文' : '点击显示释义',
                style: TextStyle(
                  fontSize: 12,
                  color: btnTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
