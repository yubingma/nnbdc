import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/sort_alg.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/router.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/word_util.dart';

/// 易混淆单词：以用户学习过的词（学习记录 ∪ 已掌握）为锚点，聚合学习词书内
/// 锚点及与锚点拼写相近（编辑距离 ≤ 1 且长度相同且 ≥ 3 字母）的单词，按簇式排序
/// （锚点成簇、组内同长度、组间不接龙）的动态虚拟词表。纯浏览视图：不落库、
/// 不产生 DbLog、不触发同步。
class ConfusableWordsProvider with WordsProvider {
  /// 注意：不要缓存 `MyDatabase.instance`。
  /// 数据库在 `wipeAllTables()` / `closeDatabase()` 后会重建实例，
  /// 若缓存旧实例会导致 "Can't re-open a database after closing it"。
  MyDatabase get _db => MyDatabase.instance;

  /// 固定原始序：返回 semantic 会触发控制器 TSP 排序分支，必须避免。
  /// 排序由 provider 内部的簇式排序决定，与排序设置无关。
  @override
  Future<WordSortAlg> getSortAlg() async => WordSortAlg.original;

  /// 虚拟词表不支持自定义排序（用于隐藏"排序设置"菜单）
  @override
  bool get canCustomizeSort => false;

  /// 与最近一次 getAPageOfWords 返回行对应的组号表（0 = 默认底色；>0 按锚点簇交替着色）
  List<int> _groupIds = [];

  /// 分组展示：簇式排序中每个锚点簇为一组（组号从 1 递增），供卡片底色区分边界
  @override
  int groupIndexOf(int index) {
    if (index < 0 || index >= _groupIds.length) return 0;
    return _groupIds[index];
  }

  /// 非词书数据源，无单元概念
  @override
  Future<bool> get hasUnits async => false;

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final sw = Stopwatch()..start();
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        return PagedResults<WordWrapper>(0);
      }

      // 1. 全量排序 id：内存缓存命中即快，首次进入的 isolate 排序耗时由页面 loading 态覆盖；
      //    锚点集合用于分组着色（每个锚点簇 = 一组）
      final sortedIds = await WordBo().getConfusableWordIds(userId);
      final anchorIds = await WordBo().getConfusableAnchorIds(userId);

      // 2. 一次性批量查详情（words 批量 + 批量释义），避免逐词循环；
      //    释义缺失的异常词由容错加载跳过，保证单条数据异常不清空整页
      final words = await (_db.select(_db.words)..where((w) => w.id.isIn(sortedIds))).get();
      final wordMap = {for (final w in words) w.id: w};
      final meaningsMap = await _loadMeaningsTolerantly(sortedIds, userId);

      // 3. 按排序后的 id 顺序组装 WordWrapper（详情/释义缺失的异常词跳过）；
      //    同步构建组号表：遇锚点组号 +1，成员沿用当前组号（异常词跳过时组号也跳过）
      final results = PagedResults<WordWrapper>(0);
      final groupIds = <int>[];
      var group = 0;
      for (final id in sortedIds) {
        if (anchorIds.contains(id)) group++;
        final wordEntry = wordMap[id];
        final mItems = meaningsMap[id];
        if (wordEntry == null || mItems == null) {
          Global.logger.w('跳过易混淆单词（详情或释义缺失）: wordId=$id');
          continue;
        }
        final wordVo = WordVo.c2(wordEntry.spell)
          ..id = wordEntry.id
          ..americaPronounce = wordEntry.americaPronounce
          ..britishPronounce = wordEntry.britishPronounce
          ..popularity = wordEntry.popularity
          ..pronounce = wordEntry.pronounce
          ..shortDesc = wordEntry.shortDesc
          ..longDesc = wordEntry.longDesc
          ..groupInfo = wordEntry.groupInfo;
        wordVo.meaningItems = mItems
            .map((mi) => MeaningItemVo.from(mi.ciXing, mi.meaning)..id = mi.id)
            .toList();
        results.rows.add(WordWrapper(wordVo, wordVo));
        groupIds.add(group);
      }
      // 实际可展示的单词数（异常词被跳过）作为总数
      results.total = results.rows.length;

      // 4. 控制器对非 DictWordsProvider 走 getAPageOfWords(0, 999999) 全量 + 内存切片路径，
      //    此处按签名切片，保持接口语义（组号表同步切片）
      if (fromIndex > 0 || pageSize < results.rows.length) {
        final end = (fromIndex + pageSize) > results.rows.length
            ? results.rows.length
            : (fromIndex + pageSize);
        final sliced = fromIndex >= results.rows.length
            ? <WordWrapper>[]
            : results.rows.sublist(fromIndex, end);
        results.rows
          ..clear()
          ..addAll(sliced);
        final slicedGroups = fromIndex >= groupIds.length
            ? <int>[]
            : groupIds.sublist(fromIndex, fromIndex + sliced.length);
        groupIds
          ..clear()
          ..addAll(slicedGroups);
      }
      _groupIds = groupIds;

      Global.logger.d('ConfusableWordsProvider: getAPageOfWords(from=$fromIndex) completed in ${sw.elapsedMilliseconds}ms');
      return results;
    } catch (e) {
      Global.logger.e("获取易混淆单词失败: $e");
      return PagedResults<WordWrapper>(0);
    }
  }

  /// 批量释义容错加载：正常路径单次批量查询；个别词释义缺失（数据异常）导致批量抛异常时，
  /// 回退为逐词加载并跳过异常词（map 中缺失即跳过），保证单条数据异常不清空整页。
  Future<Map<String, List<MeaningItem>>> _loadMeaningsTolerantly(
      List<String> sortedIds, String userId) async {
    try {
      return await WordBo().getConfusableMeaningsInBatch(sortedIds.toSet(), userId);
    } catch (e) {
      Global.logger.e('易混淆单词批量释义失败，回退逐词容错: $e');
      final map = <String, List<MeaningItem>>{};
      for (final id in sortedIds) {
        try {
          final single = await WordBo().getConfusableMeaningsInBatch({id}, userId);
          final items = single[id];
          if (items != null) map[id] = items;
        } catch (e) {
          // 异常词不在 map 中，由组装循环记录并跳过
        }
      }
      return map;
    }
  }

  @override
  Future<int> getWordIndex(String spell) async {
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return -1;
    final sortedIds = await WordBo().getConfusableWordIds(userId);
    final words = await (_db.select(_db.words)
          ..where((w) => w.spell.equals(spell))
          ..limit(1))
        .get();
    if (words.isEmpty) return -1;
    // sortedIds 为排序后的全量 id 列表，直接按 id 定位（0 基）
    return sortedIds.indexOf(words.first.id);
  }

  /// 只读浏览：不允许删除
  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async => false;

  /// 仅浏览：不进入学习轨道。"掌握"按钮点击后提示并返回 false，
  /// 控制器视为未成功，不做移除列表/更新学习状态等任何变更。
  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
    ToastUtil.info('仅浏览：易混淆单词词表不提供掌握操作');
    return false;
  }

  /// 仅浏览："已掌握"单词的取消掌握同样提示并返回 false，
  /// 不写 masteredWords 表、不产生 DbLog、不触发同步。
  @override
  Future<bool> unmasterWord(WordWrapper wordWrapper) async {
    ToastUtil.info('仅浏览：易混淆单词词表不提供掌握操作');
    return false;
  }
}

class ConfusableWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 0.0;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 100.0;
  }
}

/// 内存 no-op 书签：不写 bookMarks 表、不产生 DbLog、不触发同步。
/// 会话内书签定位由页面内存态维持，不跨会话恢复（与纯浏览视图一致）。
class ConfusableWordsBookMarkProvider implements BookMarkProvider {
  @override
  Future<BookMarkVo?> getBookMark() async => null;

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async => true;
}

Future<dynamic>? toConfusableWordsListPage() {
  return goRouter.push('/word_list',
      extra: WordListPageArgs(
          '易混淆单词', ConfusableWordsProvider(), true, false, false, '', ConfusableWordsProgressProvider(), ConfusableWordsBookMarkProvider(), null));
}
