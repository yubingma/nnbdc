import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/asr.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';

/// 「开麦失败」这条链路的回归测试。
///
/// 线上现场（iPhone）：用户进「说」模式，开麦失败，屏上连堆两条一模一样的"语音未就绪，请重试"，
/// 界面卡在"正在处理中…"（ASR 状态被置成 unknown），可说多久都没有识别结果。
///
/// 根因：开麦失败被状态机转换吞掉后，startSession 仍带着"已开麦"的错觉去启动识别，
/// 原生立刻回 NOT_RECORDING —— 同一次失败被报成两次，第二条还把真正的现场盖住。
class _FailingMicAsr implements Asr {
  int startAsrCallCount = 0;
  int stopMicrophoneCallCount = 0;

  @override
  AsrState get state => AsrState.unknown;

  @override
  AsrLanguage? get currentLanguage => null;

  @override
  Future<void> updateLanguage(AsrLanguage language) async {}

  @override
  void addStateListener(Function(AsrState) listener) {}

  @override
  void removeStateListener(Function(AsrState) listener) {}

  @override
  Future<void> startMicrophone() async {
    throw PlatformException(
        code: 'AUDIO_ENGINE_NOT_READY', message: '音频引擎未能启动（录放会话未就绪）');
  }

  @override
  Future<void> startAsr(AsrLanguage language,
      {List<String>? phrases, bool playHintSound = true}) async {
    startAsrCallCount++;
  }

  @override
  Future<void> stopMicrophone() async {
    stopMicrophoneCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试桩未实现: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mockChannel(String name, Future<Object?>? Function(MethodCall)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), handler);
  }

  setUp(() {
    // 音频会话与播放器的通道一律成功：把"变量"单独留给开麦这一步
    mockChannel('com.ryanheise.audio_session', (call) async => null);
    mockChannel('com.ryanheise.just_audio.methods', (call) async => {});
    mockChannel('com.ryanheise.just_audio.events', (call) async => null);
    // 单测跑在 macOS 上，需显式声明"本平台支持 ASR"，否则 record 会被降级成 playback
    PlatformUtils.asrSupportedOverride = true;
    StudyAudioSessionController.instance.resetForTesting();
  });

  tearDown(() {
    PlatformUtils.asrSupportedOverride = null;
    StudyAudioSessionController.instance.resetForTesting();
    mockChannel('com.ryanheise.audio_session', null);
    mockChannel('com.ryanheise.just_audio.methods', null);
    mockChannel('com.ryanheise.just_audio.events', null);
    mockChannel('nnbdc/asr_commands', null);
  });

  test('开麦失败时状态机转换返回 false，并物理熔断回 idle', () async {
    final asr = _FailingMicAsr();
    final controller = StudyAudioSessionController.instance;
    controller.debugSetAsrForTesting(asr);

    final switched = await controller.transitTo(AudioMode.record);

    expect(switched, isFalse, reason: '开麦没成功，就不能对外报告"已切到录放模式"');
    expect(controller.activeMode, AudioMode.idle, reason: '失败必须物理熔断回 idle');
    expect(asr.stopMicrophoneCallCount, greaterThan(0),
        reason: '熔断要真的把麦克风释放掉，不能只是记账');
  });

  test('开麦失败后不得继续启动识别（否则用户会收到第二条一模一样的提示）', () async {
    final asr = _FailingMicAsr();
    final controller = StudyAudioSessionController.instance;
    controller.debugSetAsrForTesting(asr);

    await controller.startSession(
      language: AsrLanguage.chinese,
      phrases: const ['苹果'],
      isSpeakMode: true,
    );

    expect(asr.startAsrCallCount, 0,
        reason: '开麦没成功就启动识别，原生必然回 NOT_RECORDING，同一次失败被报成两次');
  });

  group('原生音频现场快照', () {
    test('原生没有这个方法时返回空串，绝不因诊断本身再抛错', () async {
      mockChannel('nnbdc/asr_commands', (call) async => null);

      expect(await Asr().audioDiagnostics(), '');
    });

    test('原生读取现场失败时同样只返回空串', () async {
      mockChannel('nnbdc/asr_commands', (call) async {
        throw PlatformException(code: 'DIAG_FAILED', message: '读取失败');
      });

      expect(await Asr().audioDiagnostics(), '');
    });
  });
}
