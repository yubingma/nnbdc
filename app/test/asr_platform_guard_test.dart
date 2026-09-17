import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/platform_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('在不支持 ASR 的平台上（如 Linux CI 环境），ASR 操作直接安全跳过且不产生 pending timer', () async {
    // 显式将 ASR 支持覆盖为 false（模拟 Linux CI runner / Web / 桌面环境）
    PlatformUtils.asrSupportedOverride = false;
    addTearDown(() => PlatformUtils.asrSupportedOverride = null);

    bool channelInvoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('nnbdc/asr'),
      (MethodCall methodCall) async {
        channelInvoked = true;
        return null;
      },
    );

    await Asr().stopMicrophone();
    await Asr().startMicrophone();
    await Asr().reset();
    await Asr().setContextualStrings(['hello']);
    await Asr().preloadModels();

    expect(channelInvoked, isFalse, reason: '不支持 ASR 的平台绝不可穿透调用原生通道');
  });
}
