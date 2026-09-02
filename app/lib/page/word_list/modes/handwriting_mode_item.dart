import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:provider/provider.dart';
import '../../../../state.dart';
import '../../../../theme/app_theme.dart';
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
  final GroupCardPosition groupPosition;

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
    this.groupPosition = GroupCardPosition.single,
  });

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

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
      groupPosition: groupPosition,
      centerContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onWordTap(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildReadOnlyTextField(themeConfig),
              _buildHint(),
            ],
          ),
        ),
      ),
      rightContent: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => actions.onWordTap(word, index),
                onLongPress: () => actions.onWordLongPress(word, index),
                child: ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0),
              ),
            ),
            _buildHandwritingButton(themeConfig),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyTextField(AppThemeConfig themeConfig) {
    final accentColor = themeConfig.primaryColor;
    final textNormal = themeConfig.textPrimary;

    return TextField(
      readOnly: true,
      enableInteractiveSelection: false,
      controller: word.spellController,
      decoration: InputDecoration(
        isCollapsed: true,
        border: UnderlineInputBorder(borderSide: BorderSide(color: isDarkMode ? Colors.white24 : Colors.black26)),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDarkMode ? Colors.white24 : Colors.black26)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor)),
        contentPadding: EdgeInsets.zero,
        hintText: '请在屏幕手写拼写',
        hintStyle: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white38 : const Color(0xFF8EA8A3)),
      ),
      onTap: () => actions.onWordTap(word, index),
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Util.equalsIgnoreCase(word.word.spell, word.spellController.text)
            ? word.isAnswerProvidedBySystem
                ? textNormal
                : accentColor
            : Colors.redAccent,
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

  Widget _buildHandwritingButton(AppThemeConfig themeConfig) {
    final accentColor = themeConfig.primaryColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => actions.onHandwritingPressed(word, index),
      child: Container(
        width: 50,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Icon(
          Icons.edit_rounded,
          size: 20,
          color: isBookmarked
              ? accentColor
              : (isDarkMode ? Colors.white38 : const Color(0xFF789691)),
        ),
      ),
    );
  }
}
