import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/edit_distance.dart';

/// 基于 CMU Pronouncing Dictionary 的音素工具
/// - 懒加载 assets/cmudict.dict
/// - 提供单词到音素的查找
/// - 提供音素级编辑距离与相似度评分
class PhonemeUtil {
  static const String _assetPath = 'assets/cmudict.dict';
  static bool _loaded = false;
  static final Map<String, List<List<String>>> _wordToPhonemeVariants = {};

  /// 懒加载 CMUdict（多次调用安全）
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final content = await rootBundle.loadString(_assetPath);
      _parse(content);
      _loaded = true;
      Global.logger.d('PhonemeUtil loaded: ${_wordToPhonemeVariants.length} entries');
    } catch (e, st) {
      Global.logger.e('Failed to load $_assetPath: $e', error: e, stackTrace: st);
    }
  }

  /// 查找单词的音素列表(可能有多个变体)，若无返回空列表
  static Future<List<List<String>>> lookup(String word) async {
    if (!_loaded) {
      await load();
    }
    final key = word.trim().toLowerCase();
    return _wordToPhonemeVariants[key] ?? const [];
  }

  /// 返回两个单词的音素相似度(0-100)
  static Future<int> similarity(String a, String b) async {
    if (a.isEmpty || b.isEmpty) return 0;
    final aVars = await lookup(a);
    final bVars = await lookup(b);
    if (aVars.isEmpty || bVars.isEmpty) return 0;

    int best = 0;
    for (final ap in aVars) {
      for (final bp in bVars) {
        final s = _phonemeSimilarity(ap, bp);
        if (s > best) best = s;
      }
    }
    return best;
  }

  /// 在候选集中按音素相似度选最佳项，返回原候选串
  static Future<String> bestMatch(List<String> candidates, String target) async {
    if (candidates.isEmpty) return '';
    int bestScore = -1;
    String best = candidates.first;
    for (final c in candidates) {
      final s = await similarity(c, target);
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    return best;
  }

  // ---------- 内部实现 ----------

  static void _parse(String content) {
    // CMUdict 每行格式: WORD  PH1 PH2 PH3 ...
    // 允许注释与空行；带有 (1)/(2) 变体的词，去掉括号编号作为同词的不同变体
    final lines = content.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith(';;;') || line.startsWith('#')) continue;

      final parts = line.split(RegExp(r"\s+"));
      if (parts.length < 2) continue;

      var head = parts.first;
      // 处理变体：WORD(1)
      final paren = head.indexOf('(');
      if (paren > 0 && head.endsWith(')')) {
        head = head.substring(0, paren);
      }
      final word = head.toLowerCase();
      // 注意：CMU 音素里元音带 0/1/2 重音数字，这里去掉数字以做宽松匹配
      final phonemes = parts
          .sublist(1)
          .map((p) => p.replaceAll(RegExp(r"\d+"), ''))
          .toList();

      final variants = _wordToPhonemeVariants.putIfAbsent(word, () => <List<String>>[]);
      variants.add(phonemes);
    }
  }

  /// 将两个音素序列的 Levenshtein 距离映射为 0-100 相似度
  static int _phonemeSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final dist = EditDistance.forLists(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    final score = ((maxLen - dist) * 100.0 / maxLen).clamp(0.0, 100.0).round();
    return score;
    
  }
  
}


