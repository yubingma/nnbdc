import 'package:equatable/equatable.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:nnbdc/util/asr.dart';
import '../models/word_ui_state.dart';

class BdcState extends Equatable {
  final bool dataLoaded;
  final bool isGettingNextWord;
  final GetWordResult? currentGetWordResult;
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
  final String asrPassRuleCache;
  final FsrsRating? lowestRatingForCurrentWord;
  final FsrsRating? assessmentRating;
  final String? englishDigestOfFirstSentence;

  final Map<String, bool> playingStates;
  final int hintTapCount;
  final bool isWordMastered;
  final int accumulatedSeconds;
  
  final DateTime? wordStartTime;
  final DateTime? firstMatchTime;

  final bool isUpdatingByHint;
  final int progressBarTapCount;
  final bool showAnswerButtons;
  final double slideDirection;
  final bool isEditMode;
  final WordImageVo? highlightedWordImg;
  final bool isWordImageEdited;

  const BdcState({
    this.dataLoaded = false,
    this.isGettingNextWord = false,
    this.currentGetWordResult,
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
    this.asrPassRuleCache = 'ONE',
    this.lowestRatingForCurrentWord,
    this.assessmentRating,
    this.englishDigestOfFirstSentence,
    this.playingStates = const {'word': false, 'sentence': false},
    this.hintTapCount = 0,
    this.isWordMastered = false,
    this.accumulatedSeconds = 0,
    this.wordStartTime,
    this.firstMatchTime,
    this.isUpdatingByHint = false,
    this.progressBarTapCount = 0,
    this.showAnswerButtons = false,
    this.slideDirection = 1.0,
    this.isEditMode = false,
    this.highlightedWordImg,
    this.isWordImageEdited = false,
  });

  bool get autoJumpAfterCorrect {
    if (studyStep == StudyStep.ch2En.json) {
      return autoJumpAfterCorrectCh2En;
    }
    return autoJumpAfterCorrectEn2Ch;
  }

  BdcState copyWith({
    bool? dataLoaded,
    bool? isGettingNextWord,
    GetWordResult? currentGetWordResult,
    WordVo? word,
    WordWrapper? wordWrapper,
    String? studyStep,
    List<UserStudyStepVo>? activeUserStudySteps,
    bool? hasFinishedAnswering,
    bool? canLeaveCurrWord,
    int? selectedAnswerIndex,
    int? correctAnswerIndex,
    Set<int>? flippedAnswerIndices,
    String? meaningText,
    int? currentScore,
    bool? showSentenceTranslation,
    int? tabIndex,
    List<GetWordResult>? history,
    int? historyIndex,
    Map<String, WordUIState>? wordUIStates,
    FSRSItem? fsrsItem,
    int? daysSinceLastReview,
    FsrsRating? lastFsrsRating,
    String? lastFsrsRatingReason,
    List<WordVo>? words,
    bool? buttonsEnabled,
    bool? showHandwritingBoard,
    AsrState? asrState,
    String? asrResult,
    List<String>? currentAsrCandidates,
    bool? isKeyboardVisible,
    bool? autoJumpAfterCorrectCh2En,
    bool? autoJumpAfterCorrectEn2Ch,
    String? asrPassRuleCache,
    FsrsRating? lowestRatingForCurrentWord,
    FsrsRating? assessmentRating,
    String? englishDigestOfFirstSentence,
    Map<String, bool>? playingStates,
    int? hintTapCount,
    bool? isWordMastered,
    int? accumulatedSeconds,
    DateTime? wordStartTime,
    DateTime? firstMatchTime,
    bool? isUpdatingByHint,
    int? progressBarTapCount,
    bool? showAnswerButtons,
    double? slideDirection,
    bool? isEditMode,
    WordImageVo? highlightedWordImg,
    bool? isWordImageEdited,
  }) {
    return BdcState(
      dataLoaded: dataLoaded ?? this.dataLoaded,
      isGettingNextWord: isGettingNextWord ?? this.isGettingNextWord,
      currentGetWordResult: currentGetWordResult ?? this.currentGetWordResult,
      word: word ?? this.word,
      wordWrapper: wordWrapper ?? this.wordWrapper,
      studyStep: studyStep ?? this.studyStep,
      activeUserStudySteps: activeUserStudySteps ?? this.activeUserStudySteps,
      hasFinishedAnswering: hasFinishedAnswering ?? this.hasFinishedAnswering,
      canLeaveCurrWord: canLeaveCurrWord ?? this.canLeaveCurrWord,
      selectedAnswerIndex: selectedAnswerIndex ?? this.selectedAnswerIndex,
      correctAnswerIndex: correctAnswerIndex ?? this.correctAnswerIndex,
      flippedAnswerIndices: flippedAnswerIndices ?? this.flippedAnswerIndices,
      meaningText: meaningText ?? this.meaningText,
      currentScore: currentScore ?? this.currentScore,
      showSentenceTranslation: showSentenceTranslation ?? this.showSentenceTranslation,
      tabIndex: tabIndex ?? this.tabIndex,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      wordUIStates: wordUIStates ?? this.wordUIStates,
      fsrsItem: fsrsItem ?? this.fsrsItem,
      daysSinceLastReview: daysSinceLastReview ?? this.daysSinceLastReview,
      lastFsrsRating: lastFsrsRating ?? this.lastFsrsRating,
      lastFsrsRatingReason: lastFsrsRatingReason ?? this.lastFsrsRatingReason,
      words: words ?? this.words,
      buttonsEnabled: buttonsEnabled ?? this.buttonsEnabled,
      showHandwritingBoard: showHandwritingBoard ?? this.showHandwritingBoard,
      asrState: asrState ?? this.asrState,
      asrResult: asrResult ?? this.asrResult,
      currentAsrCandidates: currentAsrCandidates ?? this.currentAsrCandidates,
      isKeyboardVisible: isKeyboardVisible ?? this.isKeyboardVisible,
      autoJumpAfterCorrectCh2En: autoJumpAfterCorrectCh2En ?? this.autoJumpAfterCorrectCh2En,
      autoJumpAfterCorrectEn2Ch: autoJumpAfterCorrectEn2Ch ?? this.autoJumpAfterCorrectEn2Ch,
      asrPassRuleCache: asrPassRuleCache ?? this.asrPassRuleCache,
      lowestRatingForCurrentWord: lowestRatingForCurrentWord ?? this.lowestRatingForCurrentWord,
      assessmentRating: assessmentRating ?? this.assessmentRating,
      englishDigestOfFirstSentence: englishDigestOfFirstSentence ?? this.englishDigestOfFirstSentence,
      playingStates: playingStates ?? this.playingStates,
      hintTapCount: hintTapCount ?? this.hintTapCount,
      isWordMastered: isWordMastered ?? this.isWordMastered,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      wordStartTime: wordStartTime ?? this.wordStartTime,
      firstMatchTime: firstMatchTime ?? this.firstMatchTime,
      isUpdatingByHint: isUpdatingByHint ?? this.isUpdatingByHint,
      progressBarTapCount: progressBarTapCount ?? this.progressBarTapCount,
      showAnswerButtons: showAnswerButtons ?? this.showAnswerButtons,
      slideDirection: slideDirection ?? this.slideDirection,
      isEditMode: isEditMode ?? this.isEditMode,
      highlightedWordImg: highlightedWordImg ?? this.highlightedWordImg,
      isWordImageEdited: isWordImageEdited ?? this.isWordImageEdited,
    );
  }

  @override
  List<Object?> get props => [
    dataLoaded,
    isGettingNextWord,
    currentGetWordResult,
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
    asrPassRuleCache,
    lowestRatingForCurrentWord,
    assessmentRating,
    englishDigestOfFirstSentence,
    playingStates,
    hintTapCount,
    isWordMastered,
    accumulatedSeconds,
    wordStartTime,
    firstMatchTime,
    isUpdatingByHint,
    progressBarTapCount,
    showAnswerButtons,
    slideDirection,
    isEditMode,
    highlightedWordImg,
    isWordImageEdited,
  ];
}
