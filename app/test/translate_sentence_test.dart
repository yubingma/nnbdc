import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/word_util.dart';

void main() {
  group('Translate Sentence - Scoring Algorithm', () {
    test('Exact match yields 100 score', () {
      final score = getChineseSentenceMatchScore('今天天气很好', '今天天气很好');
      expect(score, equals(100));
    });

    test('Homophones (他/她/它, 的/得/地) are normalized and match with 100 score', () {
      final score1 = getChineseSentenceMatchScore('她是我的好朋友', '他是我的好朋友');
      expect(score1, equals(100));

      final score2 = getChineseSentenceMatchScore('跑的很快', '跑得很快');
      expect(score2, equals(100));
    });

    test('Ignores punctuation and non-Chinese characters', () {
      final score = getChineseSentenceMatchScore('今天天气很好！', '今天天气很好。');
      expect(score, equals(100));
    });

    test('Ignores <b> tags in target chinese sentence', () {
      final score = getChineseSentenceMatchScore('我吃了一个苹果', '我吃了一个<b>苹果</b>。');
      expect(score, equals(100));
    });

    test('Partial match calculates correct percentage', () {
      // 目标 6 个字，匹配 4 个字 -> 4/6 = 67分
      final score = getChineseSentenceMatchScore('今天天气', '今天天气很好');
      expect(score, equals(67));
      expect(score >= 60, isTrue);
    });

    test('Empty input or target returns 0', () {
      expect(getChineseSentenceMatchScore('', '今天天气很好'), equals(0));
      expect(getChineseSentenceMatchScore('今天天气很好', ''), equals(0));
    });

    test('AsrUtil.mergeAsrText merges overlapping Chinese text chunks correctly', () {
      final merged1 = AsrUtil.mergeAsrText('今天天气很', '天气很好我们出去玩');
      expect(merged1, equals('今天天气很好我们出去玩'));

      final merged2 = AsrUtil.mergeAsrText('今天天气很好', '我们出去玩');
      expect(merged2, equals('今天天气很好 我们出去玩'));
    });
  });

  group('Translate Sentence - WordWrapper State & Clone', () {
    test('WordWrapper retains currentSentence and sentenceTranslatedPassed', () {
      final wordVo = WordVo.c2('apple');
      wordVo.id = '1';
      final wrapper = WordWrapper(wordVo, null);

      final sentence = SentenceVo(
        's1',
        'I ate an apple.',
        '我吃了一个苹果。',
        'digest123',
        'n.',
        'tts',
        0,
        0,
        UserVo.c2('author1'),
      );

      wrapper.currentSentence = sentence;
      wrapper.sentenceTranslatedPassed = true;
      wrapper.isAiEvaluatedPassed = true;
      wrapper.isAiEvaluating = true;
      wrapper.pronunciationScore = 95;

      final cloned = wrapper.clone();
      expect(cloned.currentSentence?.id, equals('s1'));
      expect(cloned.currentSentence?.english, equals('I ate an apple.'));
      expect(cloned.currentSentence?.chinese, equals('我吃了一个苹果。'));
      expect(cloned.sentenceTranslatedPassed, isTrue);
      expect(cloned.isAiEvaluatedPassed, isTrue);
      expect(cloned.isAiEvaluating, isTrue);
      expect(cloned.pronunciationScore, equals(95));
    });

    test('WordListStudyMode includes translateSentence', () {
      expect(WordListStudyMode.values.contains(WordListStudyMode.translateSentence), isTrue);
    });
  });
}
