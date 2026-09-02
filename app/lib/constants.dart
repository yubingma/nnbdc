/// 应用全局常量定义
class Constants {
  // ========== 界面元素透明度全局配置 (方便随时微调通透质感) ==========

  /// 界面通用元素（矩形卡片框、常规按钮等）的基础不透明度 (0.0 完全透明 - 1.0 完全不透明)
  /// 主流微透毛玻璃质感建议 0.80 - 0.88，既能轻盈透出底层流光，又能保证文字阅读的扎实可读性
  static const double uiElementOpacity = 0.85;

  /// 界面矩形卡片框（题目区卡片、做题区卡片、例句框等）的背景不透明度 (0.0 - 1.0)
  static const double cardOpacity = 0.85;

  /// 次级容器与轻量元素（如输入框、辅助练习卡片、轻底色容器等）的背景不透明度 (0.0 - 1.0)
  static const double subtleOpacity = 0.65;

  /// 按钮背景不透明度（如“不认识”、“再学学”等操作按钮）
  static const double buttonOpacity = 0.85;

  /// 主色高亮按钮（如“下一个”等主行动按钮）的背景不透明度
  static const double primaryButtonOpacity = 0.92;

  // ========== 音素匹配相关常量 ==========

  /// 音素匹配判定阈值（0-100）
  /// 当音素相似度 >= 此阈值时，认为识别结果与目标词高保真匹配可直接放行，低于此阈值交由 AI 裁判
  static const int phonemeMatchThreshold = 60;

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
