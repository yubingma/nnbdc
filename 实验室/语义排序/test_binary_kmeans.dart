import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

// -----------------------------------------------------------------------------
// Binary / Bisecting K-Means/Modes Implementation in 2048-dim Hamming Space
// -----------------------------------------------------------------------------

// Perform 2-Modes clustering on high-dimensional binary vectors (Hamming Space)
class BisectingKModes {
  final Random _random = Random(42); // Seeded for determinism

  // Runs K-Modes with K=2 on a list of words. Returns two lists.
  List<List<WordRecord>> split(List<WordRecord> cluster) {
    if (cluster.length < 2) return [cluster, []];

    // Initialize 2 cluster centroids as clones of random elements
    // (Ensure we select two distinct words if possible)
    int idx0 = _random.nextInt(cluster.length);
    int idx1 = _random.nextInt(cluster.length);
    while (idx1 == idx0 && cluster.length > 1) {
      idx1 = _random.nextInt(cluster.length);
    }

    // Centroids represented as 2048-bit vectors (Uint32List of size 64)
    final Uint32List c0 = Uint32List.fromList(cluster[idx0].emb32);
    final Uint32List c1 = Uint32List.fromList(cluster[idx1].emb32);

    List<WordRecord> list0 = [];
    List<WordRecord> list1 = [];

    // Max 10 iterations (typically converges extremely fast on Hamming space)
    for (int iter = 0; iter < 10; iter++) {
      list0 = [];
      list1 = [];

      for (final word in cluster) {
        final d0 = computeHammingDistance(word.emb32, c0);
        final d1 = computeHammingDistance(word.emb32, c1);
        if (d0 <= d1) {
          list0.add(word);
        } else {
          list1.add(word);
        }
      }

      // If one of the clusters becomes empty, force-split them roughly equally
      if (list0.isEmpty || list1.isEmpty) {
        final half = cluster.length ~/ 2;
        return [cluster.sublist(0, half), cluster.sublist(half)];
      }

      // Update centroids to K-Modes (majority voting per bit)
      final Uint32List nextC0 = _calculateModeCentroid(list0);
      final Uint32List nextC1 = _calculateModeCentroid(list1);

      // Check if centroids changed
      bool centroidsChanged = false;
      for (int i = 0; i < 64; i++) {
        if (c0[i] != nextC0[i] || c1[i] != nextC1[i]) {
          centroidsChanged = true;
          break;
        }
      }

      if (!centroidsChanged) break;

      c0.setAll(0, nextC0);
      c1.setAll(0, nextC1);
    }

    return [list0, list1];
  }

  // Helper: Majority voting on bits to find the Mode Centroid
  Uint32List _calculateModeCentroid(List<WordRecord> words) {
    // 2048 dimensions = 64 Uint32 ints
    // For each bit, count how many words have it set to 1.
    final List<int> counts = List.filled(2048, 0);
    for (final w in words) {
      for (int b = 0; b < 2048; b++) {
        final int byteIdx = b ~/ 8;
        final int bitIdx = b % 8;
        if ((w.embedding[byteIdx] & (1 << bitIdx)) != 0) {
          counts[b]++;
        }
      }
    }

    final int half = words.length ~/ 2;
    final Uint8List newCentroidBytes = Uint8List(256);
    for (int b = 0; b < 2048; b++) {
      if (counts[b] > half) {
        final int byteIdx = b ~/ 8;
        final int bitIdx = b % 8;
        newCentroidBytes[byteIdx] |= (1 << bitIdx);
      }
    }

    return Uint32List.view(newCentroidBytes.buffer);
  }

  // Recursively bisect clusters until we have at least K clusters.
  // We prioritize splitting clusters with larger SSE (Sum of Squared Errors, in Hamming distance).
  List<List<WordRecord>> cluster(List<WordRecord> list, int k) {
    if (k <= 1 || list.length < 2) return [list];

    // Priority queue of clusters represented as a list sorted by cluster error
    final List<MapEntry<List<WordRecord>, double>> activeClusters = [];

    double calculateError(List<WordRecord> c) {
      if (c.isEmpty) return 0.0;
      final center = _calculateModeCentroid(c);
      double error = 0.0;
      for (final w in c) {
        final dist = computeHammingDistance(w.emb32, center);
        error += dist * dist; // SSE
      }
      return error;
    }

    activeClusters.add(MapEntry(list, calculateError(list)));

    while (activeClusters.length < k) {
      // Find the cluster with the highest error to split
      activeClusters.sort((a, b) => b.value.compareTo(a.value));
      final clusterToSplit = activeClusters.removeAt(0).key;

      if (clusterToSplit.length < 2) {
        // Can't split further, add back and stop
        activeClusters.add(MapEntry(clusterToSplit, 0.0));
        break;
      }

      final splitRes = split(clusterToSplit);
      final left = splitRes[0];
      final right = splitRes[1];

      if (left.isNotEmpty) activeClusters.add(MapEntry(left, calculateError(left)));
      if (right.isNotEmpty) activeClusters.add(MapEntry(right, calculateError(right)));
    }

    return activeClusters.map((e) => e.key).toList();
  }
}

// Bisecting K-Modes Hierarchical Tree Sort
class HierarchicalKModesSorter {
  final BisectingKModes _bisecter = BisectingKModes();

  // Sort by recursively splitting, and then concatenating paths
  List<String> sort(List<WordRecord> list) {
    if (list.isEmpty) return [];
    if (list.length <= 1) return [list[0].id];
    
    // We do a top-down hierarchical split down to leaves
    final path = <String>[];
    _traverse(list, path);
    return path;
  }

  void _traverse(List<WordRecord> sublist, List<String> path) {
    if (sublist.isEmpty) return;
    if (sublist.length <= 2) {
      path.add(sublist[0].id);
      if (sublist.length == 2) {
        path.add(sublist[1].id);
      }
      return;
    }

    final splitRes = _bisecter.split(sublist);
    _traverse(splitRes[0], path);
    _traverse(splitRes[1], path);
  }
}

// -----------------------------------------------------------------------------
// Existing Baseline & TSP Algorithms for comparison
// -----------------------------------------------------------------------------

// Hybrid 3D Filter + Hamming Nearest Neighbor TSP
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

// -----------------------------------------------------------------------------
// Quality Metrics
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// Main execution
// -----------------------------------------------------------------------------
void main() async {
  print('=== Binary K-Means (二分 K-Modes) 算法实验 ===\n');

  // Load PCA config (only to support Hybrid TSP coordinates)
  final pcaFile = File('scratch/pca_config.json');
  final Map<String, dynamic> pcaJson = jsonDecode(pcaFile.readAsStringSync());
  final List<dynamic> meanList = pcaJson['mean'] as List<dynamic>;
  final List<dynamic> compList = pcaJson['components'] as List<dynamic>;
  final pcaConfig = PCAConfig(
    meanList.map((e) => (e as num).toDouble()).toList(),
    compList.map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList(),
  );

  // Load words
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

  // Precompute PCA for the hybrid candidate filter
  for (final w in words) {
    final coords = pcaConfig.projectTo3D(w.embedding);
    w.x = coords[0];
    w.y = coords[1];
    w.z = coords[2];
  }

  final List<int> testSizes = [1000, 2000, 5000, 10000];

  for (final size in testSizes) {
    print('-------------------------------------------');
    print('【测试规模: N = $size】');
    print('-------------------------------------------');

    final testSubset = words.sublist(0, size);

    // 1. Bisecting K-Modes Hierarchical Tree Sort (纯二进制二叉树遍历)
    final stopwatchTree = Stopwatch()..start();
    final treeSorter = HierarchicalKModesSorter();
    final List<String> sortedTreeIds = treeSorter.sort(testSubset);
    stopwatchTree.stop();
    final timeTree = stopwatchTree.elapsedMilliseconds;
    final qualityTree = evaluateQuality(sortedTreeIds, testSubset);

    print('算法 1 (二分 K-Modes 层次树排序):');
    print('  - 执行时间: $timeTree ms');
    print('  - 平均相邻汉明距离: ${qualityTree.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityTree.maxDist}');
    print('  - 大跳转次数 (>128): ${qualityTree.jumps}');

    // 2. Bisecting K-Modes (K = 5) + TSP 排序 (分组分片 TSP)
    final stopwatchKModesTsp = Stopwatch()..start();
    final kModesClusterer = BisectingKModes();
    final clusters = kModesClusterer.cluster(testSubset, 5);
    
    // Sort clusters by their centroids
    final List<Uint32List> centroids = clusters.map((c) => kModesClusterer._calculateModeCentroid(c)).toList();
    final List<int> sortedClusterIndices = [0];
    final List<bool> clusterVisited = List.filled(clusters.length, false)..setAll(0, [true]);
    
    int currCluster = 0;
    for (int step = 1; step < clusters.length; step++) {
      int minDist = 999999;
      int nextCluster = -1;
      for (int i = 0; i < clusters.length; i++) {
        if (clusterVisited[i]) continue;
        final dist = computeHammingDistance(centroids[currCluster], centroids[i]);
        if (dist < minDist) {
          minDist = dist;
          nextCluster = i;
        }
      }
      if (nextCluster == -1) break;
      currCluster = nextCluster;
      sortedClusterIndices.add(currCluster);
      clusterVisited[currCluster] = true;
    }

    final List<String> sortedKModesTspIds = [];
    for (final idx in sortedClusterIndices) {
      final clusterWords = clusters[idx];
      // Perform Hybrid TSP + 2-Opt on each cluster
      final rawPath = runHybridTsp(clusterWords, 20);
      final optimizedPath = optimizePath2OptLocal(rawPath, clusterWords, 15);
      sortedKModesTspIds.addAll(optimizedPath);
    }
    stopwatchKModesTsp.stop();
    final timeKModesTsp = stopwatchKModesTsp.elapsedMilliseconds;
    final qualityKModesTsp = evaluateQuality(sortedKModesTspIds, testSubset);

    print('算法 2 (二分 K-Modes [K=5] + Hybrid-TSP + 2-Opt):');
    print('  - 执行时间: $timeKModesTsp ms');
    print('  - 平均相邻汉明距离: ${qualityKModesTsp.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityKModesTsp.maxDist}');
    print('  - 大跳转次数 (>128): ${qualityKModesTsp.jumps}');

    // 3. Compare with our Champion: Hybrid TSP + 2-Opt (Without Clustering)
    final stopwatchChamp = Stopwatch()..start();
    final rawChampPath = runHybridTsp(testSubset, 50);
    final optimizedChampPath = optimizePath2OptLocal(rawChampPath, testSubset, 15);
    stopwatchChamp.stop();
    final timeChamp = stopwatchChamp.elapsedMilliseconds;
    final qualityChamp = evaluateQuality(optimizedChampPath, testSubset);

    print('算法 3 (混合 3D-50过滤 + Hamming TSP + 2-Opt) [无聚类]:');
    print('  - 执行时间: $timeChamp ms');
    print('  - 平均相邻汉明距离: ${qualityChamp.avgDist.toStringAsFixed(2)}');
    print('  - 最大相邻汉明距离: ${qualityChamp.maxDist}');
    print('  - 大跳转次数 (>128): ${qualityChamp.jumps}');
    print('');
  }
}
