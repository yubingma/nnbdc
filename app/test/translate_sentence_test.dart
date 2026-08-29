import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/word_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('isChineseSentenceCoreKeywordsMatched validates bold core words and meanings correctly', () {
      final wordVo = WordVo.c2('clerk');
      wordVo.meaningItems = [
        MeaningItemVo.from('n.', '职员，店员'),
      ];

      // 1. 输入包含了加粗核心词“职员” -> 匹配成功
      final match1 = isChineseSentenceCoreKeywordsMatched('前面台子上的那位职员会帮助你', '前面台子上的那位<b>职员</b>会帮助你。', wordVo);
      expect(match1, isTrue);

      // 2. 输入中的核心词被误识为“煅” -> 匹配失败 (触发AI裁判)
      final match2 = isChineseSentenceCoreKeywordsMatched('前面台子上的那位煅会帮助你', '前面台子上的那位<b>职员</b>会帮助你。', wordVo);
      expect(match2, isFalse);

      // 3. 输入命中了单词其他释义“店员” -> 匹配成功
      final match3 = isChineseSentenceCoreKeywordsMatched('前面台子上的那位店员会帮助你', '前面台子上的那位<b>职员</b>会帮助你。', wordVo);
      expect(match3, isTrue);
    });

    test('isEnglishSentenceCoreKeywordsMatched validates bold core words and missing keywords correctly', () async {
      final wordVo = WordVo.c2('laughter');

      // 1. 输入包含了加粗核心词“laughter” -> 匹配成功
      final match1 = await isEnglishSentenceCoreKeywordsMatched('Her laughter filled the room.', 'Her <b>laughter</b> filled the room.', wordVo);
      expect(match1, isTrue);

      // 2. 输入中漏掉了核心词（如识别成 Her field is the room） -> 匹配失败
      final match2 = await isEnglishSentenceCoreKeywordsMatched('Her field is the room', 'Her <b>laughter</b> filled the room.', wordVo);
      expect(match2, isFalse);
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
