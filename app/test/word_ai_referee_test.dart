import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/ai_referee_util.dart';
import 'package:nnbdc/util/word_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Word AI Referee - Response Parsing and Tolerance', () {
    test('Correct JSON parsing for valid synonym response', () {
      const rawAiResponse = '''
```json
{
  "isCorrect": true
}
```
''';

      String cleanJson = rawAiResponse.trim();
      if (cleanJson.contains('```')) {
        final regExp = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
        final match = regExp.firstMatch(cleanJson);
        if (match != null) {
          cleanJson = match.group(1) ?? cleanJson;
        }
      }
      final startIdx = cleanJson.indexOf('{');
      final endIdx = cleanJson.lastIndexOf('}');
      expect(startIdx != -1 && endIdx != -1 && endIdx > startIdx, isTrue);

      cleanJson = cleanJson.substring(startIdx, endIdx + 1);
      final parsed = jsonDecode(cleanJson.trim()) as Map<String, dynamic>;
      expect(parsed['isCorrect'], isTrue);
    });

    test('Parse intendedMeaning when AI corrects homophone / phonetic error', () {
      const rawAiResponse = '''
{
  "isCorrect": true,
  "intendedMeaning": "工资"
}
''';
      final parsed = jsonDecode(rawAiResponse.trim()) as Map<String, dynamic>;
      expect(parsed['isCorrect'], isTrue);
      expect(parsed['intendedMeaning'], equals('工资'));
    });

    test('Incorrect JSON parsing with explanation for unrelated input', () {
      const rawAiResponse = '{"isCorrect": false, "explanation": "与salary含义不符"}';

      final startIdx = rawAiResponse.indexOf('{');
      final endIdx = rawAiResponse.lastIndexOf('}');
      final cleanJson = rawAiResponse.substring(startIdx, endIdx + 1);
      final parsed = jsonDecode(cleanJson.trim()) as Map<String, dynamic>;

      expect(parsed['isCorrect'], isFalse);
      expect(parsed['explanation'], equals('与salary含义不符'));
    });

    test('WordWrapper reveals all remaining meanings on AI referee pass', () {
      final wordVo = WordVo.c2('salary');
      wordVo.meaningItems = [
        MeaningItemVo.from('n.', '薪水'),
        MeaningItemVo.from('vt.', '发薪水'),
      ];
      final wrapper = WordWrapper(wordVo, null);

      expect(wrapper.asrMatchedMeaningItemParts.isEmpty, isTrue);
      expect(wrapper.asrRevealedMeaningItemParts.isEmpty, isTrue);

      wrapper.isAiEvaluatedPassed = true;
      wrapper.revealAllRemainingMeanings();

      expect(wrapper.asrRevealedMeaningItemParts.length, equals(2));
      expect(wrapper.asrRevealedMeaningItemParts.contains(Pair(0, 0)), isTrue);
      expect(wrapper.asrRevealedMeaningItemParts.contains(Pair(1, 0)), isTrue);
    });

    test('markAllMeaningsAsAiMatched marks all parts as matched and records aiApprovedAnswer', () {
      final wordVo = WordVo.c2('salary');
      wordVo.meaningItems = [
        MeaningItemVo.from('n.', '薪水'),
        MeaningItemVo.from('vt.', '发薪水'),
      ];
      final wrapper = WordWrapper(wordVo, null);

      wrapper.markAllMeaningsAsAiMatched(approvedAnswer: '工资');

      expect(wrapper.isAiEvaluatedPassed, isTrue);
      expect(wrapper.aiApprovedAnswer, equals('工资'));
      expect(wrapper.answeredAllMeanings, isTrue);
      expect(wrapper.asrMatchedMeaningItemParts.length, equals(2));
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(0, 0)), isTrue);
      expect(wrapper.asrMatchedMeaningItemParts.contains(Pair(1, 0)), isTrue);

      final widgets = renderAsrMeaningItems(wrapper);
      expect(widgets.isNotEmpty, isTrue);
      // 第一个 widget 应当是包含 AI 认可回答的组件
      expect(widgets.length, equals(3)); // 1 个 AI 认可 badge + 2 个词性 Wrap
    });

    test('AiRefereeUtil.parseRefereeResponse parses ch2En phonetic match correctly', () {
      const rawAiResponse = '{"isCorrect": true}';
      final parsed = AiRefereeUtil.parseRefereeResponse(rawAiResponse);
      expect(parsed.isCorrect, isTrue);
      expect(parsed.isSynonym, isFalse);
    });

    test('AiRefereeUtil.parseRefereeResponse parses ch2En synonym correctly with friendly hint', () {
      const rawAiResponse = '{"isCorrect": false, "isSynonym": true, "explanation": "「buy」意思正确，但请尝试读出目标词「purchase」"}';
      final parsed = AiRefereeUtil.parseRefereeResponse(rawAiResponse);
      expect(parsed.isCorrect, isFalse);
      expect(parsed.isSynonym, isTrue);
      expect(parsed.explanation, contains('「buy」意思正确'));
    });

    test('AiRefereeUtil.parseRefereeResponse parses unrelated wrong word correctly', () {
      const rawAiResponse = '{"isCorrect": false, "isSynonym": false, "explanation": "发音与目标词不符"}';
      final parsed = AiRefereeUtil.parseRefereeResponse(rawAiResponse);
      expect(parsed.isCorrect, isFalse);
      expect(parsed.isSynonym, isFalse);
      expect(parsed.explanation, equals('发音与目标词不符'));
    });
  });
}
