import 'dart:math';

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
  /// @param rating 1: Again, 2: Hard, 3: Good, 4: Easy
  FSRSItem init(int rating) {
    double stability = w[rating - 1];
    double difficulty = w[4] - (rating - 1) * w[5];
    difficulty = difficulty.clamp(1.0, 10.0);

    return FSRSItem(
      stability: stability,
      difficulty: difficulty,
      elapsedDays: 0,
      scheduledDays: _calculateInterval(stability),
      reps: 1,
      lapses: (rating == 1) ? 1 : 0,
      state: 1, // Learning
    );
  }

  /// 复习状态转换
  /// @param lastItem 当前单词的状态
  /// @param rating 1: Again, 2: Hard, 3: Good, 4: Easy
  /// @param elapsedDays 自上次复习以来经过的天数
  FSRSItem next(FSRSItem lastItem, int rating, int elapsedDays) {
    double s = lastItem.stability;
    double d = lastItem.difficulty;
    double r = pow(0.9, elapsedDays / s).toDouble(); // Retrievability

    // 更新难度
    double nextD = d - w[6] * (rating - 3);
    nextD = _meanReversion(w[4], nextD);
    nextD = nextD.clamp(1.0, 10.0);

    // 更新稳定性
    double nextS;
    if (rating == 1) {
      // 遗忘
      nextS = w[7] * pow(nextD, -w[8]) * (pow(s + 1, w[9]) - 1) * exp(w[10] * (1 - r));
    } else {
      // 记忆
      double hardPenalty = (rating == 2) ? w[15] : 1.0;
      double easyBonus = (rating == 4) ? w[16] : 1.0;
      nextS = s * (1 + exp(w[11]) * (11 - nextD) * pow(s, -w[12]) * (exp((1 - r) * w[13]) - 1) * hardPenalty * easyBonus);
    }
    
    // 稳定性下限保护
    nextS = max(nextS, 0.1);

    return FSRSItem(
      stability: nextS,
      difficulty: nextD,
      elapsedDays: elapsedDays,
      scheduledDays: _calculateInterval(nextS),
      reps: lastItem.reps + 1,
      lapses: (rating == 1) ? lastItem.lapses + 1 : lastItem.lapses,
      state: (rating == 1) ? 3 : 2, // 3: Relearning, 2: Review
    );
  }

  int _calculateInterval(double stability) {
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
  final int state;

  FSRSItem({
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.reps,
    required this.lapses,
    required this.state,
  });
}
