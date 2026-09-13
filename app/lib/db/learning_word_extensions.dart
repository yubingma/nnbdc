import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/util/date_utils.dart';

/// LearningWord 实体类的扩展方法，封装全部关于已掌握和进度判定细节的逻辑推导。
extension LearningWordProgressExtension on LearningWord {
  /// 1. 判定单词是否已经有效掌握 / 已毕业
  bool isEffectivelyMastered(Set<String> masteredWordIds) {
    if (masteredWordIds.contains(wordId)) return true;
    if (stability != null && stability! >= Constants.graduationStability) return true;
    return false;
  }

  /// 2. 获取单词在今日贡献的已完成步骤数
  /// （如果是已掌握单词，直接贡献满格步骤数；否则贡献今日实际学习次数，但不超过该词轨道长度）
  int getCompletedSteps(Set<String> masteredWordIds, int trackLength) {
    assert(trackLength >= 0, 'Track length cannot be negative: $trackLength');
    if (isEffectivelyMastered(masteredWordIds)) {
      return trackLength;
    }
    return todayLearnedTimes > trackLength ? trackLength : todayLearnedTimes;
  }

  /// 3. 判定单词今天是否已经完成了学习
  /// （要么已经是已掌握/已毕业状态，要么今日学习次数已走完该词自身的轨道）
  bool isTodayFinished(Set<String> masteredWordIds, int trackLength) {
    assert(trackLength >= 0, 'Track length cannot be negative: $trackLength');
    return isEffectivelyMastered(masteredWordIds) || todayLearnedTimes >= trackLength;
  }

  /// 4. 判定单词的"今日进度"是否早于本日计划所属的业务日 [planDay]，即往日的残留进度。
  /// todayLearnedTimes 与 lastLearningDate 由 updateCurrWord 同日而写（学习发生在哪一天，今日进度就属于哪一天），
  /// 故进度日早于计划日只可能是昨日残留：本日跨天重置尚未执行，这份进度绝不能被当成今天的成绩
  /// （否则学习页会判定"今日已全部完成"，直接把用户送去打卡页）。
  /// 注意必须是**严格早于**：进度属于更晚的业务日（多设备/时区差异）时绝不能当作残留清零，
  /// 那会把别的设备今天的进度倒扣掉。
  bool hasTodayProgressBefore(DateTime planDay) {
    if (todayLearnedTimes <= 0) return false;
    if (lastLearningDate == null) return true;
    return DateUtils.businessDate(lastLearningDate!).isBefore(DateUtils.businessDate(planDay));
  }
}
