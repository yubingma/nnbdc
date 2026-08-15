import 'dart:math';
import '../api/enum.dart';

/// FSRS (Free Spaced Repetition Scheduler) 算法实现 (v4.5)
/// 核心逻辑参考: https://github.com/open-spaced-repetition/fsrs4anki
class FSRS {
  /// 默认权重参数 (w)
  static const List<double> defaultWeights = [
    0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61
  ];

  /// 目标保留率 (Request Retention)
  final double requestRetention;

  /// 权重参数
  final List<double> w;

  FSRS({this.requestRetention = 0.9, this.w = defaultWeights});

  /// 初始状态转换 (New -> Learning/Review)
  /// @param rating FsrsRating.again, FsrsRating.hard, FsrsRating.good, FsrsRating.easy
  /// @param nextState 学习步骤全部完成后由调用方指定（默认 learning：
  ///   若该评分已是当天最后一个评分环节，调用方应传 review/relearning，
  ///   避免学完的词次日被"学一半"判定误抓）
  FSRSItem init(FsrsRating rating, {FsrsState nextState = FsrsState.learning}) {
    int ratingValue = rating.value;
    
    double stability = w[ratingValue - 1];
    double difficulty = w[4] - (ratingValue - 1) * w[5];
    difficulty = difficulty.clamp(1.0, 10.0);

    return FSRSItem(
      stability: stability,
      difficulty: difficulty,
      elapsedDays: 0,
      scheduledDays: _calculateInterval(stability),
      reps: 1,
      lapses: (rating == FsrsRating.again) ? 1 : 0,
      state: nextState,
    );
  }

  /// 复习状态转换
  /// @param lastItem 当前单词的状态
  /// @param rating FsrsRating.again, FsrsRating.hard, FsrsRating.good, FsrsRating.easy
  /// @param elapsedDays 自上次复习以来经过的天数
  FSRSItem next(FSRSItem lastItem, FsrsRating rating, int elapsedDays) {
    // 根因定位辅助断言
    assert(lastItem.stability > 0 && lastItem.stability.isFinite, 'FSRS next: 输入的 stability 异常: ${lastItem.stability}');
    assert(lastItem.difficulty >= 1 && lastItem.difficulty <= 10 && lastItem.difficulty.isFinite, 'FSRS next: 输入的 difficulty 异常: ${lastItem.difficulty}');
    assert(elapsedDays >= 0, 'FSRS next: elapsedDays 不能为负数: $elapsedDays');

    double s = lastItem.stability;
    double d = lastItem.difficulty;
    double r = pow(0.9, elapsedDays / s).toDouble(); // Retrievability

    // 更新难度
    double nextD = d - w[6] * (rating.value - 3);
    nextD = _meanReversion(w[4], nextD);
    nextD = nextD.clamp(1.0, 10.0);

    // 更新稳定性
    double nextS;
    if (rating == FsrsRating.again) {
      // 遗忘
      nextS = w[7] * pow(nextD, -w[8]) * (pow(s + 1, w[9]) - 1) * exp(w[10] * (1 - r));
    } else {
      // 记忆（FSRS-4.5 原版公式：与遗忘分支共用 w[8]/w[9]/w[10] 三元组，
      // 此前误用 w[11]/w[12]/w[13]（FSRS-5 索引位置），与 4.5 默认权重不匹配）
      double hardPenalty = (rating == FsrsRating.hard) ? w[15] : 1.0;
      double easyBonus = (rating == FsrsRating.easy) ? w[16] : 1.0;
      nextS = s * (1 + exp(w[8]) * (11 - nextD) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus);
    }
    
    // 稳定性下限保护
    nextS = max(nextS, 0.1);

    return FSRSItem(
      stability: nextS,
      difficulty: nextD,
      elapsedDays: elapsedDays,
      scheduledDays: _calculateInterval(nextS),
      reps: lastItem.reps + 1,
      lapses: (rating == FsrsRating.again) ? lastItem.lapses + 1 : lastItem.lapses,
      state: (rating == FsrsRating.again) ? FsrsState.relearning : FsrsState.review,
    );
  }

  /// 学习/恢复事件：当天同一词的非首次评分（学习轨道巩固环节、复习轨道恢复环节）
  ///
  /// FSRS 学习步骤语义：直接重设稳定性与难度（可升可降，最后一次评分决定当天结果），
  /// 与复习公式 [next]（每天一次的复习信号）严格区分。
  FSRSItem relearn(FSRSItem last, FsrsRating rating, {required FsrsState nextState}) {
    int ratingValue = rating.value;

    double stability = w[ratingValue - 1];
    double difficulty = (w[4] - (ratingValue - 1) * w[5]).clamp(1.0, 10.0);

    return FSRSItem(
      stability: stability,
      difficulty: difficulty,
      elapsedDays: 0,
      scheduledDays: _calculateInterval(stability),
      reps: last.reps + 1,
      lapses: (rating == FsrsRating.again) ? last.lapses + 1 : last.lapses,
      state: nextState,
    );
  }

  int _calculateInterval(double stability) {
    assert(stability.isFinite, 'FSRS _calculateInterval: stability 为无穷大或 NaN');
    assert(requestRetention > 0 && requestRetention < 1, 'FSRS: requestRetention 必须在 (0, 1) 之间');
    
    // interval = S * (ln(retention) / ln(0.9))
    // 对于默认 retention=0.9, interval = S
    double interval = stability * (log(requestRetention) / log(0.9));
    return max(1, interval.round());
  }

  double _meanReversion(double init, double current) {
    return 0.05 * init + 0.95 * current;
  }
}

/// FSRS 算法计算结果数据结构
class FSRSItem {
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays;
  final int reps;
  final int lapses;
  final FsrsState state;

  FSRSItem({
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.reps,
    required this.lapses,
    required this.state,
  });

  factory FSRSItem.fromMap(Map<String, dynamic> map) {
    return FSRSItem(
      stability: (map['stability'] as num).toDouble(),
      difficulty: (map['difficulty'] as num).toDouble(),
      elapsedDays: (map['elapsedDays'] as num).toInt(),
      scheduledDays: (map['scheduledDays'] as num).toInt(),
      reps: (map['reps'] as num).toInt(),
      lapses: (map['lapses'] as num).toInt(),
      state: FsrsStateExt.fromInt(map['state'] as int?),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stability': stability,
      'difficulty': difficulty,
      'elapsedDays': elapsedDays,
      'scheduledDays': scheduledDays,
      'reps': reps,
      'lapses': lapses,
      'state': state.value,
    };
  }
}
