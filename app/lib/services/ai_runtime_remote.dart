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
        final sysPrompt = '你是一名顶级英语外教。请帮学生巧记单词。\n'
            '核心要求：\n'
            '0. 必须全程中文解答！\n'
            '1. 极度精简（80字以内），拒绝一切开场白。**严禁在结尾增加任何引导性提问或社交客套，说完即止。**\n'
            '2. 长难词：直接拆解词根词缀，给出一句极其有趣的“串记法”。\n'
            '3. 基础词：只教1个地道神仙搭配/俚语。不要讲原理。\n'
            '4. 视觉简洁：适度使用图标，不要过度堆叠。';
        final userPrompt = '单词: "$spell"，释义: ${jsonEncode(meanings)}';
        
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
            'content': '你是一名懂语言学、极度精简的英语外教。请回答极其简练，**严禁在结尾附带任何引导性语句、追问或社交客套**，仅针对提问直面要点，说完即止。'
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
