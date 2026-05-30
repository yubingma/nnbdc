import 'package:flutter/material.dart';
import 'package:nnbdc/util/word_util.dart';

/// 词表页面通用的子组件（如单词标题、释义等）
class ModeComponents {
  static Widget buildWordHeader(WordWrapper word, bool isBookmarked, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            word.word.spell,
            softWrap: false,
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              color: isBookmarked
                  ? const Color(0xFF0097A7)
                  : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.3,
              letterSpacing: 0.3,
            ),
          ),
        ),
        if (word.word.mergedPronounce.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '[${word.word.mergedPronounce}]',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              color: isDarkMode ? Colors.white38 : Colors.black38,
              fontSize: 12,
              fontFamily: 'NotoSans',
              fontWeight: FontWeight.w400,
              height: 1.3,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ],
    );
  }

  static Widget buildWordMeaning(WordWrapper word, bool isDarkMode, {double topPadding = 8}) {
    final meaning = word.word.getMeaningStr();
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        child: Text(
          meaning.isNotEmpty ? meaning : "（暂无释义）",
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
            height: 1.5,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  static Widget buildAudioIndicator(
      WordWrapper word, bool isBookmarked, Widget? audioLevelBar) {
    if (isBookmarked && audioLevelBar != null) {
      // 当前单词显示波形
      return Container(
        width: 32,
        height: 12,
        margin: const EdgeInsets.only(top: 3),
        child: audioLevelBar,
      );
    } else if (word.pronunciationScore != null &&
        word.pronunciationScore! > 0) {
      // 已过单词显示评分
      return Container(
        width: 32,
        height: 12,
        margin: const EdgeInsets.only(top: 3),
        alignment: Alignment.center,
        child: Text(
          '${word.pronunciationScore}',
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.w600,
            fontFamily: 'RobotoCondensed',
            color:
                word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
