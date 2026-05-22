import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/constants.dart';

/// LearningWord 实体类的扩展方法，封装全部关于已掌握和进度判定细节的逻辑推导。
extension LearningWordProgressExtension on LearningWord {
  /// 1. 判定单词是否已经有效掌握 / 已毕业
  bool isEffectivelyMastered(Set<String> masteredWordIds) {
    if (masteredWordIds.contains(wordId)) return true;
    if (stability != null && stability! >= Constants.graduationStability) return true;
    return false;
  }

  /// 2. 获取单词在今日贡献的已完成步骤数
  /// （如果是已掌握单词，直接贡献满格步骤数；否则贡献今日实际学习次数，但不超过最大步骤数）
  int getCompletedSteps(Set<String> masteredWordIds, int activeStepsCount) {
    assert(activeStepsCount >= 0, 'Active steps count cannot be negative: $activeStepsCount');
    if (isEffectivelyMastered(masteredWordIds)) {
      return activeStepsCount;
    }
    return todayLearnedTimes > activeStepsCount ? activeStepsCount : todayLearnedTimes;
  }

  /// 3. 判定单词今天是否已经完成了学习
  /// （要么已经是已掌握/已毕业状态，要么今日学习次数已达到或超过本模式规定的步骤数）
  bool isTodayFinished(Set<String> masteredWordIds, int activeStepsCount) {
    assert(activeStepsCount >= 0, 'Active steps count cannot be negative: $activeStepsCount');
    return isEffectivelyMastered(masteredWordIds) || todayLearnedTimes >= activeStepsCount;
  }
}
