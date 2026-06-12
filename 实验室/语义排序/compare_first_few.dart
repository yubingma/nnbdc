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
  final pcaFile = File('scratch/pca_config.json');
  final Map<String, dynamic> pcaJson = jsonDecode(pcaFile.readAsStringSync());
  final List<dynamic> meanList = pcaJson['mean'] as List<dynamic>;
  final List<dynamic> compList = pcaJson['components'] as List<dynamic>;
  final pcaConfig = PCAConfig(
    meanList.map((e) => (e as num).toDouble()).toList(),
    compList.map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList(),
  );

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

  for (final w in words) {
    final coords = pcaConfig.projectTo3D(w.embedding);
    w.x = coords[0];
    w.y = coords[1];
    w.z = coords[2];
  }

  final subset = words.sublist(0, 2000);

  // A. Pure Hamming TSP (No Filter)
  print('正在计算 Pure Hamming TSP (全局搜索)...');
  final List<String> pathPure = runPureHammingTsp(subset);

  // B. Hybrid TSP (M=50) + 2-Opt (windowSize=15)
  print('正在计算 Hybrid TSP (M=50) + 2-Opt...');
  final List<String> pathHybridRaw = runHybridTsp(subset, 50);
  final List<String> pathHybridOpt = optimizePath2OptLocal(pathHybridRaw, subset, 15);

  // C. Hybrid TSP (M=200) + 2-Opt
  print('正在计算 Hybrid TSP (M=200) + 2-Opt...');
  final List<String> pathHybrid200Raw = runHybridTsp(subset, 200);
  final List<String> pathHybrid200Opt = optimizePath2OptLocal(pathHybrid200Raw, subset, 15);

  final buffer = StringBuffer();
  buffer.writeln('=== 首100词排序效果比对 (N=2000) ===\n');

  buffer.writeln('【比对列 1】Pure Hamming TSP (全局)      | 【比对列 2】Hybrid TSP (M=50) + 2-Opt  | 【比对列 3】Hybrid TSP (M=200) + 2-Opt');
  buffer.writeln('-----------------------------------------+----------------------------------------+----------------------------------------');

  final Map<String, WordRecord> map = {for (var w in subset) w.id: w};

  for (int i = 0; i < 100; i++) {
    final wPure = map[pathPure[i]]!;
    final wHybrid = map[pathHybridOpt[i]]!;
    final wHybrid200 = map[pathHybrid200Opt[i]]!;

    String distPureStr = '';
    if (i > 0) {
      final prevWP = map[pathPure[i - 1]]!;
      distPureStr = '(${computeHammingDistance(prevWP.emb32, wPure.emb32)})';
    } else {
      distPureStr = '(start)';
    }

    String distHybridStr = '';
    if (i > 0) {
      final prevWH = map[pathHybridOpt[i - 1]]!;
      distHybridStr = '(${computeHammingDistance(prevWH.emb32, wHybrid.emb32)})';
    } else {
      distHybridStr = '(start)';
    }

    String distHybrid200Str = '';
    if (i > 0) {
      final prevWH200 = map[pathHybrid200Opt[i - 1]]!;
      distHybrid200Str = '(${computeHammingDistance(prevWH200.emb32, wHybrid200.emb32)})';
    } else {
      distHybrid200Str = '(start)';
    }

    final col1 = '${(i + 1).toString().padLeft(3, '0')}. ${wPure.spell.padRight(18)} $distPureStr'.padRight(40);
    final col2 = '${(i + 1).toString().padLeft(3, '0')}. ${wHybrid.spell.padRight(18)} $distHybridStr'.padRight(40);
    final col3 = '${(i + 1).toString().padLeft(3, '0')}. ${wHybrid200.spell.padRight(18)} $distHybrid200Str';

    buffer.writeln('$col1 | $col2 | $col3');
  }

  final outFile = File('scratch/compare_paths_first_100.txt');
  outFile.writeAsStringSync(buffer.toString());
  print('✅ 比对结果已成功写入 scratch/compare_paths_first_100.txt');
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
