import 'package:nnbdc/api/enum.dart';

/// 学习环节轨道推导：每个词按状态分配"学习轨道"（scope='new' 新词）或
/// "复习轨道"（scope='review' 旧词），两条轨道同构：
/// [测评, 按当天首条评分选答对/答错组, List]。
/// 新词与旧词的区别仅在评分语义（init/relearn 重设 vs next 复习公式），
/// 轨道构造完全一致（三组显式配置，无隐含规则）。
class StudyTrack {
  /// 判定该词今天是否走复习轨道。
  ///
  /// 单一真理来源：如果提供了 [isTodayNewWord]，直接遵从今日计划生成时权威固化的标记（!isTodayNewWord 即为复习词），
  /// 彻底消除同一业务日内多次学习或零间隔 FSRS relearn（elapsedDays == 0）导致旧词被误当成新词的漏洞。
  /// 未提供 [isTodayNewWord] 时，按今天首条日志 elapsedDays 固化（init=0 → 学习轨道；跨天 next>0 → 复习轨道），
  /// 或按进入计划时的初始 FSRS 状态判定。
  static bool isReviewTrack({
    bool? isTodayNewWord,
    double? stability,
    int? state,
    DateTime? lastLearningDate,
    int? todayFirstLogElapsedDays,
    DateTime? today,
  }) {
    // 优先：遵从今日计划固化的权威新词标记
    if (isTodayNewWord != null) {
      return !isTodayNewWord;
    }
    // 降级：今天已提交过评分，以今天首条评分日志的间隔固化轨道
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

  /// 反向互补的单词环节：英→中方向（单词/例句）→ Ch2En；中→英方向 → En2Ch。
  static String oppositeWordStep(String step) {
    return (step == 'Ch2En' || step == 'ChSentence2En') ? 'En2Ch' : 'Ch2En';
  }

  /// 该词今天的环节轨道：[测评, 后续组(按首条评分选择), List]。
  /// 测评尚未提交（todayFirstLogRating == null）→ 仅 [测评, List]（评分后轨道扩展）。
  static List<String> trackOf({
    bool? isTodayNewWord,
    double? stability,
    int? state,
    DateTime? lastLearningDate,
    int? todayFirstLogElapsedDays,
    int? todayFirstLogRating,
    required String newCheck,
    required List<String> newCorrect,
    required List<String> newWrong,
    required String reviewCheck,
    required List<String> reviewCorrect,
    required List<String> reviewWrong,
    DateTime? today,
  }) {
    final isReview = isReviewTrack(
      isTodayNewWord: isTodayNewWord,
      stability: stability,
      state: state,
      lastLearningDate: lastLearningDate,
      todayFirstLogElapsedDays: todayFirstLogElapsedDays,
      today: today,
    );
    final check = isReview ? reviewCheck : newCheck;
    final correct = isReview ? reviewCorrect : newCorrect;
    final wrong = isReview ? reviewWrong : newWrong;
    final after = todayFirstLogRating == null
        ? const <String>[]
        : (todayFirstLogRating == FsrsRating.again.value ? wrong : correct);
    return [check, ...after, 'List'];
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
