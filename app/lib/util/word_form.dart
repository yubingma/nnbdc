/// 英文单词的屈折变形归并：判断两个拼写是否属于同一个单词的不同形式。
///
/// 只处理屈折后缀及其拼写变体：
/// - 复数 / 第三人称单数：-s、-es、-ies
/// - 过去式 / 过去分词：-ed、-ied
/// - 现在分词：-ing
/// - 副词：-ly、-ily
/// - 比较级 / 最高级：-er、-ier、-est、-iest
/// - 拼写变体：词尾 e 脱落（confuse → confusing）、词尾辅音双写（run → running）、
///   y → i（happy → happily）
///
/// 不做派生后缀（-tion、-ment、-ness、-al 等）归并：confusion、national、reasonable
/// 这类词的释义与词根不同，是有效的干扰项，不应被误并。
/// 也不做「词尾 e 脱落成更短词」的反向归并：hope/hop、thine/thin 是不同单词。
///
/// 判断为"同词变形"时宁可漏判（少排除）也不误判（多排除）——被误排除的词本可
/// 作为干扰项，被漏判的词还有释义重合这道判据兜底。
bool isSameWordForm(String a, String b) {
  final x = a.trim().toLowerCase();
  final y = b.trim().toLowerCase();
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  // 含空格/连字符/标点的是词组或带符号条目（如 "happy birthday!"），只做精确比较
  if (!_isPlainWord(x) || !_isPlainWord(y)) return false;
  return _stems(x).intersection(_stems(y)).isNotEmpty;
}

/// 英文单词的"同一词族"归并：在 [isSameWordForm]（屈折变形）之上，再归并
/// 派生词与英美拼写变体。
///
/// - 拼写变体：-ise/-ize（fertilise → fertilize、organisation → organization）、
///   -yse/-yze（analyse → analyze）；
/// - 派生词：confuse → confusion、nation → national、happy → happiness、
///   organize → organization、danger → dangerous、beauty → beautiful。
///
/// 判据是"剥离派生后缀后的词干相同"，且词干不少于 5 个字母：
/// fertilizer / fertilize / fertilise / fertilization 的词干都是 fertiliz，
/// 因此它们不会出现在同一道题的选项里。
///
/// 阈值取 5 是为了不误并前缀相同而实为两词的组合——liver/live、only/one、
/// hardy/hard、interest/interment 都不算同族：被误并的词本可作干扰项，白白损失。
///
/// 代价是 [isSameWordForm] 的 -er 比较级规则会顺带把"名词 + er"一并归并
/// （corner/corn、flower/flow、mother/moth），方向同样是宁可多排除。
bool isSameWordFamily(String a, String b) {
  final x = a.trim().toLowerCase();
  final y = b.trim().toLowerCase();
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  if (!_isPlainWord(x) || !_isPlainWord(y)) return false;
  if (isSameWordForm(x, y)) return true;
  return _familyStems(x).intersection(_familyStems(y)).isNotEmpty;
}

/// 词干短于该长度不作词族归并（见 [isSameWordFamily]）
const int _minFamilyStemLength = 5;

/// 派生后缀（屈折后缀由 [_stems] 负责）；顺序无关，逐个尝试并迭代剥离
const List<String> _derivationSuffixes = [
  'ation', 'ness', 'ment', 'ance', 'ence', 'able', 'ible', 'ity', 'ive',
  'ous', 'ful', 'less', 'ish', 'ism', 'ist', 'ize', 'ify', 'ion', 'al',
  'ic', 'ly', 'er', 'or', 'ant', 'ent', 'age', 'ary', 'ery',
];

/// 一个单词所有可能的词干（含原词本身与拼写变体），短于阈值的词干不收录
Set<String> _familyStems(String word) {
  final stems = <String>{};
  final pending = <String>[_normalizeSpelling(word)];
  while (pending.isNotEmpty) {
    final w = pending.removeLast();
    if (w.length < _minFamilyStemLength) continue;
    if (!stems.add(w)) continue;

    // happy → happi、nice → nic、running → run
    if (w.endsWith('y')) pending.add('${w.substring(0, w.length - 1)}i');
    if (w.endsWith('e')) pending.add(w.substring(0, w.length - 1));
    pending.add(_unDouble(w));

    // -ize 家族：剥掉派生后缀后残留的 -iz（fertiliz → fertil、organiz → organ）
    if (w.endsWith('iz')) pending.add(w.substring(0, w.length - 2));

    for (final suffix in _derivationSuffixes) {
      if (w.endsWith(suffix)) {
        pending.add(w.substring(0, w.length - suffix.length));
      }
    }
  }
  return stems;
}

/// 英式拼写归一为美式：fertilise → fertilize、organisation → organization
String _normalizeSpelling(String word) {
  if (word.endsWith('ise')) return '${word.substring(0, word.length - 3)}ize';
  if (word.endsWith('yse')) return '${word.substring(0, word.length - 3)}yze';
  return word.replaceAll('isat', 'izat');
}

final RegExp _plainWord = RegExp(r'^[a-z]+$');

bool _isPlainWord(String w) => _plainWord.hasMatch(w);

/// 一个单词所有可能的词干（含原词本身）；词干长度 < 3 时不收录，避免过短词干误配
Set<String> _stems(String word) {
  final stems = <String>{word};
  void add(String stem) {
    if (stem.length >= 3) stems.add(stem);
  }

  // 复数 / 第三人称单数
  if (word.endsWith('ies') && word.length > 4) {
    add('${word.substring(0, word.length - 3)}y');
  }
  if (!word.endsWith('ies') &&
      word.endsWith('es') &&
      (word.endsWith('ses') ||
          word.endsWith('xes') ||
          word.endsWith('zes') ||
          word.endsWith('ches') ||
          word.endsWith('shes') ||
          word.endsWith('oes'))) {
    add(word.substring(0, word.length - 2));
  }
  if (word.endsWith('s') && !word.endsWith('ss')) {
    add(word.substring(0, word.length - 1));
  }

  // 过去式 / 过去分词
  if (word.endsWith('ied') && word.length > 4) {
    add('${word.substring(0, word.length - 3)}y');
  }
  if (word.endsWith('ed') && word.length > 3) {
    final body = word.substring(0, word.length - 2);
    add(body);
    add('${body}e');
    add(_unDouble(body));
  }

  // 现在分词
  if (word.endsWith('ing') && word.length > 4) {
    final body = word.substring(0, word.length - 3);
    add(body);
    add('${body}e');
    add('${body}y');
    add(_unDouble(body));
  }

  // 副词
  if (word.endsWith('ily') && word.length > 4) {
    add('${word.substring(0, word.length - 3)}y');
  }
  if (word.endsWith('ly') && word.length > 3) {
    final body = word.substring(0, word.length - 2);
    add(body);
    // 只在词干足够长时补回词尾 e：only → on 会误配 one
    if (body.length >= 3) add('${body}e');
  }

  // 比较级 / 最高级
  if (word.endsWith('iest') && word.length > 5) {
    add('${word.substring(0, word.length - 4)}y');
  }
  if (word.endsWith('ier') && word.length > 4) {
    add('${word.substring(0, word.length - 3)}y');
  }
  if (word.endsWith('est') && word.length > 4) {
    add(word.substring(0, word.length - 3));
  }
  if (word.endsWith('er') && word.length > 3) {
    add(word.substring(0, word.length - 2));
  }

  return stems;
}

/// 去掉词尾重复的辅音字母（running → run、stopped → stop）
String _unDouble(String body) {
  if (body.length < 3) return body;
  final last = body[body.length - 1];
  if (last == body[body.length - 2] && !'aeiou'.contains(last)) {
    return body.substring(0, body.length - 1);
  }
  return body;
}
