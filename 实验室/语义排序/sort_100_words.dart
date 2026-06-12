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

class WordRecord {
  final String id;
  final String spell;
  final Uint8List embedding;
  final Uint32List emb32;
  
  // 64-bit Signature (2 x Uint32)
  late Uint32List signature;

  WordRecord(this.id, this.spell, this.embedding) : emb32 = _buildEmb32(embedding);

  static Uint32List _buildEmb32(Uint8List emb) {
    final aligned = Uint8List(256)..setAll(0, emb);
    return Uint32List.view(aligned.buffer);
  }
}

// 64 high-entropy dimensions (static global)
const List<int> highEntropyDims = [
  1826, 1699, 1458, 912, 1660, 93, 788, 1966, 1632, 187,
  1351, 8, 1189, 1483, 257, 979, 1806, 1608, 1544, 1712,
  2009, 2003, 675, 214, 197, 563, 842, 1776, 1968, 583,
  1833, 427, 110, 1656, 956, 2007, 74, 227, 1883, 33,
  86, 1416, 1468, 2027, 1284, 995, 235, 1706, 985, 1644,
  1599, 711, 1218, 275, 174, 1005, 412, 789, 2022, 1362,
  1692, 593, 69, 81
];

void main() async {
  final wordsFile = File('实验室/语义排序/test_100_words.jsonl');
  if (!wordsFile.existsSync()) {
    print('错误: 未找到 test_100_words.jsonl');
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
    final Uint8List emb = decodeHex(hexEmb);
    words.add(WordRecord(id, spell, emb));
  }
  print('已加载 ${words.length} 个单词。');

  // 构建每个单词的 64-bit 签名
  for (final w in words) {
    final sig = Uint32List(2);
    for (int i = 0; i < 64; i++) {
      final int dim = highEntropyDims[i];
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

  // 1. Pure Hamming TSP (Fallback path for N <= 100)
  final List<String> pathPure = runPureHammingTsp(words);
  final List<String> pathPureOpt = optimizePath2OptLocal(pathPure, words, 15);

  // 2. Signature Filtered TSP (Forcing Scheme B without fallback, M=20)
  // Since total words = 100, we select candidates M=20
  final List<String> pathSig = runSignatureFilteredTsp(words, 20);
  final List<String> pathSigOpt = optimizePath2OptLocal(pathSig, words, 15);

  final buffer = StringBuffer();
  buffer.writeln('=== 100个单词排序效果比对 ===\n');

  // Calculate metrics
  buffer.writeln('【算法指标对比】');
  buffer.writeln('1. Pure Hamming TSP (无损退化方案):');
  final metricsPure = calculateMetrics(pathPureOpt, words);
  buffer.writeln('   - 平均相邻汉明距离: ${metricsPure.avgDist.toStringAsFixed(2)}');
  buffer.writeln('   - 最大相邻汉明距离: ${metricsPure.maxDist}');
  buffer.writeln('   - 汉明距离 > 128 突变个数: ${metricsPure.jumps}');
  
  buffer.writeln('2. Signature Filtered TSP (64位过滤强行应用, M=20):');
  final metricsSig = calculateMetrics(pathSigOpt, words);
  buffer.writeln('   - 平均相邻汉明距离: ${metricsSig.avgDist.toStringAsFixed(2)}');
  buffer.writeln('   - 最大相邻汉明距离: ${metricsSig.maxDist}');
  buffer.writeln('   - 汉明距离 > 128 突变个数: ${metricsSig.jumps}');
  buffer.writeln('--------------------------------------------------\n');

  buffer.writeln('【比对列 1】Pure Hamming TSP (无损退化)    | 【比对列 2】Signature Filtered TSP (强制 Scheme B)');
  buffer.writeln('-------------------------------------------+-------------------------------------------');

  final Map<String, WordRecord> map = {for (var w in words) w.id: w};

  for (int i = 0; i < words.length; i++) {
    final wPure = map[pathPureOpt[i]]!;
    final wSig = map[pathSigOpt[i]]!;

    String distPureStr = '';
    if (i > 0) {
      final prevWP = map[pathPureOpt[i - 1]]!;
      distPureStr = '(${computeHammingDistance(prevWP.emb32, wPure.emb32)})';
    } else {
      distPureStr = '(start)';
    }

    String distSigStr = '';
    if (i > 0) {
      final prevWS = map[pathSigOpt[i - 1]]!;
      distSigStr = '(${computeHammingDistance(prevWS.emb32, wSig.emb32)})';
    } else {
      distSigStr = '(start)';
    }

    final col1 = '${(i + 1).toString().padLeft(3, '0')}. ${wPure.spell.padRight(18)} $distPureStr'.padRight(42);
    final col2 = '${(i + 1).toString().padLeft(3, '0')}. ${wSig.spell.padRight(18)} $distSigStr';

    buffer.writeln('$col1 | $col2');
  }

  final outFile = File('实验室/语义排序/sorted_100_words_comparison.txt');
  outFile.writeAsStringSync(buffer.toString());
  print('✅ 结果已成功写入 实验室/语义排序/sorted_100_words_comparison.txt');
}

class Metrics {
  final double avgDist;
  final int maxDist;
  final int jumps;
  Metrics(this.avgDist, this.maxDist, this.jumps);
}

Metrics calculateMetrics(List<String> path, List<WordRecord> originalList) {
  final Map<String, WordRecord> map = {for (var w in originalList) w.id: w};
  int totalDist = 0;
  int maxDist = 0;
  int jumps = 0;
  
  for (int i = 0; i < path.length - 1; i++) {
    final w1 = map[path[i]]!;
    final w2 = map[path[i + 1]]!;
    final dist = computeHammingDistance(w1.emb32, w2.emb32);
    totalDist += dist;
    if (dist > maxDist) maxDist = dist;
    if (dist > 128) jumps++;
  }
  final double avgDist = path.length > 1 ? totalDist / (path.length - 1) : 0.0;
  return Metrics(avgDist, maxDist, jumps);
}

// Pure Hamming Distance NN TSP
List<String> runPureHammingTsp(List<WordRecord> list) {
  final int n = list.length;
  final List<bool> visited = List.filled(n, false);
  final List<String> path = [];

  int curr = 0;
  path.add(list[curr].id);
  visited[curr] = true;

  for (int step = 1; step < n; step++) {
    int minDist = 999999;
    int nextIdx = -1;
    final currEmb = list[curr].emb32;

    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;
      final dist = computeHammingDistance(currEmb, list[i].emb32);
      if (dist < minDist) {
        minDist = dist;
        nextIdx = i;
      }
    }

    if (nextIdx == -1) break;
    curr = nextIdx;
    path.add(list[curr].id);
    visited[curr] = true;
  }
  return path;
}

// Signature Filtered TSP (Scheme B)
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

// Local 2-Opt
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
