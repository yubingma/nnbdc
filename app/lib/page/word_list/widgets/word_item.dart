import 'package:flutter/material.dart';
import 'package:flutter_animation_progress_bar/flutter_animation_progress_bar.dart';
import 'package:provider/provider.dart';

import '../../../api/enum.dart';
import '../../../state.dart';
import '../../../util/word_util.dart';
import '../../../widget/handwriting_board.dart';

abstract class WordProgressProvider {
  double getWordProgress(dynamic wordTag);
  double getWordProgressMax(dynamic wordTag);
}

class WordItem extends StatefulWidget {
  final WordWrapper word;
  final int index;
  final int baseIndex;
  final bool isBookmarked;
  final bool showWordProgress;
  final String wordProgressLabel;
  final WordProgressProvider wordProgressProvider;
  final WordListStudyMode studyMode;
  final bool showDelBtn;
  final dynamic asrResult;
  final String appBarTitle;
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
  State<WordItem> createState() => _WordItemState();
}

class _WordItemState extends State<WordItem> {
  bool _showHandwritingBoard = false;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: _buildDecoration(isDarkMode),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              focusColor: Colors.transparent,
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildNumberColumn(isDarkMode),
                    const SizedBox(width: 12),
                    Expanded(child: _buildWordContent(context, isDarkMode)),
                  ],
                ),
              ),
            ),
          ),
          if (widget.showDelBtn || _shouldShowActionButtons()) _buildActionButtons(isDarkMode),
        ],
      ),
    );
  }

  BoxDecoration _buildDecoration(bool isDarkMode) {
    return BoxDecoration(
      gradient: widget.isBookmarked
          ? LinearGradient(
              colors: [
                const Color(0xFF0097A7).withValues(alpha: 0.08),
                const Color(0xFF00ACC1).withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      color: widget.isBookmarked
          ? null
          : isDarkMode
              ? const Color(0xFF1E1E1E).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(12),
      border: widget.isBookmarked
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
          color: widget.isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.black : Colors.grey).withValues(alpha: 0.1),
          blurRadius: widget.isBookmarked ? 8 : 4,
          offset: Offset(0, widget.isBookmarked ? 4 : 2),
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
              colors: widget.isBookmarked ? [const Color(0xFF0097A7), const Color(0xFF00ACC1)] : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: (widget.isBookmarked ? const Color(0xFF0097A7) : Colors.grey).withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${(widget.baseIndex + widget.index + 1) > 0 ? (widget.baseIndex + widget.index + 1) : 1}',
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
        if (widget.showWordProgress)
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 4),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: FAProgressBar(
                borderRadius: const BorderRadius.all(Radius.circular(2)),
                currentValue: widget.wordProgressProvider.getWordProgress(widget.word.tag),
                maxValue: widget.wordProgressProvider.getWordProgressMax(widget.word.tag),
                displayText: '',
                direction: Axis.horizontal,
                displayTextStyle: const TextStyle(color: Color(0x00000000), fontSize: 0),
                backgroundColor: isDarkMode ? const Color(0xFF404040) : const Color(0xFFE5E7EB),
                progressColor: _getProgressColor(),
                animatedDuration: const Duration(milliseconds: 200),
              ),
            ),
          ),
        if ((widget.studyMode == WordListStudyMode.speakChinese || widget.studyMode == WordListStudyMode.speakEnglish) && widget.isBookmarked)
          Container(
            width: 32,
            height: 12,
            margin: const EdgeInsets.only(top: 3),
            child: widget.audioLevelBar ?? const SizedBox(),
          )
        else if (widget.word.pronunciationScore != null && widget.word.pronunciationScore! > 0)
          Container(
            width: 32,
            height: 12,
            margin: const EdgeInsets.only(top: 3),
            alignment: Alignment.center,
            child: Text(
              '${widget.word.pronunciationScore}',
              textScaler: TextScaler.linear(1.0),
              style: TextStyle(
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w900,
                fontFamily: 'RobotoCondensed',
                color: widget.word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWordContent(BuildContext context, bool isDarkMode) {
    bool isWide = MediaQuery.of(context).size.width > 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.studyMode != WordListStudyMode.dictation && widget.studyMode != WordListStudyMode.speakEnglish) _buildWordAndPronounce(isDarkMode),
        if (widget.studyMode == WordListStudyMode.list ||
            widget.studyMode == WordListStudyMode.dictation ||
            widget.studyMode == WordListStudyMode.speakEnglish)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: isWide && widget.studyMode == WordListStudyMode.dictation
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          widget.word.word.getMeaningStr(),
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
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDictationInput(isDarkMode),
                            if (_showHandwritingBoard) ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 260,
                                child: HandwritingBoard(
                                  onRecognized: (text) {
                                    setState(() {
                                      widget.word.spellController.text = text;
                                      _showHandwritingBoard = false;
                                    });
                                  },
                                  onCancel: () {
                                    setState(() {
                                      _showHandwritingBoard = false;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : Text(
                    widget.word.word.getMeaningStr(),
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
        if (widget.studyMode == WordListStudyMode.dictation && widget.isBookmarked && !isWide)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.word.word.spell.substring(0, widget.word.hintLetterCount)),
              ],
            ),
          ),
        if (widget.studyMode == WordListStudyMode.dictation && !isWide) ...[
          _buildDictationInput(isDarkMode),
          if (_showHandwritingBoard) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: HandwritingBoard(
                onRecognized: (text) {
                  setState(() {
                    widget.word.spellController.text = text;
                    _showHandwritingBoard = false;
                  });
                },
                onCancel: () {
                  setState(() {
                    _showHandwritingBoard = false;
                  });
                },
              ),
            ),
          ],
        ],
        if (widget.studyMode == WordListStudyMode.speakChinese)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildAsrMeaningItems(),
          ),
        if (widget.studyMode == WordListStudyMode.speakEnglish) _buildSpeakEnglishContent(isDarkMode),
      ],
    );
  }

  Widget _buildWordAndPronounce(bool isDarkMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spellWidth = widget.word.word.spell.length * 14.0;
        final pronounceWidth = widget.word.word.mergedPronounce.isNotEmpty ? (widget.word.word.mergedPronounce.length * 7.0 + 24.0) : 0.0;
        final totalWidth = spellWidth + pronounceWidth + 16.0;
        final shouldWrap = totalWidth > constraints.maxWidth || widget.word.word.mergedPronounce.length > 25;

        if (shouldWrap && widget.word.word.mergedPronounce.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.word.word.spell,
                softWrap: false,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: widget.isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
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
                    '[${widget.word.word.mergedPronounce}]',
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
              Text(
                widget.word.word.spell,
                softWrap: false,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: widget.isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  letterSpacing: 0.3,
                ),
              ),
              if (widget.word.word.mergedPronounce.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '[${widget.word.word.mergedPronounce}]',
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

  // 辅助转换
  WordListStudyMode get studyMode => widget.studyMode;
  bool get isBookmarked => widget.isBookmarked;
  WordWrapper get word => widget.word;

  Widget _buildDictationInput(bool isDarkMode) {
    return AnimatedBuilder(
      animation: widget.word.focusNode,
      builder: (context, child) {
        const fontSize = 16.0;
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.word.spellController,
                focusNode: widget.word.focusNode,
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
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                _showHandwritingBoard ? Icons.keyboard : Icons.gesture,
                color: _showHandwritingBoard ? const Color(0xFF0097A7) : Colors.grey,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _showHandwritingBoard = !_showHandwritingBoard;
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSpeakEnglishContent(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        if (!widget.word.speakEnglishPassed) ...[
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
            ),
          ),
          if (widget.isBookmarked && widget.word.pronunciationScore != null && widget.word.pronunciationScore! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.word.pronunciationScore! >= 60 ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.record_voice_over,
                      size: 14,
                      color: widget.word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '发音: ${widget.word.pronunciationScore}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: widget.word.pronunciationScore! >= 60 ? Colors.green : Colors.orange,
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
        final spellWidth = widget.word.word.spell.length * 14.0;
        final pronounceWidth = widget.word.word.mergedPronounce.isNotEmpty ? (widget.word.word.mergedPronounce.length * 7.0 + 24.0) : 0.0;
        final totalWidth = spellWidth + pronounceWidth + 8.0;
        final shouldWrap =
            totalWidth > constraints.maxWidth || (widget.word.word.mergedPronounce.isNotEmpty && widget.word.word.mergedPronounce.length > 25);

        if (shouldWrap && widget.word.word.mergedPronounce.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.word.word.spell,
                softWrap: false,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: widget.isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
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
                    '[${widget.word.word.mergedPronounce}]',
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
              Text(
                widget.word.word.spell,
                softWrap: false,
                textScaler: TextScaler.linear(1.0),
                style: TextStyle(
                  color: widget.isBookmarked ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (widget.word.word.mergedPronounce.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDarkMode ? Colors.grey[700] : Colors.grey[200])?.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '[${widget.word.word.mergedPronounce}]',
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
            if (widget.onHintTap != null)
              _buildActionButton(
                icon: Icons.lightbulb,
                color: const Color(0xFFFFA726),
                onTap: widget.onHintTap!,
              ),
            if (widget.onClearHintTap != null) ...[
              const SizedBox(height: 6),
              _buildActionButton(
                icon: Icons.lightbulb_outline,
                color: const Color(0xFF9E9E9E),
                onTap: widget.onClearHintTap!,
              ),
            ],
          ],
          if (widget.onMasterTap != null) ...[
            if (_shouldShowActionButtons()) const SizedBox(height: 6),
            _buildActionButton(
              icon: Icons.check,
              color: const Color(0xFF4CAF50),
              onTap: widget.onMasterTap!,
            ),
          ],
          if (widget.showDelBtn && widget.onDeleteTap != null) ...[
            if (_shouldShowActionButtons() || widget.onMasterTap != null) const SizedBox(height: 6),
            _buildActionButton(
              icon: _getActionIcon(),
              color: _getActionColor(),
              onTap: widget.onDeleteTap!,
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
    return [];
  }

  bool _shouldShowActionButtons() {
    return (widget.studyMode == WordListStudyMode.dictation ||
            widget.studyMode == WordListStudyMode.speakChinese ||
            widget.studyMode == WordListStudyMode.speakEnglish) &&
        widget.isBookmarked;
  }

  Color _getProgressColor() {
    double ratio = widget.wordProgressProvider.getWordProgress(widget.word.tag) / widget.wordProgressProvider.getWordProgressMax(widget.word.tag);
    if (ratio < 0.4) return Colors.red;
    if (ratio < 0.6) return Colors.orange;
    if (ratio < 0.8) return Colors.blueGrey;
    if (ratio < 1.0) return Colors.blue;
    return Colors.green;
  }



  IconData _getActionIcon() {
    switch (widget.appBarTitle) {
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
    switch (widget.appBarTitle) {
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
