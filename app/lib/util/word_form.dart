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
