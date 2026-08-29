import 'dart:convert';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/global.dart';

/// AI 裁判统一工具类，消除背单词页面与词表页面在提示词及结果解析上的冗余
class AiRefereeUtil {
  /// 单词释义裁判系统提示词（含 ASR 声学容错与同义词覆盖规则）
  static const String wordRefereeSystemPrompt = '''
You are an expert bilingual lexicographer and translation referee. Your task is to judge whether the user's spoken answer accurately represents a valid meaning, synonym, or translation of the target English word.

CRITICAL INSTRUCTIONS & CONSTRAINTS:
1. SEMANTIC VALIDITY & SYNONYMS:
   - The user's answer does NOT need to match the dictionary reference text word-for-word.
   - Any accurate translation, synonym, or valid definition of the English word MUST be accepted as TRUE {"isCorrect": true} (e.g., for "salary", answers like "工资", "薪水", "薪酬", "月薪", "收入", "报酬" are all correct).
   - If the meaning is completely unrelated or wrong (e.g., "苹果", "香蕉", "汽车" for "salary"), judge as FALSE {"isCorrect": false}.

2. SPEECH RECOGNITION (ASR) ACOUSTIC TOLERANCE:
   - The user input comes from an automatic speech recognition (ASR) system and may contain minor phonetic transcription artifacts or homophone substitutions.
   - Homophones & Near-Homophones: Tolerate common Chinese homophones or near-homophones if the spoken sound genuinely corresponds to a valid meaning (e.g., "工资本" vs "工资", "心水/新水" vs "薪水", "薪资" vs "新资").
   - NEVER accept phonetically and semantically unrelated inputs (e.g., completely different words).

Respond ONLY in raw JSON format (no markdown code blocks, no ```json):
{"isCorrect": true, "intendedMeaning": "Corrected/standard Chinese meaning (e.g. 工资 or 薪水)"} if the answer is a valid meaning or acoustically matching translation of the word.
{"isCorrect": false, "explanation": "Brief reason in Chinese (max 12 words)"} if incorrect.
''';

  /// 例句翻译裁判系统提示词（含 ASR 声学容错与核心成分匹配规则）
  static const String sentenceRefereeSystemPrompt = '''
You are an expert bilingual translation referee. Your task is to judge whether the user's translation accurately conveys the meaning of the source sentence.

CRITICAL INSTRUCTIONS & CONSTRAINTS:
1. CORE ENTITIES & KEY COMPONENTS MUST BE ACCURATE:
   - The key subject, core verbs, and essential objects of the sentence MUST be present and correctly expressed.
   - If a core subject or entity is completely wrong, missing, or replaced with an unrelated word (e.g. "The dove" translated/recognized as "琼艇/游艇/潜艇/汽车", or "doctor" as "教师"), you MUST judge it as FALSE {"isCorrect": false}.

2. STRICT CRITERIA FOR SPEECH RECOGNITION (ASR) ACOUSTIC TOLERANCE:
   - In Chinese: Homophones & Structural Particles (他/她/它, 的/得/地, 在/再, 座/做/作, 像/向/相, 进/近) are interchangeable.
   - Genuine Pinyin/Phonetic Similarity: ONLY tolerate acoustic errors where the pronunciation is GENUINELY similar in context (e.g. "鸽子" vs "格子/歌子", "苹果" vs "平果").
   - NEVER tolerate completely different pronunciations or fabricated entities (e.g. "qióng tǐng" has NO phonetic similarity to "gē zi", so "琼艇" must NOT be accepted for "dove/鸽子").

3. SEMANTIC FAITHFULNESS:
   - Allow natural synonymous expressions and varied natural syntax as long as all core components of the source sentence are faithfully and fully conveyed.

Respond ONLY in raw JSON format (no markdown code blocks, no ```json):
{"isCorrect": true} if the translation is faithful and all core entities/meanings are correct.
{"isCorrect": false, "explanation": "Brief reason in Chinese (max 12 words)"} if incorrect.
''';

  /// 解析大模型返回的 JSON 判决结果
  static ({bool isCorrect, String explanation, String? intendedMeaning}) parseRefereeResponse(String? rawResponse) {
    if (rawResponse == null || rawResponse.trim().isEmpty) {
      return (isCorrect: false, explanation: '无裁判结果', intendedMeaning: null);
    }

    try {
      String cleanJson = rawResponse.trim();
      if (cleanJson.contains('```')) {
        final regExp = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
        final match = regExp.firstMatch(cleanJson);
        if (match != null) {
          cleanJson = match.group(1) ?? cleanJson;
        }
      }

      final startIdx = cleanJson.indexOf('{');
      final endIdx = cleanJson.lastIndexOf('}');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        cleanJson = cleanJson.substring(startIdx, endIdx + 1);
      }

      final parsed = jsonDecode(cleanJson.trim());
      final isCorrect = parsed['isCorrect'] as bool? ?? false;
      final explanation = parsed['explanation'] as String? ?? '';
      final intendedMeaning = parsed['intendedMeaning'] as String?;
      return (isCorrect: isCorrect, explanation: explanation, intendedMeaning: intendedMeaning);
    } catch (e) {
      Global.logger.w('解析 AI 裁判结果异常: rawResponse=$rawResponse', error: e);
      return (isCorrect: false, explanation: '解析裁判结果失败', intendedMeaning: null);
    }
  }

  /// 请求大模型进行单词释义裁判
  static Future<({bool isCorrect, String explanation, String? intendedMeaning, String? rawResponse})> judgeWordMeaning({
    required String targetWord,
    required String referenceMeanings,
    required String userInput,
    List<String>? candidates,
    required String userId,
  }) async {
    final candidateStr = (candidates != null && candidates.length > 1)
        ? candidates.join(', ')
        : userInput;

    final userPrompt = '''
Target English Word: $targetWord
Dictionary Reference Meanings: $referenceMeanings
User's Speech-to-Text Input: $userInput
ASR Candidate List: $candidateStr
''';

    final messages = [
      {"role": "system", "content": wordRefereeSystemPrompt},
      {"role": "user", "content": userPrompt}
    ];

    final result = await Api.client.aiChat(jsonEncode(messages), userId);
    if (result.success && result.data != null) {
      final parsed = parseRefereeResponse(result.data);
      return (
        isCorrect: parsed.isCorrect,
        explanation: parsed.explanation,
        intendedMeaning: parsed.intendedMeaning,
        rawResponse: result.data,
      );
    } else {
      return (isCorrect: false, explanation: result.msg ?? '调用 AI 裁判失败', intendedMeaning: null, rawResponse: null);
    }
  }

  /// 请求大模型进行例句翻译裁判
  static Future<({bool isCorrect, String explanation, String? rawResponse})> judgeSentenceTranslation({
    required String sourceSentence,
    required String referenceTranslation,
    required String userInput,
    String? exerciseType,
    required String userId,
  }) async {
    final userPrompt = '''
Exercise Type: ${exerciseType ?? 'SentenceTranslation'}
Source Sentence: $sourceSentence
Reference Translation: $referenceTranslation
User Answer: $userInput
''';

    final messages = [
      {"role": "system", "content": sentenceRefereeSystemPrompt},
      {"role": "user", "content": userPrompt}
    ];

    final result = await Api.client.aiChat(jsonEncode(messages), userId);
    if (result.success && result.data != null) {
      final parsed = parseRefereeResponse(result.data);
      return (isCorrect: parsed.isCorrect, explanation: parsed.explanation, rawResponse: result.data);
    } else {
      return (isCorrect: false, explanation: result.msg ?? '调用 AI 裁判失败', rawResponse: null);
    }
  }
}
