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

void main() {
  final wordsFile = File('scratch/words_10k.jsonl');
  if (!wordsFile.existsSync()) {
    print('Error: scratch/words_10k.jsonl not found');
    return;
  }
  final List<Uint8List> embeddings = [];
  final List<String> lines = wordsFile.readAsLinesSync();
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final Map<String, dynamic> record = jsonDecode(line);
    final String hexEmb = record['embedding1bit'];
    embeddings.add(decodeHex(hexEmb));
  }
  print('Loaded ${embeddings.length} words from 10k file.');

  // Calculate top 64 dims on 10k subset
  final List<int> bitCounts = List.filled(2048, 0);
  for (final emb in embeddings) {
    for (int d = 0; d < 2048; d++) {
      final int byteIdx = d ~/ 8;
      final int bitIdx = d % 8;
      if ((emb[byteIdx] & (1 << bitIdx)) != 0) {
        bitCounts[d]++;
      }
    }
  }

  final List<MapEntry<int, double>> dimDeviation = [];
  final double targetRatio = 0.5;
  for (int d = 0; d < 2048; d++) {
    final double ratio = bitCounts[d] / embeddings.length;
    final double deviation = (ratio - targetRatio).abs();
    dimDeviation.add(MapEntry(d, deviation));
  }
  dimDeviation.sort((a, b) => a.value.compareTo(b.value));
  final List<int> subsetDims = dimDeviation.take(64).map((e) => e.key).toList();

  // Global static dims (from 47,717 words)
  final List<int> globalDims = const [
    1826, 1699, 1458, 912, 1660, 93, 788, 1966, 1632, 187,
    1351, 8, 1189, 1483, 257, 979, 1806, 1608, 1544, 1712,
    2009, 2003, 675, 214, 197, 563, 842, 1776, 1968, 583,
    1833, 427, 110, 1656, 956, 2007, 74, 227, 1883, 33,
    86, 1416, 1468, 2027, 1284, 995, 235, 1706, 985, 1644,
    1599, 711, 1218, 275, 174, 1005, 412, 789, 2022, 1362,
    1692, 593, 69, 81
  ];

  final Set<int> subsetSet = subsetDims.toSet();
  final Set<int> globalSet = globalDims.toSet();

  final Set<int> intersection = subsetSet.intersection(globalSet);
  final Set<int> onlyInSubset = subsetSet.difference(globalSet);
  final Set<int> onlyInGlobal = globalSet.difference(subsetSet);

  print('=== 维度对比分析 ===');
  print('10k局部子集选取维度的总数: ${subsetDims.length}');
  print('47k全局数据库选取维度的总数: ${globalDims.length}');
  print('交集大小 (完全一致的维度个数): ${intersection.length}');
  print('偏移维度大小 (发生偏移的维度个数): ${onlyInGlobal.length}');
  print('仅在10k子集中出现的维度: $onlyInSubset');
  print('仅在47k全局中出现的维度: $onlyInGlobal');
}
