import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/utils.dart';

/// 汉译英题目区的挖空例句：把例句里的当前单词换成等长下划线。
/// 挖不到当前单词时必须返回 null —— 宁可不给提示，也不能把答案拼写露出来。
void main() {
  String blanks(int count) => ''.padRight(count, '_');

  group('maskWordInSentence 挖空例句', () {
    test('原形：等长下划线替换，标点与空格原样保留', () {
      expect(Util.maskWordInSentence('They abandon the plan.', 'abandon'),
          'They ${blanks(7)} the plan.');
      expect(Util.maskWordInSentence('Abandon it!', 'abandon'),
          '${blanks(7)} it!');
    });

    test('词形变化（第三人称、过去式、现在分词）同样挖空', () {
      expect(Util.maskWordInSentence('She abandons it.', 'abandon'),
          'She ${blanks(8)} it.');
      expect(Util.maskWordInSentence('He abandoned it.', 'abandon'),
          'He ${blanks(9)} it.');
      expect(Util.maskWordInSentence('They are abandoning it.', 'abandon'),
          'They are ${blanks(10)} it.');
    });

    test('去掉例句里的加粗标签后再挖空', () {
      expect(Util.maskWordInSentence('They <b>abandon</b> the plan.', 'abandon'),
          'They ${blanks(7)} the plan.');
    });

    test('英文逗号紧贴单词时不留多余空格', () {
      expect(Util.maskWordInSentence('If they abandon, we leave.', 'abandon'),
          'If they ${blanks(7)}, we leave.');
    });

    test('例句里没有该词（短语、无关词）时返回 null', () {
      expect(Util.maskWordInSentence('They gave up the plan.', 'abandon'),
          isNull);
      expect(Util.maskWordInSentence('They gave up the plan.', 'give up'),
          isNull);
    });
  });
}
