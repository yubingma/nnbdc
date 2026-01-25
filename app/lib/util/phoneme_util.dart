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
  /// 核心改进：利用 cmudict.dict 对“垃圾结果”进行音素骨架提取与对比
  static Future<int> similarity(String a, String b) async {
    if (a.isEmpty || b.isEmpty) return 0;

    final aVars = await lookup(a);
    final bVars = await lookup(b);

    // 情况 A：两个词都在字典里，也使用模糊骨架对比（提高容错率）
    if (aVars.isNotEmpty && bVars.isNotEmpty) {
      int best = 0;
      List<String> bestAWeakened = [];
      List<String> bestBWeakened = [];

      for (final ap in aVars) {
        for (final bp in bVars) {
          final weakAP = _weakenPhonemes(ap);
          final weakBP = _weakenPhonemes(bp);
          final s = _phonemeSimilarity(weakAP, weakBP);
          if (s > best) {
            best = s;
            bestAWeakened = weakAP;
            bestBWeakened = weakBP;
          }
        }
      }

      // 记录骨架对比日志
      Global.logger.d('===== Phonetic compare: "$a"[$bestAWeakened] vs "$b"[$bestBWeakened] score: $best');
      return best;
    }

    // 情况 B：至少一个词不在字典里（比如 ASR 吐出了乱码 suece）
    // 逻辑：估算“垃圾词”的拟真音素，并与“目标词”的弱化音素进行骨架对比
    final List<List<String>> targetPhons = aVars.isNotEmpty ? aVars : bVars;
    final String garbageWord = aVars.isNotEmpty ? b : a;

    if (targetPhons.isNotEmpty) {
      final garbagePseudo = _convertToPseudoPhonemes(garbageWord);
      int best = 0;
      List<String> bestRef = [];
      for (final tp in targetPhons) {
        final weakTP = _weakenPhonemes(tp);
        final s = _phonemeSimilarity(weakTP, garbagePseudo);
        if (s > best) {
          best = s;
          bestRef = weakTP;
        }
      }

      // 记录骨架对比日志，方便排查由于拼写导致的“听感一致”
      Global.logger.d('===== Phonetic compare: "$garbageWord"[$garbagePseudo] vs target[$bestRef] score: $best');
      return best;
    }

    // 情况 C：两个都不在字典里，退化到字符编辑距离
    final dist = EditDistance.forStrings(a.toLowerCase(), b.toLowerCase());
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 0;
    final score = ((maxLen - dist) * 100.0 / maxLen).clamp(0.0, 100.0).round();

    // 记录字符编辑距离日志
    Global.logger.d('===== Phonetic compare (fallback): "$a" vs "$b" edit-distance score: $score');
    return score;
  }

  /// 内部方法：将真实音素序列（如 [S, W, IH]）弱化处理（合并母音），以便与垃圾词对比
  static List<String> _weakenPhonemes(List<String> phons) {
    const vowels = {"AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW"};
    // 使用 @ 作为元音占位符，避免与辅音字母 V (v) 冲突
    return phons.map((p) => vowels.contains(p.replaceAll(RegExp(r'\d+'), '')) ? "@" : p.replaceAll(RegExp(r'\d+'), '')).toList();
  }

  /// 内部方法：将普通乱码文本转换为伪音素序列（骨架提取）
  static List<String> _convertToPseudoPhonemes(String word) {
    String w = word.toLowerCase().trim();
    if (w.isEmpty) return [];

    // 1. 常见辅音组合简化映射
    w = w.replaceAll('ph', 'f');
    w = w.replaceAll('sh', 'S'); // 临时占位
    w = w.replaceAll('ch', 'C');
    w = w.replaceAll('th', 'T');
    w = w.replaceAll('ck', 'k');
    w = w.replaceAll('ng', 'G');
    w = w.replaceAll('qu', 'kw');
    w = w.replaceAll(RegExp(r'ce|ci|cy'), 's');

    // 2. 转换为标准音素集映射
    final List<String> res = [];
    for (int i = 0; i < w.length; i++) {
      final char = w[i];
      if ("aeiouy".contains(char)) {
        res.add("@"); // 统一标识为母音 (@ 不会与任何辅音字母冲突)
      } else if (char == 'S') {
        res.add("SH");
      } else if (char == 'C') {
        res.add("CH");
      } else if (char == 'T') {
        res.add("TH");
      } else if (char == 'G') {
        res.add("NG");
      } else if (RegExp(r'[a-z]').hasMatch(char)) {
        res.add(char.toUpperCase());
      }
    }

    // 3. 去重坍缩（防止叠音干扰，如 ttt -> T）
    List<String> collapsed = [];
    if (res.isNotEmpty) {
      collapsed.add(res[0]);
      for (var i = 1; i < res.length; i++) {
        if (res[i] == res[i - 1]) continue;
        collapsed.add(res[i]);
      }
    }
    return collapsed;
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
// ... 剩下的解析代码保持不变

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
      final phonemes = parts.sublist(1).map((p) => p.replaceAll(RegExp(r"\d+"), '')).toList();

      final variants = _wordToPhonemeVariants.putIfAbsent(word, () => <List<String>>[]);
      variants.add(phonemes);
    }
  }

  /// 将两个音素序列的距离映射为 0-100 相似度
  static int _phonemeSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;

    // 使用加权编辑距离，考虑常见的识别混淆
    final dist = _weightedPhonemeDistance(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    final score = ((maxLen - dist) * 100.0 / maxLen).clamp(0.0, 100.0).round();
    return score;
  }

  /// 针对英语音素特性的加权编辑距离
  static double _weightedPhonemeDistance(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0) return m.toDouble();
    if (m == 0) return n.toDouble();

    final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0.0));
    for (var i = 0; i <= n; i++) {
      dp[i][0] = i.toDouble();
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j.toDouble();
    }

    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        // 计算替换代价
        final cost = _phonemeMatchCost(a[i - 1], b[j - 1]);

        final del = dp[i - 1][j] + 1.0;
        final ins = dp[i][j - 1] + 1.0;
        final sub = dp[i - 1][j - 1] + cost;

        dp[i][j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
    }
    return dp[n][m];
  }

  /// 定义音素之间的匹配代价
  static double _phonemeMatchCost(String p1, String p2) {
    if (p1 == p2) return 0.0;

    // ASR 模型易混淆组（代价设为 0.2，表示 80% 相似度）
    // 主要是处理 V-L, L-R, B-P, F-V 等经典偏差
    const confusionGroups = [
      {"V", "L"}, // 解决用户反馈的预算/视频识别偏差
      {"V", "B"},
      {"V", "F"},
      {"L", "R"},
      {"B", "P"},
      {"D", "T"},
      {"G", "K"},
      {"S", "@"}, // 某些情况下元音和擦音混淆
      {"M", "N"},
    ];

    for (final group in confusionGroups) {
      if (group.contains(p1) && group.contains(p2)) return 0.2;
    }

    return 1.0; // 完全不相关的音素，替换代价为 1
  }
}
