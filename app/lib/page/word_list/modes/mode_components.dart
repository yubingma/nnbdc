import 'package:flutter/material.dart';
import 'package:nnbdc/util/word_util.dart';
import '../../../../theme/app_theme.dart';

/// 词表页面通用的子组件（如单词标题、释义等）
class ModeComponents {
  static Widget buildWordHeader(
    WordWrapper word,
    bool isBookmarked,
    bool isDarkMode, {
    AppThemeConfig? themeConfig,
  }) {
    final accentColor = themeConfig?.primaryColor ?? (isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C));
    final textMain = themeConfig?.textPrimary ?? (isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724));
    final textSub = themeConfig?.textSecondary ?? (isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5A7570));

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
              color: isBookmarked ? accentColor : textMain,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (word.word.mergedPronounce.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            '[${word.word.mergedPronounce}]',
            textScaler: const TextScaler.linear(1.0),
            style: TextStyle(
              color: textSub,
              fontSize: 12,
              fontFamily: 'NotoSans',
              fontWeight: FontWeight.w400,
              height: 1.2,
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
    final textMeaning = isDarkMode ? const Color(0xFFC8DCD8) : const Color(0xFF334B46);

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        child: Text(
          meaning.isNotEmpty ? meaning : "（暂无释义）",
          textScaler: const TextScaler.linear(1.0),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w400,
            color: textMeaning,
            height: 1.45,
            letterSpacing: 0.15,
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
