import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Fast 32-bit bitwise popcount
int popCount32(int x) {
  x = x - ((x >>> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >>> 2) & 0x33333333);
  x = (x + (x >>> 4)) & 0x0f0f0f0f;
  return ((x * 0x01010101) >>> 24) & 0xff;
}

int computeHammingDistance(Uint32List a, Uint32List b) {
  int dist = 0;
  for (int i = 0; i < 64; i++) {
    int xor = a[i] ^ b[i];
    xor = xor - ((xor >>> 1) & 0x55555555);
    xor = (xor & 0x33333333) + ((xor >>> 2) & 0x33333333);
    xor = (xor + (xor >>> 4)) & 0x0f0f0f0f;
    dist += ((xor * 0x01010101) >>> 24) & 0xff;
  }
  return dist;
}

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
  if (s1[0] != s2[0] || s1[1] != s2[1] || s1[2] != s2[2] || s1[3] != s2[3]) {
    return false;
  }
  if ((s1.length - s2.length).abs() > 3) return false;
  return editDistance(s1, s2) <= 3;
}

class WordRecord {
  final String id;
  final String spell;
  final Uint8List embedding;
  final Uint32List emb32;
  late Uint32List signature;

  WordRecord(this.id, this.spell, this.embedding) : emb32 = _buildEmb32(embedding);

  static Uint32List _buildEmb32(Uint8List emb) {
    final aligned = Uint8List(256)..setAll(0, emb);
    return Uint32List.view(aligned.buffer);
  }
}

final List<int> old64 = [
  1826, 1699, 1458, 912, 1660, 93, 788, 1966, 1632, 187,
  1351, 8, 1189, 1483, 257, 979, 1806, 1608, 1544, 1712,
  2009, 2003, 675, 214, 197, 563, 842, 1776, 1968, 583,
  1833, 427, 110, 1656, 956, 2007, 74, 227, 1883, 33,
  86, 1416, 1468, 2027, 1284, 995, 235, 1706, 985, 1644,
  1599, 711, 1218, 275, 174, 1005, 412, 789, 2022, 1362,
  1692, 593, 69, 81
];

final List<int> new64 = [
  1897, 1105, 515, 511, 1852, 146, 1958, 252, 1630, 1420,
  1327, 1868, 454, 1805, 892, 1428, 1947, 35, 477, 855,
  1067, 1219, 381, 1879, 211, 486, 718, 29, 404, 986,
  787, 1312, 1059, 1429, 937, 503, 1913, 1921, 589, 598,
  969, 1071, 617, 440, 940, 1494, 18, 68, 874, 1800,
  1469, 783, 1863, 463, 972, 1514, 458, 1893, 1480, 1686,
  1096, 561, 723, 1039
];

void buildSignatures(List<WordRecord> list, List<int> dims) {
  for (final w in list) {
    final sig = Uint32List(2);
    for (int i = 0; i < 64; i++) {
      final int dim = dims[i];
      final int byteIdx = dim ~/ 8;
      final int bitIdx = dim % 8;
      final bool isOne = (w.embedding[byteIdx] & (1 << bitIdx)) != 0;
      if (isOne) {
        final int sigWord = i ~/ 32;
        final int sigBit = i % 32;
        sig[sigWord] |= (1 << sigBit);
      }
    }
    w.signature = sig;
  }
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
    final String id = record['id'];
    final String spell = record['spell'];
    final String hexEmb = record['embedding1bit'];
    words.add(WordRecord(id, spell, decodeHex(hexEmb)));
  }
  print('已加载 ${words.length} 个单词。');

  // Find pairs in the 10k set
  final Map<String, List<int>> groups = {};
  for (int i = 0; i < words.length; i++) {
    final prefix = words[i].spell.substring(0, words[i].spell.length < 4 ? words[i].spell.length : 4).toLowerCase();
    groups.putIfAbsent(prefix, () => []).add(i);
  }
  final List<List<int>> pairs = [];
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
  print('提取了 ${pairs.length} 对同根/形态近邻对（用于评估距离）。');

  // We evaluate on N=10000
  // Sort path with OLD dims
  buildSignatures(words, old64);
  final pathOldRaw = runSignatureFilteredTsp(words, 100);
  final pathOldOpt = optimizePath2OptLocal(pathOldRaw, words, 15);

  // Sort path with NEW dims
  buildSignatures(words, new64);
  final pathNewRaw = runSignatureFilteredTsp(words, 100);
  final pathNewOpt = optimizePath2OptLocal(pathNewRaw, words, 15);

  // Measure index distances for pairs
  final Map<String, int> oldIndexMap = {for (int i = 0; i < pathOldOpt.length; i++) pathOldOpt[i]: i};
  final Map<String, int> newIndexMap = {for (int i = 0; i < pathNewOpt.length; i++) pathNewOpt[i]: i};

  double totalDistOld = 0.0;
  double totalDistNew = 0.0;
  int pairsChecked = 0;

  for (final pair in pairs) {
    final idA = words[pair[0]].id;
    final idB = words[pair[1]].id;
    
    final idxA_Old = oldIndexMap[idA];
    final idxB_Old = oldIndexMap[idB];
    final idxA_New = newIndexMap[idA];
    final idxB_New = newIndexMap[idB];

    if (idxA_Old != null && idxB_Old != null && idxA_New != null && idxB_New != null) {
      totalDistOld += (idxA_Old - idxB_Old).abs();
      totalDistNew += (idxA_New - idxB_New).abs();
      pairsChecked++;
    }
  }

  print('\n=== 同根/近邻词在最终排序路径中的平均排序间距 (Index Distance) ===');
  print('参与评估的有效词对数: $pairsChecked');
  print('旧高熵维度 (方差最大) 排序后的平均间距: ${(totalDistOld / pairsChecked).toStringAsFixed(2)} 行');
  print('新高熵低噪维度 (黄金维度) 排序后的平均间距: ${(totalDistNew / pairsChecked).toStringAsFixed(2)} 行');
  
  final improvement = (totalDistOld - totalDistNew) / totalDistOld * 100;
  print('近邻聚集度提升: ${improvement.toStringAsFixed(2)}% (平均间距缩短了 ${((totalDistOld - totalDistNew) / pairsChecked).toStringAsFixed(2)} 行)');
}

List<String> runSignatureFilteredTsp(List<WordRecord> list, int m) {
  final int n = list.length;
  final List<bool> visited = List.filled(n, false);
  final List<String> path = [];

  int curr = 0;
  path.add(list[curr].id);
  visited[curr] = true;

  final List<int> candidates = List.filled(m, 0);
  final List<int> candidateDists = List.filled(m, 99999);

  for (int step = 1; step < n; step++) {
    final sigA = list[curr].signature;
    final currEmb = list[curr].emb32;
    int candidateCount = 0;

    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;

      final sigB = list[i].signature;
      final int distSig = popCount32(sigA[0] ^ sigB[0]) + popCount32(sigA[1] ^ sigB[1]);

      if (candidateCount < m) {
        int insertPos = candidateCount;
        while (insertPos > 0 && candidateDists[insertPos - 1] > distSig) {
          candidateDists[insertPos] = candidateDists[insertPos - 1];
          candidates[insertPos] = candidates[insertPos - 1];
          insertPos--;
        }
        candidateDists[insertPos] = distSig;
        candidates[insertPos] = i;
        candidateCount++;
      } else if (distSig < candidateDists[m - 1]) {
        int insertPos = m - 1;
        while (insertPos > 0 && candidateDists[insertPos - 1] > distSig) {
          candidateDists[insertPos] = candidateDists[insertPos - 1];
          candidates[insertPos] = candidates[insertPos - 1];
          insertPos--;
        }
        candidateDists[insertPos] = distSig;
        candidates[insertPos] = i;
      }
    }

    int minHammingDist = 999999;
    int nextIdx = -1;

    for (int k = 0; k < candidateCount; k++) {
      final int idx = candidates[k];
      final dist = computeHammingDistance(currEmb, list[idx].emb32);
      if (dist < minHammingDist) {
        minHammingDist = dist;
        nextIdx = idx;
      }
    }

    if (nextIdx == -1) break;
    curr = nextIdx;
    path.add(list[curr].id);
    visited[curr] = true;
  }
  return path;
}

List<String> optimizePath2OptLocal(List<String> path, List<WordRecord> originalList, int windowSize) {
  final Map<String, WordRecord> map = {for (var w in originalList) w.id: w};
  final List<String> optimized = List.from(path);
  final int n = optimized.length;
  bool improved = true;

  for (int pass = 0; pass < 3 && improved; pass++) {
    improved = false;
    for (int i = 0; i < n - 3; i++) {
      final int end = (i + windowSize) < n - 1 ? (i + windowSize) : (n - 2);
      for (int j = i + 2; j <= end; j++) {
        final wI = map[optimized[i]]!;
        final wI1 = map[optimized[i + 1]]!;
        final wJ = map[optimized[j]]!;
        final wJ1 = map[optimized[j + 1]]!;

        final int oldDist = computeHammingDistance(wI.emb32, wI1.emb32) +
                            computeHammingDistance(wJ.emb32, wJ1.emb32);
        final int newDist = computeHammingDistance(wI.emb32, wJ.emb32) +
                            computeHammingDistance(wI1.emb32, wJ1.emb32);

        if (newDist < oldDist) {
          _reverseSubpath(optimized, i + 1, j);
          improved = true;
        }
      }
    }
  }
  return optimized;
}

void _reverseSubpath(List<String> list, int start, int end) {
  while (start < end) {
    final temp = list[start];
    list[start] = list[end];
    list[end] = temp;
    start++;
    end--;
  }
}
