/// 学习环节轨道推导：每个词按状态分配"学习轨道"或"复习轨道"。
///
/// - 学习轨道 = 用户激活序列（含 List），用于新词（学习事件：多环节建立记忆，
///   每次评分走 FSRS 学习步骤重设语义）。
/// - 复习轨道 = [测评(激活序列第 1), 重测(方向互补单词环节), List]，用于复习词
///   （复习事件：每天单次快速检验；答错当天走重测环节，再错明日重现）。
class StudyTrack {
  /// 判定该词今天是否走复习轨道（与 [trackOf] 同参同判据，供"测评答对跳过重测环节"等场景显式使用，
  /// 避免用轨道长度推断——学习轨道 [En2Ch, Ch2En, List] 与复习轨道同为长度 3）。
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

  /// 判定该词今天应走哪条轨道，返回轨道环节名数组。
  static List<String> trackOf({
    required List<String> activeStepNames,
    double? stability,
    int? state,
    DateTime? lastLearningDate,
    int? todayFirstLogElapsedDays,
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
        ? reviewTrack(activeStepNames)
        : activeStepNames;
  }

  /// 复习轨道：测评环节 = 激活序列第 1 环节（List 恒在末位，故非 List）；
  /// 重测环节 = En2Ch/Ch2En 二者之一：
  /// - 测评是单词环节 → 方向互补的另一个（未激活也出现一次）；
  /// - 测评是例句环节 → 激活单词环节中序列靠前者（都未激活默认 En2Ch）。
  static List<String> reviewTrack(List<String> activeStepNames) {
    final check = activeStepNames.first;
    String restore;
    if (check == 'En2Ch') {
      restore = 'Ch2En';
    } else if (check == 'Ch2En') {
      restore = 'En2Ch';
    } else {
      final wordSteps =
          activeStepNames.where((s) => s == 'En2Ch' || s == 'Ch2En').toList();
      restore = wordSteps.isNotEmpty ? wordSteps.first : 'En2Ch';
    }
    return [check, restore, 'List'];
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
