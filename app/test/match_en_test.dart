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
THE  DH AH0
EFFECT  IH0 F EH1 K T
DEFLECT  D IH0 F L EH1 K T
THERMAL  TH ER1 M AH0 L
OHM  OW1 M
OH  OW1
MO  M OW1
OILFIELD  OY1 L F IY1 L D
ALL  AO1 L
YOUR  Y UH1 R
FIELD  F IY1 L D
TRUE  T R UW1
CHEW  CH UW1
LATER  L EY1 T ER0
LITER  L IY1 T ER0
CENTER  S EH1 N T ER0
CENTRE  S EH1 N T ER0
RANGE  R EY1 N JH
REFUSE  R IH0 F Y UW1 Z
REPEAT  R IH0 P IY1 T
REFEREE  R EH2 F ER0 IY1
RHYME  R AY1 M
ROLLER  R OW1 L ER0
RODER  R OW1 D ER0
ACT  AE1 K T
DO  D UW1
WATERMELON  W AO1 T ER0 M EH2 L AH0 N
WHAT  W AH1 T
MADELEIN  M AE2 D AH0 L EH1 N
ROPE  R OW1 P
JOPE  JH OW1 P
DIDN'T D IH1 D AH0 N T
COUGH K AA1 F
COLO K OW1 L OW0
CLUE K L UW1
CHOICE CH OY1 S
''';
          return ByteData.view(Uint8List.fromList(utf8.encode(content)).buffer);
        }
        return null; // Fallback for other assets
      },
    );
  });

  group('English Phoneme Matching Tests', () {
    test('choias vs choice - should match', () async {
      const String target = "choice";
      const String asrResult = "choias";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Choias vs Choice score: $score');

      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('jope vs rope - should match', () async {
      const String target = "rope";
      const String asrResult = "jope";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Jope vs Rope score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('true vs chew - should match', () async {
      const String target = "true";
      const String asrResult = "chew";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('True vs Chew score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
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
      
      expect(score, lessThanOrEqualTo(65));
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
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    
    test('deflect vs the effect - should match', () async {
      const String target = "deflect";
      const String asrResult = "the effect";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    
    test('thermal vs surmo - should match', () async {
      const String target = "thermal";
      const String asrResult = "surmo";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    
    test('ohm vs oh mo - should match', () async {
      const String target = "ohm";
      const String asrResult = "oh mo";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Ohm vs Oh Mo score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    test('oilfield vs all your field - should match', () async {
      const String target = "oilfield";
      const String asrResult = "all your field";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Oilfield vs All your field score: $score');
      
      expect(score, greaterThanOrEqualTo(45));
    });
    test('later vs litre - should match', () async {
      const String target = "later";
      const String asrResult = "litre";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Later vs Litre score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    test('centre vs center - should match', () async {
      const String target = "centre";
      const String asrResult = "center";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Centre vs Center score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    test('range vs wrenger - should not match at higher threshold', () async {
      const String target = "range";
      const String asrResult = "wrenger";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Range vs Wrenger score: $score');

      expect(score, lessThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('refuse vs repeat - should not match', () async {
      const String target = "repeat";
      const String asrResult = "refuse";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Refuse vs Repeat score: $score');

      expect(score, lessThan(Constants.phonemeMatchThreshold));
    });

    test('referee vs refuse - should not match', () async {
      const String target = "refuse";
      const String asrResult = "referee";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Referee vs Refuse score: $score');

      expect(score, lessThan(Constants.phonemeMatchThreshold));
    });

    test('rhyme vs ru - should not match', () async {
      const String target = "rhyme";
      const String asrResult = "ru";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Rhyme vs Ru score: $score');

      expect(score, lessThan(Constants.phonemeMatchThreshold));
    });

    test('roller vs roder - should match', () async {
      const String target = "roller";
      const String asrResult = "roder";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Roller vs Roder score: $score');

      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('do act vs act - should match despite extra noise', () async {
      const String target = "act";
      const String asrResult = "do act";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Do act vs Act score: $score');

      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('what madelein vs watermelon - should match', () async {
      const String target = "watermelon";
      const String asrResult = "what madelein";

      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('What madelein vs Watermelon score: $score');

      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
    
    test('didn\'t cough vs cough - should match', () async {
      const String target = "cough";
      const String asrResult = "didn't cough";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Didn\'t cough vs Cough score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('fate matches hate', () async {
      final int score = await PhonemeUtil.similarity('fate', 'hate');
      debugPrint('fate vs hate score: $score');
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });

    test('colo vs clue - should match', () async {
      const String target = "clue";
      const String asrResult = "colo";
      
      final int score = await PhonemeUtil.similarity(asrResult, target);
      debugPrint('Colo vs Clue score: $score');
      
      expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold));
    });
  });
}
