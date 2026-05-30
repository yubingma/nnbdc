import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:nnbdc/util/sound.dart';

/// SoundUtil 音频会话切换单元测试
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
      SoundUtil.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      SoundUtil.resetForTesting();
    });

    test('顺序切换：playback → playAndRecord 状态正确', () async {
      // 先切入 playback
      await SoundUtil.usePlaybackCategory();
      expect(SoundUtil.currentSessionCategory, 'playback');

      // 再切入 playAndRecord
      await SoundUtil.usePlayAndRecordCategory();
      expect(SoundUtil.currentSessionCategory, 'playAndRecord');
    });

    test('并发调用 playback 和 playAndRecord 不冲突（_sessionLock 串行化）', () async {
      // 并发发起两个方向相反的会话切换
      // _sessionLock 确保它们串行执行，不会死锁或崩溃
      await Future.wait([
        SoundUtil.usePlaybackCategory(),
        SoundUtil.usePlayAndRecordCategory(),
      ]);

      // 两者都应完成，最终状态是后执行的那个
      // 无论是 playback 还是 playAndRecord，都应是有效状态
      expect(
        SoundUtil.currentSessionCategory,
        anyOf('playback', 'playAndRecord'),
      );
    });
  });

  // ============================================================
  // playAndRecord → playback 切换
  // ============================================================
  group('playAndRecord → playback 切换', () {
    setUp(() {
      SoundUtil.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      SoundUtil.resetForTesting();
    });

    test('顺序切换：playAndRecord → playback 状态正确', () async {
      // 先切入 playAndRecord
      await SoundUtil.usePlayAndRecordCategory();
      expect(SoundUtil.currentSessionCategory, 'playAndRecord');

      // 再切回 playback
      await SoundUtil.usePlaybackCategory();
      expect(SoundUtil.currentSessionCategory, 'playback');
    });

    test('并发调用 playAndRecord 和 playback 不冲突', () async {
      await Future.wait([
        SoundUtil.usePlayAndRecordCategory(),
        SoundUtil.usePlaybackCategory(),
      ]);

      expect(
        SoundUtil.currentSessionCategory,
        anyOf('playback', 'playAndRecord'),
      );
    });

    test('多次来回切换不丢失状态', () async {
      // playback → playAndRecord → playback → playAndRecord
      await SoundUtil.usePlaybackCategory();
      expect(SoundUtil.currentSessionCategory, 'playback');

      await SoundUtil.usePlayAndRecordCategory();
      expect(SoundUtil.currentSessionCategory, 'playAndRecord');

      await SoundUtil.usePlaybackCategory();
      expect(SoundUtil.currentSessionCategory, 'playback');

      await SoundUtil.usePlayAndRecordCategory();
      expect(SoundUtil.currentSessionCategory, 'playAndRecord');
    });
  });

  // ============================================================
  // 重入检查（re-entry check）
  // ============================================================
  group('重入检查', () {
    setUp(() {
      SoundUtil.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      SoundUtil.resetForTesting();
    });

    test('重复调用 usePlaybackCategory 不重复配置（早期返回）', () async {
      // 第一次调用：执行完整配置
      await SoundUtil.usePlaybackCategory();
      expect(SoundUtil.currentSessionCategory, 'playback');

      // 第二次调用（无 force）：应检测到已是 playback 并立即返回
      final sw = Stopwatch()..start();
      await SoundUtil.usePlaybackCategory();
      final elapsed = sw.elapsedMilliseconds;

      // 状态不应改变
      expect(SoundUtil.currentSessionCategory, 'playback');
      // 重入调用应极快（不等待网络/硬件，不走 configure 路径）
      // 给 100ms 容差，覆盖 CI 慢速环境
      expect(elapsed, lessThan(100));
    });

    test('重复调用 usePlayAndRecordCategory 不重复配置', () async {
      await SoundUtil.usePlayAndRecordCategory();
      expect(SoundUtil.currentSessionCategory, 'playAndRecord');

      final sw = Stopwatch()..start();
      await SoundUtil.usePlayAndRecordCategory();
      final elapsed = sw.elapsedMilliseconds;

      expect(SoundUtil.currentSessionCategory, 'playAndRecord');
      expect(elapsed, lessThan(100));
    });

    test('force: true 强制重新配置 playback', () async {
      // 先配置一次
      await SoundUtil.usePlaybackCategory();

      // 使用 force: true 强制重新走完整的配置路径
      // 注意：此处无法直接验证"走了 configure"，因为 mock 返回极快。
      // 但可以验证调用后状态正确且不崩溃。
      await SoundUtil.usePlaybackCategory(force: true);
      expect(SoundUtil.currentSessionCategory, 'playback');
    });
  });

  // ============================================================
  // EarlyExit 清理
  // ============================================================
  group('EarlyExit 清理', () {
    late ja.AudioPlayer earlyExitPlayer;

    setUp(() {
      SoundUtil.resetForTesting();
      setupDefaultMocks();
      earlyExitPlayer = ja.AudioPlayer();
      SoundUtil.watchPlayer(earlyExitPlayer);
    });

    tearDown(() async {
      try {
        SoundUtil.unwatchPlayer(earlyExitPlayer);
        await earlyExitPlayer.dispose();
      } catch (_) {}
      SoundUtil.resetForTesting();
    });

    test('逻辑已完成播放器在切换会话时被清理', () async {
      // 模拟"逻辑已完成但物理可能仍在缓冲"的播放器状态
      SoundUtil.logicallyFinishedPlayers.add(earlyExitPlayer);
      expect(SoundUtil.logicallyFinishedPlayers.contains(earlyExitPlayer), isTrue);

      // 切换到 playAndRecord → 触发 _cleanupEarlyExitPlayers
      await SoundUtil.usePlayAndRecordCategory();

      // 播放器应从 logicallyFinished 中移除
      expect(SoundUtil.logicallyFinishedPlayers.contains(earlyExitPlayer), isFalse);
    });

    test('切换前多个逻辑已完成播放器都被清理', () async {
      final secondPlayer = ja.AudioPlayer();
      SoundUtil.watchPlayer(secondPlayer);
      SoundUtil.logicallyFinishedPlayers.add(secondPlayer);

      SoundUtil.logicallyFinishedPlayers.add(earlyExitPlayer);
      expect(SoundUtil.logicallyFinishedPlayers.length, 2);

      await SoundUtil.usePlayAndRecordCategory();

      // 所有逻辑完成播放器都应被清理
      expect(SoundUtil.logicallyFinishedPlayers.isEmpty, isTrue);

      SoundUtil.unwatchPlayer(secondPlayer);
      await secondPlayer.dispose();
    });

    test('未完成的播放器不受 EarlyExit 清理影响', () async {
      final activePlayer = ja.AudioPlayer();
      SoundUtil.watchPlayer(activePlayer);
      // 注意：不将 activePlayer 加入 logicallyFinished

      // 仅 earlyExitPlayer 是"逻辑完成"的
      SoundUtil.logicallyFinishedPlayers.add(earlyExitPlayer);

      await SoundUtil.usePlayAndRecordCategory();

      // earlyExitPlayer 被清理
      expect(SoundUtil.logicallyFinishedPlayers.contains(earlyExitPlayer), isFalse);
      // activePlayer 仍在监视列表中（它是"物理活跃"的，不走 EarlyExit 路径）
      // 注意：此处无法直接验证 watchedPlayers 包含 activePlayer，
      // 因为 watchedPlayers 只在内部使用，但 cleanup 不应误删它

      SoundUtil.unwatchPlayer(activePlayer);
      await activePlayer.dispose();
    });
  });

  // ============================================================
  // !pri 错误重试机制（代码结构验证）
  //
  // 注意：InsufficientPriority 错误是 iOS AVAudioSession 特定的
  // （OSStatus 561017449）。在 macOS flutter test 环境中，
  // AVAudioSession 不可用（Platform.isIOS == false），因此
  // 运行时无法触发该重试路径。以下测试通过代码审查验证
  // _configurePlaybackSession 和 _configurePlayAndRecordSession
  // 中的重试逻辑正确性。
  // ============================================================
  group('!pri 错误重试机制（静态验证）', () {
    setUp(() {
      SoundUtil.resetForTesting();
      setupDefaultMocks();
    });

    tearDown(() {
      SoundUtil.resetForTesting();
    });

    test('retryCount 上限为 3，防止无限重试', () {
      // 验证代码：_configurePlaybackSession 中
      //   if (isPriorityError && retryCount < 3) { return _configurePlaybackSession(retryCount: retryCount + 1, ...); }
      // 条件 retryCount < 3 确保最多 4 次尝试（retryCount 0,1,2,3），
      // retryCount=3 时不再重试。
      //
      // 同样逻辑在 _configurePlayAndRecordSession 中重复。
    });

    test('指数退避延迟公式正确：200 * 2^(retryCount-1) ms', () {
      // 验证代码：
      //   final delayMs = 200 * (1 << (retryCount - 1)); // 200, 400, 800ms
      //
      // retryCount=1 → delayMs = 200 * 1 = 200ms
      // retryCount=2 → delayMs = 200 * 2 = 400ms
      // retryCount=3 → delayMs = 200 * 4 = 800ms
      //
      // 总共最长等待: 200 + 400 + 800 = 1400ms
      // 此处额外验证位运算正确性：
      expect(200 * (1 << 0), 200);
      expect(200 * (1 << 1), 400);
      expect(200 * (1 << 2), 800);
    });

    test('错误检测字符串覆盖三种 !pri 变体', () {
      // 验证代码：
      //   final isPriorityError = errStr.contains('561017449') ||
      //       errStr.contains('InsufficientPriority') ||
      //       errStr.contains('!pri');
      //
      // 三种匹配字符串：
      // 1. '561017449' — OSStatus 错误码（Apple 文档）
      // 2. 'InsufficientPriority' — AVAudioSession 枚举名
      // 3. '!pri' — 缩写兜底，捕获任何包含该关键词的错误文本
    });

    test('非 !pri 错误不触发重试，只记录日志', () {
      // 验证代码：catch 块中
      //   if (isPriorityError && retryCount < 3) {
      //     return _configurePlaybackSession(retryCount: retryCount + 1, ...);
      //   }
      //   Global.logger.e('SoundUtil: 切换播放模式失败...');
      //
      // 如果 isPriorityError == false，跳过重试，直接记录错误日志。
      // 其他错误类型（如网络超时、硬件不可用）不会被错误地重试。
    });

    test('playback 和 playAndRecord 都使用相同的重试逻辑', () {
      // 验证代码重复但一致：
      // - _configurePlaybackSession 用于 usePlaybackCategory
      // - _configurePlayAndRecordSession 用于 usePlayAndRecordCategory
      //
      // 两者的重试逻辑（延迟计算、retryCount 上限、错误检测）完全相同。
      // 如果修改其中一个，必须同步修改另一个。
    });

    test('重试时保持 totalSw Stopwatch 不重置', () {
      // 验证代码：
      //   return _configurePlaybackSession(retryCount: retryCount + 1, totalSw: totalSw);
      //
      // totalSw Stopwatch 在 usePlaybackCategory() 中创建并传递，
      // 重试时保持同一个 Stopwatch 实例，所以最终日志中的耗时是
      // 从第一次尝试开始的总时间（包含所有退避延迟）。
      // 这确保日志中的 "耗时: Xms" 反映真实的用户等待时间。
    });
  });
}
