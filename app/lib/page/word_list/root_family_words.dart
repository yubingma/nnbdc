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

/// 同根词词表：聚合用户**学习词书范围**内共享同一词根/词缀（cigen）的单词，
/// 按词根分族展示（每族 ≥2 个词，一词多根只归属优先级最高的词根）。
/// 词表内每组由「组头（词根 + 分类 + 含义 + 词数）」与族内单词共用同一组号，
/// 复用词表页既有的分组卡片渲染。纯浏览视图：不落库、不产生 DbLog、不触发同步。
class RootFamilyWordsProvider with WordsProvider {
  /// 注意：不要缓存 `MyDatabase.instance`。
  /// 数据库在 `wipeAllTables()` / `closeDatabase()` 后会重建实例，
  /// 若缓存旧实例会导致 "Can't re-open a database after closing it"。
  MyDatabase get _db => MyDatabase.instance;

  /// 组头虚拟行的 id 前缀（与 [RootFamilyGroup.groupIdPrefix] 一致）
  static const String groupIdPrefix = RootFamilyGroup.groupIdPrefix;

  /// 固定原始序：分组顺序由词根分族决定，与排序设置无关
  @override
  Future<WordSortAlg> getSortAlg() async => WordSortAlg.original;

  /// 虚拟词表不支持自定义排序（用于隐藏"排序设置"菜单）
  @override
  bool get canCustomizeSort => false;

  /// 全量有效行对应的全局组号表（按全局绝对索引）
  List<int> _allGroupIds = [];

  /// 行 id 到组号的映射：防切片与局部视口滑动偏移
  final Map<String, int> _rowGroupMap = {};

  /// 该行是否为词根组头（词根不是单词，组头行不可点、不进详情页）
  bool isGroupHeader(WordWrapper? word) =>
      word?.word.id?.startsWith(groupIdPrefix) ?? false;

  /// 分组展示：优先按行实体获取组号（无视切片与局部视口滑动）
  @override
  int groupOfWord(WordWrapper? word, [int globalIndex = 0]) {
    final id = word?.word.id;
    if (id != null && _rowGroupMap.containsKey(id)) {
      return _rowGroupMap[id]!;
    }
    return groupIndexOf(globalIndex);
  }

  /// 分组展示：按全局绝对索引获取组号（供边界前后词探测）
  @override
  int groupIndexOf(int index) {
    if (index < 0 || index >= _allGroupIds.length) return 0;
    return _allGroupIds[index];
  }

  /// 非词书数据源，无单元概念
  @override
  Future<bool> get hasUnits async => false;

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        return PagedResults<WordWrapper>(0);
      }

      final wordBo = WordBo();
      final groups = await wordBo.getRootFamilyGroups(userId);
      if (groups.isEmpty) {
        _allGroupIds = const [];
        _rowGroupMap.clear();
        return PagedResults<WordWrapper>(0);
      }

      // 一次性批量查详情（单词批量 + 批量释义），避免逐词循环；
      // 释义缺失的异常词由容错加载跳过，保证单条数据异常不清空整页
      final allWordIds = [for (final g in groups) ...g.wordIds];
      final idSet = allWordIds.toSet();
      final words = await (_db.select(_db.words)..where((w) => w.id.isIn(idSet))).get();
      final wordMap = {for (final w in words) w.id: w};
      final meaningsMap = await _loadMeaningsTolerantly(idSet, userId);

      final rows = <WordWrapper>[];
      final rowGroupIds = <int>[];
      _rowGroupMap.clear();
      var group = 0;
      for (final g in groups) {
        // 族内单词（详情/释义缺失的异常词跳过）
        final memberRows = <WordWrapper>[];
        for (final id in g.wordIds) {
          final entry = wordMap[id];
          final mItems = meaningsMap[id];
          if (entry == null || mItems == null) {
            Global.logger.w('跳过同根词（详情或释义缺失）: wordId=$id');
            continue;
          }
          memberRows.add(WordWrapper(_buildWordVo(entry, mItems), entry));
        }
        // 有效成员不足 2 个的族整体跳过：组头不单独出现，也不占组号
        if (memberRows.length < 2) continue;
        group++;
        rows.add(WordWrapper(
          WordVo.c2(g.spell)
            ..id = g.groupId
            ..shortDesc = g.meaning
            ..meaningStr = '${memberRows.length} 词',
          CigenVo(g.cigenId, g.spell,
              spell: g.spell, category: g.category, meaningCn: g.meaning),
        ));
        rowGroupIds.add(group);
        rows.addAll(memberRows);
        rowGroupIds.addAll(List.filled(memberRows.length, group));
      }

      final results = PagedResults<WordWrapper>(0)
        ..rows.addAll(rows)
        ..total = rows.length;
      _allGroupIds = List.unmodifiable(rowGroupIds);
      for (var i = 0; i < rows.length; i++) {
        final id = rows[i].word.id;
        if (id != null) _rowGroupMap[id] = rowGroupIds[i];
      }

      // 控制器对非 DictWordsProvider 走 getAPageOfWords(0, 999999) 全量 + 内存切片路径；
      // 此处若请求局部切片，仅对 rows 做返回切片，不破坏全量全局组号字典与组号表
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
      }
      return results;
    } catch (e) {
      Global.logger.e('获取同根词失败: $e');
      return PagedResults<WordWrapper>(0);
    }
  }

  /// 由 words 行与释义组装 WordVo（与形近词词表同口径）
  WordVo _buildWordVo(Word entry, List<MeaningItem> mItems) {
    final wordVo = WordVo.c2(entry.spell)
      ..id = entry.id
      ..americaPronounce = entry.americaPronounce
      ..britishPronounce = entry.britishPronounce
      ..popularity = entry.popularity
      ..pronounce = entry.pronounce
      ..shortDesc = entry.shortDesc
      ..longDesc = entry.longDesc
      ..groupInfo = entry.groupInfo;
    wordVo.meaningItems =
        mItems.map((mi) => MeaningItemVo.from(mi.ciXing, mi.meaning)..id = mi.id).toList();
    return wordVo;
  }

  /// 批量释义容错加载：正常路径单次批量查询；个别词释义缺失（数据异常）导致批量抛异常时，
  /// 回退为逐词加载并跳过异常词（map 中缺失即跳过），保证单条数据异常不清空整页。
  Future<Map<String, List<MeaningItem>>> _loadMeaningsTolerantly(
      Set<String> wordIds, String userId) async {
    try {
      return await WordBo().getConfusableMeaningsInBatch(wordIds, userId);
    } catch (e) {
      Global.logger.e('同根词批量释义失败，回退逐词容错: $e');
      final map = <String, List<MeaningItem>>{};
      for (final id in wordIds) {
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
    final wordBo = WordBo();
    final groups = await wordBo.getRootFamilyGroups(userId);
    final spellOf = await wordBo.getRootFamilySpellMap(userId);
    var index = 0;
    for (final g in groups) {
      index++; // 组头行
      for (final id in g.wordIds) {
        if ((spellOf[id] ?? id) == spell) return index;
        index++;
      }
    }
    return -1;
  }

  /// 只读浏览：不允许删除
  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async => false;

  /// 仅浏览：不进入学习轨道。"掌握"按钮点击后提示并返回 false，
  /// 控制器视为未成功，不做移除列表/更新学习状态等任何变更。
  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
    ToastUtil.info('仅浏览：同根词词表不提供掌握操作');
    return false;
  }

  /// 仅浏览："已掌握"单词的取消掌握同样提示并返回 false，
  /// 不写 masteredWords 表、不产生 DbLog、不触发同步。
  @override
  Future<bool> unmasterWord(WordWrapper wordWrapper) async {
    ToastUtil.info('仅浏览：同根词词表不提供掌握操作');
    return false;
  }
}

class RootFamilyWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 0.0;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 100.0;
  }
}

/// 同根词书签：只保存在内存中（不写 book_marks 表、不产生 DbLog、不触发同步），
/// 会话内返回词表可恢复到上次位置，退出后不保留——与"纯浏览虚拟词表"语义一致。
class RootFamilyWordsBookMarkProvider implements BookMarkProvider {
  BookMarkVo? _bookMark;

  @override
  Future<BookMarkVo?> getBookMark() async => _bookMark;

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async {
    _bookMark = bookMark;
    return true;
  }
}

Future<dynamic>? toRootFamilyWordsListPage() {
  return goRouter.push('/word_list',
      extra: WordListPageArgs(
          '同根词',
          RootFamilyWordsProvider(),
          true,
          false,
          false,
          '',
          RootFamilyWordsProgressProvider(),
          RootFamilyWordsBookMarkProvider(),
          null));
}
