import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/global.dart';

class WordListAsrController extends ChangeNotifier {
  final Asr asr = Asr();
  final StudyAudioSessionController sessionController = StudyAudioSessionController.instance;

  static const int waveCapacity = 16;

  bool isAsrModelLoading = false;
  bool isAsrProcessing = false;
  String asrResult = "";
  String handlingAsrChinese = "";
  WordVo? detectedSimilarWord;
  AsrLanguage? lastAsrLanguage;

  final ValueNotifier<double> meterLevelNotifier = ValueNotifier<double>(0.0);
  final List<double> waveLevels = [];

  bool _disposed = false;

  WordListAsrController() {
    sessionController.meterLevelNotifier.addListener(_onMeterLevelChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    sessionController.meterLevelNotifier.removeListener(_onMeterLevelChanged);
    meterLevelNotifier.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  void _onMeterLevelChanged() {
    final v = sessionController.meterLevelNotifier.value;
    waveLevels.add(v);
    if (waveLevels.length > waveCapacity) {
      waveLevels.removeRange(0, waveLevels.length - waveCapacity);
    }
    meterLevelNotifier.value = v;
  }

  String _accumulatedSentenceAsr = "";

  void resetResult() {
    asrResult = "";
    _accumulatedSentenceAsr = "";
    handlingAsrChinese = "";
    detectedSimilarWord = null;
    notifyListeners();
  }

  AsrLanguage decideAsrLanguage(WordListStudyMode studyMode) {
    if (studyMode == WordListStudyMode.dictation ||
        studyMode == WordListStudyMode.dictationHandwriting ||
        studyMode == WordListStudyMode.speakEnglish) {
      return AsrLanguage.english;
    }
    return AsrLanguage.chinese;
  }

  Future<void> onAsrResult(
    dynamic event, {
    required WordListStudyMode studyMode,
    required String targetSpell,
    required WordWrapper? activeWord,
    required Function(String matchedResult) onMatchChecked,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    Global.logger.d("~~~~~收到语音识别原始结果: $event");

    String processedEvent = "";
    try {
      Map<String, dynamic>? resultData;
      try {
        resultData = jsonDecode(event);
      } catch (e) {
        resultData = null;
      }

      if (studyMode == WordListStudyMode.speakEnglish) {
        if (resultData != null && resultData.containsKey('candidates')) {
          List<dynamic> candidates = resultData['candidates'];
          List<String> candidateStrings = candidates.map((e) => e.toString()).toList();

          final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(candidateStrings, targetSpell);
          if (activeWord != null) {
            activeWord.pronunciationScore = result.score;
          }
          processedEvent = AsrUtil.preprocessEnglish(result.text, targetSpell);
          Global.logger.d('~~~~~ASR (Phoneme): Selected & Preprocessed: "$processedEvent" (score: ${result.score})');
        } else {
          final pre = AsrUtil.preprocessEnglish(event, targetSpell);
          final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore([pre], targetSpell);
          processedEvent = result.text;
          if (activeWord != null) {
            activeWord.pronunciationScore = result.score;
          }
          Global.logger.d('~~~~~ASR (Phoneme): Single result: "$event" -> "$processedEvent" (score: ${result.score})');
        }
        processedEvent = AsrUtil.preprocessEnglish(processedEvent, targetSpell);
      } else {
        if (resultData != null && resultData.containsKey('candidates')) {
          List<dynamic> candidates = resultData['candidates'];
          processedEvent = resultData['best'] ?? candidates.first.toString();
        } else {
          processedEvent = event;
        }
      }
    } catch (e) {
      Global.logger.e("语音识别结果处理错误: $e");
      processedEvent = event;
    }

    String newAsrResult = "";
    if (studyMode == WordListStudyMode.speakEnglish) {
      newAsrResult = processedEvent;
    } else if (studyMode == WordListStudyMode.translateSentence) {
      final cleanChunk = AsrUtil.preprocess(processedEvent);
      if (cleanChunk.isNotEmpty) {
        if (_accumulatedSentenceAsr.isNotEmpty) {
          final merged = AsrUtil.mergeAsrText(_accumulatedSentenceAsr, cleanChunk, isEnglish: false);
          final targetChinese = activeWord?.currentSentence?.chinese ?? activeWord?.word.getMeaningStr() ?? '';
          if (targetChinese.isNotEmpty) {
            final oldScore = getChineseSentenceMatchScore(_accumulatedSentenceAsr, targetChinese);
            final newScore = getChineseSentenceMatchScore(merged, targetChinese);
            if (newScore < oldScore && merged.length < _accumulatedSentenceAsr.length) {
              // 保持原有累积
            } else {
              _accumulatedSentenceAsr = merged;
            }
          } else {
            _accumulatedSentenceAsr = merged;
          }
        } else {
          _accumulatedSentenceAsr = cleanChunk;
        }
      }
      newAsrResult = _accumulatedSentenceAsr;
    } else if (studyMode == WordListStudyMode.speakChinese) {
      final cleanChunk = AsrUtil.preprocess(processedEvent);
      if (cleanChunk.isNotEmpty) {
        if (_accumulatedSentenceAsr.isNotEmpty) {
          _accumulatedSentenceAsr = AsrUtil.mergeAsrText(_accumulatedSentenceAsr, cleanChunk, isEnglish: false);
        } else {
          _accumulatedSentenceAsr = cleanChunk;
        }
      }
      newAsrResult = _accumulatedSentenceAsr;
    } else {
      newAsrResult = AsrUtil.preprocess(processedEvent);
    }

    Global.logger.d("~~~~~语音识别最终结果: $newAsrResult (耗时: ${DateTime.now().millisecondsSinceEpoch - startTime}ms)");
    
    if (newAsrResult != asrResult) {
      asrResult = newAsrResult;
      if (activeWord != null) {
        activeWord.lastAsrResult = asrResult;
      }
      if (asrResult.isNotEmpty) {
        if (asrResult != handlingAsrChinese) {
          handlingAsrChinese = asrResult;
          onMatchChecked(asrResult);
        }
      }
      notifyListeners();
    } else {
      if (newAsrResult.isNotEmpty && newAsrResult != handlingAsrChinese) {
        handlingAsrChinese = newAsrResult;
        onMatchChecked(newAsrResult);
      }
    }
  }

  Future<void> restoreAsrIfNeeded({
    required WordListStudyMode studyMode,
    required String caller,
    required List<String> phrases,
  }) async {
    if (studyMode != WordListStudyMode.speakChinese &&
        studyMode != WordListStudyMode.speakEnglish &&
        studyMode != WordListStudyMode.translateSentence) {
      return;
    }

    final language = decideAsrLanguage(studyMode);
    
    if (asr.state != AsrState.started && asr.state != AsrState.stopping) {
      Global.logger.d('$caller: 检测到ASR未启动（当前状态: ${asr.state}），尝试恢复ASR，模式: $studyMode');
      isAsrProcessing = true;
      notifyListeners();

      try {
        if (asr.state == AsrState.initialized) {
          await warmupAsr(language, phrases);
        } else {
          isAsrModelLoading = true;
          notifyListeners();
          
          await sessionController.startSession(
            language: language,
            phrases: phrases,
            isSpeakMode: true,
          );
          lastAsrLanguage = language;
        }
      } catch (e) {
        Global.logger.e("恢复ASR失败: $e");
      } finally {
        isAsrModelLoading = false;
        isAsrProcessing = false;
        notifyListeners();
      }
    }
  }

  Future<void> warmupAsr(AsrLanguage language, List<String> phrases) async {
    isAsrModelLoading = true;
    notifyListeners();
    try {
      await sessionController.startSession(
        language: language,
        phrases: phrases,
        isSpeakMode: true,
      );
      lastAsrLanguage = language;
    } finally {
      isAsrModelLoading = false;
      notifyListeners();
    }
  }

  Future<void> stopAsr() async {
    isAsrProcessing = true;
    notifyListeners();
    try {
      await asr.stopAsr();
      await asr.reset();
    } finally {
      isAsrProcessing = false;
      notifyListeners();
    }
  }

  Future<void> stopMicrophone() async {
    await asr.stopMicrophone();
    await asr.reset();
  }
}
