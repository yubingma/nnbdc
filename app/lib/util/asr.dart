import 'dart:async';
import 'package:flutter/services.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:io' show Platform;

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

  /// 标记是否正在执行 startAsr，避免并发的 start/stop 调用打架
  bool _isStarting = false;

  /// 标记是否正在初始化事件监听，避免并发初始化
  bool _isInitializing = false;

  /// 标记订阅是否应该被保护，防止在初始化后立即被取消
  bool _subscriptionProtected = false;

  /// ASR 结果事件订阅，用于在页面销毁或重新初始化时正确取消订阅，
  /// 避免多个已失效的监听器继续处理结果，导致目标单词长期停留在旧值
  StreamSubscription? _eventSubscription;



  /// Meter 流订阅，使用单例模式避免重复订阅导致 iOS 端报错
  StreamSubscription<double>? _meterSubscription;

  AsrState get state => _state;
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

  void dispose() {
    Global.logger.d('ASR: dispose() 被调用，取消事件订阅');
    // 如果正在初始化，等待初始化完成
    if (_isInitializing) {
      Global.logger.w('ASR: 警告：在初始化过程中调用 dispose()，等待初始化完成');
      // 等待初始化完成（最多等待 1 秒）
      int waitCount = 0;
      while (_isInitializing && waitCount < 20) {
        Future.delayed(const Duration(milliseconds: 50));
        waitCount++;
      }
    }
    _disposed = true;
    _stateListeners.clear();
    _subscriptionProtected = false; // 清除保护标记
    if (_subscriptionProtected) {
      Global.logger.w('ASR: 警告：在订阅保护期内调用 dispose()');
    }
    _eventSubscription?.cancel();
    _eventSubscription = null;

    // 清理 meter 订阅
    disposeMeter();
  }

  Future<void> _updateLanguage(AsrLanguage language) async {
    if (!PlatformUtils.isAsrSupported()) {
      return;
    }

    try {
      Global.logger.i('ASR: 设置语言为: ${language.locale}');
      await asrMethodChannel.invokeMethod('setLanguage', {'locale': language.locale}).timeout(const Duration(seconds: 5));
      Global.logger.i('ASR: 语言设置成功');
    } on PlatformException catch (e) {
      Global.logger.i('ASR: 设置语言失败: ${e.message}');
    } on TimeoutException catch (_) {
      Global.logger.w('ASR: 设置语言超时');
    }
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

  /// 弹出系统权限申请对话框，请求麦克风和语音识别权限
  Future<bool> _requestPermissions() async {
    if (!PlatformUtils.isAsrSupported()) {
      return false;
    }

    if (Platform.isIOS) {
      try {
        bool granted = await asrMethodChannel.invokeMethod('requestPermissions');
        return granted;
      } catch (e) {
        Global.logger.i('请求权限失败: $e');
        return false;
      }
    } else {
      // Android使用permission_handler
      var status = await Permission.microphone.request();
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
      // 弹出系统权限申请对话框，请求麦克风和语音识别权限
      bool granted = await _requestPermissions();
      if (!granted) {
        // 处理权限被拒绝的情况
        bool success = await _handlePermissionDenied();
        if (success) {
          Global.logger.i('ASR: 权限最终获取成功');
        }
        return;
      }
    }

    permissionGranted = true;
    Global.logger.i('ASR: 麦克风和语音识别权限获取成功');
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

    bool? result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('权限申请'),
        content: Text(Platform.isIOS ? '需要麦克风和语音识别权限来进行发音练习' : '需要麦克风权限来进行语音识别和发音练习'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Get.back(result: true);
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
    // 如果已经有订阅，直接返回现有的流（通过检查订阅是否存在）
    // 注意：这里无法直接返回已存在的 Stream，所以采用延迟初始化的方式
    // 调用方应该只调用一次 meterStream() 并保存订阅
    _meterStreamCache ??= asrMeterChannel
        .receiveBroadcastStream('nnbdc/asr_meter')
        .map((event) => (event as num).toDouble())
        .handleError((e) => Global.logger.i('ASR meter error: $e'))
        .asBroadcastStream(); // 确保它作为广播流可以被多次监听
    return _meterStreamCache!;
  }

  /// 获取或创建 meter 订阅，确保全局只有一个有效的 meter 订阅
  StreamSubscription<double> getOrCreateMeterSubscription(void Function(double level) onLevel) {
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
      Global.logger.w('ASR: initAsr 跳过，当前状态为: $_state, isInitializing=$_isInitializing, isStarting=$_isStarting');
      return;
    }
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
      _subscriptionProtected = false;



      if (oldSubscription != null) {
        await oldSubscription.cancel();
      }

      try {
        final stream = asrEventChannel.receiveBroadcastStream();
        final subscriptionId = DateTime.now().millisecondsSinceEpoch;
        final savedListener = asrListener;

        _eventSubscription = stream.listen(
          (event) {
            try {
              savedListener(event);
            } catch (e, stackTrace) {
              Global.logger.e('ASR: 执行监听器回调时出错: $e', stackTrace: stackTrace);
            }
          },
          onError: (error) {
            Global.logger.e('ASR: 事件通道错误: $error (subscriptionId=$subscriptionId)');
          },
          onDone: () {
            Global.logger.w('ASR: 事件流已关闭 (onDone, subscriptionId=$subscriptionId)');
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

  Future<void> startAsr(AsrLanguage language) async {
    if (!PlatformUtils.isAsrSupported()) {
      ToastUtil.info("当前平台暂不支持语音识别功能");
      return;
    }

    if (_isStarting) {
      Global.logger.i('ASR: startAsr 正在执行中，等待完成 (instance: $hashCode)');
      return;
    }

    if (state == AsrState.started) {
      Global.logger.w('ASR: ASR 已经处于 started 状态 (instance: $hashCode)');
      return;
    }

    _isStarting = true;
    try {
      await _checkAndRequestPermissions();

      if (permissionGranted) {
        try {
          Global.logger.i('ASR: Updating language first... (instance: $hashCode)');
          await _updateLanguage(language);

          Global.logger.i('ASR: Starting microphone... (instance: $hashCode)');
          await asrMethodChannel.invokeMethod('startMicrophone').timeout(const Duration(seconds: 5));

          Global.logger.i('ASR: Starting ASR... (instance: $hashCode)');
          await asrMethodChannel.invokeMethod('startAsr').timeout(const Duration(seconds: 5));

          setState(AsrState.started);
          Global.logger.i('ASR: ASR started successfully (instance: $hashCode)');
        } on PlatformException catch (e) {
          Global.logger.e('ASR: Exception during start: ${e.message} (instance: $hashCode)');
          if (e.code == 'PERMISSION_DENIED') {
            ToastUtil.error("权限被拒绝，请在设置中开启麦克风和语音识别权限");
          } else {
            if (Platform.isIOS) {
              setState(AsrState.started);
            }
          }
        }
      }
    } finally {
      _isStarting = false;
    }
  }

  Future<void> stopAsr() async {
    Global.logger.i('ASR: stopAsr() called (instance: $hashCode)');
    if (!PlatformUtils.isAsrSupported()) return;

    if (state == AsrState.stopped || state == AsrState.stopping) {
      Global.logger.w('ASR: ASR is already stopped or stopping (instance: $hashCode)');
      return;
    }

    setState(AsrState.stopping);
    try {
      await asrMethodChannel.invokeMethod('stopAsr');
      setState(AsrState.stopped);
      Global.logger.i('ASR: ASR stopped successfully (instance: $hashCode)');
    } on PlatformException catch (e) {
      Global.logger.e('ASR: Exception during stop: ${e.message} (instance: $hashCode)');
      setState(AsrState.stopped);
    }
  }

  /// 清空模型中当前的采样数据
  Future<void> reset() async {
    if (PlatformUtils.isWeb || PlatformUtils.isWindows || PlatformUtils.isMacOS) {
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
    if (PlatformUtils.isWeb || PlatformUtils.isWindows || PlatformUtils.isMacOS) return;
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
