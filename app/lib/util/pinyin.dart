import 'dart:async';
import 'package:lpinyin/lpinyin.dart';
import 'package:nnbdc/global.dart';
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
  "b-d": 0.75,

  // 双唇音/唇齿音常见混淆
  "b-m": 0.50,
  "p-m": 0.50,
  "b-f": 0.50,
  "p-f": 0.60,
  "m-f": 0.40,
  "w-f": 0.60,
  "m-w": 0.60,

  // 齿龈与边音/鼻音的混淆
  "d-n": 0.60,
  "t-n": 0.55,
  "n-l": 0.75, // 边鼻音混淆（提升权重）
  "d-l": 0.50,
  "t-l": 0.50,
  "l-r": 0.55, // 边音/卷舌音混淆

  // 软腭与声门擦音的混淆
  "g-h": 0.35,
  "k-h": 0.70, // 常用混淆（如：看/汉，苦/胡）

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

  // --- 新增常见混淆 ---
  "f-h": 0.75, // 常用南方口音（胡/夫不分）
  "m-n": 0.60, // 鼻音混淆
  "r-y": 0.40,
  "n-y": 0.82, // 新增：支持“n-y”声母模糊匹配 (如：牛-you)
  "b-w": 0.50, // 新增：支持“巴苦” (bā kǔ) 匹配 “挖苦” (wā kǔ)
  "z-c": 0.85,
  "z-s": 0.80,
  "c-s": 0.80, // 新增：支持“此时” (cǐ shí) 匹配 “四十” (sì shí)
};

Map<String, double> yunMuSimularityMap = {
  // 单元音/半元音接近
  "o-e": 0.35,
  "o-u": 0.85,
  "e-u": 0.85,
  "i-v": 0.70, // i ~ ü
  "v-u": 0.40,
  "i-ie": 0.85,

  // 双元音接近
  "ai-ei": 0.60,
  "ai-ui": 0.40,
  "ei-ui": 0.45,
  "ao-ou": 0.65,
  "ao-iu": 0.35,
  "ie-ve": 0.70,

  // 省略音节等价（书写差异）
  "ie-v": 0.65,
  "ve-v": 0.65,
  "ui-uei": 0.95,
  "ei-uei": 0.90,
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
  "eng-ong": 0.65, // 从 0.55 略升
  "ing-ong": 0.55, // 从 0.45 略升
  "iong-ong": 0.60,
  "ong-ou": 0.60,
  "iong-iu": 0.60,

  // 近邻/插入元音差异
  "an-ang": 0.75, // 前后鼻音混淆（提升权重，原 0.55）
  "en-eng": 0.75, // 前后鼻音混淆（提升权重，原 0.55）
  "in-ing": 0.80, // 前后鼻音混淆（维持高权重，平衡 consistency）
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
  "en-un": 0.75,
  "uan-un": 0.70,
  "en-uan": 0.50,
  "ian-uan": 0.70,
  "iao-ao": 0.60,
  "uan-an": 0.60, // 从 0.50 略升
  "ian-ie": 0.65, // 常用混淆（如：没见/媒介）
  "ian-an": 0.60, // 新增
  "e-an": 0.45, // 模糊混淆（如：这都/战斗）

  "i-un": 0.35, // 模糊混淆（如：顺利/视力）
  "ie-ing": 0.40, // 模糊混淆（如：下令/下列）
  "ao-o": 0.60, // 模糊混淆（如：毛型/模型）
  "an-a": 0.60, // 模糊混淆（如：毛饭/毛发）
  "ang-a": 0.60, // 模糊混淆（如：投放/头发）
  "e-ang": 0.60, // 模糊混淆（如：大哥/大纲）
  "in-van": 0.60, // 模糊混淆（如：挑衅/挑选）
  "a-en": 0.20, // 模糊混淆（如：那肉/嫩肉）
  "in-iang": 0.80, // 模糊混淆（如：树林/数量）
  "i-yi": 0.95,
  "u-wu": 0.95,
  "v-yu": 0.95,

  // 低相似示例（保留以区分）
  "an-ai": 0.45,
  "ai-ang": 0.35, // 模糊匹配（如：大概/大纲）
  "a-ai": 0.20,
  "i-ao": 0.20, // 新增：支持“打死” (dǎ sǐ) 匹配 “打扫” (dǎ sǎo)
  "uan-ua": 0.80, // 新增：支持“转” (zhuǎn) 匹配 “爪” (zhuǎ)
  "ang-ao": 0.60, // 新增：支持“对账” (duì zhàng) 匹配 “对照” (duì zhào)
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
    if (pinyinWithTone.isEmpty) {
      shengMu = "";
      yunMu = "";
      tone = 0;
      return;
    }

    // 解析音调
    String lastChar = pinyinWithTone.substring(pinyinWithTone.length - 1);
    String pinyinNormal;
    if (_digitRegExp.hasMatch(lastChar)) {
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
        shengMu = "";
        yunMu = pinyinNormal;

        // 特殊处理 yi, wu, yu 等，标准化韵母
        if (pinyinNormal == "wu") {
          yunMu = "u";
        } else if (pinyinNormal == "yi") {
          yunMu = "i";
        } else if (pinyinNormal == "yu") {
          yunMu = "v";
        } else if (pinyinNormal == "yin") {
          yunMu = "in";
        } else if (pinyinNormal == "yun") {
          yunMu = "vn";
        } else if (pinyinNormal == "ying") {
          yunMu = "ing";
        } else if (pinyinNormal == "yuan") {
          yunMu = "van";
        } else if (pinyinNormal == "yue") {
          yunMu = "ve";
        } else if (pinyinNormal == "ye") {
          yunMu = "ie";
        }
        return;
      }
    }

    // 处理 w 和 y 开头的音节，将其视为声母 (为了 fuzzy match)
    if (pinyinNormal.startsWith('w')) {
      shengMu = "w";
      yunMu = pinyinNormal.substring(1);
      if (yunMu.isEmpty) yunMu = "u"; // 处理 "wu" -> "w" + "u"
      return;
    }
    if (pinyinNormal.startsWith('y')) {
      shengMu = "y";
      yunMu = pinyinNormal.substring(1);
      if (yunMu.isEmpty) yunMu = "i"; // 处理 "yi" -> "y" + "i"
      if (pinyinNormal == "you") yunMu = "iu"; // 标准化：you 的实际韵母与 iu 相同，皆为 iou
      return;
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

    // 标准拼音中，j q x y 后的 u 实际上是 ü (在这里用 v 表示)
    if ((shengMu == "j" || shengMu == "q" || shengMu == "x" || shengMu == "y") && yunMu.startsWith("u")) {
      yunMu = "v${yunMu.substring(1)}";
    }
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
    return ['yo1', 'yao1', 'you1'];
  }

  var pinyins = PinyinHelper.convertToPinyinArray(hanzi2, PinyinFormat.WITH_TONE_NUMBER);
  // 过滤在现代汉语中极罕见/已不使用的古音、异读音，防范 ASR 错配
  if (hanzi2 == '枝') {
    pinyins = pinyins.where((p) => p != 'qi2').toList();
  }
  return pinyins;
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
  // 零声母与半元音 y, w 的相似度（如：阿姨 - 牙医）
  if ((shengMu1 == "" && (shengMu2 == "y" || shengMu2 == "w")) || (shengMu2 == "" && (shengMu1 == "y" || shengMu1 == "w"))) {
    return 0.6;
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

final RegExp _digitRegExp = RegExp(r'[0-9]');
final RegExp _bracketRegExp1 = RegExp(r"[（\(].*[）\)]");
final RegExp _bracketRegExp2 = RegExp(r"\[.*\]");
final RegExp _nonChineseRegExp = RegExp(r"[^\u4e00-\u9fa5,，]");
final RegExp _commaRegExp = RegExp(r"[,，]");
final RegExp _nonPinyinRegExp = RegExp(r"[^a-z1-5]");

/// 计算两个拼音（都对应一个汉字）的发音相似性
///
/// @param parts1
/// @param parts2
/// @return
double similarityOf2ParsedPinyin(PinyinParser parts1, PinyinParser parts2) {
  var shengmuSim = similarityOf2ShengMu(parts1.shengMu, parts2.shengMu);
  var yunmuSim = similarityOf2YunMu(parts1.yunMu, parts2.yunMu);
  var toneSim = similarityOf2Tone(parts1.tone, parts2.tone);
  if (parts1.shengMu.isEmpty && parts2.shengMu.isEmpty) {
    return (yunmuSim * yunmuSimilarityWeight + toneSim * toneSimilarityWeight) / (yunmuSimilarityWeight + toneSimilarityWeight);
  } else {
    return shengmuSim * shengmuSimilarityWeight + yunmuSim * yunmuSimilarityWeight + toneSim * toneSimilarityWeight;
  }
}

/// 计算两个拼音（都对应一个汉字）的发音相似性
/// (向后兼容方法)
double similarityOf2Pinyin(String pinyin1, String pinyin2) {
  if (pinyin1.isEmpty || pinyin2.isEmpty) {
    return 0.0;
  }
  var parts1 = PinyinParser(pinyin1);
  var parts2 = PinyinParser(pinyin2);
  return similarityOf2ParsedPinyin(parts1, parts2);
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

  String asrText = chinese1.toString().replaceAll(_nonChineseRegExp, "");
  if (asrText.isEmpty) return false;

  var meaning = chinese2;
  meaning = meaning.replaceAll(_bracketRegExp1, "").replaceAll(_bracketRegExp2, ""); //去掉释义中包含在括号中的内容
  meaning = meaning.toLowerCase().replaceAll(_nonChineseRegExp, "").trim(); // 去掉释义中的非汉字字符
  var meaningUnits = meaning.split(_commaRegExp);

  for (var unit in meaningUnits) {
    if (unit.isEmpty) continue;

    int M = unit.length;
    
    // 核心优化：为了防止 ASR 长期累积的长句或背景噪声导致字数惩罚过重，
    // 我们从 ASR 文本（特别是最近说出的末尾部分）中提取长度为 M 到 M+3 的滑动窗口子串作为候选。
    List<String> subCandidates = [asrText];
    int startIdx = asrText.length > 12 ? asrText.length - 12 : 0;
    String recentText = asrText.substring(startIdx);
    for (int len = M; len <= M + 3; len++) {
      for (int i = 0; i <= recentText.length - len; i++) {
        String sub = recentText.substring(i, i + len);
        if (!subCandidates.contains(sub)) {
          subCandidates.add(sub);
        }
      }
    }

    // 对每个候选子串进行 DP 匹配，只要有一个通过，该 unit 即匹配成功
    bool unitMatched = false;
    for (var cand in subCandidates) {
      if (_matchSingleCandidate(cand, unit)) {
        unitMatched = true;
        break;
      }
    }
    
    if (unitMatched) {
      return true;
    }
  }

  return false;
}

/// 针对单个候选文本的拼音模糊匹配（核心 DP 算法）
bool _matchSingleCandidate(String asrText, String unit) {
  if (asrText.isEmpty) return false;

  List<List<PinyinParser>> userPinyins = [];
  for (var i = 0; i < asrText.length; i++) {
    var hanzi = asrText[i];
    var pinyins = hanziToPinyin(hanzi);
    userPinyins.add(pinyins.map((p) => PinyinParser(p)).toList());
  }

  // 获取 target 的每一个字的可能拼音
  List<List<PinyinParser>> targetPinyins = [];
  for (var i = 0; i < unit.length; i++) {
    var hanzi = unit[i];
    var pinyins = hanziToPinyin(hanzi);
    var cleans = pinyins.map((p) => p.toLowerCase().replaceAll(_nonPinyinRegExp, "").trim()).where((p) => p.isNotEmpty).toList();
    if (cleans.isEmpty) cleans = [hanzi.toLowerCase()];
    targetPinyins.add(cleans.map((p) => PinyinParser(p)).toList());
  }

  int M = targetPinyins.length;
  int N = userPinyins.length;

  List<List<double>> dp = List.generate(M + 1, (_) => List.filled(N + 1, 0.0));

  for (int i = 1; i <= M; i++) {
    for (int j = 1; j <= N; j++) {
      double maxSim = 0.0;
      for (var pTarget in targetPinyins[i - 1]) {
        for (var pUser in userPinyins[j - 1]) {
          double sim = similarityOf2ParsedPinyin(pUser, pTarget);
          if (sim > maxSim) maxSim = sim;
        }
      }

      double v1 = dp[i - 1][j];
      double v2 = dp[i][j - 1];
      double v3 = dp[i - 1][j - 1] + maxSim;

      if (maxSim <= 0.3 && j >= 2) {
        bool isConsecutiveDuplicate =
            userPinyins[j - 1].any((p1) => userPinyins[j - 2].any((p2) => p1.shengMu == p2.shengMu && p1.yunMu == p2.yunMu));
        if (isConsecutiveDuplicate) {
          double vSkip = dp[i - 1][j];
          if (maxSim < 0.31 && vSkip > 0.9) {
            v3 = vSkip;
          }
        }
      }

      if (N > 1 && i >= 2 && dp[i - 1][j] > dp[i - 2][j]) {
        bool hasBridge = false;
        for (var pPrev in targetPinyins[i - 2]) {
          for (var pCurr in targetPinyins[i - 1]) {
            String firstVowel = pCurr.yunMu.isNotEmpty ? pCurr.yunMu.substring(0, 1) : "";
            bool isVowelBridgeStart = (pCurr.shengMu.isEmpty && (firstVowel == 'i' || firstVowel == 'u' || firstVowel == 'v')) ||
                (pCurr.shengMu == 'y') ||
                (pCurr.shengMu == 'w');

            if (isVowelBridgeStart) {
              String bridgeVowel = pCurr.shengMu == 'w' ? 'u' : (pCurr.shengMu == 'y' ? 'i' : firstVowel);
              if (pCurr.shengMu == 'y' && pCurr.yunMu.startsWith('v')) bridgeVowel = 'v';

              if (pPrev.yunMu.endsWith(bridgeVowel) ||
                  (pPrev.yunMu.contains(bridgeVowel) && (pPrev.yunMu.endsWith('n') || pPrev.yunMu.endsWith('g')))) {
                hasBridge = true;
                break;
              }
            }
          }
          if (hasBridge) break;
        }

        if (hasBridge) {
          double mergedSim = 0.8;
          double v4 = dp[i - 1][j] * mergedSim;
          if (v4 > v3) v3 = v4;
        }
      }

      double maxV = v1 > v2 ? v1 : v2;
      maxV = maxV > v3 ? maxV : v3;
      dp[i][j] = maxV;
    }
  }

  double maxSimSum = dp[M][N];
  double avgSim = maxSimSum / M;

  int asrCharCount = asrText.length;
  if (asrCharCount < M && asrCharCount >= 1) {
    double avgSimOfMatched = maxSimSum / asrCharCount;
    if (avgSimOfMatched > 0.92) {
      avgSim = (avgSim + avgSimOfMatched) / 2;
    }
  }

  if (asrCharCount >= M) {
    double avgSimOfMatched = maxSimSum / asrCharCount;
    if (avgSimOfMatched > 0.92) {
      avgSim = avgSimOfMatched;
    }
  }

  if (asrCharCount > M) {
    double factor = M <= 2 ? 0.03 : 0.025;
    double penalty = 1.0 - factor * (asrCharCount - M);
    double minPenalty = M <= 2 ? 0.70 : 0.75;
    if (penalty < minPenalty) penalty = minPenalty;
    avgSim *= penalty;
  }

  double finalThreshold = M == 1 ? 0.82 : (M == 2 ? 0.72 : (M == 3 ? 0.76 : (M == 4 ? 0.74 : minSimularityForMatch)));

  if (avgSim > finalThreshold) {
    return true;
  }

  if (asrCharCount >= 2) {
    bool hasConsecutiveDuplicate = false;
    for (int i = 1; i < asrText.length; i++) {
      if (asrText[i] == asrText[i - 1]) {
        hasConsecutiveDuplicate = true;
        break;
      }
    }
    if (hasConsecutiveDuplicate) {
      StringBuffer deduped = StringBuffer();
      for (int i = 0; i < asrText.length; i++) {
        if (i == 0 || asrText[i] != asrText[i - 1]) {
          deduped.write(asrText[i]);
        }
      }
      String dedupedText = deduped.toString();
      if (dedupedText.length < asrCharCount) {
        return _matchSingleCandidate(dedupedText, unit);
      }
    }
  }

  return false;
}

/// 异步预热拼音词典，避免首次匹配时加载词典文件引发的数秒卡顿
void prewarmPinyin() {
  unawaited(() async {
    try {
      final stopwatch = Stopwatch()..start();
      // 触发一次简单的拼音转换，迫使 lpinyin 加载并解析其内部的大型字典数据
      hanziToPinyin('热');
      Global.logger.i('🔊 [Pinyin] 拼音词典预热完成，耗时: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      Global.logger.w('🔊 [Pinyin] 预热拼音词典失败: $e');
    }
  }());
}
