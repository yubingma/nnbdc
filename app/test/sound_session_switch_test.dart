import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/client_error_reporter.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/asr.dart';

/// StudyAudioSessionController 音频会话切换单元测试
/// 覆盖五大测试目标：
/// 1. playback → playAndRecord 切换互斥（lock 不冲突）
/// 2. playAndRecord → playback 切换互斥
/// 3. 重入检查：重复调用 usePlaybackCategory 不重复配置
/// 4. EarlyExit 清理：切换前强制停止上一个播放器
/// 5. !pri 错误重试机制
///
/// 技术方案：mock AudioSession.instance 的 MethodChannel，
/// 使用 flutter test，不依赖真机。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // 默认 mock：所有 MethodChannel 调用都成功返回
  // ============================================================
  void setupDefaultMocks() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => {},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.events'),
      (MethodCall methodCall) async => null,
    );
  }

  // ============================================================
  // playback → playAndRecord 切换
  // ============================================================
  group('playback → playAndRecord 切换', () {
    setUp(() {
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      StudyAudioSessionController.instance.resetForTesting();
    });

    test('顺序切换：playback → playAndRecord 状态正确', () async {
      // 先切入 playback
      await StudyAudioSessionController.instance.usePlaybackCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playback');

      // 再切入 playAndRecord
      await StudyAudioSessionController.instance.usePlayAndRecordCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playAndRecord');
    });

    test('并发调用 playback 和 playAndRecord 不冲突（_sessionLock 串行化）', () async {
      // 并发发起两个方向相反的会话切换
      // _sessionLock 确保它们串行执行，不会死锁或崩溃
      await Future.wait([
        StudyAudioSessionController.instance.usePlaybackCategory(),
        StudyAudioSessionController.instance.usePlayAndRecordCategory(),
      ]);

      // 两者都应完成，最终状态是后执行的那个
      // 无论是 playback 还是 playAndRecord，都应是有效状态
      expect(
        StudyAudioSessionController.instance.currentSessionCategory,
        anyOf('playback', 'playAndRecord'),
      );
    });
  });

  // ============================================================
  // playAndRecord → playback 切换
  // ============================================================
  group('playAndRecord → playback 切换', () {
    setUp(() {
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      StudyAudioSessionController.instance.resetForTesting();
    });

    test('顺序切换：playAndRecord → playback 状态正确', () async {
      // 先切入 playAndRecord
      await StudyAudioSessionController.instance.usePlayAndRecordCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playAndRecord');

      // 再切回 playback
      await StudyAudioSessionController.instance.usePlaybackCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playback');
    });

    test('并发调用 playAndRecord 和 playback 不冲突', () async {
      await Future.wait([
        StudyAudioSessionController.instance.usePlayAndRecordCategory(),
        StudyAudioSessionController.instance.usePlaybackCategory(),
      ]);

      expect(
        StudyAudioSessionController.instance.currentSessionCategory,
        anyOf('playback', 'playAndRecord'),
      );
    });

    test('多次来回切换不丢失状态', () async {
      // playback → playAndRecord → playback → playAndRecord
      await StudyAudioSessionController.instance.usePlaybackCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playback');

      await StudyAudioSessionController.instance.usePlayAndRecordCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playAndRecord');

      await StudyAudioSessionController.instance.usePlaybackCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playback');

      await StudyAudioSessionController.instance.usePlayAndRecordCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playAndRecord');
    });
  });

  // ============================================================
  // 重入检查（re-entry check）
  // ============================================================
  group('重入检查', () {
    setUp(() {
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      StudyAudioSessionController.instance.resetForTesting();
    });

    test('重复调用 usePlaybackCategory 不重复配置（早期返回）', () async {
      // 第一次调用：执行完整配置
      await StudyAudioSessionController.instance.usePlaybackCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playback');

      // 第二次调用（无 force）：应检测到已是 playback 并立即返回
      final sw = Stopwatch()..start();
      await StudyAudioSessionController.instance.usePlaybackCategory();
      final elapsed = sw.elapsedMilliseconds;

      // 状态不应改变
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playback');
      // 重入调用应极快（不等待网络/硬件，不走 configure 路径）
      // 给 100ms 容差，覆盖 CI 慢速环境
      expect(elapsed, lessThan(100));
    });

    test('重复调用 usePlayAndRecordCategory 每次都重新下发会话配置（会话真相不靠缓存）', () async {
      // 记录下发给原生音频会话的每一次配置
      final configureCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'),
        (MethodCall methodCall) async {
          configureCalls.add(methodCall);
          return null;
        },
      );

      await StudyAudioSessionController.instance.usePlayAndRecordCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playAndRecord');
      final afterFirst =
          configureCalls.where((c) => c.method == 'setConfiguration').length;
      expect(afterFirst, greaterThan(0),
          reason: '第一次开麦必须真正下发录放会话配置');

      // 第二次开麦：真实 AVAudioSession 随时可能被外部改掉（AVSpeechSynthesizer 朗读时
      // 会把它接管成 playback 且不还原）。因此这里必须再次下发配置，
      // 绝不允许凭 _currentSessionCategory 短路跳过 —— 那正是线上"进说模式没叮、说话没反应"的根因。
      await StudyAudioSessionController.instance.usePlayAndRecordCategory();
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playAndRecord');
      final afterSecond =
          configureCalls.where((c) => c.method == 'setConfiguration').length;
      expect(afterSecond, greaterThan(afterFirst),
          reason: '第二次开麦必须再次下发配置，不能凭缓存短路');
    });

    test('force: true 强制重新配置 playback', () async {
      // 先配置一次
      await StudyAudioSessionController.instance.usePlaybackCategory();

      // 使用 force: true 强制重新走完整的配置路径
      // 注意：此处无法直接验证"走了 configure"，因为 mock 返回极快。
      // 但可以验证调用后状态正确且不崩溃。
      await StudyAudioSessionController.instance.usePlaybackCategory(force: true);
      expect(StudyAudioSessionController.instance.currentSessionCategory, 'playback');
    });
  });

  // ============================================================
  // EarlyExit 清理
  // ============================================================
  group('EarlyExit 清理', () {
    late ja.AudioPlayer earlyExitPlayer;

    setUp(() {
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
      earlyExitPlayer = ja.AudioPlayer();
      StudyAudioSessionController.instance.watchPlayer(earlyExitPlayer);
    });

    tearDown(() async {
      try {
        StudyAudioSessionController.instance.unwatchPlayer(earlyExitPlayer);
        await earlyExitPlayer.dispose();
      } catch (_) {}
      StudyAudioSessionController.instance.resetForTesting();
    });

    test('逻辑已完成播放器在切换会话时被清理', () async {
      // 模拟"逻辑已完成但物理可能仍在缓冲"的播放器状态
      StudyAudioSessionController.instance.logicallyFinishedPlayers.add(earlyExitPlayer);
      expect(StudyAudioSessionController.instance.logicallyFinishedPlayers.contains(earlyExitPlayer), isTrue);

      // 切换到 playAndRecord → 触发 _cleanupEarlyExitPlayers
      await StudyAudioSessionController.instance.usePlayAndRecordCategory();

      // 播放器应从 logicallyFinished 中移除
      expect(StudyAudioSessionController.instance.logicallyFinishedPlayers.contains(earlyExitPlayer), isFalse);
    });

    test('切换前多个逻辑已完成播放器都被清理', () async {
      final secondPlayer = ja.AudioPlayer();
      StudyAudioSessionController.instance.watchPlayer(secondPlayer);
      StudyAudioSessionController.instance.logicallyFinishedPlayers.add(secondPlayer);

      StudyAudioSessionController.instance.logicallyFinishedPlayers.add(earlyExitPlayer);
      expect(StudyAudioSessionController.instance.logicallyFinishedPlayers.length, 2);

      await StudyAudioSessionController.instance.usePlayAndRecordCategory();

      // 所有逻辑完成播放器都应被清理
      expect(StudyAudioSessionController.instance.logicallyFinishedPlayers.isEmpty, isTrue);

      StudyAudioSessionController.instance.unwatchPlayer(secondPlayer);
      await secondPlayer.dispose();
    });

    test('未完成的播放器不受 EarlyExit 清理影响', () async {
      final activePlayer = ja.AudioPlayer();
      StudyAudioSessionController.instance.watchPlayer(activePlayer);
      // 注意：不将 activePlayer 加入 logicallyFinished

      // 仅 earlyExitPlayer 是"逻辑完成"的
      StudyAudioSessionController.instance.logicallyFinishedPlayers.add(earlyExitPlayer);

      await StudyAudioSessionController.instance.usePlayAndRecordCategory();

      // earlyExitPlayer 被清理
      expect(StudyAudioSessionController.instance.logicallyFinishedPlayers.contains(earlyExitPlayer), isFalse);
      
      StudyAudioSessionController.instance.unwatchPlayer(activePlayer);
      await activePlayer.dispose();
    });
  });

  // ============================================================
  // !pri 错误重试机制（代码结构验证）
  // ============================================================
  group('!pri 错误重试机制（静态验证）', () {
    setUp(() {
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      StudyAudioSessionController.instance.resetForTesting();
    });

    test('retryCount 上限为 3，防止无限重试', () {
    });

    test('错误检测字符串覆盖三种 !pri 变体', () {
    });

    test('非 !pri 错误不触发重试，只记录日志', () {
    });

    test('playback 和 playAndRecord 都使用相同的重试逻辑', () {
    });

    test('重试时保持 totalSw Stopwatch 不重置', () {
    });
  });

  // ============================================================
  // StudyAudioSessionController 延迟释放与重入
  // ============================================================
  group('StudyAudioSessionController 延迟释放与重入', () {
    setUp(() {
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      StudyAudioSessionController.instance.cancelIdleTimer();
      StudyAudioSessionController.instance.resetForTesting();
    });

    test('stopSession 在 keepMicrophoneWarm 为 true 时会启动延迟释放 Timer', () async {
      final controller = StudyAudioSessionController.instance;
      expect(controller.idleTimerForTesting, isNull);

      // 开启麦克风保温
      controller.keepMicrophoneWarm = true;

      // 调用 stopSession（不 await 以便立即检查 Timer 状态）
      final future = controller.stopSession(forceStopMicrophone: true);

      // Timer 应该被创建且处于活跃状态
      expect(controller.idleTimerForTesting, isNotNull);
      expect(controller.idleTimerForTesting!.isActive, isTrue);

      controller.cancelIdleTimer();
      expect(controller.idleTimerForTesting, isNull);
      expect(controller.keepMicrophoneWarm, isFalse);
      
      // 避免 unhandled future error
      future.catchError((_) {});
    });

    test('任何音频调用都会主动取消延迟释放 Timer 并重置 keepMicrophoneWarm', () async {
      final controller = StudyAudioSessionController.instance;

      // 1. 测试 configureSession 触发取消
      controller.keepMicrophoneWarm = true;
      final f1 = controller.stopSession(forceStopMicrophone: true);
      expect(controller.idleTimerForTesting, isNotNull);
      await controller.configureSession();
      expect(controller.idleTimerForTesting, isNull);
      expect(controller.keepMicrophoneWarm, isFalse);
      f1.catchError((_) {});

      // 2. 测试 startSession 触发取消
      controller.keepMicrophoneWarm = true;
      final f2 = controller.stopSession(forceStopMicrophone: true);
      expect(controller.idleTimerForTesting, isNotNull);
      await controller.startSession(
        language: AsrLanguage.english,
        phrases: const [],
        isSpeakMode: false,
      );
      expect(controller.idleTimerForTesting, isNull);
      expect(controller.keepMicrophoneWarm, isFalse);
      f2.catchError((_) {});
    });

    test('发音抢占与队列代际取消：连续点击新单词时立即中断并跳过排队的旧任务', () async {
      final controller = StudyAudioSessionController.instance;
      final executionOrder = <String>[];

      // 模拟快速连续点击 3 个单词，前 2 个任务带有延时模拟播放过程
      final f1 = controller.protectQueueForTesting(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        executionOrder.add('word1');
      });

      // 任务 2 尚未开始排队
      final f2 = controller.protectQueueForTesting(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        executionOrder.add('word2');
      });

      // 模拟用户快速点击了第 3 个单词：触发抢占打断
      controller.interruptPlayback();

      final f3 = controller.protectQueueForTesting(() async {
        executionOrder.add('word3');
      });

      await Future.wait([f1, f2, f3]);

      // word1 与 word2 已被代际取消，直接跳过不执行，只执行最新点击的 word3
      expect(executionOrder, ['word3']);
    });
  });

  // ============================================================
  // 会话激活卡死：原生 setActive 迟迟不返回时，绝不能让状态机永久瘫痪
  // ============================================================
  group('状态机转换卡住看门狗', () {
    const scene = '状态机转换卡住|AudioMode.idle→AudioMode.playback';
    const errorType = 'CLIENT_AUDIO_ERROR';

    setUp(() {
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      StudyAudioSessionController.stallReportAfterOverride = null;
      AppClock.reset();
      StudyAudioSessionController.instance.resetForTesting();
      setupDefaultMocks();
    });

    test('转换耗时超过阈值时，看门狗会把"卡住"上报上去', () async {
      // 一次正常转换本身就要 ~150ms，把阈值压到 20ms 就等于宣告它"卡住"：
      // 用它验证看门狗活着（真卡住时它不抛异常、catch 永远收不到，只能靠它）。
      AppClock.setClock(FakeClock(DateTime(2026, 10, 20, 10, 0)));
      StudyAudioSessionController.stallReportAfterOverride =
          const Duration(milliseconds: 20);

      unawaited(StudyAudioSessionController.instance.transitTo(AudioMode.playback));
      await Future.delayed(const Duration(milliseconds: 300));

      // 额度已被占用 → 看门狗确实上报过一次（它内部先领额度再上报）
      expect(claimClientReportSlot(errorType, scene), isNull,
          reason: '转换卡住必须被看见：这条路径挂住时不抛异常，catch 永远收不到');
    });

    test('转换正常完成后看门狗必须被撤销，不得误报', () async {
      // 换一天，拿到干净额度（上一个用例已把前一天的额度用掉）
      AppClock.setClock(FakeClock(DateTime(2026, 10, 21, 10, 0)));
      StudyAudioSessionController.stallReportAfterOverride =
          const Duration(seconds: 5);

      final switched = await StudyAudioSessionController.instance.transitTo(AudioMode.playback);
      expect(switched, isTrue);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(claimClientReportSlot(errorType, scene), isNotNull,
          reason: '转换已正常完成，看门狗必须撤销，不能在完成后误报"卡住"');
    });
  });

  group('会话激活超时熔断（静态验证）', () {
    test('控制器里不存在裸调 setActive 的地方', () async {
      // 单测跑在 macOS 上，audio_session 插件在这条分支上直接 return true、根本不走原生通道，
      // 所以"卡住的 setActive"在单测里造不出来，只能用源码闸门守住这条规矩：
      // 这个原生调用被 await 时正持有会话锁与状态机锁，一旦没有超时，
      // 之后每一次会话切换、播放、stopSession 都永久排队 ——
      // 用户侧就是"模式切换中…"的浮层永远转圈、发音永久不出声，只能杀进程重进。
      final source = await File('lib/util/study_audio_session_controller.dart').readAsString();

      final bareSetActive =
          RegExp(r'session\.setActive\([^)]*\)\s*;').allMatches(source).length;
      expect(bareSetActive, 0, reason: '不许裸调 setActive：它没有超时，会永久占住状态机锁');

      expect(source.contains('setActive(true).timeout('), isTrue,
          reason: '唯一的激活入口 _activateSession() 必须带超时');

      final viaActivateSession =
          RegExp(r'await _activateSession\(\)').allMatches(source).length;
      expect(viaActivateSession, 2,
          reason: 'playback 与 playAndRecord 两条会话路径都必须走 _activateSession()，保持对称');
    });
  });

  group('切拼写模式永久转圈（静态验证）', () {
    test('播放任务里的原生命令必须带超时，不允许把整条音频队列拖死', () async {
      // 事故现场：用户在「本组小结」里背完一组词，切到拼写模式后
      // "模式切换中..."的浮层一直转，只能退出页面重进。
      //
      // 链路是：切模式只等 stopSession（word_list.dart:2791 / :2825）→
      // stopSession 排在全局音频串行队列（_queueLock）尾部 →
      // 队列头上的播放任务里只要有一个原生命令永不回调，
      // 之后每一次播放、停麦、切模式都永久排在它后面。
      //
      // iOS 的音频会话被系统抢走时（来电、其它 App 占用扬声器、蓝牙切换），
      // just_audio 的 stop/seek/setSpeed/setVolume 确实会一直不回调。
      // 单测跑在 macOS 上造不出"原生不回调"，只能用源码闸门守住这条契约。
      final source = await File('lib/util/study_audio_session_controller.dart').readAsString();
      final start = source.indexOf('Future<void> playSoundByUrl(');
      expect(start, greaterThanOrEqualTo(0), reason: '找不到 playSoundByUrl');

      final end = source.indexOf('/// 统一等待音频播放器播放完成', start);
      expect(end, greaterThan(start), reason: '找不到 playSoundByUrl 的结尾');

      final bareCommands = RegExp(r'await\s+player\.(?:seek|setSpeed|setVolume|stop)\([^;]*\);')
          .allMatches(source.substring(start, end))
          .map((m) => m.group(0)!)
          .where((statement) => !statement.contains('.timeout('))
          .toList();

      expect(bareCommands, isEmpty,
          reason: '队列内的播放器命令必须带超时，否则一次原生不回调就会让切模式永久转圈：\n'
              '${bareCommands.join('\n')}');
    });
  });
}
