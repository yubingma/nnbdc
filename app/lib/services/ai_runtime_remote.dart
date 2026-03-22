import 'dart:async';
import 'dart:convert';

import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/ai_service.dart';

class RemoteAiRuntime implements AiRuntime {
  @override
  AiCapabilityLevel get capabilityLevel => AiCapabilityLevel.full;

  final StreamController<String> _partialController = StreamController<String>.broadcast();

  @override
  Stream<String> get partialStream => _partialController.stream;

  @override
  Future<AiResponse> runTask(AiRequest request) async {
    try {
      if (request.type == AiTaskType.explainWord) {
        // Need to convert explainWord payload to messages
        final payload = request.payload;
        final spell = (payload['spell'] ?? '').toString();
        final meanings = payload['meanings'] as List<dynamic>? ?? [];
        final sysPrompt = '你是一名英语单词助教, 主要用中文和学生交流, 尽量不啰嗦。\n你的任务是针对学生正在学习的单词，通过一些手段帮助他记忆, 比如：\n1. 近义词/反义词拓展\n2. 词根分析和同根词拓展\n不需要给学生出题。';
        final userPrompt = '请帮助我学习单词: "$spell"。释义为: ${jsonEncode(meanings)}';
        
        final messages = [
          {'role': 'system', 'content': sysPrompt},
          {'role': 'user', 'content': userPrompt}
        ];
        
        final res = await Api.client.aiChat(jsonEncode(messages));
        if (res.success && res.data != null) {
          final text = res.data!;
          _partialController.add(text);
          return AiResponse.ok(text);
        } else {
          return AiResponse.error(res.msg ?? '远程服务异常');
        }
      } else if (request.type == AiTaskType.chat) {
        final messages = request.payload['messages'] as List<dynamic>? ?? [];
        final res = await Api.client.aiChat(jsonEncode(messages));
        if (res.success && res.data != null) {
          final text = res.data!;
          _partialController.add(text);
          return AiResponse.ok(text);
        } else {
          return AiResponse.error(res.msg ?? '远程服务异常');
        }
      }
      return AiResponse.error('未支持的远程任务');
    } catch (e) {
      Global.logger.e('远程 AI 请求失败: $e');
      return AiResponse.error('远程服务失败: $e');
    }
  }
}
