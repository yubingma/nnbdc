import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/phoneme_asset.dart';

/// 音素相似度打分的判别力基准：这个分数只衡量"两个词的发音有多像"。
///
/// 背景（真机复现）：iPad 上单词 `fearful`，用户说 `worried`，日志显示
/// `ASR SELECTION: Best candidate is "Worried" with score 61 (target: "fearful")`，
/// 即两个听感差别很大的词拿到了 61 分，越过了 60 分判定线。
///
/// 根因是音素混淆表把爆破塞音 `D` 与流音 `L`/`R`/儿化音 `ER` 当成近似同音（代价 0.2），
/// 于是 `worried` 与 `fearful` 能靠「删掉一个辅音 + 把 L 当成 D」拼出极短的对齐路径，
/// 弱化相似度被抬到 76 分。收紧为 {L,R,ER} 后该对回落到 38 分。
///
/// 本用例从两侧钉住这条打分线的判别力：发音差别大的词必须落在阈值线下，
/// 而真实口音与识别近似必须仍然达到阈值（实测量值见各断言）。
/// 音素数据逐字取自 cmudict 源数据 `app/tool/phoneme/cmudict.dict`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      if (message == null) return null;
      final String key = utf8.decode(message.buffer.asUint8List());
      if (key == 'assets/cmudict.pho') {
        return ByteData.sublistView(encodePhonemeAsset(parseCmudictText('''
worried W ER1 IY0 D
fearful F IH1 R F AH0 L
helpful HH EH1 L P F AH0 L
instrumental IH2 N S T R AH0 M EH1 N T AH0 L
newcomer N UW1 K AH2 M ER0
arrival ER0 AY1 V AH0 L
huge HH Y UW1 JH
gigantic JH AY0 G AE1 N T IH0 K
buy B AY1
purchase P ER1 CH AH0 S
kid K IH1 D
child CH AY1 L D
crucial K R UW1 SH AH0 L
grim G R IH1 M
multiplied M AH1 L T AH0 P L AY2 D
preside P R IH0 Z AY1 D
food F UW1 D
fusion F Y UW1 ZH AH0 N
sink S IH1 NG K
fink F IH1 NG K
think TH IH1 NG K
walk W AO1 K
walked W AO1 K T
stop S T AA1 P
stopped S T AA1 P T
very V EH1 R IY0
wary W EH1 R IY0
annie AE1 N IY0
any EH1 N IY0
glass G L AE1 S
grass G R AE1 S
play P L EY1
pray P R EY1
''')));
      }
      return null;
    });
  });

  Future<int> scoreOf(String spoken, String target) async {
    final result = await AsrUtil.selectBestCandidateWithPhonemeAndScore([spoken], target);
    return result.score;
  }

  group('听感差别大的词必须落在阈值线下', () {
    // 前 6 对是"按中文释义说了另一个英文词"，第 7~9 对是真机上确实说错的异词。
    const shouldNotPass = <List<String>>[
      ['worried', 'fearful'], // 回归用例：原为 61 分越线，收紧混淆组后 38 分
      ['helpful', 'instrumental'],
      ['newcomer', 'arrival'],
      ['huge', 'gigantic'],
      ['buy', 'purchase'],
      ['kid', 'child'],
      ['crucial', 'grim'],
      ['multiplied', 'preside'],
      ['food', 'fusion'],
    ];

    for (final pair in shouldNotPass) {
      test('说「${pair[0]}」对「${pair[1]}」的音素相似度应低于阈值', () async {
        final score = await scoreOf(pair[0], pair[1]);
        expect(score, lessThan(Constants.phonemeMatchThreshold),
            reason: '「${pair[0]}」与「${pair[1]}」听感差别很大，却算得 $score 分；'
                '达到 ${Constants.phonemeMatchThreshold} 分就越过了判定线');
      });
    }
  });

  group('真实口音与识别近似必须仍然达到阈值', () {
    const shouldPass = <List<String>>[
      ['sink', 'think'], // th 读成 s
      ['fink', 'think'], // th 读成 f
      ['walked', 'walk'], // 词尾 -ed 脱落
      ['stopped', 'stop'],
      ['very', 'wary'], // v/w 混淆
      ['annie', 'any'], // 真机日志：说 any 被识别成 Annie
      ['glass', 'grass'], // l/r 不分
      ['play', 'pray'],
    ];

    for (final pair in shouldPass) {
      test('说「${pair[0]}」对「${pair[1]}」的音素相似度应达到阈值', () async {
        final score = await scoreOf(pair[0], pair[1]);
        expect(score, greaterThanOrEqualTo(Constants.phonemeMatchThreshold),
            reason: '「${pair[0]}」是「${pair[1]}」的合理口音/识别近似，'
                '却只算得 $score 分，低于 ${Constants.phonemeMatchThreshold} 的判定线');
      });
    }
  });
}
