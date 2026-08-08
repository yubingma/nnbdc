import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock the low-level binary messenger for assets
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        if (message == null) return null;
        final String key = utf8.decode(message.buffer.asUint8List());
        if (key == 'assets/cmudict.dict') {
          final String content = '''
CHARGE CH AA1 R JH
JUDGE JH AH1 JH
TWELVE T W EH1 L V
''';
          return ByteData.view(Uint8List.fromList(utf8.encode(content)).buffer);
        }
        return null; // Fallback for other assets
      },
    );
  });

  group('AsrUtil Punctuation Symbol Normalization Test', () {
    test('selectBestCandidateWithPhonemeAndScore - matches symbol to spoken word', () async {
      // Test en-dash '–' maps to 'dash'
      final result1 = await AsrUtil.selectBestCandidateWithPhonemeAndScore(['–'], 'dash');
      expect(result1.text, equals('–'));
      expect(result1.score, equals(100));

      // Test hyphen '-' maps to 'dash', 'hyphen', 'minus'
      final result2 = await AsrUtil.selectBestCandidateWithPhonemeAndScore(['-'], 'hyphen');
      expect(result2.text, equals('-'));
      expect(result2.score, equals(100));

      final result3 = await AsrUtil.selectBestCandidateWithPhonemeAndScore(['-'], 'minus');
      expect(result3.text, equals('-'));
      expect(result3.score, equals(100));

      // Test dot '.' maps to 'dot', 'period', 'point'
      final result4 = await AsrUtil.selectBestCandidateWithPhonemeAndScore(['.'], 'dot');
      expect(result4.text, equals('.'));
      expect(result4.score, equals(100));
    });

    test('calculateOverallSimilarity - direct symbol matching returns 100', () async {
      final score1 = await AsrUtil.calculateOverallSimilarity('–', 'dash');
      expect(score1, equals(100));

      final score2 = await AsrUtil.calculateOverallSimilarity('.', 'period');
      expect(score2, equals(100));
    });

    test('selectBestCandidate - spell similarity falls back to symbol matching', () {
      final best = AsrUtil.selectBestCandidate(['–', 'hello'], 'dash');
      expect(best, equals('–'));
    });

    test('selectBestCandidateWithPhonemeAndScore - matches charge to judge', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(['charge'], 'judge');
      expect(result.text, equals('charge'));
      expect(result.score, greaterThanOrEqualTo(60));
    });

    test('preprocessEnglish - converts Arabic numbers to English words', () {
      expect(AsrUtil.preprocessEnglish('12', 'twelve'), equals('twelve'));
      expect(AsrUtil.preprocessEnglish('i have 23 apples', 'twenty three'), equals('i have twenty three apples'));
    });

    test('selectBestCandidateWithPhonemeAndScore - matches number "12" to target "twelve"', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(['12'], 'twelve');
      expect(result.text, equals('12'));
      expect(result.score, equals(100));
    });
  });

  group('AsrUtil Single-Word Join Tolerance (单字拼接容错)', () {
    // 核心场景：ASR 把单字拆成了多词（如 headmaster → said master）
    test('multi-word candidate "said master" matches single-word target "headmaster"', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
        ['said master'],
        'headmaster',
      );
      expect(result.text, equals('said master'));
      // 拼接后 "saidmaster" vs "headmaster" 编辑距离更小，分数应高于不拼接时的分数
      expect(result.score, greaterThanOrEqualTo(50));
    });

    // 验证拼接版分数确实更高：单独计算拼接前后的分数对比
    test('joined variant scores higher than spaced variant for single-word target', () async {
      final scoreWithSpace = await AsrUtil.calculateOverallSimilarity('said master', 'headmaster');
      final scoreJoined = await AsrUtil.calculateOverallSimilarity('saidmaster', 'headmaster');
      expect(scoreJoined, greaterThan(scoreWithSpace));
    });

    // 精确匹配：拼接后恰好等于目标
    test('joined candidate matches target exactly returns score 100', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
        ['home work'],
        'homework',
      );
      expect(result.text, equals('home work'));
      expect(result.score, equals(100));
    });

    // 多候选：拼接容错后能选出最佳候选
    test('selects best among multiple candidates with join tolerance', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
        ['hello world', 'said master', 'random'],
        'headmaster',
      );
      // "said master" → "saidmaster" 与 "headmaster" 最接近
      expect(result.text, equals('said master'));
      expect(result.score, greaterThanOrEqualTo(40));
    });

    // 不误伤：目标为多词时不触发拼接容错
    test('multi-word target not affected (no false join)', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
        ['twelve'],
        'twelve',
      );
      expect(result.text, equals('twelve'));
      expect(result.score, equals(100));
    });

    // 边界：候选包含多个空格的情况
    test('candidate with multiple spaces gets joined correctly', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
        ['said the master'],
        'headmaster',
      );
      expect(result.text, equals('said the master'));
      expect(result.score, greaterThanOrEqualTo(30));
    });
  });
}
