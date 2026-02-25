import 'package:flutter/material.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:provider/provider.dart';

import '../../../api/enum.dart';
import '../../../state.dart';
import '../../../util/word_util.dart';

abstract class WordProgressProvider {
  double getWordProgress(dynamic wordTag);
  double getWordProgressMax(dynamic wordTag);
}

class WordItem extends StatelessWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final bool isBookmarked;
  final bool showWordProgress;
  final String wordProgressLabel;
  final WordProgressProvider wordProgressProvider;
  final WordListStudyMode studyMode;
  final bool showDelBtn;
  final String appBarTitle;
  final dynamic asrResult;
  final Widget? audioLevelBar;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onHintTap;
  final VoidCallback? onClearHintTap;
  final VoidCallback? onDeleteTap;
  final VoidCallback? onMasterTap;

  const WordItem({
    super.key,
    required this.word,
    required this.index,
    required this.baseIndex,
    required this.isBookmarked,
    required this.showWordProgress,
    required this.wordProgressLabel,
    required this.wordProgressProvider,
    required this.studyMode,
    required this.showDelBtn,
    required this.appBarTitle,
    this.asrResult,
    this.audioLevelBar,
    this.onTap,
    this.onLongPress,
    this.onHintTap,
    this.onClearHintTap,
    this.onDeleteTap,
    this.onMasterTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;

    return Container(
      margin: EdgeInsets.only(
        left: 4,
        right: 4,
        top: 4,
        bottom: 4, // Will be adjusted by parent
      ),
      decoration: _buildDecoration(isDarkMode),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              focusColor: Colors.transparent,
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildNumberColumn(isDarkMode),
                    const SizedBox(width: 12),
                    Expanded(child: _buildWordContent(isDarkMode)),
                  ],
                ),
              ),
            ),
          ),
          if (showDelBtn || _shouldShowActionButtons()) _buildActionButtons(isDarkMode),
        ],
      ),
    );
  }

  BoxDecoration _buildDecoration(bool isDarkMode) {
    return BoxDecoration(
      gradient: isBookmarked
          ? LinearGradient(
              colors: [
                const Color(0xFF0097A7).withValues(alpha: 0.08),
                const Color(0xFF00ACC1).withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      color: isBookmarked
          ? null
          : isDarkMode
              ? const Color(0xFF1E1E1E).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(12),
      border: isBookmarked
          ? Border.all(
              width: 2,
              color: const Color(0xFF0097A7).withValues(alpha: 0.3),
            )
          : Border.all(
              width: 1,
              color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
            ),
      boxShadow: [
        BoxShadow(
          color: isBookmarked ? const Color(0xFF0097A7).withValues(alpha: 0.2) : (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
          blurRadius: isBookmarked ? 8 : 4,
          offset: Offset(0, isBookmarked ? 4 : 2),
        ),
      ],
    );
  }

  Widget _buildNumberColumn(bool isDarkMode) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isBookmarked ? [const Color(0xFF0097A7), const Color(0xFF00ACC1)] : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: (isBookmarked ? const Color(0xFF0097A7) : Colors.grey).withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${(baseIndex + index + 1) > 0 ? (baseIndex + index + 1) : 1}',
              textScaler: TextScaler.linear(1.0),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        if (showWordProgress)
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 4),
            child: FAProgressBar(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              currentValue: wordProgressProvider.getWordProgress(word.tag),
              maxValue: wordProgressProvider.getWordProgressMax(word.tag),
              displayText: '',
              direction: Axis.horizontal,
              displayTextStyle: const TextStyle(color: Color(0x00000000)),
              backgroundColor: isDarkMode ? const Color(0xFF404040) : const Color(0xFFE5E7EB),
              progressColor: _getProgressColor(),
              animatedDuration: const Duration(milliseconds: 200),
            ),
          ),
        if ((studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) && isBookmarked)
          Container(
            width: 32,
            height: 12,
            margin: const EdgeInsets.only(top: 3),
            child: audioLevelBar ?? const SizedBox(),
          )
        else if (word.pronunciationScore != null && word.pronunciationScore! > 0)
          Container(
            width: 32,
            height: 12,
            margin: const EdgeInsets.only(top: 3),
            alignment: Alignment.center,
            child: Text(
              '${word.pronunciationScore}',
              textScaler: TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w900,
                fontFamily: 'RobotoCondensed',
                color: word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWordContent(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (studyMode != WordListStudyMode.dictation && studyMode != WordListStudyMode.speakEnglish) _buildWordAndPronounce(isDarkMode),
        if (studyMode == WordListStudyMode.list || studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.speakEnglish)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              word.word.getMeaningStr(),
              textScaler: TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                height: 1.5,
                letterSpacing: 0.3,
              ),
            ),
          ),
        if (studyMode == WordListStudyMode.dictation && isBookmarked)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(word.word.spell.substring(0, word.hintLetterCount)),
              ],
            ),
          ),
        if (studyMode == WordListStudyMode.dictation) _buildDictationInput(isDarkMode),
        if (studyMode == WordListStudyMode.speakChinese)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildAsrMeaningItems(),
          ),
        if (studyMode == WordListStudyMode.speakEnglish) _buildSpeakEnglishContent(isDarkMode),
      ],
    );
  }

  Widget _buildWordAndPronounce(bool isDarkMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spellWidth = word.word.spell.length * 11.0;
        final pronounceWidth = word.word.mergedPronounce.isNotEmpty ? (word.word.mergedPronounce.length * 7.0 + 24.0) : 0.0;
        final totalWidth = spellWidth + pronounceWidth + 16.0;
        final shouldWrap = totalWidth > constraints.maxWidth || word.word.mergedPronounce.length > 25;

        if (shouldWrap && word.word.mergedPronounce.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                word.word.spell,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  letterSpacing: 0.3,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '[${word.word.mergedPronounce}]',
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                      fontSize: 12,
                      fontFamily: 'NotoSans',
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          );
        } else {
          return Row(
            children: [
              Flexible(
                child: Text(
                  word.word.spell,
                  textScaler: TextScaler.linear(1.0),
                  style: TextStyle(
                    color: isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (word.word.mergedPronounce.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '[${word.word.mergedPronounce}]',
                      textScaler: TextScaler.linear(1.0),
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                        fontSize: 12,
                        fontFamily: 'NotoSans',
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ],
          );
        }
      },
    );
  }

  Widget _buildDictationInput(bool isDarkMode) {
    return AnimatedBuilder(
      animation: word.focusNode,
      builder: (context, child) {
        final hasFocus = word.focusNode.hasFocus;
        final fontSize = hasFocus ? 22.0 : 16.0;
        return TextField(
          controller: word.spellController,
          focusNode: word.focusNode,
          keyboardType: TextInputType.visiblePassword,
          decoration: const InputDecoration(
            isCollapsed: true,
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF0097A7)),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          style: TextStyle(
            fontSize: fontSize,
            color: _getInputTextColor(),
          ),
        );
      },
    );
  }

  Widget _buildSpeakEnglishContent(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        if (!word.speakEnglishPassed) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              constraints: const BoxConstraints(minWidth: 120),
              padding: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDarkMode ? Colors.white38 : (Colors.grey[500] ?? Colors.grey),
                    width: 1.0,
                  ),
                ),
              ),
              child: Text(
                isBookmarked
                    ? (word.hintLetterCount > 0
                        ? word.word.spell.substring(0, word.hintLetterCount)
                        : ((asrResult is String && (asrResult as String).isNotEmpty) ? (asrResult as String) : '请说出单词发音'))
                    : '',
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode ? Colors.white54 : Colors.grey[600],
                  height: 1.2,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          if (isBookmarked && word.pronunciationScore != null && word.pronunciationScore! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: word.pronunciationScore! >= 60 ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.record_voice_over,
                      size: 14,
                      color: word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '发音: ${word.pronunciationScore}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ] else ...[
          _buildPassedWordAndPronounce(isDarkMode),
        ],
      ],
    );
  }

  Widget _buildPassedWordAndPronounce(bool isDarkMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spellWidth = word.word.spell.length * 11.0;
        final pronounceWidth = word.word.mergedPronounce.isNotEmpty ? (word.word.mergedPronounce.length * 7.0 + 24.0) : 0.0;
        final totalWidth = spellWidth + pronounceWidth + 8.0;
        final shouldWrap = totalWidth > constraints.maxWidth || (word.word.mergedPronounce.isNotEmpty && word.word.mergedPronounce.length > 25);

        if (shouldWrap && word.word.mergedPronounce.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.word.spell,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '[${word.word.mergedPronounce}]',
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                      fontSize: 12,
                      fontFamily: 'NotoSans',
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          );
        } else {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  word.word.spell,
                  textScaler: TextScaler.linear(1.0),
                  style: TextStyle(
                    color: isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (word.word.mergedPronounce.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '[${word.word.mergedPronounce}]',
                      textScaler: TextScaler.linear(1.0),
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                        fontSize: 12,
                        fontFamily: 'NotoSans',
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ],
          );
        }
      },
    );
  }

  Widget _buildActionButtons(bool isDarkMode) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 60),
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_shouldShowActionButtons()) ...[
            if (onHintTap != null)
              _buildActionButton(
                icon: Icons.lightbulb,
                color: const Color(0xFFFFA726),
                onTap: onHintTap!,
              ),
            if (onClearHintTap != null) ...[
              const SizedBox(height: 6),
              _buildActionButton(
                icon: Icons.lightbulb_outline,
                color: const Color(0xFF9E9E9E),
                onTap: onClearHintTap!,
              ),
            ],
          ],
          if (onMasterTap != null) ...[
            if (_shouldShowActionButtons()) const SizedBox(height: 6),
            _buildActionButton(
              icon: Icons.check,
              color: const Color(0xFF4CAF50),
              onTap: onMasterTap!,
            ),
          ],
          if (showDelBtn && onDeleteTap != null) ...[
            if (_shouldShowActionButtons() || onMasterTap != null) const SizedBox(height: 6),
            _buildActionButton(
              icon: _getActionIcon(),
              color: _getActionColor(),
              onTap: onDeleteTap!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 22,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAsrMeaningItems() {
    // This would need to be implemented based on the original renderAsrMeaningItems method
    return [];
  }

  bool _shouldShowActionButtons() {
    return (studyMode == WordListStudyMode.dictation || studyMode == WordListStudyMode.speakChinese || studyMode == WordListStudyMode.speakEnglish) &&
        isBookmarked;
  }

  Color _getProgressColor() {
    double ratio = wordProgressProvider.getWordProgress(word.tag) / wordProgressProvider.getWordProgressMax(word.tag);
    if (ratio < 0.4) return Colors.red;
    if (ratio < 0.6) return Colors.orange;
    if (ratio < 0.8) return Colors.blueGrey;
    if (ratio < 1.0) return Colors.blue;
    return Colors.green;
  }

  Color _getInputTextColor() {
    // This would need access to Util.equalsIgnoreCase and word.spellController.text
    // For now, return a default color
    return Colors.red;
  }

  IconData _getActionIcon() {
    switch (appBarTitle) {
      case '已掌握':
        return Icons.refresh;
      case '学习中':
      case '单词列表':
      case '今日错词':
      case '今日新词':
      case '今日旧词':
      case '今日单词':
        return Icons.check;
      case '生词本':
      default:
        return Icons.delete;
    }
  }

  Color _getActionColor() {
    switch (appBarTitle) {
      case '已掌握':
        return const Color(0xFF2196F3);
      case '学习中':
      case '单词列表':
      case '今日错词':
      case '今日新词':
      case '今日旧词':
      case '今日单词':
        return const Color(0xFF4CAF50);
      case '生词本':
      default:
        return const Color(0xFFEF5350);
    }
  }
}
