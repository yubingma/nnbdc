import 'edit_distance.dart';

/// 易混淆单词排序的输入：单词 id + 拼写
typedef ConfusableWord = ({String id, String spell});

/// 长度分桶剪枝允许的最大长度差。
/// 编辑距离 >= |len 差|，长度差 > [_delta] 的词编辑距离必 > [_delta]，
/// 因此桶内最优距离 <= [_delta] 时桶外词不可能更近，剪枝安全。
const int _delta = 3;

/// 按拼写相似度贪心最近邻排序，返回排序后的 id 列表。
/// 从字典序最小的词出发，每一步选未访问词中与当前词编辑距离最小的下一个
/// （距离相同取 spell 字典序更小，再取 id 字典序更小）；长度分桶剪枝 +
/// 回退全量扫描，结果与朴素全量贪心严格一致。
List<String> confusableSort(List<ConfusableWord> words) {
  if (words.length <= 1) {
    return [for (final w in words) w.id];
  }

  // 按 (spell, id) 字典序排序：起始词取最小者；平局扫描保持同一顺序，结果确定
  final sorted = [...words]..sort((a, b) {
        final bySpell = a.spell.compareTo(b.spell);
        return bySpell != 0 ? bySpell : a.id.compareTo(b.id);
      });

  // 长度分桶：spell.length -> 桶内保持 (spell, id) 字典序
  final buckets = <int, List<ConfusableWord>>{};
  for (final w in sorted) {
    buckets.putIfAbsent(w.spell.length, () => []).add(w);
  }

  final order = <String>[sorted.first.id];
  final unvisited = <String>{for (final w in sorted.skip(1)) w.id};
  var curSpell = sorted.first.spell;

  while (unvisited.isNotEmpty) {
    // 1) 桶内候选：长度差 <= DELTA 的未访问词
    ConfusableWord? best;
    var bestDist = 0;
    final curLen = curSpell.length;
    for (var len = curLen - _delta; len <= curLen + _delta; len++) {
      final bucket = buckets[len];
      if (bucket == null) continue;
      for (final w in bucket) {
        if (!unvisited.contains(w.id)) continue;
        final d = EditDistance.forStrings(curSpell, w.spell);
        if (_isBetter(w, d, best, bestDist)) {
          best = w;
          bestDist = d;
        }
      }
    }
    // 桶内最优距离 <= DELTA 时桶外词（距离必 > DELTA）不可能更近，剪枝安全
    if (best != null && bestDist <= _delta) {
      _take(best, order, unvisited);
      curSpell = best.spell;
      continue;
    }
    // 2) 回退全量扫描：桶内候选为空，或桶内最优距离 > DELTA（桶外可能有更近词）
    best = null;
    bestDist = 0;
    for (final w in sorted) {
      if (!unvisited.contains(w.id)) continue;
      final d = EditDistance.forStrings(curSpell, w.spell);
      if (_isBetter(w, d, best, bestDist)) {
        best = w;
        bestDist = d;
      }
    }
    _take(best!, order, unvisited);
    curSpell = best.spell;
  }
  return order;
}

/// 候选 w（距离 d）是否优于当前最优 best（距离 bestDist）：
/// 距离更小，或距离相同取 (spell, id) 字典序更小
bool _isBetter(ConfusableWord w, int d, ConfusableWord? best, int bestDist) {
  if (best == null || d < bestDist) return true;
  if (d > bestDist) return false;
  final bySpell = w.spell.compareTo(best.spell);
  return bySpell != 0 ? bySpell < 0 : w.id.compareTo(best.id) < 0;
}

void _take(ConfusableWord w, List<String> order, Set<String> unvisited) {
  order.add(w.id);
  unvisited.remove(w.id);
}

/// 返回 candidates 中"属于锚点 或 与某锚点编辑距离 ≤ maxDist"的 id 集合。
/// 规则（叠加）：参与词 len ≥ 3、相近词对长度相同、编辑距离 ≤ 1（默认 maxDist）。
/// 长度相同 + 距离 ≤ 1 ⇒ 相近词只可能是"一字之差"（恰好一次替换；同拼写不同 id 的
/// dist=0 按公式 ≤ 1 仍包含）。长度分桶剪枝：编辑距离 ≥ |len 差|，长度相同约束下只查
/// b 的同长度锚点桶（长度差为 0 时下界恰为 0，桶内无漏收），结果与朴素两两全量严格一致。
/// len < 3 的锚点不进桶、len < 3 的候选不返回。
Set<String> selectConfusableNear(
  Set<ConfusableWord> anchors,
  List<ConfusableWord> candidates, {
  int maxDist = 1,
}) {
  if (anchors.isEmpty) return {};
  // 锚点按 spell 长度分桶（len < 3 的锚点不参与匹配）
  final buckets = <int, List<ConfusableWord>>{};
  for (final a in anchors) {
    if (a.spell.length < 3) continue;
    buckets.putIfAbsent(a.spell.length, () => []).add(a);
  }
  final result = <String>{};
  for (final b in candidates) {
    if (b.spell.length < 3) continue; // len < 3 的候选不返回
    // 候选本身是锚点（len ≥ 3）→ 直接包含；否则与同长度锚点桶计算距离
    if (anchors.contains(b) || _nearAnyAnchor(b, buckets, maxDist)) {
      result.add(b.id);
    }
  }
  return result;
}

/// b 是否与 [buckets] 中与 b 同长度的锚点编辑距离 ≤ maxDist（短路）。
/// 规则要求相近词对长度相同，故只查 b 长度的精确桶；
/// 编辑距离 ≥ |len 差| 保证同长度桶（长度差 0，下界 0）不漏收。
bool _nearAnyAnchor(
  ConfusableWord b,
  Map<int, List<ConfusableWord>> buckets,
  int maxDist,
) {
  final bucket = buckets[b.spell.length];
  if (bucket == null) return false;
  for (final a in bucket) {
    if (EditDistance.forStrings(b.spell, a.spell) <= maxDist) return true;
  }
  return false;
}

/// isolate 传参：ids 与 spells 一一对应；anchorIds 与 anchorSpells 一一对应
/// （anchorIds 为空表示无锚点，过滤退化为仅 len ≥ 3，与正常路径语义一致）
class ConfusableSortParams {
  final List<String> ids;
  final List<String> spells;
  final List<String> anchorIds;
  final List<String> anchorSpells;

  ConfusableSortParams(
    this.ids,
    this.spells, {
    this.anchorIds = const [],
    this.anchorSpells = const [],
  })  : assert(ids.length == spells.length, 'ids 与 spells 必须一一对应'),
        assert(anchorIds.length == anchorSpells.length,
            'anchorIds 与 anchorSpells 必须一一对应');
}

/// isolate 入口：先按锚点过滤（selectConfusableNear），再对结果集贪心排序，
/// 供 WordBo 用 compute 调用。无锚点时过滤退化为仅 len ≥ 3（与正常路径一致，
/// 不豁免最短词长约束）。
List<String> confusableSortInIsolate(ConfusableSortParams params) {
  final candidates = <ConfusableWord>[
    for (var i = 0; i < params.ids.length; i++)
      (id: params.ids[i], spell: params.spells[i]),
  ];
  final anchors = <ConfusableWord>{
    for (var i = 0; i < params.anchorIds.length; i++)
      (id: params.anchorIds[i], spell: params.anchorSpells[i]),
  };
  if (anchors.isEmpty) {
    return confusableSort([
      for (final w in candidates)
        if (w.spell.length >= 3) w,
    ]);
  }
  final selected = selectConfusableNear(anchors, candidates, maxDist: 1);
  final filtered = [for (final w in candidates) if (selected.contains(w.id)) w];
  return confusableSort(filtered);
}
