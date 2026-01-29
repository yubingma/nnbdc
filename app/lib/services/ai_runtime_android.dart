import 'dart:async';
import 'package:flutter/services.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/services/ai_prompt_builder.dart';
import 'package:nnbdc/util/platform_util.dart';

class AndroidAiRuntime implements AiRuntime {
  static const MethodChannel _channel = MethodChannel('com.nnbdc.ai_inference');
  
  final String modelPath;
  AiCapabilityLevel _capability = AiCapabilityLevel.none;
  bool _isModelLoaded = false;
  final StreamController<String> _partialController = StreamController<String>.broadcast();

  Stream<String> get partialStream => _partialController.stream;

  AndroidAiRuntime({required this.modelPath}) {
    // 监听原生侧的增量输出回调，用于流式展示 AI 思考/回答过程
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPartialResult') {
        try {
          final args = call.arguments;
          String delta;
          if (args is Map) {
            delta = (args['text'] ?? '').toString();
          } else {
            delta = args?.toString() ?? '';
          }
          if (delta.isNotEmpty) {
            _partialController.add(delta);
          }
        } catch (e) {
          Global.logger.w('[AndroidAiRuntime] 处理部分结果失败: $e');
        }
      }
      return null;
    });
  }

  @override
  AiCapabilityLevel get capabilityLevel => _capability;
  
  /// 检查是否支持 AI (Android)
  static Future<bool> isSupported() async {
    if (!PlatformUtils.isAndroid) return false;
    
    try {
      // 检查Android设备是否支持AI推理（例如是否有足够的RAM等）
      final result = await _channel.invokeMethod('checkCapability');
      if (result is Map) {
        final capStr = result['capability'] as String?;
        return capStr != 'none';
      }
      return false;
    } catch (e) {
      Global.logger.w('[AndroidAiRuntime] 能力检测失败: $e');
      return false;
    }
  }

  /// 初始化运行时：检查能力 + 加载模型
  Future<bool> initialize() async {
    try {
      // 0. 检查设备兼容性
      final supported = await isSupported();
      if (!supported) {
        Global.logger.w('[AndroidAiRuntime] ⚠️ 当前设备不支持本地 AI 功能');
        _capability = AiCapabilityLevel.none;
        return false;
      }

      // 1. 检查设备能力
      final capResult = await _channel.invokeMethod('checkCapability');
      if (capResult is Map) {
        final capStr = capResult['capability'] as String?;
        if (capStr == 'full') {
          _capability = AiCapabilityLevel.full;
        } else if (capStr == 'light') {
          _capability = AiCapabilityLevel.light;
        } else {
          _capability = AiCapabilityLevel.none;
        }
        Global.logger.i('Android AI 能力: $_capability, 内存: ${capResult['memoryGB']} GB');
      }

      if (_capability == AiCapabilityLevel.none) {
        Global.logger.w('[AndroidAiRuntime] ⚠️ 设备能力报告不足，但将尝试继续初始化...');
        // 允许继续尝试加载模型，即使能力检测为 none
      }

      // 2. 加载模型
      final loadResult = await _channel.invokeMethod('loadModel', {
        'modelPath': modelPath,
      });

      if (loadResult is Map && loadResult['success'] == true) {
        _isModelLoaded = true;
        Global.logger.i('Android AI 模型加载成功: $modelPath');
        return true;
      } else {
        Global.logger.w('Android AI 模型加载失败');
        return false;
      }
    } catch (e, st) {
      Global.logger.e('Android AI 初始化失败', error: e, stackTrace: st);
      return false;
    }
  }

  @override
  Future<AiResponse> runTask(AiRequest request) async {
    if (!_isModelLoaded) {
      return AiResponse.error('模型未加载');
    }

    try {
      // 1. 使用 AiPromptBuilder 构建完整 prompt
      final prompt = AiPromptBuilder.buildPrompt(request);
      Global.logger.d('Android AI 推理 prompt 长度: ${prompt.length}');

      // 2. 调用原生层推理
      final result = await _channel.invokeMethod('inference', {
        'prompt': prompt,
        'maxTokens': 2048,
        'temperature': 0.7,
        'stop': ['\u1010', '', '\u1011'],
      });

      if (result is Map && result['success'] == true) {
        final text = result['text'] as String? ?? '';
        final tokensGenerated = result['tokensGenerated'] as int? ?? 0;
        final inferenceTimeMs = result['inferenceTimeMs'] as int? ?? 0;
        
        Global.logger.i('Android AI 推理完成: $tokensGenerated tokens, ${inferenceTimeMs}ms');
        return AiResponse.ok(text);
      } else {
        return AiResponse.error('推理失败');
      }
    } catch (e, st) {
      Global.logger.e('Android AI 推理异常', error: e, stackTrace: st);
      return AiResponse.error('推理异常: $e');
    }
  }

  /// 卸载模型
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('unloadModel');
      _isModelLoaded = false;
      Global.logger.i('Android AI 模型已卸载');
    } catch (e) {
      Global.logger.w('Android AI 模型卸载失败: $e');
    }
  }
}