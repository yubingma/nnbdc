import 'package:flutter/services.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/services/ai_prompt_builder.dart';

class MacOsAiRuntime implements AiRuntime {
  static const MethodChannel _channel = MethodChannel('com.nnbdc.ai_inference');
  
  final String modelPath;
  AiCapabilityLevel _capability = AiCapabilityLevel.none;
  bool _isModelLoaded = false;

  MacOsAiRuntime({required this.modelPath});

  @override
  AiCapabilityLevel get capabilityLevel => _capability;

  /// 初始化运行时：检查能力 + 加载模型
  Future<bool> initialize() async {
    try {
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
        Global.logger.i('macOS AI 能力: $_capability, 内存: ${capResult['memoryGB']} GB');
      }

      if (_capability == AiCapabilityLevel.none) {
        Global.logger.w('设备能力不足，无法运行本地 AI 模型');
        return false;
      }

      // 2. 加载模型
      final loadResult = await _channel.invokeMethod('loadModel', {
        'modelPath': modelPath,
      });

      if (loadResult is Map && loadResult['success'] == true) {
        _isModelLoaded = true;
        Global.logger.i('macOS AI 模型加载成功: $modelPath');
        return true;
      } else {
        Global.logger.w('macOS AI 模型加载失败');
        return false;
      }
    } catch (e, st) {
      Global.logger.e('macOS AI 初始化失败', error: e, stackTrace: st);
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
      Global.logger.d('macOS AI 推理 prompt 长度: ${prompt.length}');

      // 2. 调用原生层推理
      final result = await _channel.invokeMethod('inference', {
        'prompt': prompt,
        'maxTokens': 512,
        'temperature': 0.7,
      });

      if (result is Map && result['success'] == true) {
        final text = result['text'] as String? ?? '';
        final tokensGenerated = result['tokensGenerated'] as int? ?? 0;
        final inferenceTimeMs = result['inferenceTimeMs'] as int? ?? 0;
        
        Global.logger.i('macOS AI 推理完成: $tokensGenerated tokens, ${inferenceTimeMs}ms');
        return AiResponse.ok(text);
      } else {
        return AiResponse.error('推理失败');
      }
    } catch (e, st) {
      Global.logger.e('macOS AI 推理异常', error: e, stackTrace: st);
      return AiResponse.error('推理异常: $e');
    }
  }

  /// 卸载模型
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('unloadModel');
      _isModelLoaded = false;
      Global.logger.i('macOS AI 模型已卸载');
    } catch (e) {
      Global.logger.w('macOS AI 模型卸载失败: $e');
    }
  }
}
