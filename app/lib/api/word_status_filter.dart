/// 词表学习状态三态（未学习 / 学习中 / 已掌握）。
///
/// 判定口径唯一来源是 [WordBo.getWordsLearningStatusBatch]：
/// 在「已掌握」词书内 → mastered；否则有学习记录且未毕业 → learning；其余 → unlearned。
enum WordLearningStatus {
  /// 未学习：词书收录，但用户还没有学习记录
  unlearned,

  /// 学习中：已取词且尚未掌握
  learning,

  /// 已掌握：在用户的「已掌握」词书内
  mastered;

  /// 持久化编码（与展示文案分离，便于文案调整不影响已存数据）
  String get code {
    switch (this) {
      case WordLearningStatus.unlearned:
        return 'UNLEARNED';
      case WordLearningStatus.learning:
        return 'LEARNING';
      case WordLearningStatus.mastered:
        return 'MASTERED';
    }
  }

  String get label {
    switch (this) {
      case WordLearningStatus.unlearned:
        return '未学习';
      case WordLearningStatus.learning:
        return '学习中';
      case WordLearningStatus.mastered:
        return '已掌握';
    }
  }

  static WordLearningStatus? fromCode(String code) {
    for (final status in WordLearningStatus.values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// 词表学习状态筛选：三态多选，默认全选（= 不裁剪任何单词，与历史行为完全一致）。
class WordStatusFilter {
  final Set<WordLearningStatus> statuses;

  const WordStatusFilter._(this.statuses);

  /// 全选（默认态）
  static const WordStatusFilter all = WordStatusFilter._({
    WordLearningStatus.unlearned,
    WordLearningStatus.learning,
    WordLearningStatus.mastered,
  });

  bool get isAll => statuses.length == WordLearningStatus.values.length;

  bool contains(WordLearningStatus status) => statuses.contains(status);

  /// 切换某一态的勾选；取消最后一项时自动回落到全选（避免把用户关进空列表）
  WordStatusFilter toggle(WordLearningStatus status) {
    final next = Set<WordLearningStatus>.from(statuses);
    if (!next.remove(status)) {
      next.add(status);
    }
    return next.isEmpty ? all : WordStatusFilter._(next);
  }

  /// 该学习状态（null=未学习, false=学习中, true=已掌握）在当前筛选下是否可见
  bool allows(bool? learningStatus) {
    final status = learningStatus == true
        ? WordLearningStatus.mastered
        : learningStatus == false
            ? WordLearningStatus.learning
            : WordLearningStatus.unlearned;
    return contains(status);
  }

  /// 持久化编码（按固定顺序拼接，保证同一选择编码稳定）
  String get code =>
      WordLearningStatus.values.where(statuses.contains).map((s) => s.code).join(',');

  /// 从持久化编码还原；null / 空 / 无法识别一律回落到全选（默认态，而非错误态）
  factory WordStatusFilter.fromCode(String? code) {
    if (code == null || code.trim().isEmpty) return all;
    final parsed = code
        .split(',')
        .map(WordLearningStatus.fromCode)
        .whereType<WordLearningStatus>()
        .toSet();
    return parsed.isEmpty ? all : WordStatusFilter._(parsed);
  }

  /// 菜单与弹窗摘要：全选=全部，单项=该项名，多项用「+」连接
  String get label {
    if (isAll) return '全部';
    return WordLearningStatus.values
        .where(statuses.contains)
        .map((s) => s.label)
        .join('+');
  }

  /// 仅选中单一状态时返回该状态（用于空态文案），否则返回 null
  WordLearningStatus? get singleStatus => statuses.length == 1 ? statuses.first : null;

  @override
  bool operator ==(Object other) =>
      other is WordStatusFilter &&
      other.statuses.length == statuses.length &&
      other.statuses.containsAll(statuses);

  @override
  int get hashCode => Object.hashAllUnordered(statuses);

  @override
  String toString() => 'WordStatusFilter($label)';
}

/// 词书三态数量（总数 = 未学习 + 学习中 + 已掌握）
class WordStatusCounts {
  final int unlearned;
  final int learning;
  final int mastered;

  const WordStatusCounts({
    required this.unlearned,
    required this.learning,
    required this.mastered,
  });

  int get total => unlearned + learning + mastered;

  int countOf(WordLearningStatus status) {
    switch (status) {
      case WordLearningStatus.unlearned:
        return unlearned;
      case WordLearningStatus.learning:
        return learning;
      case WordLearningStatus.mastered:
        return mastered;
    }
  }

  @override
  String toString() =>
      'WordStatusCounts(未学习: $unlearned, 学习中: $learning, 已掌握: $mastered)';
}
