import 'package:nnbdc/api/enum.dart';

/// 学习环节轨道推导：每个词按状态分配"学习轨道"或"复习轨道"。
///
/// - 学习轨道 = 用户激活序列（含 List），用于新词（学习事件：多环节建立记忆，
///   每次评分走 FSRS 学习步骤重设语义）。
/// - 复习轨道 = [测评, 后续环节(按答对/答错分组显式配置), List]，用于旧词
///   （复习事件：测评 = 每天单次复习信号；后续环节按测评结果走对应组）。
class StudyTrack {
  /// 判定该词今天是否走复习轨道（与 [trackOf] 同参同判据，供"测评后跳过空组"等场景显式使用）。
  ///
  /// 轨道在"今天首次评分"时固化：今天首条评分日志的 elapsedDays 决定当天轨道
  /// （init=0 → 学习轨道；跨天 next>0 → 复习轨道），当天后续评分不再改变轨道，
  /// 防止"新词评分后 state 转 review"导致轨道中途漂移。
  static bool isReviewTrack({
    required List<String> activeStepNames,
    double? stability,
    int? state,
    DateTime? lastLearningDate,
    int? todayFirstLogElapsedDays,
    required DateTime today,
  }) {
    // 今天已提交过评分：以今天首条评分日志的间隔固化轨道
    if (todayFirstLogElapsedDays != null) {
      return todayFirstLogElapsedDays > 0;
    }
    // 今天尚无评分：按进入计划时的状态判定
    // 新词：从未建立 FSRS 进度 → 学习轨道
    if (stability == null || stability == 0.0) {
      return false;
    }
    // 已建立进度（review/relearning，或昨天学一半的 learning）→ 复习轨道
    return true;
  }

  /// 旧词三组的有效值（含未设置时的回退默认）：
  /// - 测评 = 配置的 checkStep；未设置 → 新词序列第 1 环节；
  /// - 答对组 = 配置的 correctSteps；未设置 → 空（答对即完成）；
  /// - 答错组 = 配置的 wrongSteps；未设置 → [反向互补环节]（旧行为）。
  static ({String check, List<String> correct, List<String> wrong})
      effectiveReviewConfig({
    required List<String> reviewCheckSteps,
    required List<String> reviewCorrectSteps,
    required List<String> reviewWrongSteps,
    required List<String> fallbackActiveStepNames,
  }) {
    if (reviewCheckSteps.isNotEmpty) {
      return (
        check: reviewCheckSteps.first,
        correct: List.of(reviewCorrectSteps),
        wrong: List.of(reviewWrongSteps),
      );
    }
    final fallbackCheck = fallbackActiveStepNames.first;
    return (
      check: fallbackCheck,
      correct: const [],
      wrong: [oppositeWordStep(fallbackCheck)],
    );
  }

  /// 反向互补的单词环节：英→中方向（单词/例句）→ Ch2En；中→英方向 → En2Ch。
  static String oppositeWordStep(String step) {
    return (step == 'Ch2En' || step == 'ChSentence2En') ? 'En2Ch' : 'Ch2En';
  }

  /// 复习轨道：测评 + 按测评结果（当天首条评分日志的 rating）走答对/答错组 + List。
  /// 测评尚未提交（firstLogRating == null）→ 仅 [测评, List]（评分后轨道扩展）。
  static List<String> reviewTrack({
    required List<String> reviewCheckSteps,
    required List<String> reviewCorrectSteps,
    required List<String> reviewWrongSteps,
    required List<String> fallbackActiveStepNames,
    required int? firstLogRating,
  }) {
    final eff = effectiveReviewConfig(
      reviewCheckSteps: reviewCheckSteps,
      reviewCorrectSteps: reviewCorrectSteps,
      reviewWrongSteps: reviewWrongSteps,
      fallbackActiveStepNames: fallbackActiveStepNames,
    );
    final after = firstLogRating == null
        ? const <String>[]
        : (firstLogRating == FsrsRating.again.value ? eff.wrong : eff.correct);
    return [eff.check, ...after, 'List'];
  }

  /// 判定该词今天应走哪条轨道，返回轨道环节名数组。
  static List<String> trackOf({
    required List<String> activeStepNames,
    double? stability,
    int? state,
    DateTime? lastLearningDate,
    int? todayFirstLogElapsedDays,
    required List<String> reviewCheckSteps,
    required List<String> reviewCorrectSteps,
    required List<String> reviewWrongSteps,
    int? todayFirstLogRating,
    required DateTime today,
  }) {
    return isReviewTrack(
      activeStepNames: activeStepNames,
      stability: stability,
      state: state,
      lastLearningDate: lastLearningDate,
      todayFirstLogElapsedDays: todayFirstLogElapsedDays,
      today: today,
    )
        ? reviewTrack(
            reviewCheckSteps: reviewCheckSteps,
            reviewCorrectSteps: reviewCorrectSteps,
            reviewWrongSteps: reviewWrongSteps,
            fallbackActiveStepNames: activeStepNames,
            firstLogRating: todayFirstLogRating,
          )
        : activeStepNames;
  }

  /// 该评分环节（索引 currentIndex）之后是否还有评分环节。
  /// 评分环节 = 轨道中 List 之外的环节（List 不评分）。
  static bool hasMoreGradedSteps(List<String> track, int currentIndex) {
    for (int i = currentIndex + 1; i < track.length; i++) {
      if (track[i] != 'List') return true;
    }
    return false;
  }
}
