import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/widget/handwriting_board.dart';
import '../../word_detail.dart';

class HandwritingOverlay extends StatefulWidget {
  final bool isDarkMode;
  final double appBarHeight;
  final WordWrapper? activeWord;
  final int bookmarkedIndex;
  final List<WordWrapper> words;
  final WordListStudyMode studyMode;
  final ValueNotifier<bool> rightZoneVisible;
  final GlobalKey<HandwritingBoardState> handwritingBoardKey;
  
  final Function(WordWrapper word) giveALittleHint;
  final Function(WordWrapper word) clearHint;
  final Function() onCancel;
  final Function(int currIndex) onWordAnswered;
  final Function(int currIndex) onWordPrevious;

  const HandwritingOverlay({
    super.key,
    required this.isDarkMode,
    required this.appBarHeight,
    required this.activeWord,
    required this.bookmarkedIndex,
    required this.words,
    required this.studyMode,
    required this.rightZoneVisible,
    required this.handwritingBoardKey,
    required this.giveALittleHint,
    required this.clearHint,
    required this.onCancel,
    required this.onWordAnswered,
    required this.onWordPrevious,
  });

  @override
  State<HandwritingOverlay> createState() => HandwritingOverlayState();
}

class HandwritingOverlayState extends State<HandwritingOverlay> {
  final StudyAudioSessionController _sessionController = StudyAudioSessionController.instance;
  
  double _handwritingRightPadding = 60.0;
  Timer? _handwritingPaddingTimer;
  WordVo? _detectedSimilarWord;

  @override
  void dispose() {
    _handwritingPaddingTimer?.cancel();
    super.dispose();
  }

  void _clearHandwritingHints(WordWrapper? word) {
    if (_detectedSimilarWord != null || (word?.hintLetterCount ?? 0) > 0) {
      setState(() {
        _detectedSimilarWord = null;
        if (word != null) {
          widget.clearHint(word);
        }
      });
    }
  }

  void clearBoardSilently() {
    widget.handwritingBoardKey.currentState?.clearBoardSilently();
    setState(() {
      _detectedSimilarWord = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final swOverlay = Stopwatch()..start();
    Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [HandwritingOverlay 开始构造]');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      swOverlay.stop();
      Global.logger.d('🐛 PERF_LOG_OPEN_PENCIL [HandwritingOverlay 组件渲染挂载完毕] 耗时: ${swOverlay.elapsedMilliseconds}ms');
      if (Global.openPencilStopwatch.isRunning) {
        Global.openPencilStopwatch.stop();
        Global.logger.d('🔥 [超级大盘点] 从菜单点击到手写物理像素上屏，用户肉眼经历的真实总耗时：${Global.openPencilStopwatch.elapsedMilliseconds}ms');
      }
    });

    final activeWord = widget.activeWord;

    return Positioned(
      top: widget.appBarHeight,
      left: 0,
      right: 0,
      bottom: 0,
      child: Stack(
        children: [
          // 1. 左侧手写画板区域
          Positioned(
            left: 0,
            right: _handwritingRightPadding,
            top: 0,
            bottom: 0,
            child: Container(
              color: Colors.transparent,
              child: HandwritingBoard(
                key: widget.handwritingBoardKey,
                showHeader: false,
                showCloseButton: false, 
                useBoxDecoration: false,
                showCanvasButtons: true, 
                enableNavigationGestures: false,
                smartRightZoneWidth: 0, 
                rightZoneVisibleNotifier: widget.rightZoneVisible, 
                onHint: () {
                  if (activeWord != null) {
                    widget.giveALittleHint(activeWord);
                  }
                },
                onUndo: () => _clearHandwritingHints(activeWord),
                onRewrite: () => _clearHandwritingHints(activeWord),
                onStartWriting: () {
                  _handwritingPaddingTimer?.cancel();
                  _clearHandwritingHints(activeWord);
                  if (_handwritingRightPadding != 0) {
                    setState(() {
                      _handwritingRightPadding = 0;
                    });
                  }
                },
                onPointerUp: () {
                  _handwritingPaddingTimer?.cancel();
                  _handwritingPaddingTimer = Timer(const Duration(milliseconds: 500), () {
                    if (mounted && _handwritingRightPadding != 60) {
                      setState(() {
                        _handwritingRightPadding = 60;
                      });
                    }
                  });
                },
                onRecognized: (text) async {
                  final targetWord = activeWord;
                  if (targetWord != null) { 
                    String processedText = "";
                    final String lowerTarget = targetWord.word.spell.toLowerCase();
                    
                    List<Map<String, dynamic>> anchors = [];
                    for (int i = 0; i < lowerTarget.length; i++) {
                      if (lowerTarget[i] == 'd') {
                        anchors.add({'idx': i, 'type': 'd'});
                      } else if (lowerTarget[i] == 'c' && (i + 1) < lowerTarget.length && lowerTarget[i + 1] == 'l') {
                        anchors.add({'idx': i, 'type': 'cl'});
                      }
                    }
                    
                    for (int idx = 0; idx < text.length; idx++) {
                      final iChar = text[idx].toLowerCase();
                      if ((iChar == 'd' || iChar == 'c') && anchors.isNotEmpty) {
                        Map<String, dynamic> nearestAnchor = anchors[0];
                        int minDistance = (idx - (anchors[0]['idx'] as int)).abs();
                        
                        for (final anchor in anchors) {
                          final int dist = (idx - (anchor['idx'] as int)).abs();
                          if (dist < minDistance || (dist == minDistance && anchor['type'] == iChar)) {
                            minDistance = dist;
                            nearestAnchor = anchor;
                          }
                        }
                        
                        if (iChar == 'd' && nearestAnchor['type'] == 'cl') {
                          processedText += (text[idx] == 'D') ? 'CL' : 'cl';
                          continue;
                        }
                      }
                      processedText += text[idx];
                    }
                    
                    setState(() {
                      targetWord.spellController.text = processedText;
                    });
                    
                    final String normalizedTarget = targetWord.word.spell.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
                    final String normalizedInput = processedText.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
                    
                    final String fuzzyTarget = normalizedTarget.replaceAll('cl', 'd');
                    
                    if (normalizedTarget == normalizedInput || fuzzyTarget == normalizedInput) {
                       setState(() {
                         _detectedSimilarWord = null;
                       });
                       WidgetsBinding.instance.addPostFrameCallback((_) async {
                          try {
                             targetWord.speakEnglishPassed = true;
                             await _sessionController.playWordSound(targetWord.word);
                          } catch (_) {}
                          
                          clearBoardSilently();
                          widget.onWordAnswered(widget.bookmarkedIndex);
                       });
                    } else if (normalizedInput.length >= 2) {
                       final result = await WordBo().searchWordLocalOnly(normalizedInput);
                       if (result.word != null && result.word!.spell.toLowerCase() == normalizedInput) {
                         if (mounted) {
                           setState(() {
                             _detectedSimilarWord = result.word;
                           });
                         }
                       } else {
                         if (mounted) {
                           setState(() {
                             _detectedSimilarWord = null;
                           });
                         }
                       }
                    } else {
                       if (mounted) {
                         setState(() {
                           _detectedSimilarWord = null;
                         });
                       }
                    }
                  }
                },
                onSwipeUp: () async {
                  clearBoardSilently();
                  if (widget.bookmarkedIndex >= 0 && widget.bookmarkedIndex < widget.words.length) {
                    try {
                      widget.words[widget.bookmarkedIndex].speakEnglishPassed = true;
                      await _sessionController.playWordSound(widget.words[widget.bookmarkedIndex].word);
                    } catch (_) {}
                  }
                  widget.onWordAnswered(widget.bookmarkedIndex);
                },
                onSwipeDown: () async {
                  clearBoardSilently();
                  if (widget.bookmarkedIndex >= 0 && widget.bookmarkedIndex < widget.words.length) {
                    try {
                      await _sessionController.playWordSound(widget.words[widget.bookmarkedIndex].word);
                    } catch (_) {}
                  }
                  widget.onWordPrevious(widget.bookmarkedIndex);
                },
                onCancel: () {
                  widget.onCancel();
                },
              ),
            ),
          ),

          // 2. 相似词提示框
          if (_detectedSimilarWord != null)
            Positioned(
              left: 12,
              right: 12 + _handwritingRightPadding,
              top: 10,
              child: GestureDetector(
                onTap: () {
                  context.push('/word_detail',
                      extra: WordDetailPageArgs(_detectedSimilarWord!, true, null, false));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '注意，你写成了另一个单词: ${_detectedSimilarWord!.spell}',
                              style: const TextStyle(
                                color: Colors.orangeAccent, 
                                fontSize: 13, 
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 12),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: Text(
                          _detectedSimilarWord!.getMeaningStr().replaceAll('\n', ' '),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9), 
                            fontSize: 12,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            right: _handwritingRightPadding > 0 ? _handwritingRightPadding - 1 : -1,
            top: 0,
            bottom: 0,
            width: 1,
            child: IgnorePointer(
              child: Container(
                color: widget.isDarkMode 
                    ? Colors.white.withValues(alpha: 0.06) 
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
