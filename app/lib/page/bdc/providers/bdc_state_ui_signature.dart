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
  final int tabIndex;
  final int historyIndex;
  final int historyLength;
  final bool showHandwritingBoard;
  final bool buttonsEnabled;
  final bool isKeyboardVisible;
  final String? loadError;
  final int progressBarTapCount;
  final bool showAnswerButtons;
  final double slideDirection;
  final bool isEditMode;
  final String? highlightedWordImgId;
  final bool isWordImageEdited;
  final bool isSelectModePreferred;
  final int? currentScore;
  final String? asrFirstCandidate;

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
        tabIndex = s.tabIndex,
        historyIndex = s.historyIndex,
        historyLength = s.history.length,
        showHandwritingBoard = s.showHandwritingBoard,
        buttonsEnabled = s.buttonsEnabled,
        isKeyboardVisible = s.isKeyboardVisible,
        loadError = s.loadError,
        progressBarTapCount = s.progressBarTapCount,
        showAnswerButtons = s.showAnswerButtons,
        slideDirection = s.slideDirection,
        isEditMode = s.isEditMode,
        highlightedWordImgId = s.highlightedWordImg?.id,
        isWordImageEdited = s.isWordImageEdited,
        isSelectModePreferred = s.isSelectModePreferred,
        currentScore = s.currentScore,
        asrFirstCandidate = s.currentAsrCandidates.isNotEmpty ? s.currentAsrCandidates.first : null;

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
        tabIndex == other.tabIndex &&
        historyIndex == other.historyIndex &&
        historyLength == other.historyLength &&
        showHandwritingBoard == other.showHandwritingBoard &&
        buttonsEnabled == other.buttonsEnabled &&
        isKeyboardVisible == other.isKeyboardVisible &&
        loadError == other.loadError &&
        progressBarTapCount == other.progressBarTapCount &&
        showAnswerButtons == other.showAnswerButtons &&
        slideDirection == other.slideDirection &&
        isEditMode == other.isEditMode &&
        highlightedWordImgId == other.highlightedWordImgId &&
        isWordImageEdited == other.isWordImageEdited &&
        isSelectModePreferred == other.isSelectModePreferred &&
        currentScore == other.currentScore &&
        asrFirstCandidate == other.asrFirstCandidate;
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
        tabIndex,
        historyIndex,
        historyLength,
        showHandwritingBoard,
        buttonsEnabled,
        isKeyboardVisible,
        loadError,
        progressBarTapCount,
        showAnswerButtons,
        slideDirection,
        isEditMode,
        highlightedWordImgId,
        isWordImageEdited,
        isSelectModePreferred,
        currentScore,
        asrFirstCandidate,
      ]);
}
