import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/utils.dart';

void main() {
  group('Util.purifySpell', () {
    test('去掉单词结尾的标点、引号与括号', () {
      expect(Util.purifySpell('apple,'), 'apple');
      expect(Util.purifySpell('apple.'), 'apple');
      expect(Util.purifySpell('apple?'), 'apple');
      expect(Util.purifySpell('apple"'), 'apple');
      expect(Util.purifySpell("apple'"), 'apple');
      expect(Util.purifySpell('apple)'), 'apple');
      expect(Util.purifySpell('apple:'), 'apple');
      expect(Util.purifySpell('apple!'), 'apple');
      expect(Util.purifySpell('apple;'), 'apple');
      expect(Util.purifySpell('apple，'), 'apple');
      expect(Util.purifySpell('apple。'), 'apple');
    });

    test('去掉单词开头的引号与括号', () {
      expect(Util.purifySpell('"apple'), 'apple');
      expect(Util.purifySpell("'apple"), 'apple');
      expect(Util.purifySpell('(apple'), 'apple');
      expect(Util.purifySpell('“apple”'), 'apple');
    });

    test('没有标点时原样返回，短语保持原样', () {
      expect(Util.purifySpell('apple'), 'apple');
      expect(Util.purifySpell('take off,'), 'take off,');
      expect(Util.purifySpell(''), '');
      expect(Util.purifySpell('   '), '');
    });

    test('只由标点组成的输入返回空串而不是抛异常', () {
      expect(Util.purifySpell(',,,'), '');
      expect(Util.purifySpell('()'), '');
    });
  });
}
