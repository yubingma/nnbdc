import 'package:lpinyin/lpinyin.dart';
import 'package:nnbdc/util/utils.dart';

import 'cartesian_product.dart';

/// 认为两个发音匹配的最小相似度
const minSimularityForMatch = 0.7;

/// 声母相似度在整个拼音相似度中所占权重（略降权）
const shengmuSimilarityWeight = 0.4;

/// 韵母相似度在整个拼音相似度中所占权重（略升权，中文感知更依赖韵母）
const yunmuSimilarityWeight = 0.5;

/// 声调相似度在整个拼音相似度中所占权重（降权，容错更强）
const toneSimilarityWeight = 0.1;

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
  "i-v": 0.70, // i ~ ü
  "v-u": 0.40,
  "i-ie": 0.70,

  // 双元音接近
  "ai-ei": 0.60,
  "ai-ui": 0.40,
  "ei-ui": 0.45,
  "ao-ou": 0.65,
  "ao-iu": 0.35,
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
  "in-vn": 0.80,
  "in-i": 0.85,
  "in-v": 0.80,
  "un-vn": 0.60,

  // 后鼻音群
  "ang-eng": 0.50,
  "ang-ing": 0.40,
  "ang-ong": 0.60,
  "eng-ing": 0.60,
  "eng-ong": 0.55,
  "ing-ong": 0.45,
  "iong-ong": 0.60,
  "ong-ou": 0.60,
  "iong-iu": 0.60,

  // 近邻/插入元音差异
  "an-ang": 0.55,
  "en-eng": 0.55,
  "in-ing": 0.85,
  "u-ou": 0.50,
  "u-iu": 0.60,
  "v-iu": 0.70,
  "ou-iu": 0.75,
  "ou-v": 0.75,
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

  "i-yi": 0.95,
  "u-wu": 0.95,
  "v-yu": 0.95,

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
  static final List<String> zeroShengMuList = [
    "a",
    "ai",
    "an",
    "ang",
    "ao",
    "e",
    "ê",
    "ei",
    "en",
    "eng",
    "er",
    "o",
    "ou",
    "yi",
    "wu",
    "yu",
    "ye",
    "yue",
    "yuan",
    "yin",
    "yun",
    "ying"
  ];

  /// 双字母的声母
  /// zh
  /// ch
  /// sh
  ///
  /// @since 0.1.1
  static final List<String> doubleShengMuList = ["zh", "ch", "sh"];

  void parse() {
    if (pinyinWithTone.isEmpty) {
      shengMu = "";
      yunMu = "";
      tone = 0;
      return;
    }

    // 解析音调
    String lastChar = pinyinWithTone.substring(pinyinWithTone.length - 1);
    String pinyinNormal;
    if (RegExp(r'[0-9]').hasMatch(lastChar)) {
      pinyinNormal = pinyinWithTone.substring(0, pinyinWithTone.length - 1);
      tone = int.parse(lastChar);
    } else {
      pinyinNormal = pinyinWithTone;
      tone = 0;
    }

    if (pinyinNormal.isEmpty) {
      shengMu = "";
      yunMu = "";
      return;
    }

    // 解析声母
    shengMu = "";
    for (var zero in zeroShengMuList) {
      if (pinyinNormal.startsWith(zero)) {
        // 特殊处理 yi, wu, yu 等，它们本质上是 i, u, v 的零声母形式
        if (zero == "yi") {
          yunMu = "i${pinyinNormal.substring(2)}";
          return;
        } else if (zero == "wu") {
          yunMu = "u${pinyinNormal.substring(2)}";
          return;
        } else if (zero == "yu") {
          yunMu = "v${pinyinNormal.substring(2)}";
          return;
        } else if (zero == "yin") {
          yunMu = "in${pinyinNormal.substring(3)}";
          return;
        } else if (zero == "yun") {
          yunMu = "vn${pinyinNormal.substring(3)}";
          return;
        } else if (zero == "ying") {
          yunMu = "ing${pinyinNormal.substring(4)}";
          return;
        } else if (zero == "yuan") {
          yunMu = "van${pinyinNormal.substring(4)}";
          return;
        } else if (zero == "yue") {
          yunMu = "ve${pinyinNormal.substring(3)}";
          return;
        } else if (zero == "ye") {
          yunMu = "ie${pinyinNormal.substring(2)}";
          return;
        }

        // 其他情况，只要在 zeroShengMuList 中，shengMu 就是 ""
        shengMu = "";
        yunMu = pinyinNormal;
        return;
      }
    }

    String prefixDouble = pinyinNormal.length >= 2 ? pinyinNormal.substring(0, 2) : "";
    if (prefixDouble.isNotEmpty && doubleShengMuList.contains(prefixDouble)) {
      shengMu = prefixDouble;
    } else {
      // 返回第一个音节
      shengMu = pinyinNormal.substring(0, 1);
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



bool fuzzyChineseContains(Object chinese1, String chinese2) {
  if (chinese1 is List<String>) {
    for (final item in chinese1) {
      if (fuzzyChineseContains(item, chinese2)) {
        return true;
      }
    }
    return false;
  }

  var pinyin = chineseToPinyin2(chinese1.toString().replaceAll("  ", " "), true);

  var meaning = chinese2;
  meaning = meaning.replaceAll(RegExp("[（|\\(].*[）|\\)]"), "").replaceAll(RegExp("[\\[].*[\\]]"), ""); //去掉释义中包含在括号中的内容
  meaning = meaning.toLowerCase().replaceAll(RegExp(r"[^\u4e00-\u9fa5,，]"), "").trim(); // 去掉释义中的非汉字字符
  var meaningUnits = meaning.split(RegExp("[,，]"));

  var parts1Str = pinyin.toLowerCase().replaceAll(RegExp("[^a-z1-5\\s]"), "").trim();
  parts1Str = Util.replaceDoubleSpace(parts1Str);
  var parts1 = parts1Str.isEmpty ? <String>[] : parts1Str.split(" ");
  if (parts1.isEmpty) return false;

  for (var unit in meaningUnits) {
    if (unit.isEmpty) continue;

    // 获取 target 的每一个字的可能拼音
    List<List<String>> targetPinyins = [];
    for (var i = 0; i < unit.length; i++) {
      var hanzi = unit[i];
      var pinyins = hanziToPinyin(hanzi);
      var cleans = pinyins.map((p) => p.toLowerCase().replaceAll(RegExp("[^a-z1-5]"), "").trim()).where((p) => p.isNotEmpty).toList();
      if (cleans.isEmpty) cleans = [hanzi.toLowerCase()];
      targetPinyins.add(cleans);
    }

    // DP 求最大分值。这是一个顺序包含的匹配关系，也就是我们需要在 user 识别出的若干发音中，找出和 target按顺序匹配得最好的子集。
    int M = targetPinyins.length;
    int N = parts1.length;

    // dp[i][j] 为 target前i个字匹配 user前j个syllable 的最大分值
    List<List<double>> dp = List.generate(M + 1, (_) => List.filled(N + 1, 0.0));

    for (int i = 1; i <= M; i++) {
      for (int j = 1; j <= N; j++) {
        // 计算 target的第i个字（可能有多个发音）和 user的第j个音节(parts1[j-1])的最大相似度
        double maxSim = 0.0;
        for (var p2 in targetPinyins[i - 1]) {
          double sim = similarityOf2Pinyin(parts1[j - 1], p2);
          if (sim > maxSim) maxSim = sim;
        }

        double v1 = dp[i - 1][j];
        double v2 = dp[i][j - 1];
        double v3 = dp[i - 1][j - 1] + maxSim;

        double maxV = v1 > v2 ? v1 : v2;
        maxV = maxV > v3 ? maxV : v3;
        dp[i][j] = maxV;
      }
    }

    double maxSimSum = dp[M][N];
    double avgSim = maxSimSum / M;

    // 对于短句（3个字及以下），提高匹配门槛，防止被常用字干扰
    double finalThreshold = M <= 3 ? 0.60 : minSimularityForMatch;

    if (avgSim > finalThreshold) {
      return true;
    }
  }

  return false;
}
