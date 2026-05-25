import 'package:nnbdc/services/ai_service.dart';

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
    buffer.writeln('你是一名英语单词助教, 主要用中文和学生交流, 尽量不啰嗦。');
    buffer.writeln('你的任务是针对学生正在学习的单词，帮助他理解用法：');
    buffer.writeln('1. 列出常见搭配（collocation）并附中文解释');
    buffer.writeln('2. 简要用法提示（正式/口语、常见误区、英/美差异等）');
    buffer.writeln('不需要生成例句，不需要讲解词根，不需要编造记忆法。');
    buffer.writeln('<|im_end|>');

    buffer.writeln('<|im_start|>user');
    buffer.write('请帮助我学习单词: "$spell" ');

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

    final buffer = StringBuffer();

    buffer.writeln('<|im_start|>system');
    buffer.writeln('你是一个博学、亲切且专业的 AI 助教。你擅长以生动有趣的方式讲解英语单词记忆（如词根词缀、近义词辨析、联想记忆等），同时也非常乐意作为一个知识渊博的伙伴，与学生探讨任何他们感兴趣的话题，回答各领域的疑问。你的回答风格应该简洁明了，专业且富有逻辑。');
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
