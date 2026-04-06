import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/phoneme_util.dart';
import 'package:nnbdc/constants.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

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
INSURE  IH0 N SH UH1 R
SURE  SH UH1 R
YE  Y IY1
APPLE  AE1 P AH0 L
APPLY  AH0 P L AY1
HARDWARE  HH AA1 R D W EH2 R
CRUELTY  K R UW1 L T IY0
ANALYTIC  AE0 N AH0 L IH1 T IH0 K
ANALYTICAL  AE0 N AH0 L IH1 T IH0 K AH0 L
''';
          return ByteData.view(Uint8List.fromList(utf8.encode(content)).buffer);
        }
        return null; // Fallback for other assets
      },
    );
  });

  group('English Phoneme Matching Tests', () {
    test('insure vs ye sure - should match under relaxed threshold', () async {
      const String target = "insure";
      const String asrResult = "ye sure";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Phoneme similarity score: $score (threshold: ${Constants.phonemeMatchThreshold})');

      // 验证分数是否超过门限 (预期约为 66)
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('insure vs insure - exact match should be high', () async {
      const String target = "insure";
      final int score = await PhonemeUtil.similarity(target, target);
      expect(score, greaterThanOrEqualTo(95));
    });

    test('apple vs apply - should not match', () async {
      const String target = "apple";
      const String asrResult = "apply";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Apple vs Apply score: $score');
      
      expect(score, lessThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('confusion group: IH and Y', () async {
      final int score = await PhonemeUtil.similarity("ye sure", "insure");
      debugPrint('Confusion IH/Y score: $score');
      // @ N SH @ R vs Y @ SH @ R
      // @ vs Y (0.2)
      // N vs @ (1.0)
      // Others match. 1.2 distance.
      // (5 - 1.2) / 5 = 76. 
      // Penalty 10 -> 66.
      expect(score, greaterThanOrEqualTo(65)); 
    });

    test('hardware vs hathware - should match (voiced stop vs fricative confusion)', () async {
      const String target = "hardware";
      const String asrResult = "hathware";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Hardware vs Hathware score: $score');
      
      // Expected around 83 with the new confusion groups
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    
    test('cruelty vs carotti - should match', () async {
      const String target = "cruelty";
      const String asrResult = "carotti";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    
    test('analytic(al) vs analatic - should match', () async {
      const String target = "analytic(al)";
      const String asrResult = "analatic";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Analytic(al) vs Analatic score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
  });
}
