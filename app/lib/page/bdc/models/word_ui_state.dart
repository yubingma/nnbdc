import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/fsrs.dart';

class WordUIState {
  final int? stepIndex;
  final String? studyStep;
  final bool hasFinishedAnswering;
  final bool canLeaveCurrWord;
  final bool showSentenceTranslation;
  final int? selectedAnswerIndex;
  final int tabIndex;
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

  WordUIState({
    this.stepIndex,
    this.studyStep,
    required this.hasFinishedAnswering,
    required this.canLeaveCurrWord,
    required this.showSentenceTranslation,
    this.selectedAnswerIndex,
    required this.tabIndex,
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
  });
}
