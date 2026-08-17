import 'package:nnbdc/api/enum.dart';

/// 学习环节轨道推导：每个词按状态分配"学习轨道"（scope='new' 新词）或
/// "复习轨道"（scope='review' 旧词），两条轨道同构：
/// [测评, 按当天首条评分选答对/答错组, List]。
/// 新词与旧词的区别仅在评分语义（init/relearn 重设 vs next 复习公式），
/// 轨道构造完全一致（三组显式配置，无隐含规则）。
class StudyTrack {
  /// 判定该词今天是否走复习轨道。
  ///
  /// 轨道在"今天首次评分"时固化：今天首条评分日志的 elapsedDays 决定当天轨道
  /// （init=0 → 学习轨道；跨天 next>0 → 复习轨道），当天后续评分不再改变轨道，
  /// 防止"新词评分后 state 转 review"导致轨道中途漂移。
  static bool isReviewTrack({
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

  /// 反向互补的单词环节：英→中方向（单词/例句）→ Ch2En；中→英方向 → En2Ch。
  static String oppositeWordStep(String step) {
    return (step == 'Ch2En' || step == 'ChSentence2En') ? 'En2Ch' : 'Ch2En';
  }

  /// 该词今天的环节轨道：[测评, 后续组(按首条评分选择), List]。
  /// 测评尚未提交（todayFirstLogRating == null）→ 仅 [测评, List]（评分后轨道扩展）。
  static List<String> trackOf({
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
    required DateTime today,
  }) {
    final isReview = isReviewTrack(
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
