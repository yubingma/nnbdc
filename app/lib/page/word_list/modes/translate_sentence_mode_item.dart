import 'package:flutter/material.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:provider/provider.dart';
import '../../../../state.dart';
import '../../../../theme/app_theme.dart';

import '../word_list_actions.dart';
import 'mode_components.dart';
import 'word_list_item_layout.dart';

/// 翻译例句模式列表项组件（上下排版）：
/// 上半部分展示英文例句（带核心词加粗高亮）及单词拼写与发音指示器；
/// 下半部分展示例句的中文翻译（当前激活单词显示“请说出例句翻译”与“显示答案”按钮/实时识别回显/通过高亮显示）。
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
  final GroupCardPosition groupPosition;

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
    this.groupPosition = GroupCardPosition.single,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPassed = word.sentenceTranslatedPassed || word.isAnswerRevealed;
    final bool showBottomArea = isPassed || isBookmarked;

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
      groupPosition: groupPosition,
      audioIndicator: null,
      centerContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 上半部分：英文例句 + 单词信息 + 波形
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => actions.onWordTap(word, index),
              onLongPress: () => actions.onWordLongPress(word, index),
              child: _buildEnglishSentenceArea(context),
            ),
            if (showBottomArea) ...[
              const SizedBox(height: 6),
              // 下半部分：中文翻译 / 语音识别回显 / 提示区
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!isBookmarked) {
                    actions.onWordTap(word, index);
                  }
                },
                onLongPress: () => actions.onWordLongPress(word, index),
                child: isPassed
                    ? _buildTranslatedPassed()
                    : _buildTranslateNotPassed(),
              ),
            ],
          ],
        ),
      ),
      rightContent: null,
    );
  }

  Widget _buildEnglishSentenceArea(BuildContext context) {
    if (word.currentSentence != null && (word.currentSentence!.english ?? '').isNotEmpty) {
      return _buildSentenceContent(word.currentSentence!.english!, context);
    }

    if (word.word.sentences != null && word.word.sentences!.isNotEmpty) {
      word.currentSentence = word.word.sentences!.first;
      if ((word.currentSentence!.english ?? '').isNotEmpty) {
        return _buildSentenceContent(word.currentSentence!.english!, context);
      }
    }

    return FutureBuilder<List<SentenceVo>>(
      future: word.word.getSentences(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data!.isNotEmpty) {
          word.currentSentence ??= snapshot.data!.first;
          if ((word.currentSentence!.english ?? '').isNotEmpty) {
            return _buildSentenceContent(word.currentSentence!.english!, ctx);
          }
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return _buildNoSentenceHeader();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ModeComponents.buildWordHeader(word, isBookmarked, isDarkMode),
            const SizedBox(height: 2),
            Text(
              '加载例句中...',
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.white38 : Colors.black38,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSentenceContent(String sentenceEn, BuildContext context) {
    final spell = word.word.spell;
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);
    final accentColor = themeConfig.primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRichSentence(
          sentenceEn,
          TextStyle(
            color: isBookmarked
                ? (isDarkMode ? Colors.white : const Color(0xFF152724))
                : (isDarkMode ? const Color(0xFFC8DCD8) : const Color(0xFF334B46)),
            fontSize: 14.5,
            fontWeight: FontWeight.w400,
            height: 1.35,
          ),
          boldStyle: TextStyle(
            color: isBookmarked
                ? accentColor
                : (isDarkMode ? Colors.white : const Color(0xFF152724)),
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              spell,
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 11,
                color: isDarkMode ? Colors.white38 : Colors.black38,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (isBookmarked && audioLevelBar != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 32,
                height: 12,
                child: audioLevelBar,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildNoSentenceHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
    );
  }

  Widget _buildTranslateNotPassed() {
    final bool hasLiveAsr = isBookmarked && (word.lastAsrResult != null && word.lastAsrResult!.isNotEmpty);
    final String liveAsrText = word.lastAsrResult ?? '';
    final int? score = hasLiveAsr ? word.pronunciationScore : null;
    final bool isCoreMatched = hasLiveAsr
        ? isChineseSentenceCoreKeywordsMatched(
            liveAsrText,
            word.currentSentence?.chinese ?? word.word.getMeaningStr(),
            word.word,
            targetPinyinsCache: word.targetPinyinsCache,
          )
        : false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: hasLiveAsr
            ? (isDarkMode ? const Color(0xFF0097A7).withValues(alpha: 0.12) : const Color(0xFFE0F7FA))
            : (isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasLiveAsr
              ? const Color(0xFF0097A7).withValues(alpha: 0.5)
              : (isDarkMode ? Colors.white12 : Colors.grey[300]!),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              hasLiveAsr ? liveAsrText : '请说出例句翻译',
              textScaler: const TextScaler.linear(1.0),
              softWrap: true,
              style: TextStyle(
                fontSize: 13.5,
                color: hasLiveAsr
                    ? (isDarkMode ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
                    : (isDarkMode ? Colors.white38 : Colors.black38),
                height: 1.35,
                letterSpacing: 0.3,
                fontStyle: hasLiveAsr ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
          if (word.isAiEvaluating) ...[
            const SizedBox(width: 6),
            _buildAiJudgingBadge(),
          ] else if (score != null && score > 0) ...[
            const SizedBox(width: 6),
            _buildScoreBadge(score, isCoreMatched: isCoreMatched, isPassed: word.sentenceTranslatedPassed),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => actions.onToggleAnswer(word, index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDarkMode ? Colors.white24 : Colors.black12,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 13,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '显示答案',
                    textScaler: const TextScaler.linear(1.0),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslatedPassed() {
    final translation = word.currentSentence?.chinese ?? word.word.getMeaningStr();
    final baseStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      color: isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
      height: 1.35,
    );

    final score = word.pronunciationScore;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF4ADE80).withValues(alpha: 0.08)
            : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDarkMode
              ? const Color(0xFF4ADE80).withValues(alpha: 0.3)
              : const Color(0xFF86EFAC),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: translation.isEmpty
                ? Text('已通过', textScaler: const TextScaler.linear(1.0), style: baseStyle)
                : _buildRichSentence(
                    translation,
                    baseStyle,
                    boldStyle: baseStyle.copyWith(fontWeight: FontWeight.bold),
                  ),
          ),
          if (word.isAiEvaluatedPassed) ...[
            const SizedBox(width: 6),
            _buildAiRefereeBadge(),
          ] else if (score != null && score > 0) ...[
            const SizedBox(width: 6),
            _buildScoreBadge(score, isCoreMatched: true, isPassed: true),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => actions.onToggleAnswer(word, index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDarkMode ? Colors.white24 : Colors.black12,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 13,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '隐藏答案',
                    textScaler: const TextScaler.linear(1.0),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildAiRefereeBadge() {
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
          Icon(
            Icons.auto_awesome,
            size: 11,
            color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
          ),
          const SizedBox(width: 2.5),
          Text(
            'AI判定',
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

  Widget _buildScoreBadge(int score, {bool isCoreMatched = false, bool isPassed = false}) {
    final bool isGood = isPassed || (score >= 60 && isCoreMatched);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: (isGood ? Colors.green : Colors.orange).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: (isGood ? Colors.green : Colors.orange).withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isGood
              ? (isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
              : Colors.orange,
        ),
      ),
    );
  }

  /// 解析包含 <b>...</b> 或其他 XML/HTML 标签的句子并渲染为富文本
  Widget _buildRichSentence(
    String text,
    TextStyle baseStyle, {
    TextStyle? boldStyle,
  }) {
    final List<TextSpan> spans = [];
    final RegExp regExp = RegExp(r"<b>(.*?)</b>", caseSensitive: false);
    int lastMatchEnd = 0;

    for (final match in regExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        final beforeText = text
            .substring(lastMatchEnd, match.start)
            .replaceAll(RegExp(r'<[^>]*>'), '');
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(text: beforeText, style: baseStyle));
        }
      }
      final boldText =
          (match.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '');
      if (boldText.isNotEmpty) {
        spans.add(TextSpan(
          text: boldText,
          style: boldStyle ?? baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      }
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      final afterText =
          text.substring(lastMatchEnd).replaceAll(RegExp(r'<[^>]*>'), '');
      if (afterText.isNotEmpty) {
        spans.add(TextSpan(text: afterText, style: baseStyle));
      }
    }

    if (spans.isEmpty) {
      final cleanText = text.replaceAll(RegExp(r'<[^>]*>'), '');
      spans.add(TextSpan(text: cleanText, style: baseStyle));
    }

    return Text.rich(
      TextSpan(children: spans),
      textScaler: const TextScaler.linear(1.0),
    );
  }
}
