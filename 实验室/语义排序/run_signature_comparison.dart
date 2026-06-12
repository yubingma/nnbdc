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

void main() async {
  print('=== 语义排序方案 B（64位特征哈希过滤）与 Pure Hamming 性能&效果大对比 ===\n');

  // 1. 读取 10k 词表数据
  final wordsFile = File('scratch/words_10k.jsonl');
  if (!wordsFile.existsSync()) {
    print('错误: 未找到 scratch/words_10k.jsonl，请先运行数据导出。');
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

  // 2. 使用从生产库 47,717 词分析出的静态全局高熵 64 特征维度作为哈希签名
  print('使用静态全局 64 个高熵维度作为签名...');
  final List<int> selectedDims = const [
    1826, 1699, 1458, 912, 1660, 93, 788, 1966, 1632, 187,
    1351, 8, 1189, 1483, 257, 979, 1806, 1608, 1544, 1712,
    2009, 2003, 675, 214, 197, 563, 842, 1776, 1968, 583,
    1833, 427, 110, 1656, 956, 2007, 74, 227, 1883, 33,
    86, 1416, 1468, 2027, 1284, 995, 235, 1706, 985, 1644,
    1599, 711, 1218, 275, 174, 1005, 412, 789, 2022, 1362,
    1692, 593, 69, 81
  ];
  print('已选择 64 维哈希签名索引: ${selectedDims.take(10).join(', ')} ...');

  // 3. 构建每个单词的 64-bit 签名
  for (final w in words) {
    final sig = Uint32List(2);
    for (int i = 0; i < 64; i++) {
      final int dim = selectedDims[i];
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
  print('所有单词的 64-bit 签名初始化完成。\n');

  final List<int> sizes = [2000, 5000, 10000];

  for (final size in sizes) {
    print('-------------------------------------------');
    print('【正在测试规模: N = $size】');
    print('-------------------------------------------');

    final subset = words.sublist(0, size);

    // --- 运行 A: Pure Hamming TSP (无过滤全局) ---
    print('  -> 正在运行 Pure Hamming TSP (全局) + 2-Opt...');
    final stopwatchPure = Stopwatch()..start();
    final List<String> pathPureRaw = runPureHammingTsp(subset);
    final List<String> pathPureOpt = optimizePath2OptLocal(pathPureRaw, subset, 15);
    stopwatchPure.stop();
    final double timePure = stopwatchPure.elapsedMicroseconds / 1000.0;
    
    final pathPureFile = 'scratch/sorted_pure_hamming_opt_$size.txt';
    writeResultFile(pathPureFile, pathPureOpt, subset, timePure);
    print('  ✅ 无损 Pure TSP 已写入: $pathPureFile (耗时: ${timePure.toStringAsFixed(2)} ms)');

    // --- 运行 B: Signature Filtered TSP (方案 B) ---
    print('  -> 正在运行 64位特征哈希过滤 TSP (M=100) + 2-Opt...');
    final stopwatchSig = Stopwatch()..start();
    final List<String> pathSigRaw = runSignatureFilteredTsp(subset, 100);
    final List<String> pathSigOpt = optimizePath2OptLocal(pathSigRaw, subset, 15);
    stopwatchSig.stop();
    final double timeSig = stopwatchSig.elapsedMicroseconds / 1000.0;

    final pathSigFile = 'scratch/sorted_sig_filter_opt_$size.txt';
    writeResultFile(pathSigFile, pathSigOpt, subset, timeSig);
    print('  ✅ 方案 B 特征过滤已写入: $pathSigFile (耗时: ${timeSig.toStringAsFixed(2)} ms)');
    print('');
  }

  print('🎉 所有大文件已全部输出至 scratch/ 目录下，您可以直接肉眼比对体验！');
}

void writeResultFile(String path, List<String> sortedIds, List<WordRecord> originalList, double elapsedMs) {
  final Map<String, WordRecord> map = {for (var w in originalList) w.id: w};
  final file = File(path);
  final buffer = StringBuffer();
  
  // Calculate metrics
  int totalDist = 0;
  int maxDist = 0;
  int jumps = 0;
  
  for (int i = 0; i < sortedIds.length - 1; i++) {
    final w1 = map[sortedIds[i]]!;
    final w2 = map[sortedIds[i + 1]]!;
    final dist = computeHammingDistance(w1.emb32, w2.emb32);
    totalDist += dist;
    if (dist > maxDist) maxDist = dist;
    if (dist > 128) jumps++;
  }
  
  final double avgDist = sortedIds.length > 1 ? totalDist / (sortedIds.length - 1) : 0.0;
  
  buffer.writeln('=== 语义排序结果体验 ===');
  buffer.writeln('算法: ${file.uri.pathSegments.last}');
  buffer.writeln('单词总数: ${sortedIds.length}');
  buffer.writeln('【核心性能与质量指标】');
  buffer.writeln('- 排序计算耗时: ${elapsedMs.toStringAsFixed(3)} ms');
  buffer.writeln('- 平均相邻汉明距离: ${avgDist.toStringAsFixed(2)} (指标越低，相邻单词的语义过渡越连贯越好)');
  buffer.writeln('- 最大相邻汉明距离: $maxDist (指标越低，说明没有突兀的语义“大跳转”)');
  buffer.writeln('- 汉明距离 > 128 突变个数: $jumps');
  buffer.writeln('--------------------------------------------------\n');

  for (int i = 0; i < sortedIds.length; i++) {
    final w = map[sortedIds[i]]!;
    if (i == 0) {
      buffer.writeln('${(i + 1).toString().padLeft(5, '0')}. ${w.spell.padRight(18)} (起点)');
    } else {
      final prevW = map[sortedIds[i - 1]]!;
      final dist = computeHammingDistance(prevW.emb32, w.emb32);
      buffer.writeln('${(i + 1).toString().padLeft(5, '0')}. ${w.spell.padRight(18)} (相邻汉明距离: $dist)');
    }
  }
  
  file.writeAsStringSync(buffer.toString());
}

// 纯 Hamming Distance Nearest Neighbor TSP
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

// 64-bit Signature Filtered TSP (方案 B)
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

    // 1. 64-bit 特征哈希快速选择最近的 M 个未访问单词
    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;

      final sigB = list[i].signature;
      // popcount bitwise xor on 2 x Uint32
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

    // 2. 精确计算 M 个候选者的 2048-bit Hamming 距离，锁定真正的最近邻
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

// Local 2-Opt Optimization for TSP Path
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
