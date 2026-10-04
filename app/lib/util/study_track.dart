import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/fsrs.dart';

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

  /// 本环节是否首次作答（据此决定是否计分）。
  ///
  /// 每个评分环节只在首次作答时写一条评分日志，答错的词留在本环节循环重练、
  /// 重练不再计分，因此 "今天该词的评分日志条数" 与 "已走完的环节数" 的关系为：
  /// - 日志条数 == 已走完环节数 → 当前环节尚未作答，本次是首次作答（计分）
  /// - 日志条数 >  已走完环节数 → 当前环节已首答过，本次是重练（不计分）
  ///
  /// 日志条数少于进度属异常（如日志被清理），此时按首次作答处理：
  /// 宁可重复计分，也不静默丢分。
  static bool isFirstAttemptOfStep({
    required int todayLogCount,
    required int todayLearnedTimes,
  }) =>
      todayLogCount <= todayLearnedTimes;

  /// 同环节重新出题时，能不能继承上一轮缓存的答题状态（已命中的释义高亮、已揭晓的答案）。
  ///
  /// - 中断后接着答（用户答到一半退出再回来）：可以继承，用户只需补上剩下的那几个；
  /// - **本环节重测**（答错后回到队尾重来）：一律不可以 —— 那份缓存可能来自"回看时试答"
  ///   （回看是历史导航、评分不入库，但界面状态会被缓存，见 getNextWord 的 _saveCurrentWordState），
  ///   继承过来等于把答案提前送给用户。
  static bool canInheritCachedStepState({
    required int? cachedStepIndex,
    required int resultStepIndex,
    required bool isGroupStepRetry,
  }) =>
      cachedStepIndex == resultStepIndex && !isGroupStepRetry;

  /// 当天测评之后的后续环节（同一天里再次评分）该怎么结算记忆参数。
  ///
  /// 项目约定：**同一天里只认"往下扣"的评分**。
  /// - 模糊 hard（×0.8398）、忘记 again（×0.5011）照官方同日公式下调；
  /// - 良好 good（×1.4078）、轻松 easy（×2.3598）**不再改动记忆参数**，
  ///   只把"又提取过一次"记进 reps。
  ///
  /// 理由：同一天里隔几分钟的连续答对只是短期复述，不是"隔了一段时间还记得"的证据。
  /// 官方同日公式本身没错（见 [FSRS.next]，黄金向量见 test/fsrs_test.dart），
  /// 错的是把它当成独立的乘性增益连乘：实测新词"测评 + 三个巩固"全评轻松会从
  /// 15.69105 连乘到 206.1829 天，越过掌握线当场毕业，当天学的词当天就不再复习。
  ///
  /// 因此这条限制只作用于"同一天怎么结算"，算法层 [FSRS] 与官方逐位一致。
  /// [nextState] 不给时按评分推断（again → 重新学习，其余 → 复习），与 [FSRS.next] 同口径。
  static FSRSItem sameDayStep(
    FSRSItem prev,
    FsrsRating rating, {
    FsrsState? nextState,
  }) {
    if (rating == FsrsRating.good || rating == FsrsRating.easy) {
      return FSRSItem(
        stability: prev.stability,
        difficulty: prev.difficulty,
        elapsedDays: 0,
        scheduledDays: prev.scheduledDays,
        reps: prev.reps + 1,
        lapses: prev.lapses,
        state: nextState ?? FsrsState.review,
      );
    }
    return FSRS().next(prev, rating, 0, nextState: nextState);
  }
}
