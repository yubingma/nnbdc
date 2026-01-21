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

  /// 公共的角色设定 + 本地化信息
  static String _buildCommonHeader(Map<String, dynamic> payload) {
    final userLocale = (payload['userLocale'] ?? 'zh-CN').toString();
    final userLevel = (payload['userLevel'] ?? 'unknown').toString();

    return '''[ROLE]
You are an English vocabulary tutor for Chinese learners.
You MUST:
- Prefer concise and clear explanations.
- Use simple Chinese for explanations unless explicitly asked otherwise.
- Always stay within the given word list and dictionary information. Do NOT invent non-existent meanings.

[LOCALE]
User interface language: $userLocale
User level: $userLevel
''';
  }

  static String _buildExplainWordPrompt(Map<String, dynamic> payload) {
    final spell = (payload['spell'] ?? '').toString();
    final phonetics = (payload['phonetics'] ?? '').toString();
    final partOfSpeech = (payload['partOfSpeech'] ?? '').toString();

    final buffer = StringBuffer();

    // system: 说明角色 + 只输出三行
    buffer.writeln('<|im_start|>system');
    buffer.writeln('你是英语教师。用户会给出一个英文词, 请你简单地讲解一下这个单词。');
    buffer.writeln('<|im_end|>');

    // user: 明确给出单词 + 可选音标/词性 + 本地参考释义
    buffer.writeln('<|im_start|>user');
    buffer.write('单词: $spell');


    
    buffer.writeln();
    buffer.writeln('<|im_end|>');

    // 直接开始，不给思考空间
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }

  static String _buildGenerateQuizPrompt(Map<String, dynamic> payload) {
    final buffer = StringBuffer();
    buffer.write(_buildCommonHeader(payload));

    final quizType = (payload['quizType'] ?? 'multiple_choice').toString();
    final numQuestions = payload['numQuestions'] ?? 5;
    final difficulty = (payload['difficulty'] ?? 'medium').toString();

    buffer.writeln('[TASK]');
    buffer.writeln('You need to generate vocabulary quiz questions for a Chinese learner.');
    buffer.writeln();

    buffer.writeln('[SETTINGS]');
    buffer.writeln('Quiz type: $quizType');
    buffer.writeln('Number of questions: $numQuestions');
    buffer.writeln('Difficulty: $difficulty');
    buffer.writeln();

    buffer.writeln('[WORDS]');
    final words = payload['words'];
    if (words is List) {
      var idx = 1;
      for (final w in words) {
        if (w is Map<String, dynamic>) {
          final spell = (w['spell'] ?? '').toString();
          buffer.writeln('$idx. $spell');
          final meanings = w['meanings'];
          if (meanings is List) {
            buffer.writeln('   Meanings:');
            for (final m in meanings) {
              if (m is Map<String, dynamic>) {
                final cn = (m['cn'] ?? '').toString();
                final en = (m['en'] ?? '').toString();
                buffer.writeln('   - $cn (EN: $en)');
              }
            }
          }
          buffer.writeln();
          idx++;
        }
      }
    }

    buffer.writeln('[REQUIREMENTS]');
    buffer.writeln('- Use ONLY the given words to create questions.');
    buffer.writeln('- All instructions and explanations should be in Chinese.');
    buffer.writeln('- For multiple_choice:');
    buffer.writeln('  - Each question should have 1 correct option and 3 distractors.');
    buffer.writeln('  - Distractors should be plausible but clearly wrong if the learner understands the word.');
    buffer.writeln('- For each question, provide a short Chinese explanation of the correct answer.');
    buffer.writeln();

    buffer.writeln('[OUTPUT FORMAT]');
    buffer.writeln('You MUST follow this exact format:');
    buffer.writeln();
    buffer.writeln('[QUIZ]');
    buffer.writeln('Q1. (题干，用中文，比如让用户选择中文释义或填空句子)');
    buffer.writeln('OPTIONS:');
    buffer.writeln('A) ...');
    buffer.writeln('B) ...');
    buffer.writeln('C) ...');
    buffer.writeln('D) ...');
    buffer.writeln('ANSWER: <A/B/C/D>');
    buffer.writeln('EXPLANATION: (中文解释)');
    buffer.writeln();
    buffer.writeln('Q2. ...');

    return buffer.toString();
  }

  static String _buildSummarizeMistakesPrompt(Map<String, dynamic> payload) {
    final buffer = StringBuffer();
    buffer.write(_buildCommonHeader(payload));

    final timeRange = (payload['timeRange'] ?? 'today').toString();
    final studyStats = payload['studyStats'];
    final totalWords = studyStats is Map<String, dynamic> ? (studyStats['totalWords'] ?? 'unknown') : 'unknown';
    final todayNewWords = studyStats is Map<String, dynamic> ? (studyStats['todayNewWords'] ?? 'unknown') : 'unknown';
    final todayReviews = studyStats is Map<String, dynamic> ? (studyStats['todayReviews'] ?? 'unknown') : 'unknown';

    buffer.writeln('[TASK]');
    buffer.writeln('You need to analyze a learner\'s vocabulary mistakes and give a short study summary in Chinese.');
    buffer.writeln();

    buffer.writeln('[MISTAKES]');
    final mistakes = payload['mistakes'];
    if (mistakes is List && mistakes.isNotEmpty) {
      var idx = 1;
      for (final m in mistakes) {
        if (m is Map<String, dynamic>) {
          final spell = (m['spell'] ?? '').toString();
          final questionType = (m['questionType'] ?? '').toString();
          final mistakeType = (m['mistakeType'] ?? '').toString();
          final userAnswer = (m['userAnswer'] ?? '').toString();
          final correctAnswer = (m['correctAnswer'] ?? '').toString();
          final timestamp = (m['timestamp'] ?? '').toString();
          buffer.writeln('$idx. Word: $spell');
          buffer.writeln('   Question type: $questionType');
          buffer.writeln('   Mistake type: $mistakeType');
          buffer.writeln('   User answer: $userAnswer');
          buffer.writeln('   Correct answer: $correctAnswer');
          buffer.writeln('   Time: $timestamp');
          buffer.writeln();
          idx++;
        }
      }
    } else {
      buffer.writeln('No mistakes recorded.');
      buffer.writeln();
    }

    buffer.writeln('[STUDY_STATS]');
    buffer.writeln('Time range: $timeRange');
    buffer.writeln('Total words learned: $totalWords');
    buffer.writeln('New words today: $todayNewWords');
    buffer.writeln('Reviews today: $todayReviews');
    buffer.writeln();

    buffer.writeln('[REQUIREMENTS]');
    buffer.writeln('- In Chinese, summarize:');
    buffer.writeln('  - What types of mistakes are most common.');
    buffer.writeln('  - Which kinds of words (e.g., verbs, abstract nouns) are problematic.');
    buffer.writeln('- Provide 2-3 short suggestions to improve (for example, how to review, what to pay attention to).');
    buffer.writeln('- Be encouraging and concise.');
    buffer.writeln();

    buffer.writeln('[OUTPUT FORMAT]');
    buffer.writeln('You MUST follow this exact format:');
    buffer.writeln();
    buffer.writeln('[SUMMARY]');
    buffer.writeln('(用 2~4 句话概括这个时间段的错误特点，用中文)');
    buffer.writeln();
    buffer.writeln('[ADVICE]');
    buffer.writeln('1. (建议1，用中文)');
    buffer.writeln('2. (建议2，用中文)');
    buffer.writeln('3. (可选，建议3，用中文)');

    return buffer.toString();
  }

  static String _buildChatPrompt(Map<String, dynamic> payload) {
    final buffer = StringBuffer();
    buffer.write(_buildCommonHeader(payload));

    final mode = (payload['mode'] ?? 'tutor').toString();
    final scenario = (payload['scenario'] ?? 'daily_conversation').toString();

    buffer.writeln('[MODE]');
    buffer.writeln('Mode: $mode');
    buffer.writeln('Scenario: $scenario');
    buffer.writeln();

    buffer.writeln('[CONVERSATION_HISTORY]');
    final history = payload['history'];
    if (history is List && history.isNotEmpty) {
      for (final turn in history) {
        if (turn is Map<String, dynamic>) {
          final role = (turn['role'] ?? '').toString();
          final content = (turn['content'] ?? '').toString();
          buffer.writeln('$role: $content');
        }
      }
    } else {
      buffer.writeln('No previous conversation.');
    }
    buffer.writeln();

    buffer.writeln('[REQUIREMENTS]');
    buffer.writeln('- Continue the conversation naturally.');
    buffer.writeln('- Encourage the learner to practice English.');
    buffer.writeln('- When appropriate, briefly correct obvious grammar or word choice mistakes in Chinese, but do not be too long.');
    buffer.writeln('- Keep each reply short (for example within 4~6 sentences).');
    buffer.writeln();

    buffer.writeln('[OUTPUT FORMAT]');
    buffer.writeln('You MUST follow this exact format:');
    buffer.writeln();
    buffer.writeln('[CHAT_REPLY]');
    buffer.writeln('(模型的回复内容，可以中英夹杂)');

    return buffer.toString();
  }
}
