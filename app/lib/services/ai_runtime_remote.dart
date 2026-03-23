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
        final sysPrompt = '你是一名极其专业、懂语言学的英语讲师。所有回答务必极度精简，控制在150字内。\n'
            '核心要求（根据难度千人千面）：\n'
            '1. 若为非常简单的基础词（如cat, get）：严禁拆词根或强行瞎串谐音！请直接给2个母语者最爱用的【地道短语/俚语/常用词块】，帮学生拓展真实语感体验。\n'
            '2. 若为中高阶长单词：精准拆解【词根词缀】+ 给出极其生动有趣的【一句话场景记忆法/情境串记】。\n'
            '3. 如果有经典的中式英语（Chinglish）误用雷区，可补充1句话指正。\n'
            '4. 语言幽默犀利，多用短列和Emoji，严禁长篇大论背课文。请直接进入正题！';
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
            'content': '你是一名懂语言学、极度精简的英语外教。请在接下来的问答中保持幽默、犀利且极度简练的风格，多用Emoji排版。坚决不扯闲篇、不啰嗦长篇学术背景，严格将回答字数压缩在重点内。'
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
