import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';

import '../word_list_actions.dart';
import 'mode_components.dart';
import 'word_list_item_layout.dart';

/// 翻译例句模式列表项组件：
/// 左侧展示随机选出的英文例句，右侧展示例句的中文翻译（未答对前隐藏/展示提示，答对后高亮显示中文翻译）。
class TranslateSentenceModeItem extends StatelessWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final bool isBookmarked;
  final bool isDarkMode;
  final bool? learningStatus;
  final bool showWordProgress;
  final WordListActionHandler actions;
  final List<Widget> slidableActions;
  final Widget? audioLevelBar;

  const TranslateSentenceModeItem({
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
    this.audioLevelBar,
  });

  @override
  Widget build(BuildContext context) {
    return WordListItemLayout(
      word: word,
      index: index,
      baseIndex: baseIndex,
      studyMode: WordListStudyMode.translateSentence,
      isBookmarked: isBookmarked,
      isDarkMode: isDarkMode,
      learningStatus: learningStatus,
      showWordProgress: showWordProgress,
      actions: actions,
      slidableActions: slidableActions,
      audioIndicator: ModeComponents.buildAudioIndicator(word, isBookmarked, audioLevelBar),
      centerContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onWordTap(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          child: _buildEnglishSentenceArea(),
        ),
      ),
      rightContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isBookmarked) {
            actions.onGiveHint(word);
          } else {
            actions.onWordTap(word, index);
          }
        },
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: word.sentenceTranslatedPassed
              ? _buildTranslatedPassed()
              : _buildTranslateNotPassed(),
        ),
      ),
    );
  }

  Widget _buildEnglishSentenceArea() {
    final sentenceEn = word.currentSentence?.english;
    final spell = word.word.spell;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sentenceEn != null && sentenceEn.isNotEmpty) ...[
          Text(
            sentenceEn,
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              color: isBookmarked
                  ? const Color(0xFF0097A7)
                  : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            spell,
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              fontSize: 11,
              color: isDarkMode ? Colors.white38 : Colors.black38,
              fontStyle: FontStyle.italic,
            ),
          ),
        ] else ...[
          ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode),
          const SizedBox(height: 2),
          Text(
            '（暂无例句）',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTranslateNotPassed() {
    final targetChinese = word.currentSentence?.chinese ?? word.word.getMeaningStr();
    String hintText = '';
    if (word.hintLetterCount > 0) {
      final cleanTarget = targetChinese.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '');
      final count = word.hintLetterCount.clamp(0, cleanTarget.length);
      hintText = cleanTarget.substring(0, count);
    } else if (isBookmarked) {
      hintText = '请说出例句翻译';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDarkMode ? Colors.white38 : Colors.grey[500]!,
                  width: 1.0,
                ),
              ),
            ),
            child: Text(
              hintText,
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : const Color(0xFF4B5563),
                height: 1.3,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranslatedPassed() {
    final translation = word.currentSentence?.chinese ?? word.word.getMeaningStr();
    return Text(
      translation.isNotEmpty ? translation : '已通过',
      textScaler: const TextScaler.linear(1.0),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
        height: 1.35,
      ),
    );
  }
}
