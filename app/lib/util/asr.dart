import 'dart:async';
import 'package:flutter/services.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/sound.dart';
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

  /// 当前的事件监听器回调函数，用于在事件回调中正确调用
  void Function(dynamic)? _currentAsrListener;

  AsrState get state => _state;
  setState(AsrState newState) {
    Global.logger.i('===== ASR: State change: $_state => $newState');
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
    Global.logger.d('===== ASR: dispose() 被调用，取消事件订阅');
    // 如果正在初始化，等待初始化完成
    if (_isInitializing) {
      Global.logger.w('===== ASR: 警告：在初始化过程中调用 dispose()，等待初始化完成');
      // 等待初始化完成（最多等待1秒）
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
      Global.logger.w('===== ASR: 警告：在订阅保护期内调用 dispose()');
    }
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _currentAsrListener = null;
  }

  Future<void> _updateLanguage(AsrLanguage language) async {
    if (!PlatformUtils.isAsrSupported()) {
      return;
    }

    try {
      Global.logger.i('===== ASR: 设置语言为: ${language.locale}');
      await asrMethodChannel.invokeMethod('setLanguage', {'locale': language.locale});
      Global.logger.i('===== ASR: 语言设置成功');
    } on PlatformException catch (e) {
      Global.logger.i('===== ASR: 设置语言失败: ${e.message}');
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
    Global.logger.i('===== ASR: Permission denied, showing settings dialog...');
    // 直接显示设置对话框，因为系统不会再次弹出权限请求
    bool shouldRequest = await _showPermissionDialog();
    if (!shouldRequest) {
      Global.logger.i('===== ASR: 用户取消权限请求');
      return false;
    }
    // 用户选择去设置后，延迟检查权限状态
    await Future.delayed(Duration(seconds: 2));
    bool finalCheck = await _checkPermissions();
    if (finalCheck) {
      permissionGranted = true;
      Global.logger.i('===== ASR: 权限最终获取成功');
      return true;
    } else {
      Global.logger.i('===== ASR: 在等待时间内, 未能获取到授权');
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
          Global.logger.i('===== ASR: 权限最终获取成功');
        }
        return;
      }
    }

    permissionGranted = true;
    Global.logger.i('===== ASR: 麦克风和语音识别权限获取成功');
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

  Stream<double> meterStream() {
    return asrMeterChannel
        .receiveBroadcastStream('nnbdc/asr_meter')
        .map((event) => (event as num).toDouble())
        .handleError((e) => Global.logger.i('ASR meter error: $e'));
  }

  /// 初始化语音识别事件监听
  Future<void> initAsr(void Function(dynamic asrResult)? asrListener) async {
    if (_isInitializing) {
      Global.logger.w('===== ASR: initAsr 正在执行中，等待完成...');
      return;
    }
    _isInitializing = true;

    if (!PlatformUtils.isAsrSupported()) {
      _isInitializing = false;
      return;
    }

    if (asrListener == null) {
      Global.logger.w('===== ASR: initAsr 被调用，但 asrListener 为 null，跳过初始化');
      _isInitializing = false;
      return;
    }

    try {
      // 先设置事件监听器，避免权限检查失败时无法接收结果
      // 如果之前已经有订阅，先取消，保证始终只有一个有效监听器
      Global.logger.i('===== ASR: 重新初始化事件监听，取消旧订阅');
      final oldSubscription = _eventSubscription;
      _eventSubscription = null;
      _subscriptionProtected = false; // 清除旧的保护标记

      // 保存当前监听器引用，确保在回调中能正确调用
      _currentAsrListener = asrListener;

      // 取消旧订阅并等待完全取消
      if (oldSubscription != null) {
        await oldSubscription.cancel();
      }


      try {
        final stream = asrEventChannel.receiveBroadcastStream();

        // 创建一个包装的监听器，确保即使 _currentAsrListener 被改变，也能正确处理事件
        final subscriptionId = DateTime.now().millisecondsSinceEpoch;
        final savedListener = asrListener; // 保存当前监听器的引用

        _eventSubscription = stream.listen(
          (event) {
            // 使用保存的监听器（在创建订阅时已确保不为 null）
            try {
              savedListener(event);
            } catch (e, stackTrace) {
              Global.logger.e('===== ASR: 执行监听器回调时出错: $e', stackTrace: stackTrace);
            }
          },
          onError: (error) {
            Global.logger.e('===== ASR: 事件通道错误: $error (subscriptionId=$subscriptionId)');
          },
          onDone: () {
            Global.logger.w('===== ASR: 事件流已关闭 (onDone, subscriptionId=$subscriptionId)');
            // 如果当前订阅被关闭，清空引用
            if (_eventSubscription != null && _eventSubscription.hashCode == subscriptionId) {
              Global.logger.w('===== ASR: 清空事件订阅引用 (subscriptionId=$subscriptionId)');
              _eventSubscription = null;
            }
          },
          cancelOnError: false,
        );
        Global.logger.i(
            '===== ASR: 事件监听已重新绑定，监听器状态: ${_currentAsrListener != null ? "有效" : "无效"}，订阅状态: ${_eventSubscription != null ? "已创建" : "未创建"}，订阅ID: $subscriptionId');

        // 验证订阅是否真正建立（通过检查订阅状态）
        if (_eventSubscription != null) {
          // 在事件订阅创建成功后立即设置 initialized 状态
          // 注意：如果当前已经是 started 状态，说明 startAsr 已经在运行，不应该再改回 initialized
          if (_state != AsrState.started) {
            setState(AsrState.initialized);
          }

          // 标记订阅为受保护状态，防止在初始化后立即被取消
          _subscriptionProtected = true;
          // 取消保护标记
          _subscriptionProtected = false;
        } else {
          Global.logger.e('===== ASR: 警告：事件订阅创建失败，_eventSubscription 为 null');
          // 如果订阅创建失败，也设置 initialized（或者保持当前状态）
          if (_state != AsrState.started) {
            setState(AsrState.initialized);
          }
        }
      } catch (e, stackTrace) {
        Global.logger.e('===== ASR: 创建事件订阅时出错: $e', stackTrace: stackTrace);
        _currentAsrListener = null;
        rethrow;
      }
      // 注意：状态已经在事件订阅创建成功后设置，这里不需要再次设置
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> startAsr(AsrLanguage language) async {
    if (!PlatformUtils.isAsrSupported()) {
      ToastUtil.info("当前平台暂不支持语音识别功能");
      return;
    }

    // 如果已经在启动流程中，等待之前的启动完成（最多等待2秒）
    if (_isStarting) {
      Global.logger.i('===== ASR: startAsr called while another start is in progress, waiting...');
      int waitCount = 0;
      while (_isStarting && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      if (_isStarting) {
        Global.logger.w('===== ASR: Previous start is still in progress after waiting, skipping this start');
        return;
      }
      // 如果之前的启动已经完成，检查当前状态
      if (state == AsrState.started) {
        Global.logger.i('===== ASR: Previous start completed, ASR is already started');
        return;
      }
    }

    if (state == AsrState.started) {
      Global.logger.w('===== ASR: ASR is already started');
      return;
    }
    Global.logger.i('===== ASR: Starting ASR...');

    _isStarting = true;
    try {
      await _checkAndRequestPermissions();

      if (permissionGranted) {
        try {
          // 先播放启动提示音，让用户知道可以开始说话了（不等待播放完成）
          // 这样可以减少单词播放完成到提示音之间的间隔
          SoundUtil.playAssetSound('asr_ready_hint.mp3', 1.3, 1.0).catchError((e) {
            Global.logger.i('播放ASR启动提示音失败: $e');
          });

          // 先设置识别语言，再启动麦克风
          Global.logger.i('===== ASR: Updating language first...');
          await _updateLanguage(language);

          Global.logger.i('===== ASR: Starting microphone...');
          await asrMethodChannel.invokeMethod('startMicrophone');

          Global.logger.i('===== ASR: Starting ASR...');
          await asrMethodChannel.invokeMethod('startAsr');

          setState(AsrState.started);
          Global.logger.i('===== ASR: ASR started successfully');
        } on PlatformException catch (e) {
          Global.logger.e('===== ASR: Exception during start: code=${e.code}, message=${e.message}');
          // iOS 上有时会在识别已经启动或短暂异常时抛出错误，但实际仍然可以正常识别
          // 为避免误导用户，仅在明确是权限问题时提示错误，其它情况只做轻量提示或记录日志
          if (e.code == 'PERMISSION_DENIED') {
            ToastUtil.error("权限被拒绝，请在设置中开启麦克风和语音识别权限");
          } else {
            // 如果已经拿到权限，说明很可能是「正在运行」等非致命错误
            if (!permissionGranted) {
              ToastUtil.error("语音识别启动失败: ${e.message}");
            } else {
              ToastUtil.info("语音识别已在运行，可直接说出答案");
            }
          }
        }
      }
    } finally {
      _isStarting = false;
    }
  }

  Future<void> stopAsr() async {
    if (PlatformUtils.isWeb || PlatformUtils.isWindows || PlatformUtils.isMacOS) {
      return;
    }

    // 如果正在启动流程中，等待启动完成后再停止（最多等待2秒）
    if (_isStarting) {
      Global.logger.i('===== ASR: stopAsr called while starting, waiting for start to complete...');
      int waitCount = 0;
      while (_isStarting && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      if (_isStarting) {
        Global.logger.w('===== ASR: Start is still in progress after waiting, forcing stop');
        // 强制重置 _isStarting，避免卡死
        _isStarting = false;
      }
    }

    if (permissionGranted) {
      try {
        Global.logger.i('===== ASR: Stopping ASR...');
        setState(AsrState.stopping);
        await asrMethodChannel.invokeMethod('stopAsr');
        setState(AsrState.stopped);
        Global.logger.i('===== ASR: ASR stopped successfully');
      } on PlatformException catch (e) {
        Global.logger.i('===== ASR: Exception during stop: ${e.message}');
        ToastUtil.error("ASR异常: '${e.message}'.");
      }
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
