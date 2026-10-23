import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/fsrs.dart';
import '../providers/answer_mode.dart';

class WordUIState {
  final int? stepIndex;
  final String? studyStep;
  final bool hasFinishedAnswering;
  final bool canLeaveCurrWord;

  /// 那一次呈现是否"写对并通过"。
  /// 不存的话，回看时输入框会盖住正确答案：界面只知道"答完了"，不知道"过了"。
  final bool isScorePassed;
  final bool showSentenceTranslation;
  final bool showSentenceWordMeaning;
  final int? selectedAnswerIndex;
  /// 那一次呈现时用的答题方式（写/说/选）
  final AnswerMode answerMode;
  final int? currentScore;
  final String meaningText;
  final List<WordVo>? words;
  final int correctAnswerIndex;
  final FSRSItem? fsrsItem;
  final int? daysSinceLastReview;
  final FsrsRating? lastFsrsRating;
  final List<Pair<int, int>>? asrMatchedMeaningItemParts;
  final List<Pair<int, int>>? asrRevealedMeaningItemParts;
  final List<String>? currentAsrCandidates;
  final int hintTapCount;

  /// 那一次呈现时的"本组本环节进度"（第 N 组 · 轨道 · x/y）与是否本环节重练。
  ///
  /// 回看要精确还原"用户离开时看到的样子"，就必须连这条坐标一起存 ——
  /// 按"这个词现在排在哪"现算，会让一个刚点过「不认识」的词一被回看就标成「本环节重练」。
  final int groupStepNo;
  final int groupStepPosition;
  final int groupStepTotal;
  final String? groupStepTrackName;
  final bool isGroupStepRetry;

  WordUIState({
    this.stepIndex,
    this.studyStep,
    required this.hasFinishedAnswering,
    required this.canLeaveCurrWord,
    this.isScorePassed = false,
    required this.showSentenceTranslation,
    this.showSentenceWordMeaning = false,
    this.selectedAnswerIndex,
    required this.answerMode,
    this.currentScore,
    required this.meaningText,
    this.words,
    required this.correctAnswerIndex,
    this.fsrsItem,
    this.daysSinceLastReview,
    this.lastFsrsRating,
    this.asrMatchedMeaningItemParts,
    this.asrRevealedMeaningItemParts,
    this.currentAsrCandidates,
    required this.hintTapCount,
    this.groupStepNo = 0,
    this.groupStepPosition = 0,
    this.groupStepTotal = 0,
    this.groupStepTrackName,
    this.isGroupStepRetry = false,
  });
}

/// 历史栈里的一次呈现：那一次的取词结果 + 那一次的界面状态。
///
/// 两者必须绑在一起：同一个词当天可能被呈现多次（测评、重练…），
/// 只有按"呈现"存，回看才能精确还原用户离开时的样子；按词存会被后一次覆盖。
typedef WordPresentation = ({GetWordResult result, WordUIState? uiState});
