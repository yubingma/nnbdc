import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/edit_distance.dart';
import 'package:nnbdc/util/phoneme_asset.dart';

class PhonemeUtil {
  static const String _assetPath = 'assets/cmudict.pho';

  /// 判定链路等待音素词典的上限。资源是预编译的紧凑查表格式，加载本身只要几十毫秒
  /// （无 UTF-8 解码 isolate、无解析 isolate），这里的余量是留给极端内存压力下的兜底。
  static const Duration loadTimeout = Duration(seconds: 20);

  static bool _loaded = false;

  /// 本次会话已认定音素词典不可用（加载失败或超时）。判定链路据此直接按拼写相似度降级，
  /// 不必每帧重等一遍超时；后台加载若最终成功，[_loaded] 会把它重新打开。
  static bool _unavailable = false;

  /// 进行中的加载，结束后清空 —— 失败/停摆不会被永久缓存成"永远加载中"。
  static Future<void>? _loading;

  static PhonemeAsset? _asset;
  static final RegExp _digitRegExp = RegExp(r'\d+'), _lowerAlphaRegExp = RegExp(r'[a-z]');

  /// 音素词典是否已就绪。
  static bool get isReady => _loaded;

  /// 预热音素词典：幂等，可在页面初始化时提前调用。永不抛出（失败只记日志）。
  static Future<void> load() async {
    if (_loaded) return;
    await _ensureLoading();
  }

  /// 判定链路专用：有界等待音素词典就绪，返回是否可用。
  /// 绝不抛出、绝不永久阻塞 —— 这是"说了半天没反应"这类静默故障的根治点。
  static Future<bool> ensureReady({Duration timeout = loadTimeout}) async {
    if (_loaded) return true;
    if (_unavailable) return false;
    try {
      await _ensureLoading().timeout(timeout);
      return _loaded;
    } on TimeoutException {
      _unavailable = true;
      Global.logger.e('PhonemeUtil: 音素词典等待 ${timeout.inMilliseconds}ms 仍未就绪，'
          '本次会话发音比对降级为拼写比对（后台加载仍在继续，若最终成功会自动恢复）');
      return false;
    }
  }

  static Future<void> _ensureLoading() {
    return _loading ??= _doLoad().whenComplete(() => _loading = null);
  }

  /// 真正的加载：永不抛出。失败时置 [_unavailable] 并打日志。
  /// 用 `rootBundle.load`（拿 ByteData）而不是 `loadString`：后者对 >50KB 的资源会另起
  /// isolate 做 UTF-8 解码，而紧凑资源是二进制查表格式，本来就不需要解码，更不需要解析。
  static Future<void> _doLoad() async {
    final sw = Stopwatch()..start();
    try {
      final data = await rootBundle.load(_assetPath);
      final asset = PhonemeAsset.fromBytes(data);
      _asset = asset;
      _loaded = true;
      Global.logger.i('PhonemeUtil: 音素词典就绪，共 ${asset.wordCount} 词，'
          '耗时 ${sw.elapsedMilliseconds}ms');
    } catch (e, st) {
      _unavailable = true;
      Global.logger.e('PhonemeUtil: 音素词典加载失败（耗时 ${sw.elapsedMilliseconds}ms），'
          '本次会话发音比对降级为拼写比对: $e', stackTrace: st);
    }
  }

  static Future<List<List<String>>> lookup(String word) async {
    // 词典未就绪时按"无音素"处理；是否值得等待由 ensureReady 有界决定，绝不在这里无限期挂住。
    if (!_loaded) {
      final ready = await ensureReady();
      if (!ready) return const [];
    }
    String key = word.trim().toLowerCase().replaceAll(RegExp(r'\(.*?\)'), '');
    if (key.isEmpty) return const [];
    final direct = _asset!.variantsOf(key);
    if (direct != null) return direct;
    final words = key.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > 1 && words.length <= 5) {
      List<List<String>> combined = [[]];
      for (final w in words) {
        final variants = _asset!.variantsOf(w);
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
    bool isContained = wA.length != wB.length && sA.contains(sB);
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

    double penaltyMult = isContained ? 0.3 : ((baseBest > 75 && wA.length >= wB.length) ? 0.5 : 1.0);
    
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
      // 1. 优先匹配英文常用双字母组合 (Consonant Digraphs)
      if (c == 'c' && i + 1 < w.length && w[i + 1] == 'h') {
        res.add("CH");
        i++;
      } else if (c == 's' && i + 1 < w.length && w[i + 1] == 'h') {
        res.add("SH");
        i++;
      } else if (c == 't' && i + 1 < w.length && w[i + 1] == 'h') {
        res.add("TH");
        i++;
      } else if (c == 'p' && i + 1 < w.length && w[i + 1] == 'h') {
        res.add("F");
        i++;
      } else if (c == 'c' && i + 1 < w.length && w[i + 1] == 'k') {
        res.add("K");
        i++;
      } else if (c == 'n' && i + 1 < w.length && w[i + 1] == 'g') {
        res.add("NG");
        i++;
      } else if (c == 'q' && i + 1 < w.length && w[i + 1] == 'u') {
        res.add("K");
        res.add("W");
        i++;
      }
      // 2. 元音处理
      else if ("aeiouy".contains(c)) {
        res.add("@");
      }
      // 3. 常见辅音字母处理
      else if ("rmnpbtdszfvkwy".contains(c)) {
        res.add(c.toUpperCase());
      }
      // 4. 软音变化 (Soft c & Soft g, 如 gem/cell) - 修正原先匹配下一个字符的 Bug
      else if (c == 'g' && i + 1 < w.length && "eiy".contains(w[i + 1])) {
        res.add("JH");
      } else if (c == 'c' && i + 1 < w.length && "eiy".contains(w[i + 1])) {
        res.add("S");
      } else if (c == 'x') {
        res.add("K");
        res.add("S");
      }
      // 5. 其他字母降级处理
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
      for (var i = 0; i <= n; i++) {
        dp[i][0] = 0.0;
      }
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
    // 组内音素视作近似同音（代价 0.2）。{L,R,ER} 里绝不能混入 D：L/R/ER 是流音与
    // 儿化音，D 是爆破塞音，二者并不混淆。一旦 D 也算 0.2，"worried" vs "fearful"
    // 这种听感差别很大的词就能靠"删掉一个辅音 + 把 L 当成 D"拼出一条极短的对齐路径，
    // 把弱化相似度抬得虚高，合成分越过判定线（实测 61 分；收紧后 38 分）。
    const g = [{"V", "L", "B", "F", "W"}, {"L", "R", "ER"}, {"B", "P"}, {"D", "T"}, {"G", "K"}, {"S", "Z"}, {"T", "CH", "SH"}, {"D", "JH"}, {"CH", "JH"}, {"JH", "R"}, {"IY", "IH", "Y"}, {"EY", "EH", "AE", "@"}, {"AA", "AH", "AO"}, {"UH", "UW", "W"}, {"OW", "OY", "AO"}, {"M", "N", "NG"}, {"Y", "@"}, {"W", "@"}, {"R", "@"}, {"L", "@"}, {"ER", "@"}, {"AH", "@"}, {"TH", "S", "T", "F"}, {"DH", "Z", "D", "V"}, {"F", "HH"}, {"OW", "UW"}];
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
