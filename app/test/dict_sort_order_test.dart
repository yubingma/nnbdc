import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/select_book.dart';

void main() {
  group('SelectBookPage dict sorting and year parsing tests', () {
    test('SelectBookPage extracts year correctly and sorts newest first by default', () {
      final state = SelectBookPageState();

      final books = [
        DictVo.c2('1')..name = '2025考研英语词汇红宝书'..shortName = '2025考研英语词汇红宝书',
        DictVo.c2('2')..name = '2026考研英语词汇红宝书（必考）'..shortName = '2026考研英语词汇红宝书（必考）',
        DictVo.c2('3')..name = '2026考研英语词汇红宝书（基础）'..shortName = '2026考研英语词汇红宝书（基础）',
        DictVo.c2('4')..name = '2027考研英语红宝书乱序'..shortName = '2027考研英语红宝书乱序',
        DictVo.c2('5')..name = '红宝书串记手册'..shortName = '红宝书串记手册',
      ];

      // 默认最新年份优先
      final sortedNewest = List<DictVo>.from(books)
        ..sort((a, b) => state.compareDictsForTest(a, b, DictSortOrder.newestFirst));

      expect(sortedNewest.map((e) => e.name).toList(), [
        '2027考研英语红宝书乱序',
        '2026考研英语词汇红宝书（基础）',
        '2026考研英语词汇红宝书（必考）',
        '2025考研英语词汇红宝书',
        '红宝书串记手册',
      ]);
    });

    test('SelectBookPage sorts oldest first when configured', () {
      final state = SelectBookPageState();

      final books = [
        DictVo.c2('1')..name = '2025考研英语词汇红宝书'..shortName = '2025考研英语词汇红宝书',
        DictVo.c2('2')..name = '2026考研英语词汇红宝书（必考）'..shortName = '2026考研英语词汇红宝书（必考）',
        DictVo.c2('3')..name = '2027考研英语红宝书乱序'..shortName = '2027考研英语红宝书乱序',
        DictVo.c2('4')..name = '红宝书串记手册'..shortName = '红宝书串记手册',
      ];

      final sortedOldest = List<DictVo>.from(books)
        ..sort((a, b) => state.compareDictsForTest(a, b, DictSortOrder.oldestFirst));

      expect(sortedOldest.map((e) => e.name).toList(), [
        '2025考研英语词汇红宝书',
        '2026考研英语词汇红宝书（必考）',
        '2027考研英语红宝书乱序',
        '红宝书串记手册',
      ]);
    });

    test('SelectBookPage sorts by name ascending when configured', () {
      final state = SelectBookPageState();

      final books = [
        DictVo.c2('1')..name = '2027考研英语红宝书乱序'..shortName = '2027考研英语红宝书乱序',
        DictVo.c2('2')..name = '2025考研英语词汇红宝书'..shortName = '2025考研英语词汇红宝书',
        DictVo.c2('3')..name = '2026考研英语词汇红宝书'..shortName = '2026考研英语词汇红宝书',
      ];

      final sortedNameAsc = List<DictVo>.from(books)
        ..sort((a, b) => state.compareDictsForTest(a, b, DictSortOrder.nameAsc));

      expect(sortedNameAsc.map((e) => e.name).toList(), [
        '2025考研英语词汇红宝书',
        '2026考研英语词汇红宝书',
        '2027考研英语红宝书乱序',
      ]);
    });
  });
}
