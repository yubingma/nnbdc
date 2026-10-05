import 'package:drift/drift.dart';

/// 查词「拼写归一化」：忽略拼写里的分隔符，让 highpowered / high powered 也能命中
/// 词典里的 high-powered。
///
/// 归一化分两侧，两侧共用同一份 [separators] 清单：
///  - 用户输入的归一化在 Dart 侧完成（[normalize]）；
///  - 词条的归一化在 SQL 侧完成（[normalized]），可直接写进查询条件。
class SpellNormalize {
  const SpellNormalize._();

  /// 归一化时忽略的分隔符：空白与词典 spell 里出现过的各种标点。
  ///
  /// 刻意只收这些高频分隔符、而不是“所有非字母数字”：SQL 侧的归一化是一串嵌套的
  /// `replace()`，而 SQLite 的语法分析器对表达式嵌套深度有上限（几十层就会
  /// parser stack overflow），清单必须保持精简。词典里剩下不到百条的冷门标点
  /// （`= ; …` 等）不参与归一化，用户按原样输入仍能字面命中。
  static const List<String> separators = [
    ' ', '.', '-', "'", '/', '(', ')', ',', '?', '!', '\u2019', '\u00A0',
  ];

  /// 归一化用户输入：统一小写并去掉所有分隔符
  static String normalize(String spell) {
    var normalized = spell.toLowerCase();
    for (final separator in separators) {
      normalized = normalized.replaceAll(separator, '');
    }
    return normalized;
  }

  /// SQL 侧的等价归一化：LOWER + 逐个 replace 掉分隔符
  static Expression<String> normalized(Expression<String> spell) {
    Expression<String> expression = spell.lower();
    for (final separator in separators) {
      expression = FunctionCallExpression<String>(
        'replace',
        [expression, Constant(separator), const Constant('')],
      );
    }
    return expression;
  }

  /// 「忽略分隔符后与 [spell] 同前缀（含相等）」的查询条件。
  static Expression<bool> prefixCondition(
    Expression<String> column,
    String spell,
  ) =>
      _condition(column, normalize(spell), prefix: true);

  /// 「忽略分隔符后与 [spell] 完全相等」的查询条件（精确查词的兜底档）。
  static Expression<bool> equalityCondition(
    Expression<String> column,
    String spell,
  ) =>
      _condition(column, normalize(spell), prefix: false);

  /// 归一化值只能逐词算出来，直接对 words 全表跑 replace 太慢，因此先用首字符圈出候选集
  /// 走 idx_words_spell 索引：归一化只删分隔符、不改变字符顺序，词条的首个非分隔符必然
  /// 等于查询的首字符，所以候选集是完备的——首字符不是字母的词条（"(be) at stake"、
  /// "-stricken"、"7-Eleven" 等）由非字母区间兜住。
  static Expression<bool> _condition(
    Expression<String> column,
    String normalizedSpell, {
    required bool prefix,
  }) {
    if (normalizedSpell.isEmpty) {
      return const Constant<bool>(false);
    }

    final candidates = <Expression<bool>>[
      column.isSmallerThanValue('A'),
      column.isBiggerThanValue('Z') & column.isSmallerThanValue('a'),
      column.isBiggerThanValue('z'),
    ];

    final first = normalizedSpell[0];
    for (final char in {first.toLowerCase(), first.toUpperCase()}) {
      final code = char.codeUnitAt(0);
      // 非 ASCII 首字符落在外层 `spell > 'z'` 区间里
      if (code >= 0x80) continue;
      candidates.add(column.isBiggerOrEqualValue(char) &
          column.isSmallerThanValue(String.fromCharCode(code + 1)));
    }

    final normalizedColumn = normalized(column);
    final matches = prefix
        ? normalizedColumn.like('$normalizedSpell%')
        : normalizedColumn.equals(normalizedSpell);

    return candidates.reduce((a, b) => a | b) & matches;
  }
}
