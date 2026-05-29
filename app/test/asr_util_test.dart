import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/asr_util.dart';

void main() {
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
  });
}
