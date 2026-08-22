import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:nnbdc/util/confusable_sort.dart';
import 'package:nnbdc/util/edit_distance.dart';

// ===== 朴素 A×B 两两全量过滤：无剪枝的对照基准（规则与 selectConfusableNear 完全一致）=====

/// 朴素实现：候选 len ≥ 3；锚点只有在学习范围内存在与它一字之差（同长度、距离 ≤ maxDist）
/// 的词时才保留（无相近词的孤立锚点剔除，相近词可以是其他锚点）；非锚点候选与某锚点
/// 一字之差即作为相近词入选。
Set<String> naiveSelectConfusableNear(
  Set<ConfusableWord> anchors,
  List<ConfusableWord> candidates, {
  int maxDist = 1,
}) {
  if (anchors.isEmpty) return {};
  final result = <String>{};
  final nearAnchors = <String>{};
  for (final b in candidates) {
    if (b.spell.length < 3) continue;
    var matched = false;
    for (final a in anchors) {
      if (a.id == b.id) continue; // 排除自身
      if (a.spell.length == b.spell.length &&
          EditDistance.forStrings(b.spell, a.spell) <= maxDist) {
        matched = true;
        nearAnchors.add(a.id);
        if (anchors.contains(b)) nearAnchors.add(b.id);
      }
    }
    if (matched && !anchors.contains(b)) {
      result.add(b.id);
    }
  }
  result.addAll(nearAnchors);
  return result;
}

// ===== 朴素簇式排序：无分桶剪枝的对照基准（规则与 confusableClusterSort 完全一致）=====

int _bySpellThenId(ConfusableWord a, ConfusableWord b) {
  final bySpell = a.spell.compareTo(b.spell);
  return bySpell != 0 ? bySpell : a.id.compareTo(b.id);
}

/// 朴素实现：锚点按"最近学习时间降序（缺失排最后）+ (spell, id) 字典序"为簇头；
/// 每个非锚点相近词归属到"与它一字之差（同长度、距离 ≤ 1）且 (spell, id) 字典序最小"的锚点，
/// 只出现一次；簇内相近词按 (spell, id) 排序；输出 = 各簇依次展开。
List<String> naiveConfusableClusterSort(
  Set<ConfusableWord> anchors,
  List<ConfusableWord> selected, {
  Map<String, DateTime?>? anchorTimes,
}) {
  if (selected.isEmpty) return [];
  final anchorsSorted = [
    for (final a in anchors)
      if (a.spell.length >= 3) a,
  ]..sort((a, b) {
      final ta = anchorTimes?[a.id];
      final tb = anchorTimes?[b.id];
      if (ta != null && tb != null) {
        final byTime = tb.compareTo(ta);
        if (byTime != 0) return byTime;
      } else if (ta != null) {
        return -1;
      } else if (tb != null) {
        return 1;
      }
      return _bySpellThenId(a, b);
    });
  if (anchorsSorted.isEmpty) return [];
  final anchorIds = {for (final a in anchorsSorted) a.id};

  final members = <String, List<ConfusableWord>>{};
  for (final c in selected) {
    if (c.spell.length < 3 || anchorIds.contains(c.id)) continue;
    ConfusableWord? best;
    for (final a in anchorsSorted) {
      if (a.spell.length != c.spell.length) continue;
      if (EditDistance.forStrings(c.spell, a.spell) <= 1) {
        if (best == null || _bySpellThenId(a, best) < 0) best = a;
      }
    }
    if (best != null) {
      members.putIfAbsent(best.id, () => []).add(c);
    }
  }
  for (final list in members.values) {
    list.sort(_bySpellThenId);
  }

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

// ===== 断言辅助 =====

/// 结果必须是原词集的排列：无遗漏、无重复
void expectPermutation(List<String> order, List<ConfusableWord> words) {
  expect(order.length, words.length);
  expect(order.toSet(), {for (final w in words) w.id});
}

/// 组内成员在结果中连续出现（成簇相邻）
void expectContiguous(List<String> order, Set<String> groupIds) {
  final indices = [for (final id in groupIds) order.indexOf(id)]..sort();
  for (var i = 0; i + 1 < indices.length; i++) {
    expect(indices[i + 1], indices[i] + 1, reason: '组内成员应成簇相邻: $groupIds -> $order');
  }
}

// ===== 随机词集生成（含少量同 spell 不同 id 的词）=====

List<ConfusableWord> randomWords(Random rng, int n) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  final words = <ConfusableWord>[];
  for (var i = 0; i < n; i++) {
    final len = 1 + rng.nextInt(12);
    final spell = String.fromCharCodes(
      List.generate(len, (_) => letters.codeUnitAt(rng.nextInt(letters.length))),
    );
    words.add((id: 'w$i', spell: spell));
  }
  if (n >= 3) {
    words.add((id: 'dup', spell: words[rng.nextInt(n)].spell));
  }
  return words;
}

void main() {
  group('selectConfusableNear 锚点过滤', () {
    test('锚点保留语义：有相近词的锚点保留；孤立锚点（无相近词）与 len<3 锚点不在结果集', () {
      const anchors = {
        (id: 'a1', spell: 'house'), // len 5，无相近词 → 孤立锚点，不进入词表
        (id: 'a2', spell: 'go'), // len 2 < 3 → 不进入词表
        (id: 'a3', spell: 'cat'), // len 3，有相近词 cut → 保留
      };
      const candidates = [
        (id: 'a1', spell: 'house'),
        (id: 'a2', spell: 'go'),
        (id: 'a3', spell: 'cat'),
        (id: 'b1', spell: 'dog'), // 与锚点距离远，不影响
        (id: 'b2', spell: 'cut'), // 与 cat 同长 3、距离 1 → 相近词
      ];
      final result = selectConfusableNear(anchors, candidates);
      expect(result, {'a3', 'b2'});
      expect(result, isNot(contains('a1')));
      expect(result, isNot(contains('a2')));
    });

    test('锚点互邻（互为相近词）双方都保留', () {
      // drug 与 drag 同长 4、距离 1，都学习过（都是锚点）→ 互为相近词，双方保留
      const anchors = {
        (id: 'drug', spell: 'drug'),
        (id: 'drag', spell: 'drag'),
      };
      const candidates = [
        (id: 'drug', spell: 'drug'),
        (id: 'drag', spell: 'drag'),
      ];
      expect(selectConfusableNear(anchors, candidates), {'drug', 'drag'});
    });

    test('阈值边界：dist=1 含、dist=2 不含、长度不同不含、len<3 不含', () {
      expect(EditDistance.forStrings('house', 'horse'), 1);
      expect(EditDistance.forStrings('weather', 'whether'), 2);
      expect(EditDistance.forStrings('cat', 'cart'), 1); // 长度 3≠4
      expect(EditDistance.forStrings('at', 'it'), 1); // 长度 2 < 3

      const anchors = {
        (id: 'a_house', spell: 'house'),
        (id: 'a_weather', spell: 'weather'),
        (id: 'a_cat', spell: 'cat'),
        (id: 'a_at', spell: 'at'),
      };
      const candidates = [
        (id: 'b_horse', spell: 'horse'), // 与 house 同长 5、dist=1 → 含
        (id: 'b_whether', spell: 'whether'), // 与 weather 同长 7、dist=2 → 不含（距离超限）
        (id: 'b_cart', spell: 'cart'), // 与 cat 距离 1 但长度 4≠3 → 不含（长度不同）
        (id: 'b_it', spell: 'it'), // 与 at 距离 1 但长度 2<3 → 不含（最短词长）
        (id: 'b_dog', spell: 'dog'), // 无关 → 排除
      ];
      final result = selectConfusableNear(anchors, candidates);
      // 只有 house 有相近词（horse）→ house 锚点保留；weather/cat/at 无相近词 → 剔除
      expect(result, {'a_house', 'b_horse'});
      expect(result, isNot(contains('a_weather')));
      expect(result, isNot(contains('a_cat')));
    });

    test('显式 maxDist 参数在长度相同约束下仍生效', () {
      // weather/whether 同长 7、距离恰为 2：默认 1 时 whether 不是相近词、
      // weather 无相近词 → 空；显式 2 时 whether 成为相近词 → weather 锚点保留 + whether
      const anchors = {(id: 'a', spell: 'weather')};
      const candidates = [(id: 'b', spell: 'whether')];
      expect(selectConfusableNear(anchors, candidates), isEmpty);
      expect(selectConfusableNear(anchors, candidates, maxDist: 2), {'a', 'b'});
    });

    test('dist=0 同拼写不同 id：按公式距离 0 ≤ 1 仍包含', () {
      const anchors = {(id: 'a1', spell: 'house')};
      const candidates = [
        (id: 'a1', spell: 'house'),
        (id: 'b1', spell: 'house'), // 同拼写不同 id，dist=0
      ];
      expect(selectConfusableNear(anchors, candidates), {'a1', 'b1'});
    });

    test('空锚点返回空集；空候选返回空集', () {
      expect(selectConfusableNear({}, const [(id: 'b', spell: 'cat')]), isEmpty);
      expect(
        selectConfusableNear(const {(id: 'a', spell: 'cat')}, const []),
        isEmpty,
      );
    });

    test('长度分桶剪枝与朴素两两全量严格一致', () {
      const anchors = {
        (id: 'a1', spell: 'cat'),
        (id: 'a2', spell: 'cattle'),
        (id: 'a3', spell: 'x'), // len 1 < 3：不进桶、不参与匹配
        (id: 'a4', spell: 'apple'),
      };
      const candidates = [
        (id: 'a1', spell: 'cat'), // 锚点自身
        (id: 'b1', spell: 'cut'), // 与 cat 同长、距离 1
        (id: 'b2', spell: 'cart'), // 与 cat 距离 1 但长度 4≠3 → 排除
        (id: 'b3', spell: 'apple'), // 与 a4 同 spell（不同 id，距离 0）
        (id: 'b4', spell: 'cattle'), // 与 a2 同 spell（不同 id，距离 0）
        (id: 'b5', spell: 'zzzz'), // 与任何锚点距离远
        (id: 'b6', spell: 'xx'), // len 2 < 3：不返回
      ];
      for (final maxDist in [0, 1, 2, 3]) {
        expect(
          selectConfusableNear(anchors, candidates, maxDist: maxDist),
          naiveSelectConfusableNear(anchors, candidates, maxDist: maxDist),
          reason: '手工构造 maxDist=$maxDist',
        );
      }

      for (var seed = 0; seed < 50; seed++) {
        final rng = Random(seed);
        final n = 1 + rng.nextInt(60);
        final words = randomWords(rng, n);
        final anchorsSet = {for (final w in words) if (rng.nextBool()) w};
        final maxDist = rng.nextInt(4); // 0..3
        expect(
          selectConfusableNear(anchorsSet, words, maxDist: maxDist),
          naiveSelectConfusableNear(anchorsSet, words, maxDist: maxDist),
          reason: 'seed=$seed, n=$n, maxDist=$maxDist',
        );
      }

      for (var seed = 0; seed < 50; seed++) {
        final rng = Random(1000 + seed);
        final n = 1 + rng.nextInt(60);
        final words = randomWords(rng, n);
        final anchorsSet = {for (final w in words) if (rng.nextBool()) w};
        expect(
          selectConfusableNear(anchorsSet, words),
          selectConfusableNear(anchorsSet, words, maxDist: 1),
          reason: 'seed=$seed 默认 maxDist 必须为 1',
        );
        expect(
          selectConfusableNear(anchorsSet, words),
          naiveSelectConfusableNear(anchorsSet, words),
          reason: 'seed=$seed 默认 maxDist 与朴素实现一致',
        );
      }
    });
  });

  group('confusableClusterSort 簇式排序', () {
    test('唯一锚点：相近词归属该锚点、组内按 (spell, id) 排序', () {
      const anchors = {(id: 'drug', spell: 'drug')};
      const selected = [
        (id: 'drug', spell: 'drug'),
        (id: 'drum', spell: 'drum'), // 与 drug 同长 4、距离 1
        (id: 'drag', spell: 'drag'), // 与 drug 同长 4、距离 1
      ];
      // 组内按 (spell, id)：drag < drum
      expect(confusableClusterSort(anchors, selected), ['drug', 'drag', 'drum']);
      expect(
        confusableClusterSort(anchors, selected),
        naiveConfusableClusterSort(anchors, selected),
      );
    });

    test('多锚点归属：相近词归属 (spell, id) 字典序最小的锚点、只出现一次', () {
      const anchors = {
        (id: 'cat', spell: 'cat'),
        (id: 'cot', spell: 'cot'),
      };
      const selected = [
        (id: 'cat', spell: 'cat'),
        (id: 'cot', spell: 'cot'),
        (id: 'cut', spell: 'cut'), // 与 cat、cot 距离均为 1 → 归属 cat（c-a < c-o）
      ];
      final order = confusableClusterSort(anchors, selected);
      expect(order, ['cat', 'cut', 'cot']);
      expect(order.where((id) => id == 'cut').length, 1);
      expect(order, naiveConfusableClusterSort(anchors, selected));
    });

    test('组内字母数相同（组间可不同）', () {
      const anchors = {
        (id: 'drug', spell: 'drug'), // len 4
        (id: 'cat', spell: 'cat'), // len 3
      };
      const selected = [
        (id: 'drug', spell: 'drug'),
        (id: 'drum', spell: 'drum'), // len 4，属 drug 簇
        (id: 'cat', spell: 'cat'),
        (id: 'cut', spell: 'cut'), // len 3，属 cat 簇
      ];
      final order = confusableClusterSort(anchors, selected);
      expect(order, ['cat', 'cut', 'drug', 'drum']);
      // 组内长度一致：cat/cut 为 3，drug/drum 为 4
      final spells = {for (final w in selected) w.id: w.spell};
      for (final cluster in [
        ['cat', 'cut'],
        ['drug', 'drum'],
      ]) {
        final lens = cluster.map((id) => spells[id]!.length).toSet();
        expect(lens.length, 1, reason: '组内字母数必须相同: $cluster');
      }
    });

    test('组间不接龙：相近词只出现在其归属簇，不跨簇串联', () {
      // 构造贪心排序会串成链的场景：drum-drug-drag-rag-rage-age
      // 锚点 = {drug, age}（均学习过）
      const anchors = {
        (id: 'drug', spell: 'drug'),
        (id: 'age', spell: 'age'),
      };
      const selected = [
        (id: 'drug', spell: 'drug'),
        (id: 'age', spell: 'age'),
        (id: 'drum', spell: 'drum'), // 与 drug 同长 4、距离 1 → drug 簇
        (id: 'drag', spell: 'drag'), // 与 drug 同长 4、距离 1 → drug 簇
        (id: 'rag', spell: 'rag'), // 与 drag 距离 1，但与锚点 drug 距离 2 → 不进词表
        (id: 'rage', spell: 'rage'), // 与 age 长度 4≠3 → 不进词表
      ];
      // 准入后的词表只含 drug、age、drum、drag（rage/rag 因长度/距离被排除）
      final selectedFiltered = [
        for (final w in selected) w,
      ];
      final order = confusableClusterSort(anchors, selectedFiltered);
      expect(order, ['age', 'drug', 'drag', 'drum']);
      expect(order, naiveConfusableClusterSort(anchors, selectedFiltered));
    });

    test('锚点互为相近词（都学习过）各自成簇、互不并入', () {
      // drug 与 drag 同长 4、距离 1，互为相近词；但都是锚点 → 各自成簇、互不并入
      const anchors = {
        (id: 'drug', spell: 'drug'),
        (id: 'drag', spell: 'drag'),
      };
      const selected = [
        (id: 'drug', spell: 'drug'),
        (id: 'drag', spell: 'drag'),
        (id: 'drum', spell: 'drum'), // 与 drug 距离 1 → drug 簇
        (id: 'rag', spell: 'rag'), // 长度 3 ≠ 4，与 drag 长度不同 → 准入排除（不进词表）
      ];
      final order = confusableClusterSort(anchors, selected);
      expect(order, ['drag', 'drug', 'drum']);
      expect(order, naiveConfusableClusterSort(anchors, selected));
    });

    test('锚点按最近学习时间降序；缺失排最后；时间相同按字典序', () {
      final t1 = DateTime(2026, 8, 20);
      final t2 = DateTime(2026, 8, 21); // 更新
      const anchors = {
        (id: 'cat', spell: 'cat'),
        (id: 'cot', spell: 'cot'),
        (id: 'cut', spell: 'cut'),
      };
      const selected = [
        (id: 'cat', spell: 'cat'),
        (id: 'cot', spell: 'cot'),
        (id: 'cut', spell: 'cut'),
      ];
      final anchorTimes = <String, DateTime?>{
        'cat': t1,
        'cot': t2, // 最新 → 排最前
        'cut': null, // 缺失 → 排最后
      };
      final order = confusableClusterSort(anchors, selected, anchorTimes: anchorTimes);
      expect(order, ['cot', 'cat', 'cut']);
      expect(order, naiveConfusableClusterSort(anchors, selected, anchorTimes: anchorTimes));

      // 时间相同 → 按 (spell, id) 字典序（cot < cut）
      final sameTime = <String, DateTime?>{'cat': t1, 'cot': t1, 'cut': t1};
      expect(confusableClusterSort(anchors, selected, anchorTimes: sameTime),
          ['cat', 'cot', 'cut']);
    });

    test('孤立锚点（无相近词）按字典序排列', () {
      const anchors = {
        (id: 'house', spell: 'house'),
        (id: 'apple', spell: 'apple'),
      };
      const selected = [
        (id: 'house', spell: 'house'),
        (id: 'apple', spell: 'apple'),
      ];
      expect(confusableClusterSort(anchors, selected), ['apple', 'house']);
    });

    test('空锚点 / 空 selected → 空', () {
      expect(confusableClusterSort({}, const [(id: 'b', spell: 'cat')]), isEmpty);
      expect(
        confusableClusterSort(const {(id: 'a', spell: 'cat')}, const []),
        isEmpty,
      );
    });

    test('len<3 锚点不参与；len<3 候选不输出', () {
      const anchors = {
        (id: 'a_go', spell: 'go'), // len 2 < 3 → 不参与
        (id: 'a_cat', spell: 'cat'),
      };
      const selected = [
        (id: 'a_go', spell: 'go'),
        (id: 'a_cat', spell: 'cat'),
        (id: 'b_cut', spell: 'cut'), // 与 cat 距离 1 → cat 簇
        (id: 'b_at', spell: 'at'), // len 2 < 3 → 不输出
      ];
      final order = confusableClusterSort(anchors, selected);
      expect(order, ['a_cat', 'b_cut']);
      expect(order, naiveConfusableClusterSort(anchors, selected));
    });

    test('与朴素归属实现严格一致（构造 + 随机词集）', () {
      final constructed = <(Set<ConfusableWord>, List<ConfusableWord>)>[
        // 手工：锚点同长度、候选跨长度
        (
          const {
            (id: 'a1', spell: 'cat'),
            (id: 'a2', spell: 'cot'),
            (id: 'a3', spell: 'house'),
          },
          const [
            (id: 'a1', spell: 'cat'),
            (id: 'a2', spell: 'cot'),
            (id: 'a3', spell: 'house'),
            (id: 'b1', spell: 'cut'),
            (id: 'b2', spell: 'horse'),
            (id: 'b3', spell: 'cart'),
            (id: 'b4', spell: 'mouse'),
          ],
        ),
      ];
      for (final (anchorsSet, selected) in constructed) {
        expect(
          confusableClusterSort(anchorsSet, selected),
          naiveConfusableClusterSort(anchorsSet, selected),
          reason: '手工构造词集',
        );
      }

      for (var seed = 0; seed < 100; seed++) {
        final rng = Random(seed);
        final n = 1 + rng.nextInt(50);
        final words = randomWords(rng, n);
        final anchorsSet = {for (final w in words) if (rng.nextBool()) w};
        // selected 取"与锚点直接一字之差"的准入结果（与产品链路一致）
        final selectedSet = selectConfusableNear(anchorsSet, words);
        final selected = [for (final w in words) if (selectedSet.contains(w.id)) w];
        expect(
          confusableClusterSort(anchorsSet, selected),
          naiveConfusableClusterSort(anchorsSet, selected),
          reason: 'seed=$seed, n=$n',
        );
      }
    });
  });

  group('isolate 入口（锚点过滤 + 簇式排序）', () {
    test('带锚点：confusableSortInIsolate 与 selectConfusableNear + confusableClusterSort 一致', () {
      const anchors = {
        (id: 'drug', spell: 'drug'),
        (id: 'age', spell: 'age'),
      };
      const words = [
        (id: 'drug', spell: 'drug'),
        (id: 'age', spell: 'age'),
        (id: 'drum', spell: 'drum'),
        (id: 'drag', spell: 'drag'),
        (id: 'rag', spell: 'rag'), // 与 drug 距离 2 → 被准入排除
        (id: 'dog', spell: 'dog'), // 无关 → 排除
      ];
      final params = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
        anchorIds: [for (final a in anchors) a.id],
        anchorSpells: [for (final a in anchors) a.spell],
      );
      final selected = selectConfusableNear(anchors, words);
      final filtered = [for (final w in words) if (selected.contains(w.id)) w];
      final selectedAnchors = {
        for (final a in anchors)
          if (selected.contains(a.id)) a,
      };
      expect(confusableSortInIsolate(params),
          confusableClusterSort(selectedAnchors, filtered));
      expect(confusableSortInIsolate(params), isNot(contains('rag')));
      expect(confusableSortInIsolate(params), isNot(contains('dog')));
    });

    test('无锚点 → 空词表（无学习过的词则无词表）', () {
      const words = [
        (id: 'w_cat', spell: 'cat'),
        (id: 'w_cot', spell: 'cot'),
        (id: 'w_cart', spell: 'cart'),
        (id: 'w_go', spell: 'go'),
      ];
      final params = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
      );
      expect(confusableSortInIsolate(params), isEmpty);

      final paramsEmptyAnchors = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
        anchorIds: const [],
        anchorSpells: const [],
      );
      expect(confusableSortInIsolate(paramsEmptyAnchors), isEmpty);

      // 空输入
      expect(confusableSortInIsolate(ConfusableSortParams([], [])), isEmpty);
    });

    test('用户示例集成：锚点 {drug, drag}（学习过），输出为簇式、组内同长度、不接龙', () {
      // 近似用户看到的 drum/drug/drag/rag/rage/age 场景——在收紧规则（同长度 + 一字之差）下：
      // rag(3) 与 drag(4) 长度不同 → 排除；rage(4) 与 drug/drag 距离 2/3 → 排除；
      // age(3) 非锚点且与锚点距离远 → 排除；drum(4) 与 drug(4) 距离 1 → 归属 drug 簇。
      // 输出 = 锚点 drag/drug 各自成簇（互为相近词但都学习过，互不并入）。
      const anchors = {
        (id: 'drug', spell: 'drug'),
        (id: 'drag', spell: 'drag'),
      };
      const words = [
        (id: 'drug', spell: 'drug'),
        (id: 'drag', spell: 'drag'),
        (id: 'drum', spell: 'drum'),
        (id: 'rag', spell: 'rag'),
        (id: 'rage', spell: 'rage'),
        (id: 'age', spell: 'age'),
      ];
      final params = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
        anchorIds: [for (final a in anchors) a.id],
        anchorSpells: [for (final a in anchors) a.spell],
      );
      expect(confusableSortInIsolate(params), ['drag', 'drug', 'drum']);
    });
  });
}
