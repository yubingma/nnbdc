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
  });
}
