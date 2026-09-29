import 'dart:math';
import '../api/enum.dart';

/// FSRS-5 (Free Spaced Repetition Scheduler) 算法实现
///
/// 规范: https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm
/// 参考实现: https://github.com/open-spaced-repetition/py-fsrs (v4.x = FSRS-5)
/// 权重与公式逐项对齐官方默认参数，黄金向量见 test/fsrs_test.dart。
class FSRS {
  /// FSRS-5 默认权重 (w0..w18，共 19 个参数)
  static const List<double> defaultWeights = [
    0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
    0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621
  ];

  /// 遗忘曲线 R(t,S) = (1 + FACTOR * t / S)^DECAY
  /// 固定 DECAY = -0.5、FACTOR = 0.9^(1/DECAY) - 1 = 19/81，保证 R(S,S) = 0.9
  static const double _decay = -0.5;
  static const double _factor = 19 / 81;

  /// 稳定性下限：保证 stability 恒为正（既有断言与间隔计算的前提）
  static const double _minStability = 0.1;

  /// 目标保留率 (Request Retention)
  final double requestRetention;

  /// 权重参数
  final List<double> w;

  FSRS({this.requestRetention = 0.9, this.w = defaultWeights})
      : assert(w.length >= 19, 'FSRS-5 需要 19 个权重参数(w0..w18)');

  /// 首次评分（新词 → Learning/Review）
  /// @param rating FsrsRating.again, FsrsRating.hard, FsrsRating.good, FsrsRating.easy
  /// @param nextState 学习步骤全部完成后由调用方指定（默认 learning：
  ///   若该评分已是当天最后一个评分环节，调用方应传 review/relearning，
  ///   避免学完的词次日被"学一半"判定误抓）
  FSRSItem init(FsrsRating rating, {FsrsState nextState = FsrsState.learning}) {
    final double stability = max(w[rating.value - 1], _minStability);

    return FSRSItem(
      stability: stability,
      difficulty: _initialDifficulty(rating),
      elapsedDays: 0,
      scheduledDays: _calculateInterval(stability),
      reps: 1,
      lapses: (rating == FsrsRating.again) ? 1 : 0,
      state: nextState,
    );
  }

  /// 记忆状态更新
  /// @param lastItem 当前单词的状态
  /// @param rating FsrsRating.again, FsrsRating.hard, FsrsRating.good, FsrsRating.easy
  /// @param elapsedDays 自上次评分以来经过的天数：
  ///   0 表示当天重复评分（FSRS-5 短期记忆公式，S 按评分等比缩放）；
  ///   ≥ 1 表示跨天复习信号（长期记忆公式，以可提取性 R(t,S) 为输入）。
  /// @param nextState 缺省由评分推断：again → relearning，其余 → review
  FSRSItem next(FSRSItem lastItem, FsrsRating rating, int elapsedDays,
      {FsrsState? nextState}) {
    // 根因定位辅助断言
    assert(lastItem.stability > 0 && lastItem.stability.isFinite, 'FSRS next: 输入的 stability 异常: ${lastItem.stability}');
    assert(lastItem.difficulty >= 1 && lastItem.difficulty <= 10 && lastItem.difficulty.isFinite, 'FSRS next: 输入的 difficulty 异常: ${lastItem.difficulty}');
    assert(elapsedDays >= 0, 'FSRS next: elapsedDays 不能为负数: $elapsedDays');

    double s = lastItem.stability;
    double d = lastItem.difficulty;

    double nextS = elapsedDays < 1
        ? _shortTermStability(s, rating)
        : _nextStability(s, d, _retrievability(s, elapsedDays), rating);

    // 稳定性下限保护
    nextS = max(nextS, _minStability);

    return FSRSItem(
      stability: nextS,
      difficulty: _nextDifficulty(d, rating),
      elapsedDays: elapsedDays,
      scheduledDays: _calculateInterval(nextS),
      reps: lastItem.reps + 1,
      lapses: (rating == FsrsRating.again) ? lastItem.lapses + 1 : lastItem.lapses,
      state: nextState ??
          ((rating == FsrsRating.again) ? FsrsState.relearning : FsrsState.review),
    );
  }

  /// 长期记忆稳定性：按评分分流为遗忘 / 记忆两条分支
  double _nextStability(double s, double d, double r, FsrsRating rating) =>
      (rating == FsrsRating.again)
          ? _forgetStability(s, d, r)
          : _recallStability(s, d, r, rating);

  /// 遗忘后稳定性 S'_f = w11 * D^-w12 * ((S+1)^w13 - 1) * e^(w14*(1-R))
  /// 并以短期上限 S / e^(w17*w18) 封顶：一次遗忘不应比"当天连续答错"保留更多稳定性
  double _forgetStability(double s, double d, double r) {
    final double longTerm =
        w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14]);
    return min(longTerm, s / exp(w[17] * w[18]));
  }

  /// 记忆后稳定性 S'_r = S * (1 + e^w8 * (11-D) * S^-w9 * (e^((1-R)*w10) - 1) * 硬性惩罚 * 简单奖励)
  double _recallStability(double s, double d, double r, FsrsRating rating) {
    final double hardPenalty = (rating == FsrsRating.hard) ? w[15] : 1.0;
    final double easyBonus = (rating == FsrsRating.easy) ? w[16] : 1.0;

    return s *
        (1 +
            exp(w[8]) *
                (11 - d) *
                pow(s, -w[9]) *
                (exp((1 - r) * w[10]) - 1) *
                hardPenalty *
                easyBonus);
  }

  /// 当天重复评分（FSRS-5 新增）S' = S * e^(w17 * (G - 3 + w18))
  /// G=3 与 G=4 稳定上升、G=1 与 G=2 稳定下降，取代了旧版"重设回初始稳定性"的做法
  double _shortTermStability(double s, FsrsRating rating) =>
      s * exp(w[17] * (rating.value - 3 + w[18]));

  /// 难度更新（FSRS-5）：线性阻尼 ΔD*(10-D)/9，再向 D0(4) 均值回归，系数 w7
  double _nextDifficulty(double d, FsrsRating rating) {
    final double delta = -w[6] * (rating.value - 3);
    final double damped = d + (10 - d) * delta / 9;
    final double meanReversion =
        w[7] * _initialDifficulty(FsrsRating.easy) + (1 - w[7]) * damped;
    return meanReversion.clamp(1.0, 10.0);
  }

  /// 首次评分难度（FSRS-5）D0(G) = w4 - e^(w5*(G-1)) + 1，w4 即 D0(1)
  double _initialDifficulty(FsrsRating rating) =>
      (w[4] - exp(w[5] * (rating.value - 1)) + 1).clamp(1.0, 10.0);

  /// 可提取性 R(t,S) = (1 + FACTOR * t / S)^DECAY
  double _retrievability(double s, int elapsedDays) =>
      pow(1 + _factor * elapsedDays / s, _decay).toDouble();

  /// 下次复习间隔：反解 R(t,S) = requestRetention
  int _calculateInterval(double stability) {
    assert(stability.isFinite && stability > 0, 'FSRS _calculateInterval: stability 异常: $stability');
    assert(requestRetention > 0 && requestRetention < 1, 'FSRS: requestRetention 必须在 (0, 1) 之间');

    double interval = stability / _factor * (pow(requestRetention, 1 / _decay) - 1);
    return max(1, interval.round());
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
