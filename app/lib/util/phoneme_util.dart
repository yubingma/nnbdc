import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nnbdc/util/edit_distance.dart';

class PhonemeUtil {
  static const String _assetPath = 'assets/cmudict.dict';
  static Completer<void>? _loadCompleter;
  static bool _loaded = false;
  static final Map<String, List<List<String>>> _wordToPhonemeVariants = {};
  static final RegExp _digitRegExp = RegExp(r'\d+'), _cRegExp = RegExp(r'ce|ci|cy'), _lowerAlphaRegExp = RegExp(r'[a-z]');

  static Future<void> load() async {
    if (_loaded) return;
    if (_loadCompleter != null) return _loadCompleter!.future;
    _loadCompleter = Completer<void>();
    try {
      final content = await rootBundle.loadString(_assetPath);
      // 在后台 Isolate 中解析，避免阻塞主线程
      final parsedData = await compute(_parseInIsolate, content);
      _wordToPhonemeVariants.addAll(parsedData);
      _loaded = true;
      _loadCompleter!.complete();
    } catch (e, st) {
      _loadCompleter!.completeError(e, st);
      _loadCompleter = null;
    }
  }

  // 必须是顶级函数或静态函数才能用于 compute
  static Map<String, List<List<String>>> _parseInIsolate(String content) {
    final Map<String, List<List<String>>> data = {};
    for (var line in content.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      var head = parts.first;
      final pn = head.indexOf('(');
      if (pn > 0 && head.endsWith(')')) head = head.substring(0, pn);
      data
          .putIfAbsent(head.toLowerCase(), () => [])
          .add(parts.sublist(1).map((a) => a.replaceAll(RegExp(r'\d+'), '')).toList());
    }
    return data;
  }

  static Future<List<List<String>>> lookup(String word) async {
    if (!_loaded) await load();
    String key = word.trim().toLowerCase().replaceAll(RegExp(r'\(.*?\)'), '');
    if (key.isEmpty) return const [];
    if (_wordToPhonemeVariants.containsKey(key)) return _wordToPhonemeVariants[key]!;
    final words = key.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > 1 && words.length <= 5) {
      List<List<String>> combined = [[]];
      for (final w in words) {
        final variants = _wordToPhonemeVariants[w];
        if (variants == null || variants.isEmpty) return const [];
        List<List<String>> nextCombined = [];
        for (final cv in combined) {
          for (final v in variants) {
            nextCombined.add([...cv, ...v]);
          }
        }
        combined = nextCombined; if (combined.length > 32) combined = combined.sublist(0, 32);
      }
      return combined;
    }
    return const [];
  }

  static Future<int> similarity(String a, String b) async {
    if (a.isEmpty || b.isEmpty) return 0;
    final aC = a.toLowerCase().trim(), bC = b.toLowerCase().trim();
    if (aC == bC) return 100;
    final aVars = await lookup(a), bVars = await lookup(b);

    final wA = aC.split(RegExp(r'[\s\-]+')).where((w) => w.isNotEmpty).toList(), wB = bC.split(RegExp(r'[\s\-]+')).where((w) => w.isNotEmpty).toList();
    final sA = ' ${wA.join(' ')} ', sB = ' ${wB.join(' ')} ';
    bool isContained = wA.length != wB.length && (sA.contains(sB) || sB.contains(sA));
    bool useSubstring = wA.length != wB.length;
    
    int finalScore = 0, baseBest = 0;
    if (aVars.isNotEmpty && bVars.isNotEmpty) {
      for (var ap in aVars) {
        for (var bp in bVars) {
          final s = (_phonemeSimilarity(ap, bp, substring: useSubstring) * 0.4 + _phonemeSimilarity(_weakenPhonemes(ap), _weakenPhonemes(bp), substring: useSubstring) * 0.6).round();
          if (s > baseBest) baseBest = s;
        }
      }
      finalScore = baseBest;
    } else if (aVars.isNotEmpty || bVars.isNotEmpty) {
      final tps = aVars.isNotEmpty ? aVars : bVars, gWord = aVars.isNotEmpty ? b : a, gPseudo = _convertToPseudoPhonemes(gWord);
      for (final tp in tps) {
        final s = _phonemeSimilarity(_weakenPhonemes(tp), gPseudo, substring: useSubstring);
        if (s > baseBest) baseBest = s;
      }
      finalScore = baseBest - 2;
    } else {
      final dist = EditDistance.forStrings(aC, bC), maxL = aC.length > bC.length ? aC.length : bC.length;
      finalScore = maxL == 0 ? 0 : ((maxL - dist) * 100.0 / maxL).clamp(0.0, 100.0).round();
      baseBest = finalScore;
    }

    double penaltyMult = isContained ? 0.3 : (baseBest > 75 ? 0.5 : 1.0);
    
    if (isContained) finalScore += 10;
    finalScore -= ((wA.length - wB.length).abs() * 5 * penaltyMult).round();
    final aS = aVars.isNotEmpty ? _countSyllables(aVars.first) : _countSyllables(_convertToPseudoPhonemes(a));
    final bS = bVars.isNotEmpty ? _countSyllables(bVars.first) : _countSyllables(_convertToPseudoPhonemes(b));
    finalScore -= ((aS - bS).abs() * 8 * penaltyMult).round();
    
    final aPL = aVars.isNotEmpty ? aVars.first.length : _convertToPseudoPhonemes(a).length;
    final bPL = bVars.isNotEmpty ? bVars.first.length : _convertToPseudoPhonemes(b).length;
    final maxPL = aPL > bPL ? aPL : bPL;
    if (maxPL > 0) {
      final ratio = (aPL < bPL ? aPL : bPL) / maxPL;
      if (!isContained && ratio < (aVars.isEmpty || bVars.isEmpty ? 0.75 : 0.6)) {
        finalScore -= ((1.0 - ratio) * (aVars.isEmpty || bVars.isEmpty ? 25 : 15) * penaltyMult).round();
      }
    }
    return finalScore.clamp(0, 100);
  }

  static List<String> _weakenPhonemes(List<String> phons) {
    const v = {"AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW"};
    return phons.expand((p) {
      final base = p.replaceAll(_digitRegExp, '');
      if (base == "ER") return ["@", "R"];
      if (v.contains(base)) return ["@"];
      return [base];
    }).toList();
  }

  static List<String> _convertToPseudoPhonemes(String word) {
    final w = word.toLowerCase(); List<String> res = [];
    for (int i = 0; i < w.length; i++) {
      final c = w[i];
      if ("aeiouy".contains(c)) {
        res.add("@");
      } else if ("rmnpbtdszfvkwy".contains(c)) {
        res.add(c.toUpperCase());
      } else if (c == 'g' && i + 1 < w.length && _cRegExp.hasMatch(w[i + 1])) {
        res.add("JH");
      } else if (c == 'c' && i + 1 < w.length && _cRegExp.hasMatch(w[i + 1])) {
        res.add("S");
      } else if (c == 'x') { res.add("K"); res.add("S"); }
      else if (_lowerAlphaRegExp.hasMatch(c)) {
        if ("rl".contains(c) && i > 0 && i == w.length - 1 && !"aeiouy".contains(w[i - 1])) res.add("@");
        res.add(c.toUpperCase());
      }
    }
    List<String> collapsed = []; if (res.isNotEmpty) { collapsed.add(res[0]); for (var i = 1; i < res.length; i++) { if (res[i] != res[i - 1]) collapsed.add(res[i]); } }
    return collapsed;
  }


  static int _phonemeSimilarity(List<String> a, List<String> b, {bool substring = false}) {
    if (a.isEmpty || b.isEmpty) return 0;
    final isAInB = b.length > a.length;
    final long = isAInB ? b : a, short = isAInB ? a : b;

    if (substring) {
      final d = _weightedPhonemeDistance(long, short, substring: true);
      return ((short.length - d) * 100.0 / short.length).clamp(0.0, 100.0).round();
    } else {
      final d = _weightedPhonemeDistance(long, short, substring: false);
      final m = long.length;
      return ((m - d) * 100.0 / m).clamp(0.0, 100.0).round();
    }
  }

  static double _weightedPhonemeDistance(List<String> long, List<String> short, {bool substring = false}) {
    final n = long.length, m = short.length;
    final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0.0));
    double getC(List<String> l, int i) {
      if (l[i] == "@") return i == l.length - 1 ? 0.4 : 0.8;
      if (l[i] == "R" && i > 0 && ("TD".contains(l[i - 1]) || l[i - 1] == "@")) return 0.4;
      return 1.0;
    }

    if (substring) {
      for (var i = 0; i <= n; i++) dp[i][0] = 0.0;
    } else {
      for (var i = 1; i <= n; i++) {
        dp[i][0] = dp[i - 1][0] + getC(long, i - 1);
      }
    }
    for (var j = 1; j <= m; j++) {
      dp[0][j] = dp[0][j - 1] + getC(short, j - 1);
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final s = dp[i - 1][j - 1] + _phonemeMatchCost(long[i - 1], short[j - 1]);
        final d = dp[i - 1][j] + getC(long, i - 1);
        final ins = dp[i][j - 1] + getC(short, j - 1);
        dp[i][j] = [s, d, ins].reduce((v, e) => v < e ? v : e);
      }
    }

    if (substring) {
      double minD = dp[0][m];
      for (var i = 1; i <= n; i++) {
        if (dp[i][m] < minD) minD = dp[i][m];
      }
      return minD;
    }
    return dp[n][m];
  }

  static double _phonemeMatchCost(String p1, String p2) {
    if (p1 == p2) return 0.0;
    const g = [{"V", "L", "B", "F", "W"}, {"L", "R", "ER", "D"}, {"B", "P"}, {"D", "T"}, {"G", "K"}, {"S", "Z"}, {"T", "CH", "SH"}, {"D", "JH"}, {"JH", "R"}, {"IY", "IH", "Y"}, {"EY", "EH", "AE", "@"}, {"AA", "AH", "AO"}, {"UH", "UW", "W"}, {"OW", "OY", "AO"}, {"M", "N", "NG"}, {"Y", "@"}, {"W", "@"}, {"R", "@"}, {"L", "@"}, {"ER", "@"}, {"AH", "@"}, {"TH", "S", "T", "F"}, {"DH", "Z", "D", "V"}];
    for (final gi in g) {
      if (gi.contains(p1) && gi.contains(p2)) {
        return 0.2;
      }
    }
    const l = {"L", "R", "ER", "W", "Y"}, n = {"M", "N", "NG"}, o = {"P", "B", "T", "D", "K", "G", "CH", "JH", "F", "V", "TH", "DH", "S", "Z", "SH", "ZH", "HH"};
    if ((l.contains(p1) && (n.contains(p2) || o.contains(p2))) || (l.contains(p2) && (n.contains(p1) || o.contains(p1))) || (n.contains(p1) && o.contains(p2)) || (n.contains(p2) && o.contains(p1))) return 1.9;
    return 1.2;
  }

  static int _countSyllables(List<String> p) {
    const v = {"AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW", "@"};
    return p.where((x) => v.contains(x.replaceAll(_digitRegExp, ''))).length;
  }
}
