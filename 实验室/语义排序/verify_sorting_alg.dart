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

// KD-Tree Node
class KdNode {
  final List<String>? wordIds;
  final int splitDim;
  final KdNode? left;
  final KdNode? right;

  KdNode({this.wordIds, this.splitDim = -1, this.left, this.right});
  bool get isLeaf => wordIds != null;
}

// Baseline KD-Tree Sorter
class KdTreeSorter {
  static KdNode buildKdTree(List<MapEntry<String, Uint8List>> words, Set<int> usedDims) {
    if (words.isEmpty) {
      return KdNode(wordIds: []);
    }

    if (words.length <= 1) {
      return KdNode(wordIds: words.map((w) => w.key).toList());
    }

    int bestDim = -1;
    double minDiff = double.infinity;
    final int total = words.length;
    final int target = total ~/ 2;

    for (int d = 0; d < 2048; d++) {
      if (usedDims.contains(d)) continue;

      final int byteIdx = d ~/ 8;
      final int bitIdx = d % 8;
      int count1 = 0;
      for (final w in words) {
        final emb = w.value;
        if ((emb[byteIdx] & (1 << bitIdx)) != 0) {
          count1++;
        }
      }

      if (count1 == 0 || count1 == total) continue;

      final double diff = (count1 - target).abs().toDouble();
      if (diff < minDiff) {
        minDiff = diff;
        bestDim = d;
      }
    }

    if (bestDim == -1) {
      return KdNode(wordIds: words.map((w) => w.key).toList());
    }

    final List<MapEntry<String, Uint8List>> leftWords = [];
    final List<MapEntry<String, Uint8List>> rightWords = [];
    final int byteIdx = bestDim ~/ 8;
    final int bitIdx = bestDim % 8;

    for (final w in words) {
      final emb = w.value;
      if ((emb[byteIdx] & (1 << bitIdx)) != 0) {
        rightWords.add(w);
      } else {
        leftWords.add(w);
      }
    }

    final nextUsedDims = Set<int>.from(usedDims)..add(bestDim);
    final leftChild = buildKdTree(leftWords, nextUsedDims);
    final rightChild = buildKdTree(rightWords, nextUsedDims);

    return KdNode(
      splitDim: bestDim,
      left: leftChild,
      right: rightChild,
    );
  }

  static void traverseKdTree(KdNode? node, List<String> result) {
    if (node == null) return;
    if (node.isLeaf) {
      result.addAll(node.wordIds!);
      return;
    }
    traverseKdTree(node.left, result);
    traverseKdTree(node.right, result);
  }
}

void main() async {
  print('=== 语义排序算法实验与基准测试 ===\n');

  // 1. 读取 PCA 降维配置
  print('正在加载 PCA 配置...');
  final pcaFile = File('scratch/pca_config.json');
  if (!pcaFile.existsSync()) {
    print('错误: 未找到 scratch/pca_config.json，请先运行数据导出命令。');
    return;
  }
  final Map<String, dynamic> pcaJson = jsonDecode(pcaFile.readAsStringSync());
  final List<dynamic> meanList = pcaJson['mean'] as List<dynamic>;
  final List<dynamic> compList = pcaJson['components'] as List<dynamic>;
  final pcaConfig = PCAConfig(
    meanList.map((e) => (e as num).toDouble()).toList(),
    compList.map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList(),
  );
  print('PCA 矩阵维度: mean=${pcaConfig.mean.length}, components=${pcaConfig.components.length}x${pcaConfig.components[0].length}\n');

  // 2. 读取词表数据
  print('正在加载词表数据...');
  final wordsFile = File('scratch/words_10k.jsonl');
  if (!wordsFile.existsSync()) {
    print('错误: 未找到 scratch/words_10k.jsonl，请先运行数据导出命令。');
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
  print('成功加载 ${words.length} 个单词，并完成了 Uint32List 转换。\n');

  // 3. 计算所有单词的 3D 投影坐标 (PCA)
  print('正在对所有单词执行 PCA 3D 投影...');
  final stopwatchPca = Stopwatch()..start();
  for (final w in words) {
    final coords = pcaConfig.projectTo3D(w.embedding);
    w.x = coords[0];
    w.y = coords[1];
    w.z = coords[2];
  }
  stopwatchPca.stop();
  print('PCA 投影耗时: ${stopwatchPca.elapsedMilliseconds} ms\n');

  final List<int> testSizes = [1000, 2000, 5000, 10000];

  for (final size in testSizes) {
    if (size > words.length) continue;
    print('-------------------------------------------');
    print('【测试规模: N = $size】');
    print('-------------------------------------------');

    final testSubset = words.sublist(0, size);

    // --- 算法 A: 1-bit KD-Tree (当前基线) ---
    final stopwatchA = Stopwatch()..start();
    final List<MapEntry<String, Uint8List>> kdInput = testSubset.map((w) => MapEntry(w.id, w.embedding)).toList();
    final rootNode = KdTreeSorter.buildKdTree(kdInput, {});
    final List<String> sortedIdsA = [];
    KdTreeSorter.traverseKdTree(rootNode, sortedIdsA);
    stopwatchA.stop();
    final timeA = stopwatchA.elapsedMilliseconds;

    // --- 算法 B: 纯高维 Hamming-TSP ---
    final stopwatchB = Stopwatch()..start();
    final List<String> sortedIdsB = runPureHammingTsp(testSubset);
    stopwatchB.stop();
    final timeB = stopwatchB.elapsedMilliseconds;

    // --- 算法 C: 混合 3D过滤 + Hamming-TSP ---
    final stopwatchC50 = Stopwatch()..start();
    final List<String> sortedIdsC50 = runHybridTsp(testSubset, 50);
    stopwatchC50.stop();
    final timeC50 = stopwatchC50.elapsedMilliseconds;

    final stopwatchC100 = Stopwatch()..start();
    final List<String> sortedIdsC100 = runHybridTsp(testSubset, 100);
    stopwatchC100.stop();
    final timeC100 = stopwatchC100.elapsedMilliseconds;

    final stopwatchC200 = Stopwatch()..start();
    final List<String> sortedIdsC200 = runHybridTsp(testSubset, 200);
    stopwatchC200.stop();
    final timeC200 = stopwatchC200.elapsedMilliseconds;

    // --- 算法 D: 3D Morton 空间填充曲线排序 ---
    final stopwatchD = Stopwatch()..start();
    final List<String> sortedIdsD = runMortonSort(testSubset);
    stopwatchD.stop();
    final timeD = stopwatchD.elapsedMilliseconds;

    // --- 评价排序质量 ---
    final qualityA = evaluateQuality(sortedIdsA, testSubset);
    final qualityB = evaluateQuality(sortedIdsB, testSubset);
    final qualityC50 = evaluateQuality(sortedIdsC50, testSubset);
    final qualityC100 = evaluateQuality(sortedIdsC100, testSubset);
    final qualityC200 = evaluateQuality(sortedIdsC200, testSubset);
    final qualityD = evaluateQuality(sortedIdsD, testSubset);

    print('算法 A (KD-Tree 遍历):');
    print('  - 执行时间: $timeA ms');
    print('  - 平均相邻汉明距离: ${qualityA.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityA.maxDist}');

    print('算法 B (纯 Hamming-TSP):');
    print('  - 执行时间: $timeB ms');
    print('  - 平均相邻汉明距离: ${qualityB.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityB.maxDist}');

    print('算法 C-50 (混合 3D-50过滤 + Hamming-TSP):');
    print('  - 执行时间: $timeC50 ms');
    print('  - 平均相邻汉明距离: ${qualityC50.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityC50.maxDist}');

    // --- 算法 C-50-Opt: 混合 3D-50过滤 + Hamming-TSP + 本地 2-Opt 优化 ---
    final stopwatchCOpt = Stopwatch()..start();
    final List<String> sortedIdsCOpt = optimizePath2OptLocal(sortedIdsC50, testSubset, 15);
    stopwatchCOpt.stop();
    final timeCOpt = timeC50 + stopwatchCOpt.elapsedMilliseconds;
    final qualityCOpt = evaluateQuality(sortedIdsCOpt, testSubset);

    print('算法 C-50-Opt (混合 TSP + 2-Opt 优化):');
    print('  - 执行时间: $timeCOpt ms');
    print('  - 平均相邻汉明距离: ${qualityCOpt.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityCOpt.maxDist}');

    print('算法 C-100 (混合 3D-100过滤 + Hamming-TSP):');
    print('  - 执行时间: $timeC100 ms');
    print('  - 平均相邻汉明距离: ${qualityC100.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityC100.maxDist}');

    print('算法 C-200 (混合 3D-200过滤 + Hamming-TSP):');
    print('  - 执行时间: $timeC200 ms');
    print('  - 平均相邻汉明距离: ${qualityC200.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityC200.maxDist}');

    print('算法 D (3D Morton 空间填充曲线):');
    print('  - 执行时间: $timeD ms');
    print('  - 平均相邻汉明距离: ${qualityD.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityD.maxDist}');
    print('');
  }
}

// 3D Morton Curve (Z-Order) Sorter
List<String> runMortonSort(List<WordRecord> list) {
  if (list.isEmpty) return [];
  
  // 1. Find bounding box of 3D coordinates
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;
  double minZ = double.infinity, maxZ = -double.infinity;
  
  for (final w in list) {
    if (w.x < minX) minX = w.x;
    if (w.x > maxX) maxX = w.x;
    if (w.y < minY) minY = w.y;
    if (w.y > maxY) maxY = w.y;
    if (w.z < minZ) minZ = w.z;
    if (w.z > maxZ) maxZ = w.z;
  }
  
  final double rangeX = (maxX - minX).abs() < 1e-6 ? 1.0 : (maxX - minX);
  final double rangeY = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
  final double rangeZ = (maxZ - minZ).abs() < 1e-6 ? 1.0 : (maxZ - minZ);
  
  // 2. Map coordinates to a 1024x1024x1024 grid (10 bits per axis)
  final List<MapEntry<String, int>> idToMorton = [];
  
  for (final w in list) {
    final int xGrid = (((w.x - minX) / rangeX) * 1023).round().clamp(0, 1023);
    final int yGrid = (((w.y - minY) / rangeY) * 1023).round().clamp(0, 1023);
    final int zGrid = (((w.z - minZ) / rangeZ) * 1023).round().clamp(0, 1023);
    
    // Interleave bits of xGrid, yGrid, zGrid
    int morton = 0;
    for (int i = 0; i < 10; i++) {
      morton |= ((xGrid >> i) & 1) << (3 * i + 2);
      morton |= ((yGrid >> i) & 1) << (3 * i + 1);
      morton |= ((zGrid >> i) & 1) << (3 * i);
    }
    idToMorton.add(MapEntry(w.id, morton));
  }
  
  // 3. Sort by Morton index
  idToMorton.sort((a, b) => a.value.compareTo(b.value));
  
  return idToMorton.map((e) => e.key).toList();
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

class QualityMetrics {
  final double avgDist;
  final int maxDist;
  final int jumps;

  QualityMetrics(this.avgDist, this.maxDist, this.jumps);
}

QualityMetrics evaluateQuality(List<String> sortedIds, List<WordRecord> originalList) {
  final Map<String, WordRecord> map = {for (var w in originalList) w.id: w};
  int totalDist = 0;
  int maxDist = 0;
  int jumps = 0;

  for (int i = 0; i < sortedIds.length - 1; i++) {
    final w1 = map[sortedIds[i]]!;
    final w2 = map[sortedIds[i+1]]!;
    final dist = computeHammingDistance(w1.emb32, w2.emb32);

    totalDist += dist;
    if (dist > maxDist) {
      maxDist = dist;
    }
    if (dist > 128) {
      jumps++;
    }
  }

  final double avg = sortedIds.length > 1 ? totalDist / (sortedIds.length - 1) : 0.0;
  return QualityMetrics(avg, maxDist, jumps);
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
          // Reverse subpath between i+1 and j
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
