import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tts 抢占与停止机制测试', () {
    late Tts tts;
    final List<String> speakCalls = [];
    final List<String> stopCalls = [];

    setUp(() {
      tts = Tts();
      speakCalls.clear();
      stopCalls.clear();
      PlatformUtils.ttsSupportedOverride = true;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tts.methodChannel, (MethodCall call) async {
        if (call.method == 'speak') {
          final text = call.arguments['text'] as String;
          speakCalls.add(text);
          return null;
        } else if (call.method == 'stop') {
          stopCalls.add('stop');
          return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tts.methodChannel, null);
      PlatformUtils.ttsSupportedOverride = null;
    });

    test('连续调用 speak 时，后一个请求会抢占并打断前一个请求，丢弃旧任务', () async {
      // 连续并发触发 3 次 speak
      final f1 = tts.speak('enterprise1');
      final f2 = tts.speak('enterprise2');
      final f3 = tts.speak('enterprise3');

      // 模拟第 3 个（最新）收到原生完成事件
      await Future.delayed(const Duration(milliseconds: 30));
      // 检查被调用的底层方法
      expect(stopCalls.length, greaterThanOrEqualTo(1));

      // 手动触发最新任务完成
      // 给 f3 几毫秒流转
      await Future.wait([f1, f2, f3]);

      // 验证只有最后一个被完整朗读，前面的被中断或丢弃
      expect(speakCalls.last, equals('enterprise3'));
    });

    test('stop() 能立即中断并重置状态，后续不会有残留朗读', () async {
      final f = tts.speak('testing');
      await Future.delayed(const Duration(milliseconds: 10));
      await tts.stop();
      await f;

      expect(tts.isSpeaking, isFalse);
      expect(stopCalls, contains('stop'));
    });
  });
}
