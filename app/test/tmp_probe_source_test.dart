import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/phoneme_asset.dart';

// 临时探针：验证 source 被识别成 sauce 时的音素得分是否越过判定线。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      if (message == null) return null;
      final String key = utf8.decode(message.buffer.asUint8List());
      if (key == 'assets/cmudict.pho') {
        return ByteData.sublistView(encodePhonemeAsset(parseCmudictText('''
source S AO1 R S
sauce S AO1 S
sources S AO1 R S IH0 Z
''')));
      }
      return null;
    });
  });

  test('probe', () async {
    for (final pair in [
      ['sauce', 'source'],
      ['sauce', 'sauce'],
      ['source', 'source'],
      ['sources', 'source'],
    ]) {
      final r = await AsrUtil.selectBestCandidateWithPhonemeAndScore([pair[0]], pair[1]);
      // ignore: avoid_print
      print('PROBE ${pair[0]} vs ${pair[1]} => score=${r.score} (threshold=${Constants.phonemeMatchThreshold})');
    }
  });
}
