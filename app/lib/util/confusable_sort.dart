import 'edit_distance.dart';

/// 易混淆单词排序的输入：单词 id + 拼写
typedef ConfusableWord = ({String id, String spell});

/// 按 (spell, id) 字典序比较两个词：用于簇头排序、归属锚点选择、组内排序，保证结果确定。
int _compareWord(ConfusableWord a, ConfusableWord b) {
  final bySpell = a.spell.compareTo(b.spell);
  return bySpell != 0 ? bySpell : a.id.compareTo(b.id);
}

/// 返回"词表集合"的 id 集：**有相近词的锚点** ∪ 与锚点一字之差的相近词。
/// 规则（叠加）：参与词 len ≥ 3、相近词对长度相同、编辑距离 ≤ 1（默认 maxDist）；
/// 锚点只有在学习范围内存在与它一字之差（同长度、距离 ≤ maxDist）的词时才保留
/// （无相近词的孤立锚点不进入词表）；相近词可以是其他锚点（锚点互邻时双方都保留）。
/// 长度相同 + 距离 ≤ 1 ⇒ 相近词只可能是"一字之差"（恰好一次替换；同拼写不同 id 的
/// dist=0 按公式 ≤ 1 仍包含）。长度分桶剪枝：编辑距离 ≥ |len 差|，长度相同约束下只查
/// b 的同长度锚点桶（长度差为 0 时下界恰为 0，桶内无漏收），结果与朴素两两全量严格一致。
/// len < 3 的锚点不进桶、len < 3 的候选不返回。本函数只做"与锚点直接匹配"的准入，
/// 不产生任何连锁（相近词不因与其他相近词相近而进入）。
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
  final nearAnchors = <String>{};
  for (final b in candidates) {
    if (b.spell.length < 3) continue; // len < 3 的候选不返回
    final bucket = buckets[b.spell.length];
    if (bucket == null) continue;
    var matched = false;
    for (final a in bucket) {
      if (a.id == b.id) continue; // 排除自身
      if (EditDistance.forStrings(b.spell, a.spell) <= maxDist) {
        matched = true;
        nearAnchors.add(a.id);
        // b 是锚点且与其他锚点互邻 → b 也有相近词
        if (anchors.contains(b)) nearAnchors.add(b.id);
      }
    }
    // 非锚点候选命中 → 相近词进入词表；锚点只通过 nearAnchors 进入
    if (matched && !anchors.contains(b)) {
      result.add(b.id);
    }
  }
  result.addAll(nearAnchors);
  return result;
}

/// 簇式排序：以锚点为簇头、相近词唯一归属、组内同长度、组间不接龙。
///
/// 输入 [selected] 为已通过准入过滤的词表集合（锚点 ∪ 与锚点一字之差的相近词）。
/// 规则：
/// - 锚点（len ≥ 3）按 (spell, id) 字典序作为簇头序列；
/// - 每个非锚点相近词归属到"与它一字之差（同长度、编辑距离 ≤ 1）的锚点中
///   (spell, id) 字典序最小者"，只出现一次（锚点互不为邻居）；
/// - 簇 = [锚点, ...其归属相近词按 (spell, id) 排序]；组内全部词长度相同
///   （相近词与锚点同长度由准入保证）；
/// - 组间不接龙：相近词只出现在其归属簇内；
/// - 无锚点或空 [selected] → 空列表。
List<String> confusableClusterSort(
  Set<ConfusableWord> anchors,
  List<ConfusableWord> selected,
) {
  if (selected.isEmpty) return const [];

  // 锚点按 (spell, id) 字典序；len < 3 的锚点不参与（与准入一致）
  final anchorsSorted = [
    for (final a in anchors)
      if (a.spell.length >= 3) a,
  ]..sort(_compareWord);
  if (anchorsSorted.isEmpty) return const [];

  // 锚点按长度分桶（相近词只与同长度锚点匹配）
  final buckets = <int, List<ConfusableWord>>{};
  for (final a in anchorsSorted) {
    buckets.putIfAbsent(a.spell.length, () => []).add(a);
  }
  final anchorIds = {for (final a in anchorsSorted) a.id};

  // 相近词归属：候选 → 与它一字之差且 (spell, id) 字典序最小的锚点
  final members = <String, List<ConfusableWord>>{};
  for (final c in selected) {
    if (c.spell.length < 3 || anchorIds.contains(c.id)) continue;
    final bucket = buckets[c.spell.length];
    if (bucket == null) continue;
    ConfusableWord? best;
    for (final a in bucket) {
      if (EditDistance.forStrings(c.spell, a.spell) <= 1) {
        if (best == null || _compareWord(a, best) < 0) best = a;
      }
    }
    if (best != null) {
      members.putIfAbsent(best.id, () => []).add(c);
    }
  }
  for (final list in members.values) {
    list.sort(_compareWord);
  }

  // 展开：簇头按字典序，簇内 = 锚点 + 其归属相近词
  final result = <String>[];
  for (final a in anchorsSorted) {
    result.add(a.id);
    final m = members[a.id];
    if (m != null) {
      result.addAll(m.map((w) => w.id));
    }
  }
  return result;
}

/// isolate 传参：ids 与 spells 一一对应；anchorIds 与 anchorSpells 一一对应
/// （anchorIds 为空表示无锚点 → 词表为空，与业务语义"无学习过的词则无词表"一致）。
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

/// isolate 入口：先按锚点过滤（selectConfusableNear，无连锁准入），再对结果集簇式排序
/// （confusableClusterSort），供 WordBo 用 compute 调用。
List<String> confusableSortInIsolate(ConfusableSortParams params) {
  final candidates = <ConfusableWord>[
    for (var i = 0; i < params.ids.length; i++)
      (id: params.ids[i], spell: params.spells[i]),
  ];
  final anchors = <ConfusableWord>{
    for (var i = 0; i < params.anchorIds.length; i++)
      (id: params.anchorIds[i], spell: params.anchorSpells[i]),
  };
  if (anchors.isEmpty) return const [];
  final selected = selectConfusableNear(anchors, candidates, maxDist: 1);
  final filtered = [
    for (final w in candidates)
      if (selected.contains(w.id)) w,
  ];
  // 簇式排序只接收"有相近词的锚点"（孤立锚点已被准入剔除，不再作簇头输出）
  final selectedAnchors = {
    for (final a in anchors)
      if (selected.contains(a.id)) a,
  };
  return confusableClusterSort(selectedAnchors, filtered);
}
