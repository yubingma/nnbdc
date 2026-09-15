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
  
  final String meaningText;
  final int? currentScore;
  final bool isScorePassed;
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
  /// 手写板是否为「中文默写」模式（英译汉时手写中文释义，结果走中文匹配而非英文拼写）。
  /// 它是手写板的子模式：只在 [showHandwritingBoard] 为 true 期间有意义，
  /// 板子关闭时由 copyWith 强制复位（见 [copyWith] 中的说明）。
  final bool isChineseDictation;
  /// 中文默写判题进度：已命中的释义子项数（仅用于展示，不参与判题决策）
  final int dictationMatchedCount;
  /// 中文默写判题进度：达到通过线所需命中的释义子项数（0 表示无进度可展示）
  final int dictationRequiredCount;
  /// 拼写或默写判对成功后的视觉反馈与退场过渡态（文字变绿、绿勾反馈，随后平滑淡退）
  final bool isSpellingSuccess;
  
  final AsrState asrState;
  final String asrResult;
  final List<String> currentAsrCandidates;

  final bool isKeyboardVisible;
  final bool autoJumpAfterCorrectCh2En;
  final bool autoJumpAfterCorrectEn2Ch;
  final bool autoJumpAfterCorrectChSentence2En;
  final bool autoJumpAfterCorrectEnSentence2Ch;
  final bool showWordDetailAfterCorrect;
  final String asrPassRuleCache;
  final FsrsRating? lowestRatingForCurrentWord;
  final FsrsRating? assessmentRating;
  final int? assessmentScheduledDays;
  final String? englishDigestOfFirstSentence;

  final Map<String, bool> playingStates;
  final int hintTapCount;
  final bool isWordMastered;
  /// 当前单词今天是否走复习轨道（旧词），由 handleWord 按轨道推导，用于把环节名映射为「新词/旧词」。
  final bool isReviewWord;
  /// 本组（每组单词数可配置，见 StudyBo.batchSize）的序号（1 起）
  /// 与当前环节的排队位置、队列长度，
  /// 用于学习页「第 N 组 · 轨道 · 环节 x/y」指示；位置为 0 表示当前无指示可展示
  /// （如 List 环节或无法定位）。
  final int groupStepNo;
  final int groupStepPosition;
  final int groupStepTotal;

  /// 当前词所属的轨道名（如「新词答错」）；x/y 是该轨道在本组本环节内的进度，
  /// 见 StudyBo.getBatchPhaseProgress。
  final String? groupStepTrackName;

  /// 本组环节切换时的一次性轻提示（只在切换后第一个词上展示，切词即清空）
  final String? groupStepHint;
  
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
  final bool isSentenceSelectModePreferred;

  /// 例句环节 PTT(按下说话)按钮是否处于按住状态
  final bool isPttPressed;

  /// 大模型裁判是否正在判定中（单词中英/例句环节通用）
  final bool isAiEvaluating;

  /// 例句环节当前词是否处于练习模式（查看答案后隐藏答案继续练习）
  final bool isPracticeMode;

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
    this.meaningText = "",
    this.currentScore,
    this.isScorePassed = false,
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
    this.isChineseDictation = false,
    this.dictationMatchedCount = 0,
    this.dictationRequiredCount = 0,
    this.isSpellingSuccess = false,
    this.asrState = AsrState.unknown,
    this.asrResult = "",
    this.currentAsrCandidates = const [],
    this.isKeyboardVisible = false,
    this.autoJumpAfterCorrectCh2En = true,
    this.autoJumpAfterCorrectEn2Ch = true,
    this.autoJumpAfterCorrectChSentence2En = true,
    this.autoJumpAfterCorrectEnSentence2Ch = true,
    this.showWordDetailAfterCorrect = false,
    this.asrPassRuleCache = 'ONE',
    this.lowestRatingForCurrentWord,
    this.assessmentRating,
    this.assessmentScheduledDays,
    this.englishDigestOfFirstSentence,
    this.playingStates = const {'word': false, 'sentence': false},
    this.hintTapCount = 0,
    this.isWordMastered = false,
    this.isReviewWord = false,
    this.groupStepNo = 0,
    this.groupStepPosition = 0,
    this.groupStepTotal = 0,
    this.groupStepTrackName,
    this.groupStepHint,
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
    this.isSentenceSelectModePreferred = false,
    this.isPttPressed = false,
    this.isAiEvaluating = false,
    this.isPracticeMode = false,
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
    Object? meaningText = _sentinel,
    Object? currentScore = _sentinel,
    bool? isScorePassed,
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
    bool? isChineseDictation,
    int? dictationMatchedCount,
    int? dictationRequiredCount,
    bool? isSpellingSuccess,
    AsrState? asrState,
    String? asrResult,
    List<String>? currentAsrCandidates,
    bool? isKeyboardVisible,
    bool? autoJumpAfterCorrectCh2En,
    bool? autoJumpAfterCorrectEn2Ch,
    bool? autoJumpAfterCorrectChSentence2En,
    bool? autoJumpAfterCorrectEnSentence2Ch,
    bool? showWordDetailAfterCorrect,
    String? asrPassRuleCache,
    Object? lowestRatingForCurrentWord = _sentinel,
    Object? assessmentRating = _sentinel,
    Object? assessmentScheduledDays = _sentinel,
    Object? englishDigestOfFirstSentence = _sentinel,
    Map<String, bool>? playingStates,
    int? hintTapCount,
    bool? isWordMastered,
    bool? isReviewWord,
    int? groupStepNo,
    int? groupStepPosition,
    int? groupStepTotal,
    Object? groupStepTrackName = _sentinel,
    Object? groupStepHint = _sentinel,
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
    bool? isSentenceSelectModePreferred,
    bool? isPttPressed,
    bool? isAiEvaluating,
    bool? isPracticeMode,
  }) {
    // 「中文默写」及其进度是手写板的子状态：板子不在时一律不成立。
    // 关闭手写板的路径很多（答对成功过渡、主动点「答对/认识」、换词、提示已全展示、取消），
    // 逐一清标记必漏；一旦残留，回到背单词页后的正常作答会被当成"中文默写"严格判错，
    // 并连发"答案不正确或未写完整，请重写"。故在状态构造处收口：不开板子就不存在默写模式。
    final bool handwritingBoardVisible =
        showHandwritingBoard ?? this.showHandwritingBoard;
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
      meaningText: meaningText == _sentinel ? this.meaningText : (meaningText as String? ?? ""),
      currentScore: currentScore == _sentinel ? this.currentScore : (currentScore as int?),
      isScorePassed: isScorePassed ?? this.isScorePassed,
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
      showHandwritingBoard: handwritingBoardVisible,
      isChineseDictation: handwritingBoardVisible
          ? (isChineseDictation ?? this.isChineseDictation)
          : false,
      dictationMatchedCount: handwritingBoardVisible
          ? (dictationMatchedCount ?? this.dictationMatchedCount)
          : 0,
      dictationRequiredCount: handwritingBoardVisible
          ? (dictationRequiredCount ?? this.dictationRequiredCount)
          : 0,
      isSpellingSuccess: isSpellingSuccess ?? this.isSpellingSuccess,
      asrState: asrState ?? this.asrState,
      asrResult: asrResult ?? this.asrResult,
      currentAsrCandidates: currentAsrCandidates ?? this.currentAsrCandidates,
      isKeyboardVisible: isKeyboardVisible ?? this.isKeyboardVisible,
      autoJumpAfterCorrectCh2En: autoJumpAfterCorrectCh2En ?? this.autoJumpAfterCorrectCh2En,
      autoJumpAfterCorrectEn2Ch: autoJumpAfterCorrectEn2Ch ?? this.autoJumpAfterCorrectEn2Ch,
      autoJumpAfterCorrectChSentence2En: autoJumpAfterCorrectChSentence2En ?? this.autoJumpAfterCorrectChSentence2En,
      autoJumpAfterCorrectEnSentence2Ch: autoJumpAfterCorrectEnSentence2Ch ?? this.autoJumpAfterCorrectEnSentence2Ch,
      showWordDetailAfterCorrect: showWordDetailAfterCorrect ?? this.showWordDetailAfterCorrect,
      asrPassRuleCache: asrPassRuleCache ?? this.asrPassRuleCache,
      lowestRatingForCurrentWord: lowestRatingForCurrentWord == _sentinel ? this.lowestRatingForCurrentWord : (lowestRatingForCurrentWord as FsrsRating?),
      assessmentRating: assessmentRating == _sentinel ? this.assessmentRating : (assessmentRating as FsrsRating?),
      assessmentScheduledDays: assessmentScheduledDays == _sentinel ? this.assessmentScheduledDays : (assessmentScheduledDays as int?),
      englishDigestOfFirstSentence: englishDigestOfFirstSentence == _sentinel ? this.englishDigestOfFirstSentence : (englishDigestOfFirstSentence as String?),
      playingStates: playingStates ?? this.playingStates,
      hintTapCount: hintTapCount ?? this.hintTapCount,
      isWordMastered: isWordMastered ?? this.isWordMastered,
      isReviewWord: isReviewWord ?? this.isReviewWord,
      groupStepNo: groupStepNo ?? this.groupStepNo,
      groupStepPosition: groupStepPosition ?? this.groupStepPosition,
      groupStepTotal: groupStepTotal ?? this.groupStepTotal,
      groupStepTrackName: groupStepTrackName == _sentinel ? this.groupStepTrackName : (groupStepTrackName as String?),
      groupStepHint: groupStepHint == _sentinel ? this.groupStepHint : (groupStepHint as String?),
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
      isSentenceSelectModePreferred: isSentenceSelectModePreferred ?? this.isSentenceSelectModePreferred,
      isPttPressed: isPttPressed ?? this.isPttPressed,
      isAiEvaluating: isAiEvaluating ?? this.isAiEvaluating,
      isPracticeMode: isPracticeMode ?? this.isPracticeMode,
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
    wordWrapper != null
        ? Object.hash(
            wordWrapper!.asrMatchedMeaningItemParts.length,
            wordWrapper!.asrRevealedMeaningItemParts.length,
            wordWrapper!.hintLetterCount,
            wordWrapper!.isAiEvaluating,
            wordWrapper!.answeredAllMeanings,
          )
        : null,
    studyStep,
    activeUserStudySteps,
    hasFinishedAnswering,
    isPracticeMode,
    canLeaveCurrWord,
    selectedAnswerIndex,
    correctAnswerIndex,
    meaningText,
    currentScore,
    isScorePassed,
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
    isChineseDictation,
    dictationMatchedCount,
    dictationRequiredCount,
    asrState,
    asrResult,
    currentAsrCandidates,
    isKeyboardVisible,
    autoJumpAfterCorrectCh2En,
    autoJumpAfterCorrectEn2Ch,
    autoJumpAfterCorrectChSentence2En,
    autoJumpAfterCorrectEnSentence2Ch,
    showWordDetailAfterCorrect,
    asrPassRuleCache,
    lowestRatingForCurrentWord,
    assessmentRating,
    assessmentScheduledDays,
    englishDigestOfFirstSentence,
    playingStates,
    hintTapCount,
    isWordMastered,
    isReviewWord,
    groupStepNo,
    groupStepPosition,
    groupStepTotal,
    groupStepTrackName,
    groupStepHint,
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
    isSentenceSelectModePreferred,
    isPttPressed,
    isAiEvaluating,
  ];
}
