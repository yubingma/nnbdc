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
    final meanings = payload['meanings'] as List?;
    final sentences = payload['sentences'] as List?;
    final user = Global.getLoggedInUser();
    final nickName = user?.nickName ?? '同学';

    final buffer = StringBuffer();

    // 参考 Qwen ChatML 模板，使用自然对话风格
    buffer.writeln('<|im_start|>system');
    buffer.writeln('你是一名中国学生(昵称:$nickName)英语单词助教, 主要用中文和学生交流。');
    buffer.writeln('你的任务是针对学生正在学习的单词，提供其：');
    buffer.writeln('1. 同义词 (Synonyms) 及细微辨析');
    buffer.writeln('2. 近义词 (Near-synonyms)');
    buffer.writeln('3. 易混淆词 (Confusing words)');
    buffer.writeln('讲解要生动有趣，并指出它们在用法上的主要区别或记忆技巧。');
    buffer.writeln('<|im_end|>');

    buffer.writeln('<|im_start|>user');
    buffer.write('我正在学习单词 "$spell", ');

    // 提供上下文
    if (meanings != null && meanings.isNotEmpty) {
      buffer.write('该单词在词典中的释义有: ');
      for (var m in meanings) {
        buffer.write('${m['cn']} ');
      }
      buffer.write('。');
    }

    if (sentences != null && sentences.isNotEmpty) {
      buffer.write('参考例句有: ');
      for (var s in sentences) {
        buffer.write('${s['en']} (${s['cn']}); ');
      }
      buffer.write('。');
    }

    buffer.write('请为我提供该单词的同义词、近义词以及易混淆词的讲解。');
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
