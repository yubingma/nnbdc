import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/word_list/word_list.dart';

void main() {
  group('WordListPage Menu Constants', () {
    test('menuWordList constant is 浏览模式', () {
      expect(menuWordList, equals('浏览模式'));
    });

    test('menuHideChinese constant is 遮挡中文', () {
      expect(menuHideChinese, equals('遮挡中文'));
    });

    test('menuHideEnglish constant is 遮挡英文', () {
      expect(menuHideEnglish, equals('遮挡英文'));
    });
  });
}
