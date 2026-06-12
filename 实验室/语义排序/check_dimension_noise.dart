import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Uint8List decodeHex(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < result.length; i++) {
    final high = int.parse(hex[i * 2], radix: 16);
    final low = int.parse(hex[i * 2 + 1], radix: 16);
    result[i] = (high << 4) | low;
  }
  return result;
}

int editDistance(String s1, String s2) {
  int m = s1.length;
  int n = s2.length;
  // Optimize DP memory
  List<int> prev = List.generate(n + 1, (j) => j);
  List<int> curr = List.filled(n + 1, 0);

  for (int i = 1; i <= m; i++) {
    curr[0] = i;
    for (int j = 1; j <= n; j++) {
      if (s1[i - 1] == s2[j - 1]) {
        curr[j] = prev[j - 1];
      } else {
        int min = prev[j] < curr[j - 1] ? prev[j] : curr[j - 1];
        min = min < prev[j - 1] ? min : prev[j - 1];
        curr[j] = 1 + min;
      }
    }
    List<int> temp = prev;
    prev = curr;
    curr = temp;
  }
  return prev[n];
}

bool isMorphologicalPair(String s1, String s2) {
  if (s1 == s2) return false;
  if (s1.length < 4 || s2.length < 4) return false;
  // Fast prefix filter: must share first 4 characters
  if (s1[0] != s2[0] || s1[1] != s2[1] || s1[2] != s2[2] || s1[3] != s2[3]) {
    return false;
  }
  if ((s1.length - s2.length).abs() > 3) return false;
  return editDistance(s1, s2) <= 3;
}

class WordRecord {
  final String spell;
  final Uint8List embedding;
  WordRecord(this.spell, this.embedding);
}

void main() async {
  final wordsFile = File('实验室/语义排序/words_10k.jsonl');
  if (!wordsFile.existsSync()) {
    print('Error: words_10k.jsonl not found');
    return;
  }
  final List<WordRecord> words = [];
  final List<String> lines = wordsFile.readAsLinesSync();
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final Map<String, dynamic> record = jsonDecode(line);
    final String spell = record['spell'];
    final String hexEmb = record['embedding1bit'];
    words.add(WordRecord(spell, decodeHex(hexEmb)));
  }
  print('已加载 ${words.length} 个单词。');

  // 1. 寻找同根词/形态近邻对
  print('正在提取局部形态近邻词对...');
  final List<List<int>> pairs = [];
  
  // To speed up, we group words by their first 4 chars
  final Map<String, List<int>> groups = {};
  for (int i = 0; i < words.length; i++) {
    final spell = words[i].spell;
    if (spell.length >= 4) {
      final prefix = spell.substring(0, 4).toLowerCase();
      groups.putIfAbsent(prefix, () => []).add(i);
    }
  }

  for (final prefixList in groups.values) {
    for (int i = 0; i < prefixList.length; i++) {
      for (int j = i + 1; j < prefixList.length; j++) {
        final idxA = prefixList[i];
        final idxB = prefixList[j];
        if (isMorphologicalPair(words[idxA].spell, words[idxB].spell)) {
          pairs.add([idxA, idxB]);
        }
      }
    }
  }
  print('共提取到 ${pairs.length} 对形态近邻词对（例如 create/creative, differ/different 等）。');

  if (pairs.isEmpty) {
    print('没有提取到有效词对，退出。');
    return;
  }

  // 打印前几个词对作为示例
  print('近邻词对示例:');
  for (int i = 0; i < (pairs.length < 10 ? pairs.length : 10); i++) {
    final p = pairs[i];
    print('  - ${words[p[0]].spell} <-> ${words[p[1]].spell}');
  }

  // 2. 统计所有 2048 维度的噪声得分 (Noise Score = 翻转率)
  print('\n正在计算 2048 个维度的局部噪声得分与信息熵...');
  final List<double> flipRates = List.filled(2048, 0.0);
  final List<double> entropyRatios = List.filled(2048, 0.0);

  // 计算每个维度上 1 的占比，计算熵值
  final List<int> bitCounts = List.filled(2048, 0);
  for (final w in words) {
    for (int d = 0; d < 2048; d++) {
      final int byteIdx = d ~/ 8;
      final int bitIdx = d % 8;
      if ((w.embedding[byteIdx] & (1 << bitIdx)) != 0) {
        bitCounts[d]++;
      }
    }
  }

  for (int d = 0; d < 2048; d++) {
    // 占比越接近 0.5，高熵程度越高
    entropyRatios[d] = bitCounts[d] / words.length;
  }

  // 计算翻转数
  final List<int> flipCounts = List.filled(2048, 0);
  for (final p in pairs) {
    final embA = words[p[0]].embedding;
    final embB = words[p[1]].embedding;
    for (int d = 0; d < 2048; d++) {
      final int byteIdx = d ~/ 8;
      final int bitIdx = d % 8;
      final bool bitA = (embA[byteIdx] & (1 << bitIdx)) != 0;
      final bool bitB = (embB[byteIdx] & (1 << bitIdx)) != 0;
      if (bitA != bitB) {
        flipCounts[d]++;
      }
    }
  }

  for (int d = 0; d < 2048; d++) {
    flipRates[d] = flipCounts[d] / pairs.length;
  }

  // 3. 分析当前选取的 64 位高熵维度
  final List<int> current64 = [
    1826, 1699, 1458, 912, 1660, 93, 788, 1966, 1632, 187,
    1351, 8, 1189, 1483, 257, 979, 1806, 1608, 1544, 1712,
    2009, 2003, 675, 214, 197, 563, 842, 1776, 1968, 583,
    1833, 427, 110, 1656, 956, 2007, 74, 227, 1883, 33,
    86, 1416, 1468, 2027, 1284, 995, 235, 1706, 985, 1644,
    1599, 711, 1218, 275, 174, 1005, 412, 789, 2022, 1362,
    1692, 593, 69, 81
  ];

  print('\n=== 当前 64 位高熵维度噪声分析 ===');
  int noiseCount = 0;
  final List<Map<String, dynamic>> current64Analyzed = [];
  for (final d in current64) {
    final double flip = flipRates[d];
    final double ratio = entropyRatios[d];
    final isNoise = flip > 0.35; // 超过 35% 局部翻转即认为是明显噪声
    if (isNoise) noiseCount++;
    current64Analyzed.add({
      'dim': d,
      'flipRate': flip,
      'ratio': ratio,
      'status': isNoise ? '⚠️ 噪声' : '✅ 黄金'
    });
  }

  current64Analyzed.sort((a, b) => (b['flipRate'] as double).compareTo(a['flipRate'] as double));
  print('当前 64 维度中发现 $noiseCount 个高翻转率的疑似噪声维度 (阈值 > 35%)：');
  for (final item in current64Analyzed) {
    print('  - 维度 ${item['dim'].toString().padLeft(4)}: 1占比=${item['ratio'].toStringAsFixed(3)}, 近邻翻转率=${item['flipRate'].toStringAsFixed(3)} [${item['status']}]');
  }

  // 4. 进行黄金筛选：寻找高熵（1占比在 0.35 ~ 0.65 之间）且低噪声（翻转率 < 0.20）的维度
  print('\n=== 重新筛选：高熵且低噪声的黄金维度 ===');
  final List<MapEntry<int, double>> candidates = [];
  for (int d = 0; d < 2048; d++) {
    final double ratio = entropyRatios[d];
    final double flip = flipRates[d];
    // 宽泛的高熵条件：1 占比在 0.35 到 0.65 之间
    if (ratio >= 0.35 && ratio <= 0.65) {
      candidates.add(MapEntry(d, flip));
    }
  }

  // 按翻转率（噪声得分）从小到大排序
  candidates.sort((a, b) => a.value.compareTo(b.value));

  print('在高熵区间 (0.35 <= ratio <= 0.65) 中，噪声最低的前 64 个黄金维度：');
  final List<int> new64 = [];
  for (int i = 0; i < 64 && i < candidates.length; i++) {
    final d = candidates[i].key;
    final flip = candidates[i].value;
    new64.add(d);
    if (i < 15) {
      print('  - 维度 ${d.toString().padLeft(4)}: 1占比=${entropyRatios[d].toStringAsFixed(3)}, 近邻翻转率=${flip.toStringAsFixed(3)}');
    }
  }
  print('  ... （省略后 49 个，已提取全部 64 个）');

  print('\n新筛选的 64 位【高熵低噪】维度数组为：');
  print('[${new64.join(', ')}]');
  
  // 计算重合度
  final overlap = current64.toSet().intersection(new64.toSet()).length;
  print('\n新旧维度重合度：$overlap / 64。新方案替换了 ${64 - overlap} 个噪声较大的高熵维度！');
}
