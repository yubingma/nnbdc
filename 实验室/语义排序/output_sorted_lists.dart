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
  // 1. 读取 PCA 降维配置
  final pcaFile = File('scratch/pca_config.json');
  final Map<String, dynamic> pcaJson = jsonDecode(pcaFile.readAsStringSync());
  final List<dynamic> meanList = pcaJson['mean'] as List<dynamic>;
  final List<dynamic> compList = pcaJson['components'] as List<dynamic>;
  final pcaConfig = PCAConfig(
    meanList.map((e) => (e as num).toDouble()).toList(),
    compList.map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList(),
  );

  // 2. 读取词表数据
  final wordsFile = File('scratch/test_100_words.jsonl');
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

  // 3. 计算所有单词的 3D 投影坐标 (PCA)
  for (final w in words) {
    final coords = pcaConfig.projectTo3D(w.embedding);
    w.x = coords[0];
    w.y = coords[1];
    w.z = coords[2];
  }

  print('=== 开始生成 100 词排序体验文件 ===\n');

  // A. KD-Tree
  final stopwatchA = Stopwatch()..start();
  final List<MapEntry<String, Uint8List>> kdInput = words.map((w) => MapEntry(w.id, w.embedding)).toList();
  final rootNode = KdTreeSorter.buildKdTree(kdInput, {});
  final List<String> sortedIdsA = [];
  KdTreeSorter.traverseKdTree(rootNode, sortedIdsA);
  stopwatchA.stop();
  writeResultFile('scratch/sorted_kd_tree.txt', sortedIdsA, words, stopwatchA.elapsedMicroseconds / 1000.0);

  // B. Pure Hamming-TSP
  final stopwatchB = Stopwatch()..start();
  final List<String> sortedIdsB = runPureHammingTsp(words);
  stopwatchB.stop();
  writeResultFile('scratch/sorted_pure_hamming_tsp.txt', sortedIdsB, words, stopwatchB.elapsedMicroseconds / 1000.0);

  // C. Hybrid TSP
  final stopwatchC = Stopwatch()..start();
  final List<String> sortedIdsC = runHybridTsp(words, 20);
  stopwatchC.stop();
  writeResultFile('scratch/sorted_hybrid_tsp.txt', sortedIdsC, words, stopwatchC.elapsedMicroseconds / 1000.0);

  // C-Opt. Hybrid TSP + 2-Opt
  final stopwatchCOpt = Stopwatch()..start();
  final List<String> sortedIdsCOpt = optimizePath2OptLocal(sortedIdsC, words, 15);
  stopwatchCOpt.stop();
  final totalTimeCOpt = (stopwatchC.elapsedMicroseconds + stopwatchCOpt.elapsedMicroseconds) / 1000.0;
  writeResultFile('scratch/sorted_hybrid_tsp_opt.txt', sortedIdsCOpt, words, totalTimeCOpt);

  // D. Morton
  final stopwatchD = Stopwatch()..start();
  final List<String> sortedIdsD = runMortonSort(words);
  stopwatchD.stop();
  writeResultFile('scratch/sorted_morton.txt', sortedIdsD, words, stopwatchD.elapsedMicroseconds / 1000.0);

  // E. KMeans + TSP
  final stopwatchE = Stopwatch()..start();
  final List<String> sortedIdsE = runKMeansTspSort(words, 5);
  stopwatchE.stop();
  writeResultFile('scratch/sorted_kmeans_tsp.txt', sortedIdsE, words, stopwatchE.elapsedMicroseconds / 1000.0);

  print('✅ 体验文件已成功生成至 `scratch/` 目录下！');
  print('1. KD-Tree 排序:        scratch/sorted_kd_tree.txt');
  print('2. 纯高维 Hamming TSP:   scratch/sorted_pure_hamming_tsp.txt');
  print('3. 混合 3D-Hamming TSP:  scratch/sorted_hybrid_tsp.txt');
  print('4. 混合 TSP + 2-Opt:    scratch/sorted_hybrid_tsp_opt.txt');
  print('5. 3D Morton 曲线排序:   scratch/sorted_morton.txt');
  print('6. K-Means 聚类 + TSP:   scratch/sorted_kmeans_tsp.txt\n');
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
      buffer.writeln('${(i + 1).toString().padLeft(3, '0')}. ${w.spell.padRight(15)} (起点)');
    } else {
      final prevW = map[sortedIds[i - 1]]!;
      final dist = computeHammingDistance(prevW.emb32, w.emb32);
      buffer.writeln('${(i + 1).toString().padLeft(3, '0')}. ${w.spell.padRight(15)} (相邻汉明距离: $dist)');
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

class Point3D {
  double x;
  double y;
  double z;
  Point3D(this.x, this.y, this.z);
}

// 3D K-Means Clustering
List<List<WordRecord>> runKMeans3D(List<WordRecord> list, int k) {
  final int n = list.length;
  if (k <= 1) return [List.from(list)];
  if (k >= n) return list.map((w) => [w]).toList();

  final List<Point3D> centroids = [];
  centroids.add(Point3D(list[0].x, list[0].y, list[0].z));
  
  for (int i = 1; i < k; i++) {
    double maxDist = -1.0;
    int bestIdx = 0;
    for (int j = 0; j < n; j++) {
      double minDistToCentroid = double.infinity;
      for (final c in centroids) {
        final double dx = list[j].x - c.x;
        final double dy = list[j].y - c.y;
        final double dz = list[j].z - c.z;
        final double d = dx * dx + dy * dy + dz * dz;
        if (d < minDistToCentroid) minDistToCentroid = d;
      }
      if (minDistToCentroid > maxDist) {
        maxDist = minDistToCentroid;
        bestIdx = j;
      }
    }
    centroids.add(Point3D(list[bestIdx].x, list[bestIdx].y, list[bestIdx].z));
  }

  final List<int> labels = List.filled(n, 0);
  bool changed = true;
  
  for (int iter = 0; iter < 20 && changed; iter++) {
    changed = false;
    for (int i = 0; i < n; i++) {
      double minDist = double.infinity;
      int nearestCentroid = 0;
      for (int c = 0; c < k; c++) {
        final double dx = list[i].x - centroids[c].x;
        final double dy = list[i].y - centroids[c].y;
        final double dz = list[i].z - centroids[c].z;
        final double distSq = dx * dx + dy * dy + dz * dz;
        if (distSq < minDist) {
          minDist = distSq;
          nearestCentroid = c;
        }
      }
      if (labels[i] != nearestCentroid) {
        labels[i] = nearestCentroid;
        changed = true;
      }
    }

    final List<double> sumX = List.filled(k, 0.0);
    final List<double> sumY = List.filled(k, 0.0);
    final List<double> sumZ = List.filled(k, 0.0);
    final List<int> count = List.filled(k, 0);

    for (int i = 0; i < n; i++) {
      final int c = labels[i];
      sumX[c] += list[i].x;
      sumY[c] += list[i].y;
      sumZ[c] += list[i].z;
      count[c]++;
    }

    for (int c = 0; c < k; c++) {
      if (count[c] > 0) {
        centroids[c].x = sumX[c] / count[c];
        centroids[c].y = sumY[c] / count[c];
        centroids[c].z = sumZ[c] / count[c];
      }
    }
  }

  final List<List<WordRecord>> clusters = List.generate(k, (_) => []);
  for (int i = 0; i < n; i++) {
    clusters[labels[i]].add(list[i]);
  }
  
  clusters.removeWhere((c) => c.isEmpty);
  return clusters;
}

List<String> runKMeansTspSort(List<WordRecord> list, int k) {
  if (list.isEmpty) return [];
  
  final List<List<WordRecord>> clusters = runKMeans3D(list, k);
  
  final List<Point3D> clusterCentroids = [];
  for (final cluster in clusters) {
    double sumX = 0.0, sumY = 0.0, sumZ = 0.0;
    for (final w in cluster) {
      sumX += w.x;
      sumY += w.y;
      sumZ += w.z;
    }
    clusterCentroids.add(Point3D(sumX / cluster.length, sumY / cluster.length, sumZ / cluster.length));
  }
  
  final int clusterCount = clusters.length;
  final List<bool> clusterVisited = List.filled(clusterCount, false);
  final List<int> sortedClusterIndices = [];
  
  int currCluster = 0;
  sortedClusterIndices.add(currCluster);
  clusterVisited[currCluster] = true;
  
  for (int step = 1; step < clusterCount; step++) {
    double minDistSq = double.infinity;
    int nextCluster = -1;
    final currC = clusterCentroids[currCluster];
    
    for (int i = 0; i < clusterCount; i++) {
      if (clusterVisited[i]) continue;
      final double dx = currC.x - clusterCentroids[i].x;
      final double dy = currC.y - clusterCentroids[i].y;
      final double dz = currC.z - clusterCentroids[i].z;
      final double distSq = dx * dx + dy * dy + dz * dz;
      if (distSq < minDistSq) {
        minDistSq = distSq;
        nextCluster = i;
      }
    }
    
    if (nextCluster == -1) break;
    currCluster = nextCluster;
    sortedClusterIndices.add(currCluster);
    clusterVisited[currCluster] = true;
  }
  
  final List<String> finalPath = [];
  for (final clusterIdx in sortedClusterIndices) {
    final clusterWords = clusters[clusterIdx];
    final sortedClusterWordIds = runPureHammingTsp(clusterWords);
    
    // Also locally optimize this cluster with 2-Opt for maximum smoothness within the unit
    final optimizedClusterWordIds = optimizePath2OptLocal(sortedClusterWordIds, clusterWords, 15);
    finalPath.addAll(optimizedClusterWordIds);
  }
  
  return finalPath;
}
