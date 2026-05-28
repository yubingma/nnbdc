import 'dart:async';
import 'package:flutter/services.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import '../services/dialog_service.dart';
import 'dart:io' show Platform;
import '../util/permission_util.dart';
import 'package:nnbdc/util/sound.dart';

enum AsrState { unknown, initialized, started, stopping, stopped }

enum AsrLanguage {
  english('en-US'),
  chinese('zh-CN');

  const AsrLanguage(this.locale);
  final String locale;
}

class Asr {
  // 单例实现，确保全局只有一个 ASR 实例和一条事件订阅链路，
  // 避免多个页面各自创建 Asr() 时争抢同一个 EventChannel
  static final Asr _instance = Asr._internal();

  factory Asr() => _instance;

  Asr._internal();

  var asrMethodChannel = MethodChannel('nnbdc/asr_commands');
  var asrEventChannel = EventChannel('nnbdc/asr_events');
  var asrMeterChannel = EventChannel('nnbdc/asr_meter');

  bool permissionGranted = false;
  AsrState _state = AsrState.unknown;
  final List<Function(AsrState)> _stateListeners = [];
  bool _disposed = false;

  /// 标记 AVAudioEngine 是否曾经被启动过，用于区分首次冷启动（硬件完全冷态）
  /// 和后续冷启动（硬件已 warm），只在首次时给引擎稳定延迟。
  bool _engineEverStarted = false;

  /// 标记是否正在执行 startAsr，避免并发的 start/stop 调用打架
  bool _isStarting = false;

  /// 跟踪麦克风引擎预热状态。非 null 表示预热正在进行中。
  Completer<void>? _micWarmupCompleter;

  /// 标记是否正在初始化事件监听，避免并发初始化
  bool _isInitializing = false;

  /// ASR 结果事件订阅，用于在页面销毁或重新初始化时正确取消订阅，
  /// 避免多个已失效的监听器继续处理结果，导致目标单词长期停留在旧值
  StreamSubscription? _eventSubscription;

  /// 当前 ASR 使用的语言，用于在启动时判断是否需要切换语言
  AsrLanguage? _currentLanguage;

  /// Meter 流订阅，使用单例模式避免重复订阅导致 iOS 端报错
  StreamSubscription<double>? _meterSubscription;

  AsrState get state => _state;
  bool get isStarting => _isStarting;
  setState(AsrState newState) {
    Global.logger.i('ASR: State change: $_state => $newState');
    if (_state != newState) {
      _state = newState;
      if (!_disposed) {
        for (var listener in _stateListeners) {
          listener(newState);
        }
      }
    }
  }

  void addStateListener(Function(AsrState) listener) {
    _stateListeners.add(listener);
  }

  void removeStateListener(Function(AsrState) listener) {
    _stateListeners.remove(listener);
  }

  Future<void> dispose() async {
    Global.logger.d('ASR: dispose() 被调用，取消事件订阅');
    // 如果正在初始化，等待初始化完成
    if (_isInitializing) {
      Global.logger.w('ASR: 警告：在初始化过程中调用 dispose()，等待初始化完成');
      // 等待初始化完成（最多等待 1 秒）
      int waitCount = 0;
      while (_isInitializing && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitCount++;
      }
    }
    _disposed = true;
    _stateListeners.clear();
    _eventSubscription?.cancel();
    _eventSubscription = null;

    // 清理 meter 订阅
    disposeMeter();
  }

  Future<void> _updateLanguage(AsrLanguage language) async {
    if (!PlatformUtils.isAsrSupported()) {
      return;
    }
    if (_currentLanguage == language) {
      Global.logger.i('ASR: 语言已是 ${language.locale}，无需重复设置');
      return;
    }

    try {
      Global.logger.i('ASR: 设置语言为: ${language.locale}');
      await asrMethodChannel.invokeMethod('setLanguage',
          {'locale': language.locale}).timeout(const Duration(seconds: 5));
      _currentLanguage = language;
      Global.logger.i('ASR: 语言设置成功');
    } on PlatformException catch (e) {
      Global.logger.i('ASR: 设置语言失败: ${e.message}');
    } on TimeoutException catch (_) {
      Global.logger.w('ASR: 设置语言超时');
    }
  }

  bool _isPreloaded = false;
  bool get isPreloaded => _isPreloaded;
  Future<void>? _preloadFuture;

  Future<void> preloadModels() async {
    if (!PlatformUtils.isAsrSupported()) return;
    if (_isPreloaded) return;
    
    if (_preloadFuture != null) {
      return _preloadFuture;
    }

    _preloadFuture = () async {
      try {
        Global.logger.i('ASR: 预加载模型');
        await asrMethodChannel.invokeMethod('preloadModels');
        _isPreloaded = true;
      } catch (e) {
        Global.logger.e('ASR: 预加载模型失败: $e');
        _preloadFuture = null; // 发生异常时清空缓存，以便下次可以重试
      }
    }();

    return _preloadFuture;
  }

  /// 检查是否授予了麦克风和语音识别权限
  Future<bool> _checkPermissions() async {
    if (!PlatformUtils.isAsrSupported()) {
      return false;
    }

    if (Platform.isIOS) {
      try {
        bool granted = await asrMethodChannel.invokeMethod('checkPermissions');
        return granted;
      } catch (e) {
        Global.logger.i('检查权限失败: $e');
        return false;
      }
    } else {
      // Android使用permission_handler
      var status = await Permission.microphone.status;
      return status.isGranted;
    }
  }

  /// 处理权限被拒绝的情况，引导用户去设置
  Future<bool> _handlePermissionDenied() async {
    Global.logger.i('ASR: Permission denied, showing settings dialog...');
    // 直接显示设置对话框，因为系统不会再次弹出权限请求
    bool shouldRequest = await _showPermissionDialog();
    if (!shouldRequest) {
      Global.logger.i('ASR: 用户取消权限请求');
      return false;
    }
    // 用户选择去设置后，延迟检查权限状态
    await Future.delayed(Duration(seconds: 2));
    bool finalCheck = await _checkPermissions();
    if (finalCheck) {
      permissionGranted = true;
      Global.logger.i('ASR: 权限最终获取成功');
      return true;
    } else {
      Global.logger.i('ASR: 在等待时间内, 未能获取到授权');
      return false;
    }
  }

  /// 检查并请求麦克风和语音识别权限
  Future<void> _checkAndRequestPermissions() async {
    // 检查权限状态
    bool hasPermission = await _checkPermissions();

    if (!hasPermission) {
      if (Platform.isIOS) {
        // iOS 平台使用原生方法同时请求麦克风和语音识别权限
        try {
          permissionGranted = await asrMethodChannel.invokeMethod('requestPermissions');
          if (!permissionGranted) {
            Global.logger.i('ASR: 用户未授予麦克风/语音识别权限(iOS)');
            await _handlePermissionDenied();
          } else {
            Global.logger.i('ASR: 麦克风和语音识别权限获取成功(iOS)');
          }
        } catch (e) {
          Global.logger.i('请求权限失败(iOS): $e');
          permissionGranted = false;
        }
        return;
      }

      // Android 平台弹出合规的权限申请说明对话框
      await PermissionUtil.requestWithRationale(
        permission: Permission.microphone,
        title: '麦克风权限',
        purpose: '${Global.appName}需要您的麦克风权限，用于进行单词发音练习和语音识别评测。',
        icon: Icons.mic_rounded,
        onGranted: () async {
          permissionGranted = true;
          Global.logger.i('ASR: 麦克风权限通过 Rationale 获取成功(Android)');
        },
        onDenied: () async {
          permissionGranted = false;
          Global.logger.i('ASR: 用户未授予麦克风权限(Android)');
          await _handlePermissionDenied();
        },
      );
      return;
    }

    permissionGranted = true;
    Global.logger.i('ASR: 麦克风和语音识别权限已存在');
  }

  /// 打开系统权限设置页面
  Future<void> _openSettings() async {
    if (!PlatformUtils.isAsrSupported()) {
      ToastUtil.info("当前平台暂不支持语音识别功能");
      return;
    }

    if (Platform.isIOS) {
      // 检查是否在模拟器中运行
      bool isSimulator = false;
      try {
        isSimulator = await asrMethodChannel.invokeMethod('isSimulator');
      } catch (e) {
        Global.logger.i('检查模拟器状态失败: $e');
      }

      if (isSimulator) {
        // 在模拟器中，显示提示信息
        ToastUtil.error("请在 Xcode 的模拟器设置中启用麦克风权限");
        return;
      }

      // 在真机上，尝试打开应用设置页面
      await openAppSettings();
    } else if (Platform.isAndroid) {
      // Android 打开应用权限设置
      await openAppSettings();
    }
  }

  Future<bool> _showPermissionDialog() async {
    if (!PlatformUtils.isAsrSupported()) {
      ToastUtil.info("当前平台暂不支持语音识别功能");
      return false;
    }

    bool? result = await DialogService.showDialog<bool>(
      AlertDialog(
        title: const Text('权限申请'),
        content: Text(
            Platform.isIOS ? '需要麦克风和语音识别权限来进行发音练习' : '需要麦克风权限来进行语音识别和发音练习'),
        actions: [
          TextButton(
            onPressed: () => DialogService.pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              DialogService.pop(true);
              await _openSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Stream<double>? _meterStreamCache;

  /// 获取音量计数据流，使用单例模式避免重复订阅
  /// 每次调用都会返回同一个流订阅，避免 iOS 端出现 "No active stream to cancel" 错误
  Stream<double> meterStream() {
    if (!PlatformUtils.isAsrSupported()) {
      return const Stream<double>.empty();
    }
    // 如果已经有订阅，直接返回现有的流（通过检查订阅是否存在）
    // 注意：这里无法直接返回已存在的 Stream，所以采用延迟初始化的方式
    // 调用方应该只调用一次 meterStream() 并保存订阅
    _meterStreamCache ??= asrMeterChannel
        .receiveBroadcastStream('nnbdc/asr_meter')
        .map((event) => (event as num).toDouble())
        .handleError((e) => Global.logger.i('ASR meter error: $e'));
    return _meterStreamCache!;
  }

  /// 获取或创建 meter 订阅，确保全局只有一个有效的 meter 订阅
  StreamSubscription<double> getOrCreateMeterSubscription(
      void Function(double level) onLevel) {
    // 如果已有订阅，先取消旧的（理论上不应该发生）
    if (_meterSubscription != null) {
      Global.logger.w('ASR: 警告：getMeterSubscription 被多次调用，取消旧订阅');
      _meterSubscription!.cancel();
    }

    _meterSubscription = meterStream().listen(onLevel);
    Global.logger.d('ASR: 创建新的 meter 订阅');
    return _meterSubscription!;
  }

  /// 取消 meter 订阅，在 dispose 时调用
  void disposeMeter() {
    Global.logger.d('ASR: disposeMeter() 被调用 (instance: $hashCode)');
    if (_meterSubscription != null) {
      _meterSubscription!.cancel();
      _meterSubscription = null;
      Global.logger.d('ASR: meter 订阅已取消 (instance: $hashCode)');
    }
  }

  /// 初始化语音识别事件监听
  Future<void> initAsr(void Function(dynamic asrResult)? asrListener) async {
    if (_isInitializing || _isStarting || _state == AsrState.started) {
      Global.logger.w(
          'ASR: initAsr 跳过，当前状态为: $_state, isInitializing=$_isInitializing, isStarting=$_isStarting');
      return;
    }

    // 恢复事件分发开关（重要！单例在退出页面后必定为 true，会导致此后再也推不出状态给新页面）
    _disposed = false;
    _isInitializing = true;

    if (!PlatformUtils.isAsrSupported()) {
      _isInitializing = false;
      return;
    }

    if (asrListener == null) {
      Global.logger.w('ASR: initAsr 被调用，但 asrListener 为 null，跳过初始化');
      _isInitializing = false;
      return;
    }

    try {
      Global.logger.i('ASR: 重新初始化事件监听，取消旧订阅');
      final oldSubscription = _eventSubscription;
      _eventSubscription = null;
      if (oldSubscription != null) {
        await oldSubscription.cancel();
      }

      try {
        final stream = asrEventChannel.receiveBroadcastStream();
        final subscriptionId = AppClock.now().millisecondsSinceEpoch;
        final savedListener = asrListener;

        _eventSubscription = stream.listen(
          (event) {
            final receiveTime = AppClock.now();
            Global.logger.d(
                '~~~~~ASR: [Event] Received result from platform at ${receiveTime.toIso8601String()}: $event');
            try {
              savedListener(event);
              final processTime = AppClock.now();
              Global.logger.d(
                  'ASR: [Event] Listener callback finished at ${processTime.toIso8601String()} (duration: ${processTime.difference(receiveTime).inMilliseconds}ms)');
            } catch (e, stackTrace) {
              Global.logger.e('ASR: 执行监听器回调时出错: $e', stackTrace: stackTrace);
            }
          },
          onError: (error) {
            Global.logger
                .e('ASR: 事件通道错误: $error (subscriptionId=$subscriptionId)');
          },
          onDone: () {
            Global.logger
                .w('ASR: 事件流已关闭 (onDone, subscriptionId=$subscriptionId)');
          },
          cancelOnError: false,
        );
        Global.logger.i('ASR: 事件监听已重新绑定 ... 订阅ID: $subscriptionId');

        if (_eventSubscription != null) {
          if (_state != AsrState.started) {
            setState(AsrState.initialized);
          }
        }
      } catch (e, stackTrace) {
        Global.logger.e('ASR: 创建事件订阅时出错: $e', stackTrace: stackTrace);

        rethrow;
      }
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> startAsr(AsrLanguage language, {List<String>? phrases, bool playHintSound = true}) async {
    debugPrint('💡 [ASR] startAsr() 触发启动。目标语言: ${language.locale}，当前状态: $state，播放提示音: $playHintSound。');
    if (!PlatformUtils.isAsrSupported()) {
      ToastUtil.info("当前平台暂不支持语音识别功能");
      return;
    }

    if (_isStarting) {
      Global.logger.i('ASR: startAsr 正在执行中，等待完成 (instance: $hashCode)');
      return;
    }

    // 如果正在停止中，需要等待停止后再尝试启动
    if (state == AsrState.stopping) {
      Global.logger.w('ASR: ASR 正在停止中，等待停止完成后重试 (instance: $hashCode)');
      int waitCount = 0;
      while (state == AsrState.stopping && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      if (state == AsrState.stopping) {
        Global.logger.w('ASR: 等待 ASR 停止超时，放弃启动 (instance: $hashCode)');
        return;
      }
    }

    if (state == AsrState.started) {
      if (_currentLanguage == language) {
        Global.logger.i('ASR: ASR 已经以 ${language.locale} 启动，仅执行 Phrases 增量更新 (instance: $hashCode)');
        if (phrases != null) {
          await setContextualStrings(phrases);
        }
        return;
      } else {
        Global.logger.i('ASR: 正在运行中切换语言从 ${_currentLanguage?.locale} 到 ${language.locale}');
        await stopAsr();
      }
    }

    _isStarting = true;
    final swStart = Stopwatch()..start();
    debugPrint('⏱️ [Latency-ASR] startAsr 入口 (语言: ${language.locale})');
    try {
      await _checkAndRequestPermissions();

      if (permissionGranted) {
        try {
          if (phrases != null) {
            Global.logger.i('ASR: Setting contextual strings... (instance: $hashCode)');
            await setContextualStrings(phrases);
          }

          Global.logger
              .i('ASR: Updating language first... (instance: $hashCode)');
          await _updateLanguage(language);

          Global.logger.i('ASR: Starting microphone... (instance: $hashCode)');
          // 等待 loadData 中启动的引擎预热完成。若引擎已就绪（之前会话保活），
          // 此调用立即返回；若预热进行中，等待其完成以避免重复初始化。
          await awaitMicWarmup();
          await SoundUtil.usePlayAndRecordCategory();
          debugPrint('⏱️ [Latency-ASR] usePlayAndRecordCategory 完成: +${swStart.elapsedMilliseconds}ms');
           
          await asrMethodChannel
              .invokeMethod('startMicrophone')
              .timeout(const Duration(seconds: 5));
          debugPrint('⏱️ [Latency-ASR] startMicrophone 完成: +${swStart.elapsedMilliseconds}ms');

          Future<void>? hintFuture;
          if (playHintSound) {
            // 首次冷启动：AVAudioEngine 硬件首次激活需要稳定窗口，延迟 150ms
            // 避免提示音在音频 pipeline 未完全就绪时播放而不稳定。
            if (!_engineEverStarted) {
              await Future.delayed(const Duration(milliseconds: 150));
              _engineEverStarted = true;
            }
            hintFuture = SoundUtil.playAsrReadyHintSound();
          }

          Global.logger.i('ASR: Starting ASR... (instance: $hashCode)');
          final startTime = AppClock.now();
          await asrMethodChannel
              .invokeMethod('startAsr')
              .timeout(const Duration(seconds: 5));
          debugPrint('⏱️ [Latency-ASR] native startAsr 完成: +${swStart.elapsedMilliseconds}ms');
          final endTime = AppClock.now();

          if (hintFuture != null) {
            await hintFuture;
          }

          setState(AsrState.started);
          Global.logger.i(
              'ASR: ASR started successfully (instance: $hashCode, duration: ${endTime.difference(startTime).inMilliseconds}ms)');
        } on PlatformException catch (e) {
          Global.logger.e(
              'ASR: Exception during start: ${e.message} (instance: $hashCode)');
          if (e.code == 'PERMISSION_DENIED') {
            ToastUtil.error("权限被拒绝，请在设置中开启麦克风和语音识别权限");
          }
          // 不再在此处针对 iOS 强制设置 started，避免错误的状态显示
          setState(AsrState.unknown);
        }
      }
    } finally {
      _isStarting = false;
    }
  }

  /// 仅启动麦克风和音频引擎（Pre-warm），不启动 ASR 识别任务。
  /// 用于在进入学习页面时提前启动硬件，消除后续识别任务启动时的切换噪音。
  Future<void> startMicrophone() async {
    if (!PlatformUtils.isAsrSupported()) return;
    if (_isStarting ||
        state == AsrState.started ||
        state == AsrState.stopping) {
      return;
    }

    try {
      if (!permissionGranted) {
        await _checkAndRequestPermissions();
      }

      if (permissionGranted) {
        Global.logger.i('ASR: Pre-warming microphone... (instance: $hashCode)');
        await SoundUtil.usePlayAndRecordCategory();
        await asrMethodChannel
            .invokeMethod('startMicrophone')
            .timeout(const Duration(seconds: 5));
        _engineEverStarted = true;
      }
    } catch (e) {
      Global.logger
          .e('ASR: Pre-warm microphone failed: $e (instance: $hashCode)');
    }
  }

  /// 启动麦克风引擎预热并跟踪完成状态。若引擎已在预热中，返回已有的 Future；
  /// 若引擎已启动，直接返回。调用方应在 startAsr 前 await 以确保引擎就绪。
  Future<void> warmupMicrophone() async {
    if (_micWarmupCompleter != null && !_micWarmupCompleter!.isCompleted) {
      return _micWarmupCompleter!.future;
    }
    if (state == AsrState.started) return;

    _micWarmupCompleter = Completer<void>();
    try {
      await startMicrophone();
      if (!_micWarmupCompleter!.isCompleted) {
        _micWarmupCompleter!.complete();
      }
    } catch (e) {
      if (!_micWarmupCompleter!.isCompleted) {
        _micWarmupCompleter!.completeError(e);
      }
      _micWarmupCompleter = null;
    }
  }

  /// 等待引擎预热完成（若正在进行中）。
  /// 在 startAsr 调用 startMicrophone 前调用，确保引擎已就绪。
  /// 预热失败时不抛异常——startAsr 会走冷启动路径兜底。
  Future<void> awaitMicWarmup() async {
    if (_micWarmupCompleter != null && !_micWarmupCompleter!.isCompleted) {
      try {
        await _micWarmupCompleter!.future;
      } catch (_) {
        // warmup failed, engine will cold-start normally in startAsr
      }
      _micWarmupCompleter = null;
    }
  }

  Future<void> stopAsr() async {
    Global.logger.i('ASR: stopAsr() called (instance: $hashCode)');
    if (!PlatformUtils.isAsrSupported()) return;

    if (state == AsrState.stopped || state == AsrState.stopping) {
      Global.logger
          .w('ASR: ASR is already stopped or stopping (instance: $hashCode)');
      return;
    }

    setState(AsrState.stopping);
    final startTime = AppClock.now();
    try {
      await asrMethodChannel.invokeMethod('stopAsr');
      final endTime = AppClock.now();
      setState(AsrState.stopped);
      Global.logger.i(
          'ASR: ASR stopped successfully (instance: $hashCode, duration: ${endTime.difference(startTime).inMilliseconds}ms)');
    } on PlatformException catch (e) {
      Global.logger
          .e('ASR: Exception during stop: ${e.message} (instance: $hashCode)');
      setState(AsrState.stopped);
    }
  }

  /// 完全停止麦克风和 ASR 引擎（彻底关闭音频引擎）
  Future<void> stopMicrophone() async {
    debugPrint('💡 [ASR] stopMicrophone() 触发关停。当前状态: $state。');
    if (PlatformUtils.isWeb ||
        PlatformUtils.isWindows ||
        PlatformUtils.isMacOS) {
      return;
    }

    if (state == AsrState.stopped || state == AsrState.initialized || state == AsrState.unknown) {
      debugPrint('💡 [ASR] stopMicrophone() ASR 已经是停止/未启动状态 ($state)，仅确保音频分类为 playback');
      await SoundUtil.usePlaybackCategory();
      return;
    }
    if (state == AsrState.stopping) {
      debugPrint('💡 [ASR] stopMicrophone() ASR 正在停止中，避免重复关停重入。');
      return;
    }

    setState(AsrState.stopping);
    try {
      await asrMethodChannel.invokeMethod('stopMicrophone');
      setState(AsrState.stopped);
      Global.logger.i('ASR: Microphone and engine stopped successfully');
      await SoundUtil.usePlaybackCategory();
    } on PlatformException catch (e) {
      Global.logger.e('ASR: Exception during stopMicrophone: ${e.message}');
      setState(AsrState.stopped);
      await SoundUtil.usePlaybackCategory();
    }
  }

  /// 清空模型中当前的采样数据
  Future<void> reset() async {
    if (PlatformUtils.isWeb ||
        PlatformUtils.isWindows ||
        PlatformUtils.isMacOS) {
      return;
    }

    if (permissionGranted) {
      try {
        await asrMethodChannel.invokeMethod('reset');
      } on PlatformException catch (e) {
        ToastUtil.error("ASR异常6: '${e.message}'.");
      }
    }
  }

  // 为 iOS 提供上下文短语，提高目标短语的识别概率（仅提示，不强制）
  Future<void> setContextualStrings(List<String> phrases) async {
    if (PlatformUtils.isWeb || PlatformUtils.isWindows || PlatformUtils.isMacOS) {
      return;
    }
    if (!permissionGranted) return;
    try {
      await asrMethodChannel.invokeMethod('setContextualStrings', {
        'phrases': phrases,
      });
    } catch (e) {
      Global.logger.i('ASR setContextualStrings error: $e');
    }
  }
}
