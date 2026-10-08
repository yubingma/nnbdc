// 回归：音素词典加载"停摆"时，发音判定链路必须在有界时间内降级返回。
//
// 线上实况（2026-10-09）：进入背单词页 1.5 秒后触发的那次加载卡住后，
// PhonemeUtil.load() 的 Future 被永久缓存，之后每一帧识别结果都停在
// bdc_notifier.dart 的 await 上：界面既不显示识别结果也不出分数，直到重启 App。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/asr_util.dart';
import 'package:nnbdc/util/phoneme_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('音素词典资源停摆：有界判定为不可用，且判定链路照常返回', () async {
    // 资源请求永不返回，复现那次"加载停摆"
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) => Completer<ByteData?>().future);

    // 1) 有界等待：超时就认定本会话不可用，绝不无限期挂住
    final ready = await PhonemeUtil.ensureReady(timeout: const Duration(milliseconds: 200));
    expect(ready, isFalse);
    expect(PhonemeUtil.isReady, isFalse);

    // 2) 判定链路照常返回（走已有的"无音素 → 拼写相似度"降级分支），不再被词典拖住
    final first = await AsrUtil.selectBestCandidateWithPhonemeAndScore(['grass'], 'gross')
        .timeout(const Duration(seconds: 3));
    expect(first.text, 'grass');

    // 3) 已认定不可用之后，后续每一帧不再各卡一次超时
    final sw = Stopwatch()..start();
    await AsrUtil.selectBestCandidateWithPhonemeAndScore(['kuros'], 'gross')
        .timeout(const Duration(seconds: 3));
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });
}
