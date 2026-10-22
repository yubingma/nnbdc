import 'package:nnbdc/api/bo/word_bo.dart';

import 'answer_mode.dart';
import 'bdc_state.dart';

/// 专为顶层 BdcPage 刷新优化的轻量级签名对象，剔除了 ASR 等高频更新字段和极其昂贵的深层集合比对。
/// 这使得只有当影响顶层核心 UI 结构与交互的状态发生实质改变时，才触发整页刷新。
class BdcStateUiSignature {
  final bool dataLoaded;
  final bool isGettingNextWord;
  final String? wordId;
  final String? studyStep;
  final bool hasFinishedAnswering;
  final bool canLeaveCurrWord;
  final int? selectedAnswerIndex;
  final int? correctAnswerIndex;
  final bool showSentenceTranslation;
  final bool showSentenceWordMeaning;
  final AnswerMode answerMode;
  final int historyIndex;
  final int historyLength;
  final bool showHandwritingBoard;
  final bool isSpellingSuccess;
  final int dictationMatchedCount;
  final int dictationRequiredCount;
  final int meaningMatchedCount;
  final int hintLetterCount;
  final bool buttonsEnabled;
  final bool isKeyboardVisible;
  final String? loadError;

  /// 当前错误属于哪一类（null = 没有错误）。
  ///
  /// 必须按错误「种类」分辨，不能只看 [loadError] 的文案：不同种类的错误渲染的界面完全不同
  ///（通用释义缺失的引导面板 / 不支持的环节的升级提示 / 普通重试页）。
  /// 签名分辨不出来时界面不会重建，那张引导卡片就永远不会出现。
  final Type? loadErrorKind;

  /// 当前错误是不是「通用释义缺失」：它决定错误页渲染哪一种界面（引导面板 vs 普通重试页）。
  bool get isMissingCommonMeaningError =>
      loadErrorKind == MissingCommonMeaningException;
  final int progressBarTapCount;
  final bool showAnswerButtons;
  final double slideDirection;
  final bool isEditMode;
  final String? highlightedWordImgId;
  final bool isWordImageEdited;
  final int? currentScore;
  final String? asrFirstCandidate;
  final bool isAiEvaluating;
  final int groupStepNo;
  final int groupStepPosition;
  final int groupStepTotal;
  final String? groupStepTrackName;
  final bool isGroupStepRetry;
  final bool isLatestAnswerWrongToday;

  BdcStateUiSignature(BdcState s)
      : dataLoaded = s.dataLoaded,
        isGettingNextWord = s.isGettingNextWord,
        wordId = s.word?.id,
        studyStep = s.studyStep,
        hasFinishedAnswering = s.hasFinishedAnswering,
        canLeaveCurrWord = s.canLeaveCurrWord,
        selectedAnswerIndex = s.selectedAnswerIndex,
        correctAnswerIndex = s.correctAnswerIndex,
        showSentenceTranslation = s.showSentenceTranslation,
        showSentenceWordMeaning = s.showSentenceWordMeaning,
        answerMode = s.answerMode,
        historyIndex = s.historyIndex,
        historyLength = s.history.length,
        showHandwritingBoard = s.showHandwritingBoard,
        isSpellingSuccess = s.isSpellingSuccess,
        dictationMatchedCount = s.dictationMatchedCount,
        dictationRequiredCount = s.dictationRequiredCount,
        meaningMatchedCount =
            s.wordWrapper?.asrMatchedMeaningItemParts.length ?? 0,
        hintLetterCount = s.wordWrapper?.hintLetterCount ?? 0,
        buttonsEnabled = s.buttonsEnabled,
        isKeyboardVisible = s.isKeyboardVisible,
        loadError = s.loadError,
        loadErrorKind = s.loadErrorCause?.runtimeType,
        progressBarTapCount = s.progressBarTapCount,
        showAnswerButtons = s.showAnswerButtons,
        slideDirection = s.slideDirection,
        isEditMode = s.isEditMode,
        highlightedWordImgId = s.highlightedWordImg?.id,
        isWordImageEdited = s.isWordImageEdited,
        currentScore = s.currentScore,
        asrFirstCandidate = s.currentAsrCandidates.isNotEmpty ? s.currentAsrCandidates.first : null,
        isAiEvaluating = s.isAiEvaluating,
        groupStepNo = s.groupStepNo,
        groupStepPosition = s.groupStepPosition,
        groupStepTotal = s.groupStepTotal,
        groupStepTrackName = s.groupStepTrackName,
        isGroupStepRetry = s.isGroupStepRetry,
        isLatestAnswerWrongToday = s.isLatestAnswerWrongToday;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BdcStateUiSignature &&
        dataLoaded == other.dataLoaded &&
        isGettingNextWord == other.isGettingNextWord &&
        wordId == other.wordId &&
        studyStep == other.studyStep &&
        hasFinishedAnswering == other.hasFinishedAnswering &&
        canLeaveCurrWord == other.canLeaveCurrWord &&
        selectedAnswerIndex == other.selectedAnswerIndex &&
        correctAnswerIndex == other.correctAnswerIndex &&
        showSentenceTranslation == other.showSentenceTranslation &&
        showSentenceWordMeaning == other.showSentenceWordMeaning &&
        answerMode == other.answerMode &&
        historyIndex == other.historyIndex &&
        historyLength == other.historyLength &&
        showHandwritingBoard == other.showHandwritingBoard &&
        isSpellingSuccess == other.isSpellingSuccess &&
        dictationMatchedCount == other.dictationMatchedCount &&
        dictationRequiredCount == other.dictationRequiredCount &&
        meaningMatchedCount == other.meaningMatchedCount &&
        hintLetterCount == other.hintLetterCount &&
        buttonsEnabled == other.buttonsEnabled &&
        isKeyboardVisible == other.isKeyboardVisible &&
        loadError == other.loadError &&
        loadErrorKind == other.loadErrorKind &&
        progressBarTapCount == other.progressBarTapCount &&
        showAnswerButtons == other.showAnswerButtons &&
        slideDirection == other.slideDirection &&
        isEditMode == other.isEditMode &&
        highlightedWordImgId == other.highlightedWordImgId &&
        isWordImageEdited == other.isWordImageEdited &&
        currentScore == other.currentScore &&
        asrFirstCandidate == other.asrFirstCandidate &&
        isAiEvaluating == other.isAiEvaluating &&
        groupStepNo == other.groupStepNo &&
        groupStepPosition == other.groupStepPosition &&
        groupStepTotal == other.groupStepTotal &&
        groupStepTrackName == other.groupStepTrackName &&
        isGroupStepRetry == other.isGroupStepRetry &&
        isLatestAnswerWrongToday == other.isLatestAnswerWrongToday;
  }

  @override
  int get hashCode => Object.hashAll([
        dataLoaded,
        isGettingNextWord,
        wordId,
        studyStep,
        hasFinishedAnswering,
        canLeaveCurrWord,
        selectedAnswerIndex,
        correctAnswerIndex,
        showSentenceTranslation,
        showSentenceWordMeaning,
        answerMode,
        historyIndex,
        historyLength,
        showHandwritingBoard,
        isSpellingSuccess,
        dictationMatchedCount,
        dictationRequiredCount,
        meaningMatchedCount,
        hintLetterCount,
        buttonsEnabled,
        isKeyboardVisible,
        loadError,
        loadErrorKind,
        progressBarTapCount,
        showAnswerButtons,
        slideDirection,
        isEditMode,
        highlightedWordImgId,
        isWordImageEdited,
        currentScore,
        asrFirstCandidate,
        isAiEvaluating,
        groupStepNo,
        groupStepPosition,
        groupStepTotal,
        groupStepTrackName,
        isGroupStepRetry,
        isLatestAnswerWrongToday,
      ]);
}
