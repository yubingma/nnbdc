/// 应用全局常量定义
class Constants {
  // ========== 音素匹配相关常量 ==========

  /// 音素匹配判定阈值（0-100）
  /// 当音素相似度 >= 此阈值时，认为识别结果与目标词高保真匹配可直接放行，低于此阈值交由 AI 裁判
  static const int phonemeMatchThreshold = 80;

  // ========== 编辑距离相关常量 ==========

  /// 编辑距离容错率（0.0-1.0）
  /// 当编辑距离 <= maxLength * 此比例时，认为匹配成功
  /// 例如：0.3 表示允许 30% 的字符差异
  static const double editDistanceTolerance = 0.3;

  // ========== 拼写相似度计算相关常量 ==========

  /// 拼写相似度匹配阈值（0-100）
  /// 当拼写相似度 >= 此阈值时，认为候选词匹配目标词
  static const int spellingMatchThreshold = 70;

  /// 编辑距离在拼写相似度中的权重（0.0-1.0）
  static const double spellingEditDistanceWeight = 0.7;

  /// 重叠度在拼写相似度中的权重（0.0-1.0）
  static const double spellingOverlapWeight = 0.3;

  // ========== FSRS 相关常量 ==========

  /// 稳定性毕业阈值 (天)
  /// 当稳定性达到此数值时，认为单词已掌握，移出学习中库
  static const double graduationStability = 180.0;
}
