import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:nnbdc/util/confusable_sort.dart';
import 'package:nnbdc/util/edit_distance.dart';

// ===== 朴素 O(n²) 全量贪心：无剪枝的对照基准（规则与 confusableSort 完全一致）=====

int _bySpellThenId(ConfusableWord a, ConfusableWord b) {
  final bySpell = a.spell.compareTo(b.spell);
  return bySpell != 0 ? bySpell : a.id.compareTo(b.id);
}

/// 候选 w（距离 d）是否优于当前最优 best（距离 bestDist）：
/// 距离更小，或距离相同取 (spell, id) 字典序更小
bool _isBetter(ConfusableWord w, int d, ConfusableWord? best, int bestDist) {
  if (best == null || d < bestDist) return true;
  if (d > bestDist) return false;
  final bySpell = w.spell.compareTo(best.spell);
  return bySpell != 0 ? bySpell < 0 : w.id.compareTo(best.id) < 0;
}

/// 朴素全量贪心：从字典序最小的词出发，每一步全量扫描未访问集选最近邻
List<String> naiveConfusableSort(List<ConfusableWord> words) {
  if (words.length <= 1) {
    return [for (final w in words) w.id];
  }
  final sorted = [...words]..sort(_bySpellThenId);
  final unvisited = <ConfusableWord>{...sorted};
  var cur = sorted.first;
  final order = <String>[cur.id];
  unvisited.remove(cur);
  while (unvisited.isNotEmpty) {
    ConfusableWord? best;
    var bestDist = 0;
    for (final w in unvisited) {
      final d = EditDistance.forStrings(cur.spell, w.spell);
      if (_isBetter(w, d, best, bestDist)) {
        best = w;
        bestDist = d;
      }
    }
    order.add(best!.id);
    cur = best;
    unvisited.remove(best);
  }
  return order;
}

// ===== 朴素 A×B 两两全量过滤：无剪枝的对照基准（规则与 selectConfusableNear 完全一致）=====

/// 朴素实现：候选属于锚点，或与任一锚点编辑距离 <= maxDist，即入选
Set<String> naiveSelectConfusableNear(
  Set<ConfusableWord> anchors,
  List<ConfusableWord> candidates, {
  int maxDist = 2,
}) {
  if (anchors.isEmpty) return {};
  return {
    for (final b in candidates)
      if (anchors.contains(b) ||
          anchors.any((a) => EditDistance.forStrings(b.spell, a.spell) <= maxDist))
        b.id,
  };
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
  // 去重按 wordId，spell 允许重复：补一个同 spell 不同 id 的词
  if (n >= 3) {
    words.add((id: 'dup', spell: words[rng.nextInt(n)].spell));
  }
  return words;
}

void main() {
  group('confusableSort 边界', () {
    test('空列表 → 空', () {
      expect(confusableSort([]), isEmpty);
      expect(naiveConfusableSort([]), isEmpty);
    });

    test('单元素 → 原样', () {
      const words = [(id: 'w1', spell: 'hello')];
      expect(confusableSort(words), ['w1']);
    });

    test('两个词：从字典序小的词出发', () {
      // 'cart' < 'cat'（第 3 位 r < t），起始词是 cart
      const words = [
        (id: 'b', spell: 'cat'),
        (id: 'a', spell: 'cart'),
      ];
      expect(confusableSort(words), ['a', 'b']);
      expect(confusableSort(words), naiveConfusableSort(words));
    });

    test('全等长词', () {
      const words = [
        (id: 'w1', spell: 'abc'),
        (id: 'w2', spell: 'bcd'),
        (id: 'w3', spell: 'cde'),
        (id: 'w4', spell: 'xyz'),
      ];
      // abc -> bcd(2) -> cde(2) -> xyz(3)
      expect(confusableSort(words), ['w1', 'w2', 'w3', 'w4']);
      expect(confusableSort(words), naiveConfusableSort(words));
    });

    test('混合长度词', () {
      const words = [
        (id: 'w1', spell: 'a'),
        (id: 'w2', spell: 'abcd'),
        (id: 'w3', spell: 'abcdefghi'),
      ];
      // a -> abcd(3，桶内) -> abcdefghi(回退全量)
      expect(confusableSort(words), ['w1', 'w2', 'w3']);
      expect(confusableSort(words), naiveConfusableSort(words));
    });
  });

  group('相似词聚簇', () {
    test('拼写相近组在结果中成簇相邻，且整体是原词集排列', () {
      const words = [
        // 相似组 A：cat 家族
        (id: 'cart', spell: 'cart'),
        (id: 'cat', spell: 'cat'),
        (id: 'cot', spell: 'cot'),
        (id: 'cut', spell: 'cut'),
        // 相似组 B
        (id: 'their', spell: 'their'),
        (id: 'there', spell: 'there'),
        // 相似组 C
        (id: 'whether', spell: 'whether'),
        (id: 'weather', spell: 'weather'),
        // 无关词（拼写距离远）
        (id: 'window', spell: 'window'),
        (id: 'umbrella', spell: 'umbrella'),
        (id: 'xylophone', spell: 'xylophone'),
        (id: 'zebra', spell: 'zebra'),
      ];

      final order = confusableSort(words);
      expectPermutation(order, words);

      // 每组在结果中成簇相邻
      expectContiguous(order, {'cart', 'cat', 'cot', 'cut'});
      expectContiguous(order, {'their', 'there'});
      expectContiguous(order, {'weather', 'whether'});

      // 与朴素全量贪心一致
      expect(order, naiveConfusableSort(words));
    });
  });

  group('平局按字典序', () {
    test('距离相同取 spell 字典序更小', () {
      // cur='cat' 时 'cot' 与 'cut' 距离均为 1，取 'cot'（c-o < c-u）
      const words = [
        (id: 'cat', spell: 'cat'),
        (id: 'cut', spell: 'cut'),
        (id: 'cot', spell: 'cot'),
      ];
      expect(confusableSort(words), ['cat', 'cot', 'cut']);
      expect(confusableSort(words), naiveConfusableSort(words));
    });
  });

  group('剪枝回退与朴素全量贪心严格一致', () {
    test('桶内最优距离 > DELTA 时回退全量扫描，选中桶外更近词', () {
      // cur='aaaa'(4)，桶（长度 1..7）内仅剩 'bbbbb'(5)，距离 5 > DELTA=3；
      // 桶外词 'aaaabbbb'(8)（长度差 4 > DELTA）距离反而为 4，更近。
      // 若实现错误地"桶内最优 > DELTA 仍直接取桶内"，会得到 [aaaa, bbbbb, aaaabbbb]，
      // 与朴素全量贪心不一致。
      const words = [
        (id: 's', spell: 'aaaa'),
        (id: 'b', spell: 'bbbbb'),
        (id: 'y', spell: 'aaaabbbb'),
      ];
      final order = confusableSort(words);
      expect(order, ['s', 'y', 'b']);
      expect(order, naiveConfusableSort(words));
    });

    test('桶内候选为空时回退全量扫描', () {
      // cur='bb'(2) 时长度 1..5 桶内已无未访问词，只剩桶外 'cccccc'(6)，必须回退全量
      const words = [
        (id: 'a', spell: 'aa'),
        (id: 'b', spell: 'bb'),
        (id: 'c', spell: 'cccccc'),
      ];
      expect(confusableSort(words), ['a', 'b', 'c']);
      expect(confusableSort(words), naiveConfusableSort(words));
    });

    test('随机词集与朴素全量贪心一致（含全等长 / 混合长度 / 同 spell 词）', () {
      // 构造词集：全等长、少量长度聚簇 + 远距 outlier、混合长度
      final constructed = <List<ConfusableWord>>[
        // 全部等长（剪枝桶集中在单一长度）
        [
          for (var i = 0; i < 20; i++)
            (id: 'e$i', spell: 'aaaaa${i.toRadixString(36).padLeft(2, '0')}'),
        ],
        // 长度聚簇在 4..6，加远距 outlier（长度 1 与 12）
        [
          for (var i = 0; i < 15; i++)
            (id: 'c$i', spell: 'abcde${i.toRadixString(36)}'),
          (id: 'o1', spell: 'x'),
          (id: 'o2', spell: 'zzzzzzzzzzzz'),
        ],
        // 混合长度（1..12 随机）
        randomWords(Random(7), 30),
        // 同 spell 不同 id
        [
          (id: 'd1', spell: 'apple'),
          (id: 'd2', spell: 'apple'),
          (id: 'd3', spell: 'pineapple'),
        ],
      ];

      for (final words in constructed) {
        expect(confusableSort(words), naiveConfusableSort(words),
            reason: '剪枝结果必须与朴素全量贪心一致: $words');
      }

      // 多组随机词集（n <= 40）
      for (var seed = 0; seed < 50; seed++) {
        final rng = Random(seed);
        final n = rng.nextInt(41);
        final words = randomWords(rng, n);
        expect(confusableSort(words), naiveConfusableSort(words),
            reason: 'seed=$seed, n=$n 时剪枝结果必须与朴素全量贪心一致');
      }
    });
  });

  group('isolate 入口', () {
    test('confusableSortInIsolate 与 confusableSort 结果一致', () {
      const words = [
        (id: 'cart', spell: 'cart'),
        (id: 'cat', spell: 'cat'),
        (id: 'cot', spell: 'cot'),
        (id: 'cut', spell: 'cut'),
        (id: 'there', spell: 'there'),
        (id: 'their', spell: 'their'),
        (id: 'window', spell: 'window'),
      ];
      final params = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
      );
      expect(confusableSortInIsolate(params), confusableSort(words));
      expect(confusableSortInIsolate(params), naiveConfusableSort(words));

      // 空输入
      expect(confusableSortInIsolate(ConfusableSortParams([], [])), isEmpty);
    });
  });

  group('selectConfusableNear 锚点过滤', () {
    test('锚点一定出现在结果集', () {
      const anchors = {
        (id: 'a1', spell: 'house'),
        (id: 'a2', spell: 'cat'),
      };
      const candidates = [
        (id: 'a1', spell: 'house'),
        (id: 'a2', spell: 'cat'),
        (id: 'b1', spell: 'dog'), // 与锚点距离远，不影响锚点保留
      ];
      final result = selectConfusableNear(anchors, candidates);
      expect(result, containsAll(['a1', 'a2']));
    });

    test('与锚点编辑距离 <= 2 的相近词加入', () {
      // 先验证构造词对的距离：house/horse=1、weather/whether=2
      expect(EditDistance.forStrings('house', 'horse'), 1);
      expect(EditDistance.forStrings('weather', 'whether'), 2);

      const anchors = {
        (id: 'a1', spell: 'house'),
        (id: 'a2', spell: 'weather'),
      };
      const candidates = [
        (id: 'b1', spell: 'horse'), // 与 house 距离 1
        (id: 'b2', spell: 'whether'), // 与 weather 距离 2
        (id: 'b3', spell: 'dog'), // 无关 → 排除
      ];
      expect(selectConfusableNear(anchors, candidates), {'b1', 'b2'});
    });

    test('阈值边界：maxDist=2 时 dist=2 加入、dist=3 排除', () {
      // 先用 EditDistance 验证构造词对的距离
      expect(EditDistance.forStrings('cat', 'cut'), 1);
      expect(EditDistance.forStrings('cat', 'cart'), 1);
      expect(EditDistance.forStrings('whether', 'weather'), 2);
      expect(EditDistance.forStrings('cat', 'cattle'), 3);

      // dist=2（边界内）：whether 与锚点 weather 距离恰为 2 → 加入
      const anchors2 = {(id: 'a', spell: 'weather')};
      const candidates2 = [(id: 'b', spell: 'whether')];
      expect(selectConfusableNear(anchors2, candidates2, maxDist: 2), {'b'});

      // dist=3（边界外）：cat 与锚点 cattle 距离恰为 3 → 排除
      const anchors3 = {(id: 'a', spell: 'cattle')};
      const candidates3 = [(id: 'b', spell: 'cat')];
      expect(selectConfusableNear(anchors3, candidates3, maxDist: 2), isEmpty);
    });

    test('空锚点返回空集；空候选返回空集', () {
      expect(selectConfusableNear({}, const [(id: 'b', spell: 'cat')]), isEmpty);
      expect(
        selectConfusableNear(const {(id: 'a', spell: 'cat')}, const []),
        isEmpty,
      );
    });

    test('长度分桶剪枝与朴素两两全量严格一致', () {
      // 手工构造：混合长度 + 锚点自身 + 同 spell 不同 id
      const anchors = {
        (id: 'a1', spell: 'cat'),
        (id: 'a2', spell: 'cattle'),
        (id: 'a3', spell: 'x'),
        (id: 'a4', spell: 'apple'),
      };
      const candidates = [
        (id: 'a1', spell: 'cat'), // 锚点自身
        (id: 'b1', spell: 'cut'), // 与 cat 距离 1
        (id: 'b2', spell: 'cart'), // 与 cat 距离 1
        (id: 'b3', spell: 'apple'), // 与 a4 同 spell（不同 id，距离 0）
        (id: 'b4', spell: 'cattle'), // 与 a2 同 spell（不同 id，距离 0）
        (id: 'b5', spell: 'zzzz'), // 与任何锚点距离远
        (id: 'b6', spell: 'xx'), // 与 a3 距离 1
      ];
      for (final maxDist in [0, 1, 2, 3]) {
        expect(
          selectConfusableNear(anchors, candidates, maxDist: maxDist),
          naiveSelectConfusableNear(anchors, candidates, maxDist: maxDist),
          reason: '手工构造 maxDist=$maxDist',
        );
      }

      // 随机对照（n <= 60，锚点随机子集，长度混合）
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
    });
  });

  group('isolate 入口（锚点过滤 + 排序）', () {
    test('带锚点：confusableSortInIsolate 与 selectConfusableNear + confusableSort 一致', () {
      const anchors = {
        (id: 'a1', spell: 'house'),
        (id: 'a2', spell: 'weather'),
      };
      const words = [
        (id: 'a1', spell: 'house'),
        (id: 'b1', spell: 'horse'),
        (id: 'a2', spell: 'weather'),
        (id: 'b2', spell: 'whether'),
        (id: 'c1', spell: 'dog'), // 无关词：过滤后被排除
      ];
      final params = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
        anchorIds: [for (final a in anchors) a.id],
        anchorSpells: [for (final a in anchors) a.spell],
      );
      final selected = selectConfusableNear(anchors, words);
      final filtered = [for (final w in words) if (selected.contains(w.id)) w];
      expect(confusableSortInIsolate(params), confusableSort(filtered));
      expect(confusableSortInIsolate(params), isNot(contains('c1')));
    });

    test('无锚点（anchorIds 空）：与既有 confusableSort 结果一致（向后兼容）', () {
      const words = [
        (id: 'cart', spell: 'cart'),
        (id: 'cat', spell: 'cat'),
        (id: 'cot', spell: 'cot'),
        (id: 'cut', spell: 'cut'),
        (id: 'window', spell: 'window'),
      ];
      // 不传锚点参数（默认空）与显式传空锚点等价
      final params = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
      );
      expect(confusableSortInIsolate(params), confusableSort(words));

      final paramsEmptyAnchors = ConfusableSortParams(
        [for (final w in words) w.id],
        [for (final w in words) w.spell],
        anchorIds: const [],
        anchorSpells: const [],
      );
      expect(confusableSortInIsolate(paramsEmptyAnchors), confusableSort(words));
    });
  });
}
