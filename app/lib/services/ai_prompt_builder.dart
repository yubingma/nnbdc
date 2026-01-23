import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/global.dart';

/// 统一的 Prompt 构建器，方案 A：在 Dart 侧一次性拼好完整 prompt
class AiPromptBuilder {
  /// 根据 AiRequest 构造适合小模型的完整 prompt 文本
  static String buildPrompt(AiRequest request) {
    switch (request.type) {
      case AiTaskType.explainWord:
        return _buildExplainWordPrompt(request.payload);
      case AiTaskType.generateQuiz:
        return _buildGenerateQuizPrompt(request.payload);
      case AiTaskType.summarizeMistakes:
        return _buildSummarizeMistakesPrompt(request.payload);
      case AiTaskType.chat:
        return _buildChatPrompt(request.payload);
    }
  }


  static String _buildExplainWordPrompt(Map<String, dynamic> payload) {
    final spell = (payload['spell'] ?? '').toString();

    final buffer = StringBuffer();

    // 参考 Qwen ChatML 模板，使用自然对话风格
    buffer.writeln('<|im_start|>system');
    buffer.writeln('你是一名英语单词助教, 主要用中文和学生交流。');
    buffer.writeln('你的任务是针对学生正在学习的单词，提供其：');
    buffer.writeln('1. 易混淆词 (Confusing words)');
    buffer.writeln('不需要给学生出题。');
    buffer.writeln('<|im_end|>');

    buffer.writeln('<|im_start|>user');
    buffer.write('请帮助我学习单词: "$spell", 尽可能不啰嗦 ');


    buffer.writeln('');

    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }

  static String _buildGenerateQuizPrompt(Map<String, dynamic> payload) {
    return "";
  }

  static String _buildSummarizeMistakesPrompt(Map<String, dynamic> payload) {
    return "";
  }

  static String _buildChatPrompt(Map<String, dynamic> payload) {
    final messages = payload['messages'] as List?;
    final user = Global.getLoggedInUser();
    final nickName = user?.nickName ?? '同学';

    final buffer = StringBuffer();

    buffer.writeln('<|im_start|>system');
    buffer.writeln('你是一名中国学生(名叫:$nickName)的英语单词助教, 主要用中文和学生交流, 你的风格简洁明了。');
    buffer.writeln('<|im_end|>');

    if (messages != null) {
      for (var msg in messages) {
        final role = msg['role'] == 'user' ? 'user' : 'assistant';
        final content = msg['content'] ?? '';
        buffer.writeln('<|im_start|>$role');
        buffer.writeln(content);
        buffer.writeln('<|im_end|>');
      }
    }

    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }
}
