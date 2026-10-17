import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/meaning_render_util.dart';
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
    // 小结的错词着色（口径见 StudyBo.getTodayWrongWordIds）：
    // - 测评就没答对 → 红色（与「答错」轨道同一判据）；
    // - 测评答对、后来巩固环节又答错 → 次级警示琥珀（与词根组头行同一个琥珀，暗色下自动提亮）；
    // - 其余保持正常字色。两种都算"今天没拿下"，但成因不同，不混为一谈。
    final spellColor = word.isWrongToday
        ? FsrsRating.again.colorWithDark(isDarkMode)
        : (word.isWrongLaterToday
            ? FsrsRating.hard.colorWithDark(isDarkMode)
            : textMain);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  word.word.spell,
                  softWrap: false,
                  style: TextStyle(
                    color: spellColor,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            if (word.word.wrongCount != null && word.word.wrongCount! >= 3) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: (isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: (isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706)).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '错${word.word.wrongCount}次',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (word.word.mergedPronounce.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            '[${word.word.mergedPronounce}]',
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

    final spans = MeaningRenderUtil.buildInlineMeaningSpans(
      word: word.word,
      meaningStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: textMeaning,
        height: 1.45,
        letterSpacing: 0.15,
      ),
      posStyle: TextStyle(
        fontSize: 12,
        fontFamily: 'NotoSans',
        fontWeight: FontWeight.w500,
        color: posColor,
        letterSpacing: 0.1,
      ),
      dotColor: textMeaning,
    );

    final Widget content = RichText(
      text: TextSpan(children: spans),
    );

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
