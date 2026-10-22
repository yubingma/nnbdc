import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/phoneme_asset.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/util/word_form_judge.dart';

/// 词形判断的判别力基准：同词干不同词形必须判错，真实口音仍要放行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      if (message == null) return null;
      final String key = utf8.decode(message.buffer.asUint8List());
      if (key == 'assets/cmudict.pho') {
        return ByteData.sublistView(encodePhonemeAsset(parseCmudictText('''
walk W AO1 K
walked W AO1 K T
play P L EY1
played P L EY1 D
need N IY1 D
needed N IY1 D AH0 D
box B AA1 K S
boxes B AA1 K S AH0 Z
study S T AH1 D IY0
studies S T AH1 D IY0 Z
nation N EY1 SH AH0 N
national N AE1 SH AH0 N AH0 L
develop D IH0 V EH1 L AH0 P
development D IH0 V EH1 L AH0 P M AH0 N T
economy IH0 K AA1 N AH0 M IY0
economic EH2 K AH0 N AA1 M IH0 K
think TH IH1 NG K
sink S IH1 NG K
man M AE1 N
men M EH1 N
mouse M AW1 S
mice M AY1 S
colour K AH1 L ER0
color K AH1 L ER0
practice P R AE1 K T AH0 S
practise P R AE1 K T IH0 S
success S AH0 K S EH1 S
succeed S AH0 K S IY1 D
product P R AA1 D AH0 K T
produce P R AH0 D UW1 S
use Y UW1 S
useful Y UW1 S F AH0 L
care K EH1 R
careful K EH1 R F AH0 L
hero HH IH1 R OW0
heroic HH IH0 R OW1 IH0 K
child CH AY1 L D
children CH IH1 L D R AH0 N
foot F UH1 T
feet F IY1 T
be B IY1
been B IH1 N
have HH AE1 V
has HH AE1 Z
go G OW1
goes G OW1 Z
do D UW1
does D AH1 Z
advice AE0 D V AY1 S
advise AE0 D V AY1 Z
rice R AY1 S
rise R AY1 Z
right R AY1 T
write R AY1 T
very V EH1 R IY0
wary W EH1 R IY0
glass G L AE1 S
grass G R AE1 S
pray P R EY1
station S T EY1 SH AH0 N
statue S T AE1 CH UW2
''')));
      }
      return null;
    });
  });

  Future<WordFormRelation> judge(String heard, String target) =>
      WordFormJudge.judge(heard, target);

  group('同一个词与同音词放行', () {
    test('拼写相同', () async {
      expect(await judge('walk', 'walk'), WordFormRelation.same);
    });

    test('拼写变体', () async {
      expect(await judge('color', 'colour'), WordFormRelation.sameSound);
      expect(await judge('practise', 'practice'), WordFormRelation.sameSound);
    });

    test('同音词', () async {
      expect(await judge('write', 'right'), WordFormRelation.sameSound);
    });
  });

  group('纯辅音词尾被吞，判对', () {
    test('walked -> walk', () async {
      expect(await judge('walk', 'walked'), WordFormRelation.swallowedTail);
    });

    test('played -> play', () async {
      expect(await judge('play', 'played'), WordFormRelation.swallowedTail);
    });

    test('studies -> study', () async {
      expect(await judge('study', 'studies'), WordFormRelation.swallowedTail);
    });

    test('goes -> go', () async {
      expect(await judge('go', 'goes'), WordFormRelation.swallowedTail);
    });
  });

  group('同词干不同词形，判错', () {
    const cases = <List<String>>[
      ['walked', 'walk'],
      ['national', 'nation'],
      ['nation', 'national'],
      ['development', 'develop'],
      ['develop', 'development'],
      ['economic', 'economy'],
      ['succeed', 'success'],
      ['produce', 'product'],
      ['men', 'man'],
      ['mice', 'mouse'],
      ['children', 'child'],
      ['feet', 'foot'],
      ['needed', 'need'],
      ['need', 'needed'],
      ['boxes', 'box'],
      ['box', 'boxes'],
      ['goes', 'go'],
      ['does', 'do'],
      ['advise', 'advice'],
    ];

    for (final pair in cases) {
      test('说「${pair[0]}」对「${pair[1]}」', () async {
        expect(await judge(pair[0], pair[1]), WordFormRelation.differentForm);
      });
    }
  });

  group('不同词干的口音近似，不参与词形判错', () {
    const cases = <List<String>>[
      ['sink', 'think'],
      ['wary', 'very'],
      ['grass', 'glass'],
      ['pray', 'play'],
      ['rise', 'rice'],
    ];

    for (final pair in cases) {
      test('说「${pair[0]}」对「${pair[1]}」', () async {
        expect(await judge(pair[0], pair[1]), WordFormRelation.unrelated);
      });
    }
  });

  group('背单词页状态', () {
    test('词形标记参与状态相等与 copyWith', () {
      const wrong = BdcState(asrWrongWordForm: true);
      expect(wrong.asrWrongWordForm, isTrue);
      expect(wrong.copyWith(currentScore: 64).asrWrongWordForm, isTrue);
      expect(wrong.copyWith(asrWrongWordForm: false).asrWrongWordForm, isFalse);
      expect(wrong == const BdcState(), isFalse);
      expect(wrong == const BdcState(asrWrongWordForm: true), isTrue);
    });
  });

  group('接入判题后的结果', () {
    test('说派生词 national 对 nation：判错', () async {
      final result =
          await AsrUtil.selectBestCandidateWithPhonemeAndScore(['national'], 'nation');
      expect(result.wrongWordForm, isTrue);
    });

    test('第一候选是派生词，第二候选恰是目标词：仍按第一候选判错', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
          ['development', 'develop'], 'develop');
      expect(result.wrongWordForm, isTrue);
      expect(result.text, 'development');
    });

    test('说目标词本身：不受影响', () async {
      final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore(
          ['develop', 'development'], 'develop');
      expect(result.wrongWordForm, isFalse);
      expect(result.score, 100);
    });

    test('口音把 think 说成 sink：仍放行', () async {
      final result =
          await AsrUtil.selectBestCandidateWithPhonemeAndScore(['sink'], 'think');
      expect(result.wrongWordForm, isFalse);
      expect(result.score, greaterThanOrEqualTo(60));
    });

    test('词尾被吞：仍放行', () async {
      final result =
          await AsrUtil.selectBestCandidateWithPhonemeAndScore(['walk'], 'walked');
      expect(result.wrongWordForm, isFalse);
      expect(result.score, greaterThanOrEqualTo(60));
    });
  });
}
