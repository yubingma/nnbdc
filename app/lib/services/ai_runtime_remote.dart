import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/util/loading_utils.dart';

class RemoteAiRuntime implements AiRuntime {
  @override
  AiCapabilityLevel get capabilityLevel => AiCapabilityLevel.full;

  final StreamController<String> _partialController = StreamController<String>.broadcast();

  @override
  Stream<String> get partialStream => _partialController.stream;

  Future<AiResponse> _streamChat(List<Map<String, String>> messages) async {
    try {
      final baseUrl = Api.useProdUrl
          ? Config.profiles["prod"]["service_url"]
          : Config.serviceUrl;
      final url = '$baseUrl/admin/aiChatStream.do';

      final response = await LoadingUtils.withoutApiLoading(() async {
        return await Api.dio.post<ResponseBody>(
          url,
          data: {
            'messagesJson': jsonEncode(messages),
          },
          options: Options(
            responseType: ResponseType.stream,
            contentType: Headers.formUrlEncodedContentType,
          ),
        );
      });

      final stream = response.data!.stream;
      final completer = Completer<AiResponse>();
      String allText = '';

      stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          if (line.startsWith('data:')) {
            final dataStr = line.substring(5).trim();
            if (dataStr.isEmpty) return;
            try {
              final json = jsonDecode(dataStr);
              if (json['success'] == true) {
                final text = json['data'] as String;
                allText += text;
                _partialController.add(text);
              } else if (json['success'] == false) {
                if (!completer.isCompleted) {
                  completer.complete(AiResponse.error(json['msg'] ?? 'AI 服务异常'));
                }
              }
            } catch (e) {
              // ignore partial json parse error if chunked incorrectly
            }
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(AiResponse.ok(allText));
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.complete(AiResponse.error('流出错了: $e'));
          }
        },
        cancelOnError: true,
      );

      return await completer.future;
    } catch (e) {
      Global.logger.e('远程 AI 流式请求失败: $e');
      return AiResponse.error('远程服务失败: $e');
    }
  }

  @override
  Future<AiResponse> runTask(AiRequest request) async {
    try {
      if (request.type == AiTaskType.explainWord) {
        // Need to convert explainWord payload to messages
        final payload = request.payload;
        final spell = (payload['spell'] ?? '').toString();
        final meanings = payload['meanings'] as List<dynamic>? ?? [];
        final sysPrompt = '你是一名只讲干货、极其精简的英语助教。\n请你严格遵守以下原则：\n1. 语言必须高度凝练，总字数严格控制在 150 字以内。\n2. 重点提供1-2个核心记忆法（如词根词源、谐音、串记），没有特殊词根的词一句带过即可，绝对不要科普长篇学术背景。\n3. 可补充2~3个最常见的近义词或反义词。\n4. 不要使用 Markdown 表格，少用长句子，多用精简的短列项目。';
        final userPrompt = '请帮助我学习单词: "$spell"。释义为: ${jsonEncode(meanings)}';
        
        final messages = [
          {'role': 'system', 'content': sysPrompt},
          {'role': 'user', 'content': userPrompt}
        ];
        
        return await _streamChat(messages);
      } else if (request.type == AiTaskType.chat) {
        final messagesRaw = request.payload['messages'] as List<dynamic>? ?? [];
        final messages = messagesRaw.map((e) => {'role': e['role'].toString(), 'content': e['content'].toString()}).toList();
        
        // 确保后续的多轮问答也遵守精简原则，防止大模型放飞自我
        if (messages.isEmpty || messages.first['role'] != 'system') {
          messages.insert(0, {
            'role': 'system',
            'content': '你是一名英语单词助教，请在对话中保持极其精简、干货居多的回答风格，多用短句，绝对不啰嗦科普冗长学术背景。'
          });
        }
        
        return await _streamChat(messages);
      }
      return AiResponse.error('未支持的远程任务');
    } catch (e) {
      Global.logger.e('远程 AI 请求失败: $e');
      return AiResponse.error('远程服务失败: $e');
    }
  }
}
