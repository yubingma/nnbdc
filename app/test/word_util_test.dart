import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/word_util.dart';

void main() {
  group('Word Util - Split Meanings', () {
    test('splits meaning by both English and Chinese semicolons', () {
      var parts = splitMeaning2Parts('苹果; 香蕉；橘子');
      expect(parts.length, 3);
      expect(parts[0], '苹果');
      expect(parts[1], ' 香蕉');
      expect(parts[2], '橘子');
    });

    test('ignores empty parts', () {
      var parts = splitMeaning2Parts('苹果;;；香蕉');
      expect(parts.length, 2);
    });
  });

  group('Word Util - Match Input Chinese With Meaning Items', () {
    late WordVo testWord;
    late WordWrapper wrapper;

    setUp(() {
      testWord = WordVo.c2('apple');
      testWord.id = '1';
      testWord.meaningItems = [
        MeaningItemVo.from('n.', '苹果;公司'),
        MeaningItemVo.from('adj.', '（废弃的用法）'), // Bracketed
      ];

      wrapper = WordWrapper(testWord, null);
    });

    test('matches complete correct answer', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '苹果');
      
      expect(result.totalCount, 2); // '苹果', '公司'. The bracketed one is ignored.
      expect(result.newMatchCount, 1);
      expect(result.matchedCount, 1);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 0)), true);
    });

    test('ignores bracketed items entirely', () {
      // Testing the _isWholeBracketed logic within matchInputChineseWithMeaningItems
      var result = matchInputChineseWithMeaningItems(wrapper, '废弃的用法');
      
      // Should not match as bracketed are skipped
      expect(result.newMatchCount, 0);
      expect(wrapper.asrMatchedMeaningItemParts.isEmpty, true);
    });

    test('multiple parts can be matched sequentially', () {
      matchInputChineseWithMeaningItems(wrapper, '苹果');
      expect(wrapper.asrMatchedMeaningItemParts.length, 1);

      var result2 = matchInputChineseWithMeaningItems(wrapper, '公司');
      expect(result2.newMatchCount, 1);
      expect(wrapper.asrMatchedMeaningItemParts.length, 2);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 1)), true);
    });

    test('redundant correct inputs do not increase newMatchCount', () {
      matchInputChineseWithMeaningItems(wrapper, '苹果');
      var result2 = matchInputChineseWithMeaningItems(wrapper, '苹果');
      expect(result2.newMatchCount, 0);
      expect(result2.matchedCount, 1);
    });

    test('handles multiple inputs (ASR candidates)', () {
      // simulate ASR giving multiple fallback candidates
      var result = matchInputChineseWithMeaningItems(wrapper, ['平果', '苹果', '拼过']);
      expect(result.newMatchCount, 1);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 0)), true);
    });
  });
}
