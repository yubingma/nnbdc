import 'package:nnbdc/global.dart';

/// 计算笛卡尔积
class PermutationAlgorithmStrings {
  final List<List<String>> elements;

  PermutationAlgorithmStrings(this.elements);

  List<List<String>> permutations() {
    List<List<String>> perms = [];
    generatePermutations(elements, perms, 0, []);
    return perms;
  }

  void generatePermutations(List<List<String>> lists, List<List<String>> result, int depth, List<String> current) {
    if (depth == lists.length) {
      result.add(current);
      return;
    }

    for (int i = 0; i < lists[depth].length; i++) {
      generatePermutations(lists, result, depth + 1, [...current, lists[depth][i]]);
    }
  }
}

void main() {
  List<List<String>> data = [
    ["a", "b", "c"],
    ["d", "e", "f"],
    ["g", "h", "i"]
  ];
  PermutationAlgorithm<String> algo = PermutationAlgorithm<String>(data);

  // 修改这一行，转为字符串
  Global.logger.d(algo.permutations().toString());
}

class PermutationAlgorithm<T> {
  final List<List<T>> data;

  PermutationAlgorithm(this.data);

  List<List<T>> permutations() {
    if (data.isEmpty) {
      return [];
    }
    if (data.length == 1) {
      return data[0].map((e) => [e]).toList();
    }
    List<List<T>> result = [];
    List<List<T>> subPermutations = PermutationAlgorithm(data.sublist(1)).permutations();
    for (var item in data[0]) {
      for (var subPerm in subPermutations) {
        result.add([item, ...subPerm]);
      }
    }
    return result;
  }
}
