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

class PCAConfig {
  final List<double> mean;
  final List<List<double>> components;

  PCAConfig(this.mean, this.components);

  List<double> projectTo3D(Uint8List embedding1bit) {
    double sum0 = 0.0;
    double sum1 = 0.0;
    double sum2 = 0.0;

    for (int i = 0; i < 2048; i++) {
      int byteIdx = i ~/ 8;
      int bitIdx = i % 8;
      bool isOne = (embedding1bit[byteIdx] & (1 << bitIdx)) != 0;
      double val = isOne ? 1.0 : 0.0;
      double centeredVal = val - mean[i];

      sum0 += centeredVal * components[i][0];
      sum1 += centeredVal * components[i][1];
      sum2 += centeredVal * components[i][2];
    }

    return [sum0, sum1, sum2];
  }
}

class WordRecord {
  final String id;
  final String spell;
  final Uint8List embedding;
  final Uint32List emb32;
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;

  WordRecord(this.id, this.spell, this.embedding) : emb32 = _buildEmb32(embedding);

  static Uint32List _buildEmb32(Uint8List emb) {
    final aligned = Uint8List(256)..setAll(0, emb);
    return Uint32List.view(aligned.buffer);
  }
}

void main() async {
  print('=== 开始生成大词表（2000/5000/10000词）的排序结果体验文件 ===\n');

  // 1. 读取 PCA 降维配置
  final pcaFile = File('scratch/pca_config.json');
  final Map<String, dynamic> pcaJson = jsonDecode(pcaFile.readAsStringSync());
  final List<dynamic> meanList = pcaJson['mean'] as List<dynamic>;
  final List<dynamic> compList = pcaJson['components'] as List<dynamic>;
  final pcaConfig = PCAConfig(
    meanList.map((e) => (e as num).toDouble()).toList(),
    compList.map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList(),
  );

  // 2. 读取 10k 词表数据
  final wordsFile = File('scratch/words_10k.jsonl');
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
  print('已成功加载 ${words.length} 个单词。');

  // 3. 计算所有单词的 3D 投影坐标 (PCA)
  for (final w in words) {
    final coords = pcaConfig.projectTo3D(w.embedding);
    w.x = coords[0];
    w.y = coords[1];
    w.z = coords[2];
  }

  final List<int> targetSizes = [2000, 5000, 10000];

  for (final size in targetSizes) {
    print('正在计算规模为 N = $size 的语义排序...');
    final subset = words.sublist(0, size);

    final stopwatch = Stopwatch()..start();
    // 运行 3D-50 过滤 + Hamming TSP (M=50)
    final List<String> sortedIds = runHybridTsp(subset, 50);
    // 运行局部 2-Opt 优化 (windowSize=15)
    final List<String> optimizedIds = optimizePath2OptLocal(sortedIds, subset, 15);
    stopwatch.stop();

    final String filename = 'scratch/sorted_hybrid_tsp_opt_$size.txt';
    writeResultFile(filename, optimizedIds, subset, stopwatch.elapsedMicroseconds / 1000.0);
    print('✅ 文件已写入: $filename');
  }

  print('\n全部完成！您可以查看对应的文件。');
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

// 混合 3D 预过滤 + Hamming Distance Nearest Neighbor TSP
List<String> runHybridTsp(List<WordRecord> list, int m) {
  final int n = list.length;
  final List<bool> visited = List.filled(n, false);
  final List<String> path = [];

  int curr = 0;
  path.add(list[curr].id);
  visited[curr] = true;

  final List<int> candidates = List.filled(m, 0);
  final List<double> candidateDists = List.filled(m, double.infinity);

  for (int step = 1; step < n; step++) {
    final double currX = list[curr].x;
    final double currY = list[curr].y;
    final double currZ = list[curr].z;
    final Uint32List currEmb = list[curr].emb32;

    int candidateCount = 0;

    // 1. 3D 快速选择最近的 M 个未访问单词
    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;

      final double dx = currX - list[i].x;
      final double dy = currY - list[i].y;
      final double dz = currZ - list[i].z;
      final double distSq = dx * dx + dy * dy + dz * dz;

      if (candidateCount < m) {
        int insertPos = candidateCount;
        while (insertPos > 0 && candidateDists[insertPos - 1] > distSq) {
          candidateDists[insertPos] = candidateDists[insertPos - 1];
          candidates[insertPos] = candidates[insertPos - 1];
          insertPos--;
        }
        candidateDists[insertPos] = distSq;
        candidates[insertPos] = i;
        candidateCount++;
      } else if (distSq < candidateDists[m - 1]) {
        int insertPos = m - 1;
        while (insertPos > 0 && candidateDists[insertPos - 1] > distSq) {
          candidateDists[insertPos] = candidateDists[insertPos - 1];
          candidates[insertPos] = candidates[insertPos - 1];
          insertPos--;
        }
        candidateDists[insertPos] = distSq;
        candidates[insertPos] = i;
      }
    }

    // 2. 在 M 个候选者中计算高精度的 Hamming 距离，找到真正的最近邻
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

  // Run up to 3 passes
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
