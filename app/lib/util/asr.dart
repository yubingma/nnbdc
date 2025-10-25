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
  var asrMethodChannel = MethodChannel('nnbdc/asr_commands');
  var asrEventChannel = EventChannel('nnbdc/asr_events');
  var asrMeterChannel = EventChannel('nnbdc/asr_meter');

  bool permissionGranted = false;
  AsrState _state = AsrState.unknown;
  final List<Function(AsrState)> _stateListeners = [];
  bool _disposed = false;

  AsrState get state => _state;
  setState(AsrState newState) {
    Global.logger.d('===== ASR: State change: $_state => $newState');
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
    _disposed = true;
    _stateListeners.clear();
  }

  Future<void> _updateLanguage(AsrLanguage language) async {
    if (!PlatformUtils.isAsrSupported()) {
      return;
    }

    try {
      Global.logger.d('===== ASR: 设置语言为: ${language.locale}');
      await asrMethodChannel.invokeMethod('setLanguage', {'locale': language.locale});
      Global.logger.d('===== ASR: 语言设置成功');
    } on PlatformException catch (e) {
      Global.logger.d('===== ASR: 设置语言失败: ${e.message}');
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
        Global.logger.d('检查权限失败: $e');
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
        Global.logger.d('请求权限失败: $e');
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
    Global.logger.d('===== ASR: Permission denied, showing settings dialog...');
    // 直接显示设置对话框，因为系统不会再次弹出权限请求
    bool shouldRequest = await _showPermissionDialog();
    if (!shouldRequest) {
      Global.logger.d('===== ASR: 用户取消权限请求');
      return false;
    }
    // 用户选择去设置后，延迟检查权限状态
    await Future.delayed(Duration(seconds: 2));
    bool finalCheck = await _checkPermissions();
    if (finalCheck) {
      permissionGranted = true;
      Global.logger.d('===== ASR: 权限最终获取成功');
      return true;
    } else {
      Global.logger.d('===== ASR: 在等待时间内, 未能获取到授权');
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
          Global.logger.d('===== ASR: 权限最终获取成功');
        }
        return;
      }
    }

    permissionGranted = true;
    Global.logger.d('===== ASR: 麦克风和语音识别权限获取成功');
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
        Global.logger.d('检查模拟器状态失败: $e');
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
        .handleError((e) => Global.logger.d('ASR meter error: $e'));
  }

  Future<void> initAsr(void Function(dynamic asrResult)? asrListener) async {
    if (!PlatformUtils.isAsrSupported()) {
      return;
    }

    // 先设置事件监听器，避免权限检查失败时无法接收结果
    asrEventChannel.receiveBroadcastStream().listen(asrListener!);
    setState(AsrState.initialized);
  }

  Future<void> startAsr(AsrLanguage language) async {
    if (!PlatformUtils.isAsrSupported()) {
      ToastUtil.info("当前平台暂不支持语音识别功能");
      return;
    }

    if (state == AsrState.started) {
      Global.logger.w('===== ASR: ASR is already started');
      return;
    }
    Global.logger.d('===== ASR: Starting ASR...');

    await _checkAndRequestPermissions();

    if (permissionGranted) {
      try {
        // 先设置识别语言，再启动麦克风
        Global.logger.d('===== ASR: Updating language first...');
        await _updateLanguage(language);

        Global.logger.d('===== ASR: Starting microphone...');
        await asrMethodChannel.invokeMethod('startMicrophone');

        Global.logger.d('===== ASR: Starting ASR...');
        await asrMethodChannel.invokeMethod('startAsr');

        setState(AsrState.started);
        Global.logger.d('===== ASR: ASR started successfully');

        // 播放启动提示音
        try {
          await SoundUtil.playAssetSound('asr_hint.mp3', 1.3, 1.0);
        } catch (e) {
          Global.logger.d('播放ASR启动提示音失败: $e');
        }
      } on PlatformException catch (e) {
        Global.logger.d('===== ASR: Exception during start: ${e.message}');
        if (e.code == 'PERMISSION_DENIED') {
          ToastUtil.error("权限被拒绝，请在设置中开启麦克风和语音识别权限");
        } else {
          ToastUtil.error("语音识别启动失败: ${e.message}");
        }
      }
    }
  }

  Future<void> stopAsr() async {
    if (PlatformUtils.isWeb || PlatformUtils.isWindows || PlatformUtils.isMacOS) {
      return;
    }

    if (permissionGranted) {
      try {
        Global.logger.d('===== ASR: Stopping ASR...');
        setState(AsrState.stopping);
        await asrMethodChannel.invokeMethod('stopAsr');
        setState(AsrState.stopped);
        Global.logger.d('===== ASR: ASR stopped successfully');
      } on PlatformException catch (e) {
        Global.logger.d('===== ASR: Exception during stop: ${e.message}');
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
      Global.logger.d('ASR setContextualStrings error: $e');
    }
  }
}
