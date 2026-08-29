import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';

import '../word_list_actions.dart';
import 'mode_components.dart';
import 'word_list_item_layout.dart';

/// 听说模式：包含“看中文说英文”和“看英文说单词发音”两种子模式。
/// 该模式会调用 ASR (语音识别) 来检查用户的发音。
class SpeakModeItem extends StatelessWidget {
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
  final Widget? audioLevelBar;

  const SpeakModeItem({
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
    this.audioLevelBar,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSpeakEnglish = studyMode == WordListStudyMode.speakEnglish;

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
      audioIndicator: ModeComponents.buildAudioIndicator(word, isBookmarked, audioLevelBar),
      centerContent: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => actions.onWordTap(word, index),
        onLongPress: () => actions.onWordLongPress(word, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
          child: isSpeakEnglish
              ? ModeComponents.buildWordMeaning(word, isDarkMode, topPadding: 0)
              : ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode),
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
          child: isSpeakEnglish
              ? _buildSpeakEnglishArea()
              : _buildSpeakChineseArea(),
        ),
      ),
    );
  }

  Widget _buildSpeakChineseArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...renderAsrMeaningItems(word, isDarkMode: isDarkMode),
        if (word.isAiEvaluating) ...[
          const SizedBox(height: 4),
          _buildAiJudgingBadge(),
        ],
      ],
    );
  }

  Widget _buildAiJudgingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 8.5,
            height: 8.5,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(width: 3.5),
          Text(
            'AI判定中...',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakEnglishArea() {
    if (word.speakEnglishPassed) {
      return _buildSpeakEnglishPassed();
    } else {
      return _buildSpeakEnglishNotPassed();
    }
  }

  Widget _buildSpeakEnglishNotPassed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              isBookmarked
                  ? (word.hintLetterCount > 0
                      ? word.word.spell.substring(0, word.hintLetterCount)
                      : '请说出单词发音')
                  : (word.hintLetterCount > 0
                      ? word.word.spell.substring(0, word.hintLetterCount)
                      : ''),
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : const Color(0xFF4B5563),
                height: 1.2,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

      ],
    );
  }

  Widget _buildSpeakEnglishPassed() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode),
        ),
      ],
    );
  }
}
