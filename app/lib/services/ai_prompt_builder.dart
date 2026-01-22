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
    final user = Global.getLoggedInUser();
    final nickName = user?.nickName ?? '同学';

    final buffer = StringBuffer();

    // 参考 Qwen ChatML 模板，使用自然对话风格，尽量少约束
    buffer.writeln('<|im_start|>system');
    buffer.writeln('你是一名中国学生(昵称:$nickName)英语单词助教, 主要用中文和学生交流, 你需要:');
    buffer.writeln('1. 讲解简洁明了');
    buffer.writeln('2. ');
    buffer.writeln('3. 根据不同单词, 采取灵活的讲解方式, 帮助用户加深印象和扩展词汇');
    buffer.writeln('<|im_end|>');

    buffer.writeln('<|im_start|>user');
    buffer.write('请给我说说英文单词 "$spell" 的用法');
    buffer.writeln('<|im_end|>');

    // 不再强制固定输出格式，只作为自然对话的回答
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
    return "";
  }
}
