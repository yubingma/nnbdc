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
              color: textMain,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.2,
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

  static Widget buildWordMeaning(
    WordWrapper word,
    bool isDarkMode, {
    double topPadding = 8,
    AppThemeConfig? themeConfig,
  }) {
    final meaningStr = word.word.getMeaningStr();
    final textMeaning = themeConfig?.textPrimary ??
        (isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B));
    final posColor = themeConfig?.textMuted.withValues(alpha: 0.85) ??
        (isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B));

    final posRegex = RegExp(
        r'(n\.|v\.|adj\.|adv\.|vt\.|vi\.|prep\.|conj\.|pron\.|art\.|num\.|int\.)\s*');
    final matches = posRegex.allMatches(meaningStr);

    Widget content;
    if (matches.isEmpty) {
      content = Text(
        meaningStr.isNotEmpty ? meaningStr : "（暂无释义）",
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textMeaning,
          height: 1.45,
          letterSpacing: 0.15,
        ),
      );
    } else {
      final List<InlineSpan> spans = [];
      int lastEnd = 0;

      for (final match in matches) {
        if (match.start > lastEnd) {
          spans.add(TextSpan(
            text: meaningStr.substring(lastEnd, match.start),
            style: TextStyle(
              color: textMeaning,
              fontSize: 13,
              height: 1.45,
            ),
          ));
        }
        final posText = match.group(1)!;
        spans.add(TextSpan(
          text: '$posText ',
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'NotoSans',
            fontWeight: FontWeight.w500,
            color: posColor,
            letterSpacing: 0.1,
          ),
        ));
        lastEnd = match.end;
      }

      if (lastEnd < meaningStr.length) {
        spans.add(TextSpan(
          text: meaningStr.substring(lastEnd),
          style: TextStyle(
            color: textMeaning,
            fontSize: 13,
            height: 1.45,
          ),
        ));
      }

      content = RichText(
        text: TextSpan(children: spans),
        textScaler: const TextScaler.linear(1.0),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        child: content,
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
