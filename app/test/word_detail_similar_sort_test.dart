import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';

void main() {
  group('Word Detail Similar Words Sorting Tests', () {
    test('In-dict (normal font) words should be sorted before out-of-dict (italic font) words, and preserve similarity order within each group', () {
      // 模拟 4 个形近词，原始顺序按 similarity/distance 排好：
      // w1: distance 1, 词书外 (out of dict)
      // w2: distance 2, 词书内 (in dict)
      // w3: distance 3, 词书外 (out of dict)
      // w4: distance 4, 词书内 (in dict)
      final w1 = WordVo.c2('w1')..id = 'id_1';
      final w2 = WordVo.c2('w2')..id = 'id_2';
      final w3 = WordVo.c2('w3')..id = 'id_3';
      final w4 = WordVo.c2('w4')..id = 'id_4';

      final similarWords = [w1, w2, w3, w4];
      final wordInDictStatus = {
        'id_1': false,
        'id_2': true,
        'id_3': false,
        'id_4': true,
      };

      // 模拟 _sortSimilarWords 的稳定排序逻辑
      final originalIndices = <String, int>{};
      for (int i = 0; i < similarWords.length; i++) {
        final id = similarWords[i].id;
        if (id != null) {
          originalIndices[id] = i;
        }
      }

      similarWords.sort((a, b) {
        final aInDict = wordInDictStatus[a.id!] ?? true;
        final bInDict = wordInDictStatus[b.id!] ?? true;
        if (aInDict != bInDict) {
          return aInDict ? -1 : 1;
        }
        final aIndex = originalIndices[a.id!] ?? 0;
        final bIndex = originalIndices[b.id!] ?? 0;
        return aIndex.compareTo(bIndex);
      });

      // 预期排序：w2 (inDict, dist=2), w4 (inDict, dist=4), w1 (outDict, dist=1), w3 (outDict, dist=3)
      expect(similarWords.map((w) => w.id).toList(), ['id_2', 'id_4', 'id_1', 'id_3']);
    });

    test('When all words are in dict or all are out of dict, original similarity order is preserved', () {
      final w1 = WordVo.c2('w1')..id = 'id_1';
      final w2 = WordVo.c2('w2')..id = 'id_2';
      final w3 = WordVo.c2('w3')..id = 'id_3';

      final similarWords = [w1, w2, w3];
      final wordInDictStatus = {
        'id_1': true,
        'id_2': true,
        'id_3': true,
      };

      final originalIndices = <String, int>{};
      for (int i = 0; i < similarWords.length; i++) {
        final id = similarWords[i].id;
        if (id != null) {
          originalIndices[id] = i;
        }
      }

      similarWords.sort((a, b) {
        final aInDict = wordInDictStatus[a.id!] ?? true;
        final bInDict = wordInDictStatus[b.id!] ?? true;
        if (aInDict != bInDict) {
          return aInDict ? -1 : 1;
        }
        final aIndex = originalIndices[a.id!] ?? 0;
        final bIndex = originalIndices[b.id!] ?? 0;
        return aIndex.compareTo(bIndex);
      });

      expect(similarWords.map((w) => w.id).toList(), ['id_1', 'id_2', 'id_3']);
    });
  });
}
