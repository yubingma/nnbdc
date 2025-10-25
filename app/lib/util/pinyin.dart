import 'package:nnbdc/global.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:nnbdc/util/utils.dart';

import 'cartesian_product.dart';
import 'clock_like_adder.dart';

/// 认为两个发音匹配的最小相似度
const minSimularityForMatch = 0.667;

/// 声母相似度在整个拼音相似度中所占权重（略降权）
const shengmuSimilarityWeight = 0.35;

/// 韵母相似度在整个拼音相似度中所占权重（略升权，中文感知更依赖韵母）
const yunmuSimilarityWeight = 0.5;

/// 声调相似度在整个拼音相似度中所占权重（降权，容错更强）
const toneSimilarityWeight = 0.15;

/// 声母相似度对照表（基于发音部位/方式与常见混淆）
Map<String, double> shengMuSimularityMap = {
  // 双清浊 / 清浊对（高相似）
  "b-p": 0.85,
  "d-t": 0.85,
  "g-k": 0.85,

  // 双唇音/唇齿音常见混淆
  "b-m": 0.50,
  "p-m": 0.50,
  "b-f": 0.50,
  "p-f": 0.60,
  "m-f": 0.40,
  "w-f": 0.25,

  // 齿龈与边音/鼻音的混淆
  "d-n": 0.60,
  "t-n": 0.55,
  "n-l": 0.65,
  "d-l": 0.50,
  "t-l": 0.50,
  "l-r": 0.35,

  // 软腭与声门擦音的混淆
  "g-h": 0.35,
  "k-h": 0.45,

  // 舌面前音组（alveolo-palatal）
  "j-q": 0.80,
  "j-x": 0.70,
  "q-x": 0.75,
  "j-y": 0.50,
  "q-y": 0.40,
  "x-y": 0.40,

  // 舌尖前后音混淆
  "z-zh": 0.60,
  "c-ch": 0.60,
  "s-sh": 0.60,
  "zh-ch": 0.70,
  "zh-sh": 0.70,
  "ch-sh": 0.70,

  // r 与卷舌擦音/舌尖音的混淆
  "zh-r": 0.55,
  "ch-r": 0.50,
  "sh-r": 0.50,
  "z-r": 0.35,
  "s-r": 0.35,
  "c-r": 0.35,
};

Map<String, double> yunMuSimularityMap = {
  // 单元音/半元音接近
  "o-e": 0.35,
  "o-u": 0.50,
  "e-u": 0.35,
  "i-v": 0.50, // i ~ ü
  "v-u": 0.40,

  // 双元音接近
  "ai-ei": 0.60,
  "ai-ui": 0.40,
  "ei-ui": 0.45,
  "ao-ou": 0.65,
  "ao-iu": 0.35,
  "ou-iu": 0.45,
  "ie-ve": 0.70,

  // 省略音节等价（书写差异）
  "ui-uei": 0.95,
  "iu-iou": 0.95,

  // 鼻化韵母接近（前鼻/后鼻 & 圆唇差异）
  "an-en": 0.45,
  "an-in": 0.35,
  "an-un": 0.35,
  "an-vn": 0.35,
  "en-in": 0.40,
  "en-vn": 0.40,
  "in-un": 0.35,
  "in-vn": 0.45,
  "un-vn": 0.60,

  // 后鼻音群
  "ang-eng": 0.50,
  "ang-ing": 0.40,
  "ang-ong": 0.60,
  "eng-ing": 0.60,
  "eng-ong": 0.55,
  "ing-ong": 0.45,
  "iong-ong": 0.60,

  // 近邻/插入元音差异
  "an-ang": 0.55,
  "en-eng": 0.55,
  "in-ing": 0.85,
  "u-ou": 0.50,
  "a-ua": 0.65,
  "uo-o": 0.70,
  "ua-a": 0.65,
  "ia-a": 0.60,

  // 复合韵近似
  "an-ian": 0.70,
  "an-uan": 0.70,
  "ian-uan": 0.70,
  "iao-ao": 0.60,
  "uan-an": 0.50,

  // 低相似示例（保留以区分）
  "an-ai": 0.30,
  "a-ai": 0.20,
};

/// 解析拼音中的声母和韵母
class PinyinParser {
  /// 不带声调的拼音
  String pinyinWithTone;

  late String shengMu;

  late String yunMu;

  late int tone;

  PinyinParser(this.pinyinWithTone) {
    parse();
  }

  /// 零声母列表
  /// a ai an ang ao e ê ei en eng er o ou
  ///
  /// @since 0.1.1
  static final List<String> zeroShengMuList = ["a", "ai", "an", "ang", "ao", "e", "ê", "ei", "en", "eng", "er", "o", "ou"];

  /// 双字母的声母
  /// zh
  /// ch
  /// sh
  ///
  /// @since 0.1.1
  static final List<String> doubleShengMuList = ["zh", "ch", "sh"];

  void parse() {
    // 解析音调
    String pinyinNormal = pinyinWithTone.substring(0, pinyinWithTone.length - 1);
    tone = int.parse(pinyinWithTone.substring(pinyinWithTone.length - 1));

    // 解析声母
    if (isZeroShengMu(pinyinNormal)) {
      shengMu = "";
    } else {
      final String prefixDouble = pinyinNormal.substring(0, 2);
      if (doubleShengMuList.contains(prefixDouble)) {
        shengMu = prefixDouble;
      } else {
        // 返回第一个音节
        shengMu = pinyinNormal.substring(0, 1);
      }
    }

    // 解析韵母
    yunMu = pinyinNormal.substring(shengMu.length);
  }

  bool isZeroShengMu(String pinyinNormal) {
    return zeroShengMuList.contains(pinyinNormal);
  }
}

/// 把汉字字符串转换为拼音(支持多多音字，比如输入"重庆"，则输出为：["chong2 qing4", "zhong4 qing4"])
List<String> chineseToPinyin(String chinese) {
  // 把每个汉字的拼音集合（一个汉字可能有多个拼音）放在数组中
  var chinese2 = Util.replaceDoubleSpace(chinese).replaceAll(" ", "");
  List<List<String>> allPinyins = []; // 每个汉字都可能有多个拼音
  for (var i = 0; i < chinese2.length; i++) {
    var hanzi = chinese2[i];
    var pinyins = hanziToPinyin((hanzi));
    allPinyins.add(pinyins);
  }

  // 获取所有汉字可能的拼音组合（笛卡尔积）
  List<String> pinyins = [];
  var allPossiablePinyins = PermutationAlgorithmStrings(allPinyins).permutations();
  for (var pinyin in allPossiablePinyins) {
    pinyins.add(pinyin.join(" "));
  }
  return pinyins;
}

/// 把汉字字符串转换为拼音
/// includeMutiPronounce： 是否包含多音字的多个拼音。比如"重庆"，包含"重"的多个拼音则为：chong2 zhong4 qing4
String chineseToPinyin2(String chinese, bool includeMutiPronounce) {
  List<String> allPinyins = [];
  var chinese_ = chinese.replaceAll(" ", "");
  for (var i = 0; i < chinese_.length; i++) {
    var hanzi = chinese_[i];
    var pinyins = hanziToPinyin((hanzi));
    if (includeMutiPronounce) {
      allPinyins.addAll(pinyins);
    } else {
      allPinyins.add(pinyins[0]);
    }
  }

  return allPinyins.join(" ");
}

/// 得到一个汉字的拼音（支持多音字）
List<String> hanziToPinyin(final String hanzi) {
  // 嗯的拼音使用新的拼音规范（n2, ng2, ng3, n3, ng4, n4），会导致后面的处理出现异常，规避之。其他一些特殊汉字也如此处理
  var hanzi2 = hanzi;
  if (hanzi2 == '嗯') {
    hanzi2 = '恩';
  } else if (hanzi2 == '儿') {
    // er2 r2
    hanzi2 = '而';
  } else if (hanzi2 == '哟' || hanzi2 == '唷') {
    // yo1 yo5
    hanzi2 = '优';
  }

  return PinyinHelper.convertToPinyinArray(hanzi2, PinyinFormat.WITH_TONE_NUMBER);
}

/// 判断pinyin是否模糊包含 pinyin's中的任一个字串
bool fuzzyContains(String pinyin, List<String> pinyins) {
  for (var unit in pinyins) {
    if (fuzzyPinyinContains(pinyin, unit)) {
      return true;
    }
  }
  return false;
}

/// 计算两个声母的发音相似度
///
/// @param shengMu1
/// @param shengMu2
/// @return
double similarityOf2ShengMu(String shengMu1, String shengMu2) {
  if (shengMu1 == shengMu2) {
    return 1.0;
  }
  var sim = shengMuSimularityMap["$shengMu1-$shengMu2"];
  sim ??= shengMuSimularityMap["$shengMu2-$shengMu1"];
  return sim ?? 0.0;
}

/// 计算两个韵母的发音相似度
///
/// @param yunMu1
/// @param yunMu2
/// @return
double similarityOf2YunMu(String yunMu1, String yunMu2) {
  if (yunMu1 == yunMu2) {
    return 1.0;
  }
  var sim = yunMuSimularityMap["$yunMu1-$yunMu2"];
  sim ??= yunMuSimularityMap["$yunMu2-$yunMu1"];
  return sim ?? 0.0;
}

/// 计算两个声调的发音相似度
///
/// @param tone1
/// @param tone2
/// @return
double similarityOf2Tone(int tone1, int tone2) {
  return tone1 == tone2 ? 1.0 : 0.0;
}

/// 计算两个拼音（都对应一个汉字）的发音相似性
///
/// @param pinyin1
/// @param pinyin2
/// @return
double similarityOf2Pinyin(String pinyin1, String pinyin2) {
  if (pinyin1.isEmpty || pinyin2.isEmpty) {
    return 0.0;
  }

  var parts1 = PinyinParser(pinyin1);
  var parts2 = PinyinParser(pinyin2);

  // 某些字特殊处理
  if (pinyin1 == "de5" && pinyin2 == "de5") {
    // 的
    return minSimularityForMatch;
  }
  var shengmuSim = similarityOf2ShengMu(parts1.shengMu, parts2.shengMu);
  var yunmuSim = similarityOf2YunMu(parts1.yunMu, parts2.yunMu);
  var toneSim = similarityOf2Tone(parts1.tone, parts2.tone);
  if (parts1.shengMu.isEmpty && parts2.shengMu.isEmpty) {
    return (yunmuSim * yunmuSimilarityWeight + toneSim * toneSimilarityWeight) / (yunmuSimilarityWeight + toneSimilarityWeight);
  } else {
    return shengmuSim * shengmuSimilarityWeight + yunmuSim * yunmuSimilarityWeight + toneSim * toneSimilarityWeight;
  }
}

/// 判断pinyin1是否包含pinyin2(均对应多个汉字)。
/// 注意，这里的包含是指模糊包含，即大致包含（发音相似）
bool fuzzyPinyinContains(String pinyin1, String pinyin2) {
  var p1 = pinyin1.toLowerCase().replaceAll(RegExp("[^a-z1-5\\s]"), "").trim(); // 去掉释义拼音中的非法字符
  p1 = Util.replaceDoubleSpace(p1);
  var p2 = pinyin2.toLowerCase().replaceAll(RegExp("[^a-z1-5\\s]"), "").trim(); // 去掉释义拼音中的非法字符
  p2 = Util.replaceDoubleSpace(p2);

  var parts1 = p1.split(" ");
  var parts2 = p2.split(" ");

  var simArray = List.generate(parts2.length, (i) => List.filled(parts1.length, 0.0, growable: false), growable: false);
  for (var i = 0; i < parts2.length; i++) {
    var part2 = parts2[i]; // part2是正确释义中一个汉字的拼音
    for (var j = 0; j < parts1.length; j++) {
      var part1 = parts1[j]; // part1是语音识别出的内容中一个汉字的拼音
      var sim = similarityOf2Pinyin(part1, part2);
      simArray[i][j] = sim;
    }
  }

  var maxSimSum = 0.0;
  var adder = ClockLikeAdder(simArray);
  maxSimSum = adder.maxSum(true);

  var sim = maxSimSum / parts2.length;

  var contains = sim > minSimularityForMatch;
  return contains;
}

/// 判断汉字字符串chinese1是否大致包含（发音大致相似）汉字字符串chinese2
/// 注：chinese2内容可能含有逗号，此时，chinese2被视为含有n个子串，只要chinese1包含其中一个子串，就认为chinese1包含chinese2
bool fuzzyChineseContains(String chinese1, String chinese2) {
  Global.logger.d('===== fuzzyChineseContains: $chinese1 - $chinese2');
  var pinyin = chineseToPinyin2(chinese1.replaceAll("  ", " "), true);

  var meaning = chinese2;
  meaning = meaning.replaceAll(RegExp("[（|\\(].*[）|\\)]"), "").replaceAll(RegExp("[\\[].*[\\]]"), ""); //去掉释义中包含在括号中的内容
  meaning = meaning.toLowerCase().replaceAll(RegExp(r"[^\u4e00-\u9fa5,，]"), "").trim(); // 去掉释义中的非汉字字符
  var meaningUnits = meaning.split(RegExp("[,，]"));
  List<String> meaningItemPartPinyin = [];
  for (var unit in meaningUnits) {
    meaningItemPartPinyin += chineseToPinyin(unit);
  }

  final byPinyin = fuzzyContains(pinyin, meaningItemPartPinyin);

  if (byPinyin) return true;

  // Fallback：中文字符级容错（允许少量缺字/多字，如“标出率”≈“标出格律”）
  final c1 = chinese1.toLowerCase().replaceAll(RegExp(r"[^\u4e00-\u9fa5]"), "");
  double bestLcsRatio = 0.0;
  for (var unit in meaningUnits) {
    final u = unit.replaceAll(RegExp(r"[^\u4e00-\u9fa5]"), "");
    if (u.isEmpty || c1.isEmpty) continue;
    final lcsLen = _lcsLength(c1, u);
    final ratio = lcsLen / u.length;
    if (ratio > bestLcsRatio) bestLcsRatio = ratio;
  }
  return bestLcsRatio >= 0.75; // 允许少量缺失/替换
}

/// 计算两个字符串的最长公共子序列长度（中文短串，性能足够）
int _lcsLength(String a, String b) {
  final n = a.length, m = b.length;
  if (n == 0 || m == 0) return 0;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (int i = 1; i <= n; i++) {
    for (int j = 1; j <= m; j++) {
      if (a[i - 1] == b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }
  return dp[n][m];
}
