import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/phoneme_util.dart';
import 'package:nnbdc/util/edit_distance.dart';

/// ASR 候选结果及其匹配分数
class AsrCandidateResult {
  final String text;
  final int score;

  AsrCandidateResult(this.text, this.score);
}

/// 语音识别结果预处理工具类
/// 主要用于处理发音相似的中英文替换问题
class AsrUtil {
  /// 发音相似的中英文映射表
  /// 格式: {英文识别结果: 正确的中文}
  static const Map<String, String> _pronunciationMap = {
    'baby': '卑鄙',
    'hello': '哈喽',
  };

  /// 发音相似的英文单词映射表（仅用于特殊情况）
  /// 格式: {错误识别结果: 正确单词}
  /// 注意：这个映射表只用于处理一些特殊的发音相似情况
  /// 大部分情况会通过编辑距离算法自动处理
  static const Map<String, String> _englishPronunciationMap = {
    // 可以在这里添加一些特殊的映射，但大部分情况不需要
    'suece': 'swiss',
    'swis': 'swiss',
    'mail': 'male',
  };

  /// 将阿拉伯数字转换为中文数字（支持0-9999）
  /// 例如：12 -> 十二，123 -> 一百二十三
  static String _convertArabicToChinese(int num) {
    if (num == 0) return '零';
    if (num > 9999) return num.toString(); // 超过范围，返回原数字

    const List<String> digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

    if (num < 10) {
      return digits[num];
    }

    if (num < 20) {
      // 10-19的特殊处理：十、十一、十二...十九
      if (num == 10) return '十';
      return '十${digits[num % 10]}';
    }

    if (num < 100) {
      // 20-99：二十、二十一...九十九
      int tens = num ~/ 10;
      int ones = num % 10;
      String result = '${digits[tens]}十';
      if (ones > 0) {
        result += digits[ones];
      }
      return result;
    }

    if (num < 1000) {
      // 100-999：一百、一百零一...九百九十九
      int hundreds = num ~/ 100;
      int remainder = num % 100;
      String result = '${digits[hundreds]}百';
      if (remainder > 0) {
        if (remainder < 10) {
          result += '零${digits[remainder]}';
        } else {
          result += _convertArabicToChinese(remainder);
        }
      }
      return result;
    }

    // 1000-9999：一千、一千零一...九千九百九十九
    int thousands = num ~/ 1000;
    int remainder = num % 1000;
    String result = '${digits[thousands]}千';
    if (remainder > 0) {
      if (remainder < 100) {
        result += '零${_convertArabicToChinese(remainder)}';
      } else {
        result += _convertArabicToChinese(remainder);
      }
    }
    return result;
  }

  /// 预处理语音识别结果
  /// 主要处理发音相似的中英文替换，并将阿拉伯数字转换为中文数字
  static String preprocess(String result) {
    if (result.isEmpty) return result;

    // 转换为小写进行匹配
    String lowerResult = result.toLowerCase().trim();

    // 检查是否包含发音相似的词
    for (String english in _pronunciationMap.keys) {
      lowerResult = lowerResult.replaceAll(english, _pronunciationMap[english]!);
    }

    // 将阿拉伯数字转换为中文数字
    // 使用正则表达式匹配所有数字（包括多位数）
    lowerResult = lowerResult.replaceAllMapped(RegExp(r'\d+'), (match) {
      final numStr = match.group(0);
      if (numStr != null) {
        try {
          final num = int.parse(numStr);
          return _convertArabicToChinese(num);
        } catch (e) {
          // 解析失败，返回原数字
          return numStr;
        }
      }
      return match.group(0) ?? '';
    });

    // 仅提取汉字，聚焦中文匹配，避免英文/符号噪声影响
    String chineseOnly = lowerResult.replaceAll(RegExp(r"[^\u4e00-\u9fa5]"), '');

    // 只保留最后 10 个汉字，控制后续相似度计算复杂度
    if (chineseOnly.length > 10) {
      chineseOnly = chineseOnly.substring(chineseOnly.length - 10);
    }

    // 如果没有中文，回退到降噪后的原结果
    return chineseOnly.isEmpty ? lowerResult : chineseOnly;
  }

  /// 预处理英文语音识别结果, 使识别结果尽量往目标单词靠拢
  /// 主要处理发音相似的英文单词替换
  /// @param result 语音识别结果
  /// @param targetWord 目标单词
  /// @return 预处理后的结果
  static String preprocessEnglish(String result, String targetWord) {
    if (result.isEmpty) return result;

    String lowerResult = result.toLowerCase().trim();
    String lowerTarget = targetWord.toLowerCase().trim();

    // 1. 完全匹配
    if (lowerResult == lowerTarget) {
      Global.logger.d('===== ASR MATCH [EXACT]: "$lowerResult" == "$lowerTarget"');
      return lowerTarget;
    }

    // 2. 特殊映射表
    if (_englishPronunciationMap.containsKey(lowerResult)) {
      String corrected = _englishPronunciationMap[lowerResult]!;
      if (corrected == lowerTarget) {
        Global.logger.d('===== ASR MATCH [MAP_RESCUE]: "$lowerResult" -> "$lowerTarget"');
        return lowerTarget;
      }
    }

    // 3. 编辑距离匹配 (收紧阈值，配合 66M 模型)
    int distance = EditDistance.forStrings(lowerResult, lowerTarget);
    int maxLength = [lowerResult.length, lowerTarget.length].reduce((a, b) => a > b ? a : b);

    // 编辑距离容错匹配
    if (maxLength > 0 && distance <= (maxLength * Constants.editDistanceTolerance).floor()) {
      Global.logger.d('===== ASR MATCH [EDIT_DIST]: "$lowerResult" -> "$lowerTarget" (dist: $distance, max: $maxLength)');
      return lowerTarget;
    }

    // 4. 重叠度匹配
    if (_hasSignificantOverlap(lowerResult, lowerTarget)) {
      Global.logger.d('===== ASR MATCH [OVERLAP]: "$lowerResult" -> "$lowerTarget"');
      return lowerTarget;
    }

    return lowerResult;
  }

  /// 计算综合相似度 (仅基于发音)
  static Future<int> calculateOverallSimilarity(String input, String target) async {
    try {
      // 用户要求独立的计算方式，只考虑发音相似度
      return await PhonemeUtil.similarity(input, target);
    } catch (e) {
      Global.logger.d('计算音素相似度失败: $e');
      // 降级使用拼写相似度
      return _calculateSimilarityScore(input, target);
    }
  }

  /// 基于音素相似度的改进版：从多个候选中选择最优（异步）
  /// @param candidates 候选列表, 来自于ASR识别结果
  /// @param targetWord 目标单词
  /// @return 最优候选及其分数
  static Future<AsrCandidateResult> selectBestCandidateWithPhonemeAndScore(
    List<String> candidates,
    String targetWord,
  ) async {
    if (candidates.isEmpty) return AsrCandidateResult('', 0);
    final lowerTarget = targetWord.toLowerCase().trim();

    // 完全匹配优先
    for (final c in candidates) {
      if (c.toLowerCase().trim() == lowerTarget) {
        Global.logger.d('===== ASR MATCH [NBEST_EXACT]: "$c" == "$lowerTarget"');
        return AsrCandidateResult(targetWord, 100);
      }
    }

    // 先用现有算法选一遍作为基准 (拼写最佳)
    final baseline = selectBestCandidate(candidates, targetWord);
    int bestScore = await calculateOverallSimilarity(baseline, lowerTarget);
    String best = baseline;

    // 遍历所有候选，寻找综合分最高的
    for (final c in candidates) {
      final s = await calculateOverallSimilarity(c, lowerTarget);
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }

    // 判定：综合相似度 ≥ 阈值则视为目标词
    if (bestScore >= Constants.phonemeMatchThreshold) {
      Global.logger.d('===== ASR MATCH [PHONETIC/HYBRID]: "$best" -> "$lowerTarget" (score: $bestScore)');
      return AsrCandidateResult(targetWord, bestScore);
    }

    return AsrCandidateResult(best, bestScore);
  }

  // 保留旧方法以兼容（如果还有其他地方调用且不需要分数），或者直接让它调用新方法
  static Future<String> selectBestCandidateWithPhoneme(
    List<String> candidates,
    String targetWord,
  ) async {
    final result = await selectBestCandidateWithPhonemeAndScore(candidates, targetWord);
    return result.text;
  }

  /// 根据拼写相似度选择最匹配的候选
  static String selectBestCandidate(List<String> candidates, String targetWord) {
    if (candidates.isEmpty) return '';

    String lowerTarget = targetWord.toLowerCase().trim();

    // 首先检查完全匹配
    for (String candidate in candidates) {
      if (candidate.toLowerCase().trim() == lowerTarget) {
        return targetWord;
      }
    }

    // 使用智能算法选择最佳候选
    String bestCandidate = candidates.first;
    int bestScore = _calculateSimilarityScore(candidates.first, lowerTarget);

    for (int i = 1; i < candidates.length; i++) {
      int score = _calculateSimilarityScore(candidates[i], lowerTarget);
      if (score > bestScore) {
        bestScore = score;
        bestCandidate = candidates[i];
      }
    }

    // 如果最佳候选的拼写相似度足够高，返回目标单词
    if (bestScore >= Constants.spellingMatchThreshold) {
      return targetWord;
    }

    return bestCandidate;
  }

  /// 计算拼写相似度分数（0-100）
  static int _calculateSimilarityScore(String candidate, String target) {
    String lowerCandidate = candidate.toLowerCase().trim();
    String lowerTarget = target.toLowerCase().trim();

    // 完全匹配
    if (lowerCandidate == lowerTarget) {
      return 100;
    }

    // 计算编辑距离相似度
    int distance = EditDistance.forStrings(lowerCandidate, lowerTarget);
    int maxLength = [lowerCandidate.length, lowerTarget.length].reduce((a, b) => a > b ? a : b);

    if (maxLength == 0) return 0;

    // 编辑距离相似度 (0-100)
    int editSimilarity = ((maxLength - distance) * 100 / maxLength).clamp(0, 100).round();

    // 重叠相似度
    int overlapSimilarity = _calculateOverlapSimilarity(lowerCandidate, lowerTarget);

    // 综合拼写相似度（使用配置的权重）
    int finalScore = (editSimilarity * Constants.spellingEditDistanceWeight + overlapSimilarity * Constants.spellingOverlapWeight).round();

    return finalScore.clamp(0, 100);
  }

  /// 计算重叠相似度
  static int _calculateOverlapSimilarity(String word1, String word2) {
    int minLength = [word1.length, word2.length].reduce((a, b) => a < b ? a : b);
    if (minLength < 3) return 0;

    int maxOverlap = 0;

    // 检查前缀重叠
    for (int i = 3; i <= minLength; i++) {
      String prefix1 = word1.substring(0, i);
      String prefix2 = word2.substring(0, i);
      if (prefix1 == prefix2) {
        maxOverlap = i;
      }
    }

    // 检查后缀重叠
    for (int i = 3; i <= minLength; i++) {
      String suffix1 = word1.substring(word1.length - i);
      String suffix2 = word2.substring(word2.length - i);
      if (suffix1 == suffix2) {
        maxOverlap = [maxOverlap, i].reduce((a, b) => a > b ? a : b);
      }
    }

    // 检查中间部分重叠
    if (minLength >= 4) {
      for (int i = 0; i <= word1.length - 4; i++) {
        String substring1 = word1.substring(i, i + 4);
        if (word2.contains(substring1)) {
          maxOverlap = [maxOverlap, 4].reduce((a, b) => a > b ? a : b);
        }
      }
    }

    return (maxOverlap * 100 / minLength).clamp(0, 100).round();
  }

  /// 检查两个单词是否有显著的重叠部分
  static bool _hasSignificantOverlap(String word1, String word2) {
    int minLength = [word1.length, word2.length].reduce((a, b) => a < b ? a : b);
    if (minLength < 3) return false; // 太短的单词不检查重叠

    // 检查前缀重叠
    for (int i = 3; i <= minLength; i++) {
      String prefix1 = word1.substring(0, i);
      String prefix2 = word2.substring(0, i);
      if (prefix1 == prefix2) {
        return true;
      }
    }

    // 检查后缀重叠
    for (int i = 3; i <= minLength; i++) {
      String suffix1 = word1.substring(word1.length - i);
      String suffix2 = word2.substring(word2.length - i);
      if (suffix1 == suffix2) {
        return true;
      }
    }

    // 检查中间部分重叠（对于复合词很有用）
    if (minLength >= 4) {
      for (int i = 0; i <= word1.length - 4; i++) {
        String substring1 = word1.substring(i, i + 4);
        if (word2.contains(substring1)) {
          return true;
        }
      }
    }

    return false;
  }

  /// 计算两个字符串的编辑距离（Levenshtein距离）
  // 移除本地实现，统一使用 EditDistance

  /// 向iOS端下发上下文短语（当前单词允许的释义子项）
  /// 提高目标短语的识别概率（仅提示，不强制）
  /// @param phrases 上下文短语列表
  /// @param asrMethodChannel ASR方法通道
  /// @param permissionGranted 权限是否已授予
  static Future<void> setContextualStrings(
    List<String> phrases,
    dynamic asrMethodChannel,
    bool permissionGranted,
  ) async {
    if (PlatformUtils.isWeb) return;
    if (!permissionGranted) return;
    if (phrases.isEmpty) return;

    try {
      await asrMethodChannel.invokeMethod('setContextualStrings', {
        'phrases': phrases,
      });
      Global.logger.d('===== ASR: 设置上下文短语成功，共${phrases.length}个短语');
    } catch (e) {
      Global.logger.d('ASR setContextualStrings error: $e');
    }
  }

  /// 从单词释义中提取上下文短语
  /// 将释义文本拆分为子项，用于ASR上下文提示
  /// @param meaningItems 释义项列表
  /// @return 提取的短语列表
  static List<String> extractContextualPhrases(List<MeaningItemVo> meaningItems) {
    List<String> allowPhrases = [];

    try {
      for (final mi in meaningItems) {
        final text = mi.meaning ?? '';
        // 拆分"；，,"为子项
        final units = text
            .replaceAll(RegExp(r"[（\(].*[）\)]"), '') // 移除括号内容
            .split(RegExp(r"[；;，,]")) // 按分号、逗号拆分
            .map((e) => e.trim()) // 去除空格
            .where((e) => e.isNotEmpty); // 过滤空字符串
        allowPhrases.addAll(units);
      }
    } catch (e) {
      Global.logger.d('提取上下文短语失败: $e');
    }

    return allowPhrases;
  }
}
