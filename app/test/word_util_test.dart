import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/utils.dart';
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

  group('Chinese Dictation Matching (手写中文默写：判题算法与语音一致，但要求写全释义)', () {
    late WordVo testWord;
    late WordWrapper wrapper;

    setUp(() {
      testWord = WordVo.c2('businesswoman');
      testWord.id = '1';
      testWord.meaningItems = [
        MeaningItemVo.from('n.', '女商人'),
      ];
      wrapper = WordWrapper(testWord, null);
    });

    test('rejects partial single-char answer (女 for 女商人)', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '女', strict: true);
      expect(result.newMatchCount, 0);
      expect(wrapper.asrMatchedMeaningItemParts.isEmpty, true);
    });

    test('rejects truncated substring answer (商人 for 女商人)', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '商人', strict: true);
      expect(result.newMatchCount, 0);
      expect(wrapper.asrMatchedMeaningItemParts.isEmpty, true);
    });

    test('accepts exact full answer (女商人)', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '女商人', strict: true);
      expect(result.newMatchCount, 1);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 0)), true);
    });

    test('accepts answer carrying user wording (我女商人)', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '我女商人', strict: true);
      expect(result.newMatchCount, 1);
    });

    test('rejects truncated answer when meaning has comma-synonyms', () {
      final w = WordVo.c2('businesswomen')..id = '2';
      w.meaningItems = [
        MeaningItemVo.from('n.', '女商人，商界女性'),
      ];
      final wr = WordWrapper(w, null);
      // 只写其中一个同义词的一部分，没把该同义词写全，不通过
      var result = matchInputChineseWithMeaningItems(wr, '女性', strict: true);
      expect(result.newMatchCount, 0);
    });

    test('accepts full-length answer with a homophone misread (女商仁 for 女商人)', () {
      // 手写识别可能把个别字误识成同音/形近字，应容忍这类小出入
      var result = matchInputChineseWithMeaningItems(wrapper, '女商仁', strict: true);
      expect(result.newMatchCount, 1);
    });

    test('rejects a genuinely wrong answer (男子人 for 女商人)', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '男子人', strict: true);
      expect(result.newMatchCount, 0);
    });
  });

  group('Chinese Dictation Matching - 连续写出多个释义', () {
    late WordVo testWord;
    late WordWrapper wrapper;

    setUp(() {
      // view: 查看;考虑;观察
      testWord = WordVo.c2('view');
      testWord.id = '1';
      testWord.meaningItems = [
        MeaningItemVo.from('v.', '查看;考虑;观察'),
      ];
      wrapper = WordWrapper(testWord, null);
    });

    test('一次性连续写出全部释义应全部匹配', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '查看考虑观察', strict: true);
      expect(result.totalCount, 3);
      expect(result.matchedCount, 3);
      expect(result.newMatchCount, 3);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 0)), true);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 1)), true);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 2)), true);
    });

    test('只写其中一个释义仍只匹配该释义', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '查看', strict: true);
      expect(result.matchedCount, 1);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 0)), true);
    });

    test('写释义时带上自己的话（我查看）同样算写对', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '我查看', strict: true);
      expect(result.matchedCount, 1);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 0)), true);
    });

    test('连续写出部分释义只匹配对应部分', () {
      var result = matchInputChineseWithMeaningItems(wrapper, '查看考虑', strict: true);
      expect(result.matchedCount, 2);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 2)), false);
    });

    test('连续写出全部释义时允许个别同音字误识', () {
      // 手写识别把"虑"误识成同音的"滤"
      var result = matchInputChineseWithMeaningItems(wrapper, '查看考滤观察', strict: true);
      expect(result.matchedCount, 3);
    });

    test('连续写出但含错误释义时不匹配错误项', () {
      final result =
          matchInputChineseWithMeaningItems(wrapper, '查看思考观察', strict: true);
      expect(result.matchedCount, 2, reason: '只有"查看"和"观察"写对');
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 1)), false);
    });
  });

  group('WordWrapper Equality and Deduplication', () {
    test('wrappers with same word id are equal regardless of UI answering state', () {
      final w1 = WordVo.c2('journal')..id = 'w_123';
      final wrapper1 = WordWrapper(w1, null);
      // wrapper1 用户已经答对并高亮了释义
      wrapper1.asrMatchedMeaningItemParts.add(Pair(0, 0));
      wrapper1.asrRevealedMeaningItemParts.add(Pair(0, 1));

      // wrapper2 是从数据库新查出的相同单词对象，未答状态
      final w2 = WordVo.c2('journal')..id = 'w_123';
      final wrapper2 = WordWrapper(w2, null);

      expect(wrapper1 == wrapper2, true);
      expect(wrapper1.hashCode, wrapper2.hashCode);

      final list = [wrapper1];
      // 核心防重判定：list 必须能正确识别 wrapper2 已存在
      expect(list.contains(wrapper2), true);
    });

    test('wrappers with different ids are not equal', () {
      final w1 = WordVo.c2('journal')..id = 'w_1';
      final w2 = WordVo.c2('mechanism')..id = 'w_2';
      expect(WordWrapper(w1, null) == WordWrapper(w2, null), false);
    });

    test('fallback to spell comparison when id is null', () {
      final w1 = WordVo.c2('apple');
      final w2 = WordVo.c2('apple');
      final w3 = WordVo.c2('banana');
      expect(WordWrapper(w1, null) == WordWrapper(w2, null), true);
      expect(WordWrapper(w1, null) == WordWrapper(w3, null), false);
    });
  });

  group('词性规范化（历史脏数据 "v.，" → "v."）', () {
    test('normalizeCiXing 剥离尾部标点', () {
      expect(MeaningItemVo.normalizeCiXing('v.，'), 'v.');
      expect(MeaningItemVo.normalizeCiXing(' n.， '), 'n.');
      expect(MeaningItemVo.normalizeCiXing('phr. v.'), 'phr. v.');
      expect(MeaningItemVo.normalizeCiXing(null), '');
    });

    test('getMergedMeaningItems 归并同一词性且词性干净', () {
      final word = WordVo.c2('trade ... for ...')
        ..meaningItems = [
          MeaningItemVo.from('v.，', '交换, 交易'),
          MeaningItemVo.from('v.', '交易'),
        ];

      final merged = word.getMergedMeaningItems();
      expect(merged.length, 1);
      expect(merged.first.ciXing, 'v.');
      expect(word.getMeaningStr(), startsWith('v. '));
    });

    test('Util.mergeMeaningItems 同样归并并规范化词性', () {
      final merged = Util.mergeMeaningItems([
        MeaningItemVo.from('n.，', '灾难'),
        MeaningItemVo.from('n.', '悲剧'),
      ]);

      expect(merged.length, 1);
      expect(merged.first.ciXing, 'n.');
    });
  });

  group('释义子项计数（通过门槛/进度展示口径）', () {
    test('按分号拆分，忽略整体被括号包裹的子项', () {
      final word = WordVo.c2('apple')..meaningItems = [
        MeaningItemVo.from('n.', '苹果;公司'),
        MeaningItemVo.from('adj.', '[ 废弃的用法 ]'),
      ];

      expect(countMeaningParts(word), 2);
    });

    test('与判题返回的 totalCount 口径一致（答对一半的算数）', () {
      final word = WordVo.c2('tragedy')
        ..meaningItems = [MeaningItemVo.from('n.', '悲剧;灾难;惨案')];

      final result = matchInputChineseWithMeaningItems(
          WordWrapper(word, null), '悲剧',
          strict: true);

      expect(result.totalCount, 3);
      expect(result.totalCount, countMeaningParts(word));
      expect(result.matchedCount, 1);
      // 答对一半（向上取整）需 2 个：只写对 1 个时还差 1 个
      expect(((result.totalCount + 1) >> 1) - result.matchedCount, 1);
    });
  });
}
