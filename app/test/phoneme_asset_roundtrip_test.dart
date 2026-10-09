// 预编译紧凑资源必须与文本源数据逐词一致 —— 保证"预编译"只换了存储形式，没有改动打分用的数据。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/phoneme_asset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assets/cmudict.pho 与 tool/phoneme/cmudict.dict 解析结果逐词一致', () async {
    // 资源目录必须在 pubspec 里声明，否则真机上会静默加载不到（编译、单测都不报错）
    expect(File('pubspec.yaml').readAsStringSync().contains('assets/cmudict.pho'), isTrue,
        reason: 'pubspec.yaml 必须声明 assets/cmudict.pho');

    final expected = parseCmudictText(File('tool/phoneme/cmudict.dict').readAsStringSync());
    final asset = PhonemeAsset.fromBytes(await rootBundle.load('assets/cmudict.pho'));

    expect(asset.wordCount, expected.length, reason: '词条总数不一致（资源是否忘了重新生成？）');
    for (final entry in expected.entries) {
      final actual = asset.variantsOf(entry.key);
      expect(actual, isNotNull, reason: '紧凑资源里查不到 ${entry.key}');
      expect(actual, entry.value, reason: '${entry.key} 的读音不一致');
    }
    expect(asset.variantsOf('zzz-not-in-cmudict'), isNull, reason: '查不到的词必须返回 null');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
