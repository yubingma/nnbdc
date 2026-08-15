import 'package:equatable/equatable.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/asr.dart';
import '../models/word_ui_state.dart';

const Object _sentinel = Object();

class BdcState extends Equatable {
  final bool dataLoaded;
  final bool isGettingNextWord;
  final GetWordResult? currentGetWordResult;
  final GetWordResult? learningGetWordResult;
  final GetWordResult? reviewReturnTarget;
  final WordVo? word;
  final WordWrapper? wordWrapper;
  final String? studyStep;
  final List<UserStudyStepVo> activeUserStudySteps;
  
  final bool hasFinishedAnswering;
  final bool canLeaveCurrWord;
  final int? selectedAnswerIndex;
  final int? correctAnswerIndex;
  final Set<int> flippedAnswerIndices;
  
  final String meaningText;
  final int? currentScore;
  final bool showSentenceTranslation;
  final int tabIndex;
  
  final List<GetWordResult> history;
  final int historyIndex;
  final Map<String, WordUIState> wordUIStates;
  
  final FSRSItem? fsrsItem;
  final int? daysSinceLastReview;
  final FsrsRating? lastFsrsRating;
  final String? lastFsrsRatingReason;
  
  final List<WordVo>? words;
  final bool buttonsEnabled;
  final bool showHandwritingBoard;
  
  final AsrState asrState;
  final String asrResult;
  final List<String> currentAsrCandidates;

  final bool isKeyboardVisible;
  final bool autoJumpAfterCorrectCh2En;
  final bool autoJumpAfterCorrectEn2Ch;
  final bool autoJumpAfterCorrectChSentence2En;
  final bool autoJumpAfterCorrectEnSentence2Ch;
  final String asrPassRuleCache;
  final FsrsRating? lowestRatingForCurrentWord;
  final FsrsRating? assessmentRating;
  final int? assessmentScheduledDays;
  final String? englishDigestOfFirstSentence;

  final Map<String, bool> playingStates;
  final int hintTapCount;
  final bool isWordMastered;
  /// 当前环节是否为复习轨道的恢复环节（测评答错后的补救环节），由 handleWord 按轨道与 stepIndex 计算
  final bool isRestoreStep;
  
  final DateTime? wordStartTime;
  final DateTime? firstMatchTime;

  final bool isUpdatingByHint;
  final int progressBarTapCount;
  final bool showAnswerButtons;
  final double slideDirection;
  final bool isEditMode;
  final WordImageVo? highlightedWordImg;
  final bool isWordImageEdited;

  final String? loadError;

  final bool isSelectModePreferred;

  /// 例句环节 PTT(按下说话)按钮是否处于按住状态
  final bool isPttPressed;

  const BdcState({
    this.dataLoaded = false,
    this.isGettingNextWord = false,
    this.currentGetWordResult,
    this.learningGetWordResult,
    this.reviewReturnTarget,
    this.word,
    this.wordWrapper,
    this.studyStep,
    this.activeUserStudySteps = const [],
    this.hasFinishedAnswering = false,
    this.canLeaveCurrWord = false,
    this.selectedAnswerIndex,
    this.correctAnswerIndex,
    this.flippedAnswerIndices = const {},
    this.meaningText = "",
    this.currentScore,
    this.showSentenceTranslation = false,
    this.tabIndex = 0,
    this.history = const [],
    this.historyIndex = -1,
    this.wordUIStates = const {},
    this.fsrsItem,
    this.daysSinceLastReview,
    this.lastFsrsRating,
    this.lastFsrsRatingReason,
    this.words,
    this.buttonsEnabled = true,
    this.showHandwritingBoard = false,
    this.asrState = AsrState.unknown,
    this.asrResult = "",
    this.currentAsrCandidates = const [],
    this.isKeyboardVisible = false,
    this.autoJumpAfterCorrectCh2En = true,
    this.autoJumpAfterCorrectEn2Ch = true,
    this.autoJumpAfterCorrectChSentence2En = true,
    this.autoJumpAfterCorrectEnSentence2Ch = true,
    this.asrPassRuleCache = 'ONE',
    this.lowestRatingForCurrentWord,
    this.assessmentRating,
    this.assessmentScheduledDays,
    this.englishDigestOfFirstSentence,
    this.playingStates = const {'word': false, 'sentence': false},
    this.hintTapCount = 0,
    this.isWordMastered = false,
    this.isRestoreStep = false,
    this.wordStartTime,
    this.firstMatchTime,
    this.isUpdatingByHint = false,
    this.progressBarTapCount = 0,
    this.showAnswerButtons = false,
    this.slideDirection = 1.0,
    this.isEditMode = false,
    this.highlightedWordImg,
    this.isWordImageEdited = false,
    this.loadError,
    this.isSelectModePreferred = false,
    this.isPttPressed = false,
  });

  bool get autoJumpAfterCorrect {
    if (studyStep == StudyStep.ch2En.json) {
      return autoJumpAfterCorrectCh2En;
    }
    if (studyStep == StudyStep.chSentence2En.json) {
      return autoJumpAfterCorrectChSentence2En;
    }
    if (studyStep == StudyStep.enSentence2Ch.json) {
      return autoJumpAfterCorrectEnSentence2Ch;
    }
    return autoJumpAfterCorrectEn2Ch;
  }

  BdcState copyWith({
    bool? dataLoaded,
    bool? isGettingNextWord,
    Object? currentGetWordResult = _sentinel,
    Object? learningGetWordResult = _sentinel,
    Object? reviewReturnTarget = _sentinel,
    Object? word = _sentinel,
    Object? wordWrapper = _sentinel,
    Object? studyStep = _sentinel,
    List<UserStudyStepVo>? activeUserStudySteps,
    bool? hasFinishedAnswering,
    bool? canLeaveCurrWord,
    Object? selectedAnswerIndex = _sentinel,
    Object? correctAnswerIndex = _sentinel,
    Set<int>? flippedAnswerIndices,
    String? meaningText,
    Object? currentScore = _sentinel,
    bool? showSentenceTranslation,
    int? tabIndex,
    List<GetWordResult>? history,
    int? historyIndex,
    Map<String, WordUIState>? wordUIStates,
    Object? fsrsItem = _sentinel,
    Object? daysSinceLastReview = _sentinel,
    Object? lastFsrsRating = _sentinel,
    Object? lastFsrsRatingReason = _sentinel,
    Object? words = _sentinel,
    bool? buttonsEnabled,
    bool? showHandwritingBoard,
    AsrState? asrState,
    String? asrResult,
    List<String>? currentAsrCandidates,
    bool? isKeyboardVisible,
    bool? autoJumpAfterCorrectCh2En,
    bool? autoJumpAfterCorrectEn2Ch,
    bool? autoJumpAfterCorrectChSentence2En,
    bool? autoJumpAfterCorrectEnSentence2Ch,
    String? asrPassRuleCache,
    Object? lowestRatingForCurrentWord = _sentinel,
    Object? assessmentRating = _sentinel,
    Object? assessmentScheduledDays = _sentinel,
    Object? englishDigestOfFirstSentence = _sentinel,
    Map<String, bool>? playingStates,
    int? hintTapCount,
    bool? isWordMastered,
    bool? isRestoreStep,
    Object? wordStartTime = _sentinel,
    Object? firstMatchTime = _sentinel,
    bool? isUpdatingByHint,
    int? progressBarTapCount,
    bool? showAnswerButtons,
    double? slideDirection,
    bool? isEditMode,
    Object? highlightedWordImg = _sentinel,
    bool? isWordImageEdited,
    Object? loadError = _sentinel,
    bool? isSelectModePreferred,
    bool? isPttPressed,
  }) {
    return BdcState(
      dataLoaded: dataLoaded ?? this.dataLoaded,
      isGettingNextWord: isGettingNextWord ?? this.isGettingNextWord,
      currentGetWordResult: currentGetWordResult == _sentinel ? this.currentGetWordResult : (currentGetWordResult as GetWordResult?),
      learningGetWordResult: learningGetWordResult == _sentinel ? this.learningGetWordResult : (learningGetWordResult as GetWordResult?),
      reviewReturnTarget: reviewReturnTarget == _sentinel ? this.reviewReturnTarget : (reviewReturnTarget as GetWordResult?),
      word: word == _sentinel ? this.word : (word as WordVo?),
      wordWrapper: wordWrapper == _sentinel ? this.wordWrapper : (wordWrapper as WordWrapper?),
      studyStep: studyStep == _sentinel ? this.studyStep : (studyStep as String?),
      activeUserStudySteps: activeUserStudySteps ?? this.activeUserStudySteps,
      hasFinishedAnswering: hasFinishedAnswering ?? this.hasFinishedAnswering,
      canLeaveCurrWord: canLeaveCurrWord ?? this.canLeaveCurrWord,
      selectedAnswerIndex: selectedAnswerIndex == _sentinel ? this.selectedAnswerIndex : (selectedAnswerIndex as int?),
      correctAnswerIndex: correctAnswerIndex == _sentinel ? this.correctAnswerIndex : (correctAnswerIndex as int?),
      flippedAnswerIndices: flippedAnswerIndices ?? this.flippedAnswerIndices,
      meaningText: meaningText ?? this.meaningText,
      currentScore: currentScore == _sentinel ? this.currentScore : (currentScore as int?),
      showSentenceTranslation: showSentenceTranslation ?? this.showSentenceTranslation,
      tabIndex: tabIndex ?? this.tabIndex,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      wordUIStates: wordUIStates ?? this.wordUIStates,
      fsrsItem: fsrsItem == _sentinel ? this.fsrsItem : (fsrsItem as FSRSItem?),
      daysSinceLastReview: daysSinceLastReview == _sentinel ? this.daysSinceLastReview : (daysSinceLastReview as int?),
      lastFsrsRating: lastFsrsRating == _sentinel ? this.lastFsrsRating : (lastFsrsRating as FsrsRating?),
      lastFsrsRatingReason: lastFsrsRatingReason == _sentinel ? this.lastFsrsRatingReason : (lastFsrsRatingReason as String?),
      words: words == _sentinel ? this.words : (words as List<WordVo>?),
      buttonsEnabled: buttonsEnabled ?? this.buttonsEnabled,
      showHandwritingBoard: showHandwritingBoard ?? this.showHandwritingBoard,
      asrState: asrState ?? this.asrState,
      asrResult: asrResult ?? this.asrResult,
      currentAsrCandidates: currentAsrCandidates ?? this.currentAsrCandidates,
      isKeyboardVisible: isKeyboardVisible ?? this.isKeyboardVisible,
      autoJumpAfterCorrectCh2En: autoJumpAfterCorrectCh2En ?? this.autoJumpAfterCorrectCh2En,
      autoJumpAfterCorrectEn2Ch: autoJumpAfterCorrectEn2Ch ?? this.autoJumpAfterCorrectEn2Ch,
      autoJumpAfterCorrectChSentence2En: autoJumpAfterCorrectChSentence2En ?? this.autoJumpAfterCorrectChSentence2En,
      autoJumpAfterCorrectEnSentence2Ch: autoJumpAfterCorrectEnSentence2Ch ?? this.autoJumpAfterCorrectEnSentence2Ch,
      asrPassRuleCache: asrPassRuleCache ?? this.asrPassRuleCache,
      lowestRatingForCurrentWord: lowestRatingForCurrentWord == _sentinel ? this.lowestRatingForCurrentWord : (lowestRatingForCurrentWord as FsrsRating?),
      assessmentRating: assessmentRating == _sentinel ? this.assessmentRating : (assessmentRating as FsrsRating?),
      assessmentScheduledDays: assessmentScheduledDays == _sentinel ? this.assessmentScheduledDays : (assessmentScheduledDays as int?),
      englishDigestOfFirstSentence: englishDigestOfFirstSentence == _sentinel ? this.englishDigestOfFirstSentence : (englishDigestOfFirstSentence as String?),
      playingStates: playingStates ?? this.playingStates,
      hintTapCount: hintTapCount ?? this.hintTapCount,
      isWordMastered: isWordMastered ?? this.isWordMastered,
      isRestoreStep: isRestoreStep ?? this.isRestoreStep,
      wordStartTime: wordStartTime == _sentinel ? this.wordStartTime : (wordStartTime as DateTime?),
      firstMatchTime: firstMatchTime == _sentinel ? this.firstMatchTime : (firstMatchTime as DateTime?),
      isUpdatingByHint: isUpdatingByHint ?? this.isUpdatingByHint,
      progressBarTapCount: progressBarTapCount ?? this.progressBarTapCount,
      showAnswerButtons: showAnswerButtons ?? this.showAnswerButtons,
      slideDirection: slideDirection ?? this.slideDirection,
      isEditMode: isEditMode ?? this.isEditMode,
      highlightedWordImg: highlightedWordImg == _sentinel ? this.highlightedWordImg : (highlightedWordImg as WordImageVo?),
      isWordImageEdited: isWordImageEdited ?? this.isWordImageEdited,
      loadError: loadError == _sentinel ? this.loadError : (loadError as String?),
      isSelectModePreferred: isSelectModePreferred ?? this.isSelectModePreferred,
      isPttPressed: isPttPressed ?? this.isPttPressed,
    );
  }

  @override
  List<Object?> get props => [
    dataLoaded,
    isGettingNextWord,
    currentGetWordResult,
    learningGetWordResult,
    reviewReturnTarget,
    word,
    wordWrapper,
    studyStep,
    activeUserStudySteps,
    hasFinishedAnswering,
    canLeaveCurrWord,
    selectedAnswerIndex,
    correctAnswerIndex,
    flippedAnswerIndices,
    meaningText,
    currentScore,
    showSentenceTranslation,
    tabIndex,
    history,
    historyIndex,
    wordUIStates,
    fsrsItem,
    daysSinceLastReview,
    lastFsrsRating,
    lastFsrsRatingReason,
    words,
    buttonsEnabled,
    showHandwritingBoard,
    asrState,
    asrResult,
    currentAsrCandidates,
    isKeyboardVisible,
    autoJumpAfterCorrectCh2En,
    autoJumpAfterCorrectEn2Ch,
    autoJumpAfterCorrectChSentence2En,
    autoJumpAfterCorrectEnSentence2Ch,
    asrPassRuleCache,
    lowestRatingForCurrentWord,
    assessmentRating,
    assessmentScheduledDays,
    englishDigestOfFirstSentence,
    playingStates,
    hintTapCount,
    isWordMastered,
    isRestoreStep,
    wordStartTime,
    firstMatchTime,
    isUpdatingByHint,
    progressBarTapCount,
    showAnswerButtons,
    slideDirection,
    isEditMode,
    highlightedWordImg,
    isWordImageEdited,
    loadError,
    isSelectModePreferred,
    isPttPressed,
  ];
}
