enum WordSortAlg {
  /// 默认序（词书的原始顺序）
  original('ORIGINAL', '原始序'),

  /// 乱序（单词拼写 MD5）
  random('RANDOM', '乱序'),

  /// 字母序
  alphabetical('ALPHABETICAL', '字母序'),

  /// 单元序
  unit('UNIT', '单元序'),

  /// 语境序（基于单词 3D 向量）
  semantic('SEMANTIC', '语境序');

  final String code;
  final String label;

  const WordSortAlg(this.code, this.label);

  static WordSortAlg fromCode(String? code) {
    return WordSortAlg.values.firstWhere(
      (e) => e.code == code,
      orElse: () => WordSortAlg.original, // 默认排序规则
    );
  }
}
