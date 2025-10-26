import 'package:drift/drift.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/utils.dart';
import 'dart:async';
import '../../services/throttled_sync_service.dart';

class WordBo {
  static final WordBo _instance = WordBo._internal();
  factory WordBo() => _instance;
  WordBo._internal();

  // 只做本地查词（包含大小写与词形多变体）
  Future<SearchWordResult> searchWordLocalOnly(String spell) async {
    final db = MyDatabase.instance;
    final purifiedSpell = Util.purifySpell(spell);
    try {
      final SearchWordResult? localHit = await _searchLocallyWithVariants(purifiedSpell, db);
      return localHit ?? SearchWordResult(null, null, null, null, null);
    } catch (e, st) {
      ErrorHandler.handleDatabaseError(e, st, operation: '本地查词');
      return SearchWordResult(null, null, null, null, null);
    }
  }

  Future<SearchWordResult?> _searchLocallyWithVariants(String purifiedSpell, MyDatabase db) async {
    var result = await _searchLocalOnly(purifiedSpell, db);
    if (result != null) return result;
    if (purifiedSpell.endsWith('s')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 1);
      result = await _searchLocalOnly(base, db);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('es')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 2);
      result = await _searchLocalOnly(base, db);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith("'s")) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 2);
      result = await _searchLocalOnly(base, db);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ies')) {
      var base = "${purifiedSpell.substring(0, purifiedSpell.length - 3)}y";
      result = await _searchLocalOnly(base, db);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ied')) {
      var base = "${purifiedSpell.substring(0, purifiedSpell.length - 3)}y";
      result = await _searchLocalOnly(base, db);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ed')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 2);
      result = await _searchLocalOnly(base, db);
      if (result != null) return result;
      var basePlusE = "${base}e";
      result = await _searchLocalOnly(basePlusE, db);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ing')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 3);
      result = await _searchLocalOnly(base, db);
      if (result != null) return result;
      var basePlusE = "${base}e";
      result = await _searchLocalOnly(basePlusE, db);
      if (result != null) return result;
    }
    return null;
  }

  Future<SearchWordResult?> _searchLocalOnly(String spell, MyDatabase db) async {
    var result = await _tryBuildLocalResultBySpell(spell, db);
    if (result != null) return result;

    var lowerSpell = spell.toLowerCase();
    if (lowerSpell != spell) {
      result = await _tryBuildLocalResultBySpell(lowerSpell, db);
      if (result != null) return result;
    }

    var upperSpell = spell.toUpperCase();
    if (upperSpell != spell) {
      result = await _tryBuildLocalResultBySpell(upperSpell, db);
      if (result != null) return result;
    }

    if (spell.isNotEmpty) {
      var capSpell = spell.substring(0, 1).toUpperCase() + spell.substring(1).toLowerCase();
      if (capSpell != spell && capSpell != lowerSpell) {
        result = await _tryBuildLocalResultBySpell(capSpell, db);
        if (result != null) return result;
      }
    }

    return null;
  }

  Future<SearchWordResult?> _tryBuildLocalResultBySpell(String spell, MyDatabase db) async {
    final wordQuery = db.select(db.words)
      ..where((w) => w.spell.equals(spell));
    final localWord = await wordQuery.getSingleOrNull();

    if (localWord != null) {
      final wordVo = WordVo.c2(localWord.spell)
        ..id = localWord.id
        ..shortDesc = localWord.shortDesc
        ..longDesc = localWord.longDesc
        ..pronounce = localWord.pronounce
        ..americaPronounce = localWord.americaPronounce
        ..britishPronounce = localWord.britishPronounce
        ..popularity = localWord.popularity
        ..groupInfo = localWord.groupInfo;

      List<MeaningItem> meaningItems = [];

      final commonQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.equals(localWord.id) & mi.dictId.equals(Global.commonDictId))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      meaningItems = await commonQuery.get();

      List<String> selectedDictIds = [];
      if (meaningItems.isEmpty) {
        final currentUser = await Global.refreshLoggedInUser();
        if (currentUser != null && currentUser.id != null) {
          final learningDicts = await (db.select(db.learningDicts)
                ..where((tbl) => tbl.userId.equals(currentUser.id!)))
              .get();
          selectedDictIds = learningDicts.map((e) => e.dictId).toList();
          if (selectedDictIds.isNotEmpty) {
            final selectedQuery = db.select(db.meaningItems)
              ..where((mi) => mi.wordId.equals(localWord.id) & mi.dictId.isIn(selectedDictIds))
              ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
            meaningItems = await selectedQuery.get();
          }
        }
      }

      if (meaningItems.isEmpty) {
        final anyQuery = db.select(db.meaningItems)
          ..where((mi) => mi.wordId.equals(localWord.id))
          ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
        meaningItems = await anyQuery.get();
      }

      final meaningItemVos = <MeaningItemVo>[];
      for (final mi in meaningItems) {
        final miVo = MeaningItemVo(
            mi.id,
            mi.ciXing,
            mi.meaning,
            null,
            null,
            null);
        meaningItemVos.add(miVo);
      }
      wordVo.meaningItems = meaningItemVos;

      bool isInMySelectedDicts = false;
      if (selectedDictIds.isEmpty) {
        final currentUser = await Global.refreshLoggedInUser();
        if (currentUser != null && currentUser.id != null) {
          final learningDicts = await (db.select(db.learningDicts)
                ..where((tbl) => tbl.userId.equals(currentUser.id!)))
              .get();
          selectedDictIds = learningDicts.map((e) => e.dictId).toList();
        }
      }
      if (selectedDictIds.isNotEmpty) {
        final selectedMiCount = await (db.selectOnly(db.meaningItems)
              ..addColumns([countAll()])
              ..where(db.meaningItems.wordId.equals(localWord.id))
              ..where(db.meaningItems.dictId.isIn(selectedDictIds)))
            .getSingle();
        isInMySelectedDicts = (selectedMiCount.read(countAll()) ?? 0) > 0;
      }

      bool isInRawWordDict = false;
      final currentUser = await Global.refreshLoggedInUser();
      if (currentUser != null && currentUser.id != null) {
        final rawDict = await db.dictsDao.findUserRawDict(currentUser.id!);
        if (rawDict != null) {
          final dw = await db.dictWordsDao.getById(rawDict.id, localWord.id);
          isInRawWordDict = dw != null;
        }
      }

      final localResult = SearchWordResult(
        wordVo,
        null,
        isInMySelectedDicts,
        isInRawWordDict,
        Util.getWordSoundUrl(localWord.spell),
      );
      return localResult;
    } else {
      return null;
    }
  }

  Future<Result<DictWordVo>> addRawWord(String spell, String addManner) async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      return Result("ERROR", "用户未登录", false);
    }
    final db = MyDatabase.instance;
    final wordQuery = db.select(db.words)..where((w) => w.spell.equals(spell));
    final word = await wordQuery.getSingleOrNull();
    if (word == null) {
      return Result("ERROR", "单词在牛牛词库中不存在", false);
    }
    final rawWordDict = await db.dictsDao.findUserRawDict(user.id);
    if (rawWordDict == null) {
      return Result("ERROR", "用户生词本不存在", false);
    }
    final existingDictWord =
        await db.dictWordsDao.getById(rawWordDict.id, word.id);
    if (existingDictWord != null) {
      return Result("ERROR", "单词已在生词本中", false);
    }
    final now = AppClock.now();
    final dictWord = DictWord(
      dictId: rawWordDict.id,
      wordId: word.id,
      seq: 0,
      createTime: now,
      updateTime: now,
    );
    
    // 使用事务确保数据一致性
    await db.transaction(() async {
      // 1. 添加dictWord
      await db.dictWordsDao.insertEntity(dictWord, true);
      
      // 2. 更新生词本的wordCount（并生成日志用于同步）
      await db.dictsDao.updateWordCount(rawWordDict.id, true);
      
      Global.logger.d('单词已添加到生词本: spell=$spell, wordId=${word.id}');
    });
    
    // 延迟触发同步，确保事务完全提交
    Future.delayed(Duration.zero, () {
      ThrottledDbSyncService().requestSync();
    });
    final dictWordVo = DictWordVo(
      DictVo.c2(""),
      WordVo.c2(word.spell),
      0,
    );
    return Result("SUCCESS", "添加成功", true)..data = dictWordVo;
  }

  Future<PagedResults<LearningWordVo>> getLearningWordsForAPage(
      int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    try {
      final query = db.select(db.learningWords)
        ..where((tbl) =>
            tbl.userId.equals(userId) & tbl.lifeValue.isBiggerThanValue(0))
        ..orderBy([
          (tbl) => OrderingTerm(expression: tbl.addTime),
          (tbl) => OrderingTerm(expression: tbl.lifeValue),
          (tbl) => OrderingTerm(expression: tbl.wordId)
        ])
        ..limit(pageSize, offset: fromIndex);
      final learningWords = await query.get();
      final countQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final lifeValueCondition =
          db.learningWords.lifeValue.isBiggerThanValue(0);
      countQuery.where(userIdCondition & lifeValueCondition);
      final countResult = await countQuery.getSingle();
      final total = countResult.read(countAll()) ?? 0;
      List<LearningWordVo> learningWordVos = [];
      for (final lw in learningWords) {
        final word = await db.wordsDao.getWordById(lw.wordId);
        if (word != null) {
          final userVo = UserVo.c2(userId);
          userVo.level = LevelVo(user.levelId);
          final wordVo = WordVo.c2(word.spell)
            ..id = word.id
            ..shortDesc = word.shortDesc
            ..longDesc = word.longDesc
            ..pronounce = word.pronounce
            ..americaPronounce = word.americaPronounce
            ..britishPronounce = word.britishPronounce
            ..popularity = word.popularity;
          final meaningItemsQuery = db.select(db.meaningItems)
            ..where((tbl) => tbl.wordId.equals(word.id))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.popularity)]);
          final meaningItems = await meaningItemsQuery.get();
          List<MeaningItemVo> meaningItemVos = [];
          for (final mi in meaningItems) {
            meaningItemVos.add(MeaningItemVo(
                mi.id, mi.ciXing, mi.meaning, null, null, null));
          }
          wordVo.meaningItems = meaningItemVos;
          final learningWordVo = LearningWordVo(
              userVo,
              lw.addTime,
              lw.addDay,
              lw.lifeValue,
              lw.lastLearningDate,
              lw.learningOrder,
              lw.learnedTimes,
              wordVo);
          learningWordVos.add(learningWordVo);
        }
      }
      final result = PagedResults<LearningWordVo>(total);
      result.rows = learningWordVos;
      return result;
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '获取学习中单词');
      rethrow;
    }
  }

  Future<PagedResults<LearningWordVo>> getTodayNewWordsForAPage(
      int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    final now = AppClock.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final query = db.select(db.learningWords)
      ..where((tbl) =>
          tbl.userId.equals(userId) &
          tbl.isTodayNewWord.equals(true) &
          tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
          tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.learningOrder)])
      ..limit(pageSize, offset: fromIndex);
    final learningWords = await query.get();
    final countQuery = db.selectOnly(db.learningWords)
      ..addColumns([countAll()])
      ..where(db.learningWords.userId.equals(userId))
      ..where(db.learningWords.isTodayNewWord.equals(true))
      ..where(
          db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay))
      ..where(
          db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay));
    final countResult = await countQuery.getSingle();
    final total = countResult.read(countAll()) ?? 0;
    List<LearningWordVo> learningWordVos = [];
    for (final lw in learningWords) {
      final word = await db.wordsDao.getWordById(lw.wordId);
      if (word != null) {
        final userVo = UserVo.c2(userId);
        userVo.level = LevelVo(user.levelId);
        final wordVo = WordVo.c2(word.spell)
          ..id = word.id
          ..shortDesc = word.shortDesc
          ..longDesc = word.longDesc
          ..pronounce = word.pronounce
          ..americaPronounce = word.americaPronounce
          ..britishPronounce = word.britishPronounce
          ..popularity = word.popularity;
        final learningDictsQuery = db.select(db.learningDicts)
          ..where((tbl) => tbl.userId.equals(userId));
        final learningDicts = await learningDictsQuery.get();
        final selectedDictIds = learningDicts.map((d) => d.dictId).toList();
        final meaningItemQuery = db.select(db.meaningItems)
          ..where((mi) =>
              mi.wordId.equals(word.id) & mi.dictId.isIn(selectedDictIds))
          ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
        final meaningItems = await meaningItemQuery.get();
        if (meaningItems.isEmpty) {
          final wordsWithoutMeaning = [word.id];
          final commonDictQuery = db.select(db.meaningItems)
            ..where((mi) =>
                mi.wordId.isIn(wordsWithoutMeaning) & mi.dictId.equals(Global.commonDictId))
            ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
          final commonMeaningItems = await commonDictQuery.get();
          meaningItems.addAll(commonMeaningItems);
        }
        List<MeaningItemVo> meaningItemVos = [];
        for (final mi in meaningItems) {
          meaningItemVos.add(MeaningItemVo(
              mi.id, mi.ciXing, mi.meaning, null, null, null));
        }
        wordVo.meaningItems = meaningItemVos;
        final learningWordVo = LearningWordVo(
            userVo,
            lw.addTime,
            lw.addDay,
            lw.lifeValue,
            lw.lastLearningDate,
            lw.learningOrder,
            lw.learnedTimes,
            wordVo);
        learningWordVos.add(learningWordVo);
      }
    }
    final result = PagedResults<LearningWordVo>(total);
    result.rows = learningWordVos;
    return result;
  }

  Future<PagedResults<LearningWordVo>> getTodayOldWordsForAPage(
      int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    final now = AppClock.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final query = db.select(db.learningWords)
      ..where((tbl) =>
          tbl.userId.equals(userId) &
          tbl.isTodayNewWord.equals(false) &
          tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
          tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.learningOrder)])
      ..limit(pageSize, offset: fromIndex);
    final learningWords = await query.get();
    final countQuery = db.selectOnly(db.learningWords)
      ..addColumns([countAll()])
      ..where(db.learningWords.userId.equals(userId))
      ..where(db.learningWords.isTodayNewWord.equals(false))
      ..where(
          db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay))
      ..where(
          db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay));
    final countResult = await countQuery.getSingle();
    final total = countResult.read(countAll()) ?? 0;
    List<LearningWordVo> learningWordVos = [];
    for (final lw in learningWords) {
      final word = await db.wordsDao.getWordById(lw.wordId);
      if (word != null) {
        final userVo = UserVo.c2(userId);
        userVo.level = LevelVo(user.levelId);
        final wordVo = WordVo.c2(word.spell)
          ..id = word.id
          ..shortDesc = word.shortDesc
          ..longDesc = word.longDesc
          ..pronounce = word.pronounce
          ..americaPronounce = word.americaPronounce
          ..britishPronounce = word.britishPronounce
          ..popularity = word.popularity;
        final learningDictsQuery = db.select(db.learningDicts)
          ..where((tbl) => tbl.userId.equals(userId));
        final learningDicts = await learningDictsQuery.get();
        final selectedDictIds = learningDicts.map((d) => d.dictId).toList();
        final meaningItemQuery = db.select(db.meaningItems)
          ..where((mi) =>
              mi.wordId.equals(word.id) & mi.dictId.isIn(selectedDictIds))
          ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
        final meaningItems = await meaningItemQuery.get();
        if (meaningItems.isEmpty) {
          final wordsWithoutMeaning = [word.id];
          final commonDictQuery = db.select(db.meaningItems)
            ..where((mi) =>
                mi.wordId.isIn(wordsWithoutMeaning) & mi.dictId.equals(Global.commonDictId))
            ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
          final commonMeaningItems = await commonDictQuery.get();
          meaningItems.addAll(commonMeaningItems);
        }
        List<MeaningItemVo> meaningItemVos = [];
        for (final mi in meaningItems) {
          meaningItemVos.add(MeaningItemVo(
              mi.id, mi.ciXing, mi.meaning, null, null, null));
        }
        wordVo.meaningItems = meaningItemVos;
        final learningWordVo = LearningWordVo(
            userVo,
            lw.addTime,
            lw.addDay,
            lw.lifeValue,
            lw.lastLearningDate,
            lw.learningOrder,
            lw.learnedTimes,
            wordVo);
        learningWordVos.add(learningWordVo);
      }
    }
    final result = PagedResults<LearningWordVo>(total);
    result.rows = learningWordVos;
    return result;
  }

  Future<PagedResults<MasteredWordVo>> getMasteredWordsForAPage(
      int fromIndex, int pageSize) async {
    try {
      final results = PagedResults<MasteredWordVo>(0);
      final db = MyDatabase.instance;
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        return results;
      }
      final countQuery = db.selectOnly(db.masteredWords)
        ..addColumns([countAll()])
        ..where(db.masteredWords.userId.equals(userId));
      final count = await countQuery.getSingle();
      results.total = count.read(countAll()) ?? 0;
      final masteredWordQuery = db.select(db.masteredWords)
        ..where((mw) => mw.userId.equals(userId))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.masterAtTime, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.wordId, mode: OrderingMode.desc)
        ])
        ..limit(pageSize, offset: fromIndex);
      final masteredWordEntries = await masteredWordQuery.get();
      if (masteredWordEntries.isEmpty) {
        return results;
      }
      final wordIds = masteredWordEntries.map((mw) => mw.wordId).toList();
      final wordQuery = db.select(db.words)..where((w) => w.id.isIn(wordIds));
      final wordEntries = await wordQuery.get();
      final wordMap = {for (var word in wordEntries) word.id: word};
      final meaningItemQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.isIn(wordIds))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final meaningItems = await meaningItemQuery.get();
      final meaningItemsMap = <String, List<MeaningItem>>{};
      for (var mi in meaningItems) {
        if (!meaningItemsMap.containsKey(mi.wordId)) {
          meaningItemsMap[mi.wordId] = [];
        }
        meaningItemsMap[mi.wordId]!.add(mi);
      }
      for (var masteredWord in masteredWordEntries) {
        final wordEntry = wordMap[masteredWord.wordId];
        if (wordEntry != null) {
          final wordVo = WordVo.c2(wordEntry.spell)
            ..id = wordEntry.id
            ..shortDesc = wordEntry.shortDesc
            ..longDesc = wordEntry.longDesc
            ..pronounce = wordEntry.pronounce
            ..americaPronounce = wordEntry.americaPronounce
            ..britishPronounce = wordEntry.britishPronounce
            ..popularity = wordEntry.popularity;
          List<MeaningItemVo> meaningItemVos = [];
          if (meaningItemsMap.containsKey(wordEntry.id)) {
            meaningItemVos = meaningItemsMap[wordEntry.id]!.map((mi) {
              return MeaningItemVo(
                  mi.id,
                  mi.ciXing,
                  mi.meaning,
                  null,
                  null,
                  null);
            }).toList();
          }
          wordVo.meaningItems = meaningItemVos;
          final userVo = UserVo.c2(userId);
          results.rows.add(MasteredWordVo(userVo, wordVo, masteredWord.masterAtTime));
        }
      }
      return results;
    } catch (e) {
      Global.logger.e("获取已掌握单词失败: $e");
      return PagedResults<MasteredWordVo>(0);
    }
  }

  Future<PagedResults<DictWordVo>> getDictWordsForAPage(
      String dictId, int fromIndex, int pageSize) async {
    try {
      final results = PagedResults<DictWordVo>(0);
      final db = MyDatabase.instance;
      final countQuery = db.selectOnly(db.dictWords)
        ..addColumns([countAll()])
        ..where(db.dictWords.dictId.equals(dictId));
      final count = await countQuery.getSingle();
      results.total = count.read(countAll()) ?? 0;
      
      final dictWordQuery = db.select(db.dictWords)
        ..where((dw) => dw.dictId.equals(dictId))
        // 所有词书都按seq排序
        ..orderBy([(t) => OrderingTerm(expression: t.seq)])
        ..limit(pageSize, offset: fromIndex);
      final dictWordEntries = await dictWordQuery.get();
      if (dictWordEntries.isEmpty) {
        return results;
      }
      final wordIds = dictWordEntries.map((dw) => dw.wordId).toList();
      final wordQuery = db.select(db.words)..where((w) => w.id.isIn(wordIds));
      final wordEntries = await wordQuery.get();
      final wordMap = {for (var word in wordEntries) word.id: word};
      // 1) 先取本词书(dictId)的定制释义
      final dictSpecificMeaningQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.isIn(wordIds) & mi.dictId.equals(dictId))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final dictSpecificMeaningItems = await dictSpecificMeaningQuery.get();

      final meaningItemsMap = <String, List<MeaningItem>>{};
      for (final mi in dictSpecificMeaningItems) {
        (meaningItemsMap[mi.wordId] ??= []).add(mi);
      }

      // 2) 对没有定制释义的单词，回退到通用释义，并按本词书的 popularityLimit 进行过滤
      final wordsWithoutCustom = wordIds
          .where((wordId) => !meaningItemsMap.containsKey(wordId) || (meaningItemsMap[wordId]?.isEmpty ?? true))
          .toList();

      int? popularityLimit;
      final currDict = await db.dictsDao.findById(dictId);
      if (currDict != null) {
        popularityLimit = currDict.popularityLimit;
      }

      if (wordsWithoutCustom.isNotEmpty) {
        final commonDictQuery = db.select(db.meaningItems)
          ..where((mi) => mi.wordId.isIn(wordsWithoutCustom) & mi.dictId.equals(Global.commonDictId))
          ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
        final commonMeaningItems = await commonDictQuery.get();

        for (final mi in commonMeaningItems) {
          if (popularityLimit == null || mi.popularity <= popularityLimit) {
            (meaningItemsMap[mi.wordId] ??= []).add(mi);
          }
        }
      }

      // 3) 批量查询被选中释义的例句
      final selectedMeaningItemIds = <String>[];
      for (final list in meaningItemsMap.values) {
        for (final mi in list) {
          selectedMeaningItemIds.add(mi.id);
        }
      }
      final sentenceQuery = db.select(db.sentences)
        ..where((s) => s.meaningItemId.isIn(selectedMeaningItemIds));
      final sentences = await sentenceQuery.get();
      final sentencesMap = <String, List<Sentence>>{};
      for (var s in sentences) {
        if (!sentencesMap.containsKey(s.meaningItemId)) {
          sentencesMap[s.meaningItemId] = [];
        }
        sentencesMap[s.meaningItemId]!.add(s);
      }
      for (final dictWord in dictWordEntries) {
        final wordEntry = wordMap[dictWord.wordId];
        if (wordEntry != null) {
          final wordVo = WordVo.c2(wordEntry.spell)
            ..id = wordEntry.id
            ..americaPronounce = wordEntry.americaPronounce
            ..britishPronounce = wordEntry.britishPronounce
            ..popularity = wordEntry.popularity
            ..pronounce = wordEntry.pronounce
            ..shortDesc = wordEntry.shortDesc
            ..longDesc = wordEntry.longDesc
            ..groupInfo = wordEntry.groupInfo;
          List<MeaningItemVo> meaningItemVos = [];
          if (meaningItemsMap.containsKey(wordEntry.id)) {
            meaningItemVos = meaningItemsMap[wordEntry.id]!.map((mi) {
              final meaningItemVo = MeaningItemVo.from(mi.ciXing, mi.meaning);
              meaningItemVo.id = mi.id;
              if (sentencesMap.containsKey(mi.id)) {
                List<SentenceVo> sentenceVos = [];
                for (var s in sentencesMap[mi.id]!) {
                  final author = UserVo.c2(s.authorId);
                  sentenceVos.add(SentenceVo(
                      s.id,
                      s.english,
                      s.chinese,
                      s.englishDigest,
                      s.theType,
                      s.footCount,
                      s.handCount,
                      author));
                }
                meaningItemVo.sentences = sentenceVos;
              }
              return meaningItemVo;
            }).toList();
          }
          wordVo.meaningItems = meaningItemVos;
          final dictWordVo = DictWordVo(DictVo.c2(dictId), wordVo, dictWord.seq);
          results.rows.add(dictWordVo);
        }
      }
      return results;
    } catch (e) {
      Global.logger.e("获取词典单词失败: $e");
      return PagedResults<DictWordVo>(0);
    }
  }

  Future<Result> deleteMasteredWord(String userId, String wordId) async {
    await MyDatabase.instance.masteredWordsDao
        .deleteMasteredWord(userId, wordId, true, true);
    final result = Result<dynamic>('200', null, true);
    return result;
  }

  Future<Result<int>> getDictWordOrder(String dictId, String spell) async {
    try {
      Global.logger.d('开始本地查询词典单词位置: dictId=$dictId, spell=$spell');
      final db = MyDatabase.instance;
      final wordQuery = db.select(db.words)
        ..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final dictWordQuery = db.select(db.dictWords)
        ..where(
            (tbl) => tbl.dictId.equals(dictId) & tbl.wordId.equals(word.id));
      final dictWord = await dictWordQuery.getSingleOrNull();
      if (dictWord == null) {
        Global.logger.d('单词 $spell 不在词典 $dictId 中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final order = dictWord.seq;
      Global.logger.d('找到单词 $spell 在词典 $dictId 中的位置: $order');
      return Result("SUCCESS", "获取成功", true)..data = order;
    } catch (e, stackTrace) {
      Global.logger.e('查询词典单词位置失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "查询单词位置失败: ${e.toString()}", false);
    }
  }

  Future<Result<int>> getLearningWordOrder(String spell, String userId) async {
    try {
      Global.logger.d('开始本地查询学习中单词位置: spell=$spell, userId=$userId');
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        Global.logger.e('查询学习中单词位置失败: 用户不存在 userId=$userId');
        return Result("ERROR", "用户不存在", false);
      }
      final wordQuery = db.select(db.words)
        ..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)
        ..where((tbl) =>
            tbl.userId.equals(userId) &
            tbl.wordId.equals(word.id) &
            tbl.lifeValue.isBiggerThanValue(0));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('用户未在学习单词 $spell');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final lifeValueCondition =
          db.learningWords.lifeValue.isBiggerThanValue(0);
      final beforeTimeCondition =
          db.learningWords.addTime.isSmallerThanValue(learningWord.addTime);
      final sameTimeSmallerLifeCondition = db.learningWords.addTime
              .equals(learningWord.addTime) &
          db.learningWords.lifeValue.isSmallerThanValue(learningWord.lifeValue);
      final sameTimeSameLifeSmallerWordIdCondition =
          db.learningWords.addTime.equals(learningWord.addTime) &
              db.learningWords.lifeValue.equals(learningWord.lifeValue) &
              db.learningWords.wordId.isSmallerThanValue(learningWord.wordId);
      countQuery.where(userIdCondition &
          lifeValueCondition &
          (beforeTimeCondition |
              sameTimeSmallerLifeCondition |
              sameTimeSameLifeSmallerWordIdCondition));
      final countResult = await countQuery.getSingle();
      int position = countResult.read(countAll()) ?? 0;
      position += 1;
      Global.logger.d('找到单词 $spell 在学习中的位置: $position');
      return Result("SUCCESS", "获取成功", true)..data = position;
    } catch (e, stackTrace) {
      Global.logger.e('查询学习中单词位置失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "查询单词位置失败: ${e.toString()}", false);
    }
  }

  Future<Result<int>> getMasteredWordOrder(String spell, String userId) async {
    final order = await MyDatabase.instance.masteredWordsDao
        .getMasteredWordOrder(userId, spell);
    final result = Result<int>('200', null, true);
    result.data = order;
    return result;
  }

  Future<Result<int>> getTodayWordOrder(String spell, String userId) async {
    try {
      Global.logger.d('开始本地查询今日单词位置: spell=$spell, userId=$userId');
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        Global.logger.e('查询今日单词位置失败: 用户不存在 userId=$userId');
        return Result("ERROR", "用户不存在", false);
      }
      final now = AppClock.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final wordQuery = db.select(db.words)
        ..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)
        ..where((tbl) =>
            tbl.userId.equals(userId) &
            tbl.wordId.equals(word.id) &
            tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
            tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('单词 $spell 不在今日单词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final dateCondition =
          db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
              db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay);
      final beforeOrderCondition = db.learningWords.learningOrder
          .isSmallerThanValue(learningWord.learningOrder);
      countQuery.where(userIdCondition & dateCondition & beforeOrderCondition);
      final countResult = await countQuery.getSingle();
      int position = countResult.read(countAll()) ?? 0;
      position += 1;
      Global.logger.d('找到单词 $spell 在今日单词列表中的位置: $position');
      return Result("SUCCESS", "获取成功", true)..data = position;
    } catch (e, stackTrace) {
      Global.logger.e('查询今日单词位置失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "查询单词位置失败: ${e.toString()}", false);
    }
  }

  Future<Result<int>> getWrongWordOrder(String spell, String userId) async {
    try {
      Global.logger.d('开始本地查询错词位置: spell=$spell, userId=$userId');
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        Global.logger.e('查询错词位置失败: 用户不存在 userId=$userId');
        return Result("ERROR", "用户不存在", false);
      }
      final wordQuery = db.select(db.words)
        ..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final wrongWordQuery = db.select(db.userWrongWords)
        ..where(
            (tbl) => tbl.userId.equals(userId) & tbl.wordId.equals(word.id));
      final wrongWord = await wrongWordQuery.getSingleOrNull();
      if (wrongWord == null) {
        Global.logger.d('单词 $spell 不在错词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.userWrongWords)
        ..addColumns([countAll()])
        ..where(db.userWrongWords.userId.equals(userId) &
            db.userWrongWords.createTime
                .isSmallerOrEqualValue(wrongWord.createTime));
      final countResult = await countQuery.getSingle();
      final position = countResult.read(countAll()) ?? 0;
      Global.logger.d('查询错词位置成功: spell=$spell, position=$position');
      return Result("SUCCESS", "获取成功", true)..data = position;
    } catch (e, stackTrace) {
      Global.logger.e('查询错词位置失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "查询错词位置失败: ${e.toString()}", false);
    }
  }

  Future<Result<int>> getTodayNewWordOrder(String spell, String userId) async {
    try {
      Global.logger.d('开始本地查询今日新词位置: spell=$spell, userId=$userId');
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        Global.logger.e('查询今日新词位置失败: 用户不存在 userId=$userId');
        return Result("ERROR", "用户不存在", false);
      }
      final now = AppClock.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final wordQuery = db.select(db.words)
        ..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)
        ..where((tbl) =>
            tbl.userId.equals(userId) &
            tbl.wordId.equals(word.id) &
            tbl.isTodayNewWord.equals(true) &
            tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
            tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('单词 $spell 不在今日新词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final isNewWordCondition = db.learningWords.isTodayNewWord.equals(true);
      final dateCondition =
          db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
              db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay);
      final beforeOrderCondition = db.learningWords.learningOrder
          .isSmallerThanValue(learningWord.learningOrder);
      countQuery.where(userIdCondition &
          isNewWordCondition &
          dateCondition &
          beforeOrderCondition);
      final countResult = await countQuery.getSingle();
      int position = countResult.read(countAll()) ?? 0;
      position += 1;
      Global.logger.d('找到单词 $spell 在今日新词列表中的位置: $position');
      return Result("SUCCESS", "获取成功", true)..data = position;
    } catch (e, stackTrace) {
      Global.logger.e('查询今日新词位置失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "查询单词位置失败: ${e.toString()}", false);
    }
  }

  Future<Result<int>> getTodayOldWordOrder(String spell, String userId) async {
    try {
      Global.logger.d('开始本地查询今日旧词位置: spell=$spell, userId=$userId');
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        Global.logger.e('查询今日旧词位置失败: 用户不存在 userId=$userId');
        return Result("ERROR", "用户不存在", false);
      }
      final now = AppClock.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final wordQuery = db.select(db.words)
        ..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)
        ..where((tbl) =>
            tbl.userId.equals(userId) &
            tbl.wordId.equals(word.id) &
            tbl.isTodayNewWord.equals(false) &
            tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
            tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('单词 $spell 不在今日旧词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final isOldWordCondition = db.learningWords.isTodayNewWord.equals(false);
      final dateCondition =
          db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
              db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay);
      final beforeOrderCondition = db.learningWords.learningOrder
          .isSmallerThanValue(learningWord.learningOrder);
      countQuery.where(userIdCondition &
          isOldWordCondition &
          dateCondition &
          beforeOrderCondition);
      final countResult = await countQuery.getSingle();
      int position = countResult.read(countAll()) ?? 0;
      position += 1;
      Global.logger.d('找到单词 $spell 在今日旧词列表中的位置: $position');
      return Result("SUCCESS", "获取成功", true)..data = position;
    } catch (e, stackTrace) {
      Global.logger.e('查询今日旧词位置失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "查询单词位置失败: ${e.toString()}", false);
    }
  }

  Future<List<WordVo>> getAnswerWrongWords(String userId) async {
    try {
      final db = MyDatabase.instance;
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        throw Exception('用户不存在');
      }
      final now = AppClock.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final wrongWordsQuery = db.select(db.userWrongWords)
        ..where((tbl) =>
            tbl.userId.equals(userId) &
            tbl.createTime.isBiggerOrEqualValue(startOfDay) &
            tbl.createTime.isSmallerOrEqualValue(endOfDay))
        ..orderBy([
          (tbl) =>
              OrderingTerm(expression: tbl.createTime, mode: OrderingMode.desc)
        ]);
      final wrongWords = await wrongWordsQuery.get();
      List<WordVo> wordVos = [];
      for (final wrongWord in wrongWords) {
        final word = await db.wordsDao.getWordById(wrongWord.wordId);
        if (word != null) {
          final wordVo = WordVo.c2(word.spell)
            ..id = word.id
            ..shortDesc = word.shortDesc
            ..longDesc = word.longDesc
            ..pronounce = word.pronounce
            ..americaPronounce = word.americaPronounce
            ..britishPronounce = word.britishPronounce
            ..popularity = word.popularity;
          final meaningItemsQuery = db.select(db.meaningItems)
            ..where((tbl) => tbl.wordId.equals(word.id))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.popularity)]);
          final meaningItems = await meaningItemsQuery.get();
          List<MeaningItemVo> meaningItemVos = [];
          for (final mi in meaningItems) {
            meaningItemVos.add(MeaningItemVo(
                mi.id, mi.ciXing, mi.meaning, null, null, null));
          }
          wordVo.meaningItems = meaningItemVos;
          wordVos.add(wordVo);
        }
      }
      return wordVos;
    } catch (e, stackTrace) {
      Global.logger.e('获取今日错词失败: $e', stackTrace: stackTrace);
      return [];
    }
  }

  Future<SentenceVo> getSentence(String sentenceId) async {
    try {
      Global.logger.d('开始本地获取句子: sentenceId=$sentenceId');
      final db = MyDatabase.instance;
      final sentence = await db.sentencesDao.getById(sentenceId);
      if (sentence == null) {
        Global.logger.e('句子不存在: sentenceId=$sentenceId');
        throw Exception('句子不存在');
      }
      final author = await db.usersDao.getUserById(sentence.authorId);
      UserVo authorVo;
      if (author != null) {
        authorVo = UserVo.c2(author.id);
        authorVo.nickName = author.nickName;
      } else {
        authorVo = UserVo.c2('unknown');
        authorVo.nickName = '未知用户';
      }
      final sentenceVo = SentenceVo(
        sentence.id,
        sentence.english,
        sentence.chinese,
        sentence.englishDigest,
        sentence.theType,
        sentence.footCount,
        sentence.handCount,
        authorVo,
      );
      sentenceVo.wordMeaning = sentence.wordMeaning;
      Global.logger.d('获取句子成功: sentenceId=$sentenceId');
      return sentenceVo;
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace,
          operation: '获取句子数据', showToast: false);
      rethrow;
    }
  }

  Future<Result<void>> removeWordFromDict(
      String dictId, String wordId, String userId) async {
    try {
      Global.logger
          .d('开始从词典删除单词: dictId=$dictId, wordId=$wordId, userId=$userId');
      final db = MyDatabase.instance;
      final dict = await db.dictsDao.findById(dictId);
      if (dict == null) {
        return Result("ERROR", "词典不存在", false);
      }
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        return Result("ERROR", "用户不存在", false);
      }
      if (dict.ownerId != user.id && !user.isInputor) {
        return Result("ERROR", "你只能编辑自己的词书", false);
      }
      final dictWord = await db.dictWordsDao.getById(dictId, wordId);
      if (dictWord == null) {
        return Result("ERROR", "词书中无该单词", false);
      }
      final seqNo = dictWord.seq;
      await db.transaction(() async {
        await db.dictWordsDao.deleteEntity(dictWord, true);
        Global.logger
            .d('已删除词典单词: dictId=$dictId, wordId=$wordId, seqNo=$seqNo');
        final laterWordsQuery = db.select(db.dictWords)
          ..where((dw) =>
              dw.dictId.equals(dictId) &
              dw.seq.isBiggerThanValue(seqNo));
        final laterWords = await laterWordsQuery.get();
        for (final laterWord in laterWords) {
          await (db.update(db.dictWords)
                ..where((dw) =>
                    dw.dictId.equals(laterWord.dictId) &
                    dw.wordId.equals(laterWord.wordId)))
              .write(DictWordsCompanion(
            seq: Value(laterWord.seq - 1),
            updateTime: Value(AppClock.now()),
          ));
        }
        // 更新词书的wordCount（并生成日志用于同步）
        await db.dictsDao.updateWordCount(dictId, true);
        final learningDict = await (db.select(db.learningDicts)
              ..where(
                  (ld) => ld.userId.equals(userId) & ld.dictId.equals(dictId)))
            .getSingleOrNull();
        if (learningDict != null && learningDict.currentWordSeq != null) {
          if (learningDict.currentWordSeq! > seqNo) {
            await (db.update(db.learningDicts)
                  ..where((ld) =>
                      ld.userId.equals(userId) & ld.dictId.equals(dictId)))
                .write(LearningDictsCompanion(
              currentWordSeq: Value(learningDict.currentWordSeq! - 1),
              updateTime: Value(AppClock.now()),
            ));
          }
        }
      });
      
      // 延迟触发同步，确保事务完全提交
      Future.delayed(Duration.zero, () {
        ThrottledDbSyncService().requestSync();
      });
      
      Global.logger.d('从词典删除单词完成: dictId=$dictId, wordId=$wordId');
      return Result("SUCCESS", "删除成功", true);
    } catch (e, stackTrace) {
      Global.logger.e('从词典删除单词失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "删除失败: ${e.toString()}", false);
    }
  }

  Future<DictVo> getRawWordDict() async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      throw Exception("用户未登录");
    }
    final db = MyDatabase.instance;
    final rawWordDict = await db.dictsDao.findUserRawDict(user.id);
    if (rawWordDict != null) {
      final dict = DictVo.c2(rawWordDict.id);
      dict.name = rawWordDict.name;
      dict.shortName = rawWordDict.name;
      dict.wordCount = rawWordDict.wordCount;
      dict.isReady = rawWordDict.isReady;
      dict.isShared = rawWordDict.isShared;
      dict.visible = rawWordDict.visible;
      return dict;
    } else {
      throw Exception("本地数据库中未找到用户的生词本");
    }
  }

  Future<Result<List<WordList>>> getWordLists() async {
    try {
      final user = Global.getLoggedInUser();
      if (user == null) {
        return Result("ERROR", "用户未登录", false);
      }
      final db = MyDatabase.instance;
      final wordLists = <WordList>[];
      final now = AppClock.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final wrongWordsQuery = db.selectOnly(db.userWrongWords)
        ..addColumns([countAll()])
        ..where(db.userWrongWords.userId.equals(user.id))
        ..where(db.userWrongWords.createTime.isBiggerOrEqualValue(startOfDay))
        ..where(db.userWrongWords.createTime.isSmallerOrEqualValue(endOfDay));
      final wrongWordsCount = await wrongWordsQuery.getSingle();
      wordLists.add(WordList("今日错词", wrongWordsCount.read(countAll()) ?? 0));
      final newWordsQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id))
        ..where(db.learningWords.isTodayNewWord.equals(true))
        ..where(
            db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay))
        ..where(
            db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay));
      final newWordsCount = await newWordsQuery.getSingle();
      wordLists.add(WordList("今日新词", newWordsCount.read(countAll()) ?? 0));
      final oldWordsQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id))
        ..where(db.learningWords.isTodayNewWord.equals(false))
        ..where(
            db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay))
        ..where(
            db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay));
      final oldWordsCount = await oldWordsQuery.getSingle();
      wordLists.add(WordList("今日旧词", oldWordsCount.read(countAll()) ?? 0));
      final todayWordsQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id))
        ..where(
            db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay))
        ..where(
            db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay));
      final totalWordsCount = await todayWordsQuery.getSingle();
      wordLists.add(WordList("今日单词", totalWordsCount.read(countAll()) ?? 0));
      final learningWordsQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id))
        ..where(db.learningWords.lifeValue.isBiggerThanValue(0));
      final learningWordsCount = await learningWordsQuery.getSingle();
      wordLists.add(WordList("学习中", learningWordsCount.read(countAll()) ?? 0));
      final rawWordDict = await db.dictsDao.findUserRawDict(user.id);
      int rawWordCount = 0;
      if (rawWordDict != null) {
        final rawWordCountQuery = db.selectOnly(db.dictWords)
          ..addColumns([countAll()])
          ..where(db.dictWords.dictId.equals(rawWordDict.id));
        final rawWordCountResult = await rawWordCountQuery.getSingle();
        rawWordCount = rawWordCountResult.read(countAll()) ?? 0;
      }
      wordLists.add(WordList("生词本", rawWordCount));
      final masteredWordsQuery = db.selectOnly(db.masteredWords)
        ..addColumns([countAll()])
        ..where(db.masteredWords.userId.equals(user.id));
      final masteredWordsCount = await masteredWordsQuery.getSingle();
      wordLists.add(WordList("已掌握", masteredWordsCount.read(countAll()) ?? 0));
      return Result("SUCCESS", "获取成功", true)..data = wordLists;
    } catch (e, stackTrace) {
      Global.logger.e('获取单词列表失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "获取单词列表失败: ${e.toString()}", false);
    }
  }

  Future<Result> deleteRawWord(String wordId) async {
    try {
      Global.logger.d('开始删除生词: wordId=$wordId');
      final db = MyDatabase.instance;
      final user = Global.getLoggedInUser();
      if (user == null) {
        Global.logger.e('删除生词失败: 用户未登录');
        return Result("ERROR", "用户未登录", false);
      }
      final rawWordDict = await db.dictsDao.findUserRawDict(user.id);
      if (rawWordDict == null) {
        Global.logger.w('用户没有生词本词典: userId=${user.id}');
        return Result("SUCCESS", "生词本不存在", true);
      }
      return await removeWordFromDict(rawWordDict.id, wordId, user.id);
    } catch (e, stackTrace) {
      Global.logger.e('删除生词失败: $e', stackTrace: stackTrace);
      return Result("ERROR", "删除失败: ${e.toString()}", false);
    }
  }

  Future<PagedResults<LearningWordVo>> getTodayWordsForAPage(
      int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    final now = AppClock.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final query = db.select(db.learningWords)
      ..where((tbl) =>
          tbl.userId.equals(userId) &
          tbl.lastLearningDate.isBiggerOrEqualValue(startOfDay) &
          tbl.lastLearningDate.isSmallerOrEqualValue(endOfDay))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.learningOrder)])
      ..limit(pageSize, offset: fromIndex);
    final learningWords = await query.get();
    final countQuery = db.selectOnly(db.learningWords)
      ..addColumns([countAll()])
      ..where(db.learningWords.userId.equals(userId))
      ..where(
          db.learningWords.lastLearningDate.isBiggerOrEqualValue(startOfDay))
      ..where(
          db.learningWords.lastLearningDate.isSmallerOrEqualValue(endOfDay));
    final countResult = await countQuery.getSingle();
    final total = countResult.read(countAll()) ?? 0;
    List<LearningWordVo> learningWordVos = [];
    for (final lw in learningWords) {
      final word = await db.wordsDao.getWordById(lw.wordId);
      if (word != null) {
        final userVo = UserVo.c2(userId);
        userVo.level = LevelVo(user.levelId);
        final wordVo = WordVo.c2(word.spell)
          ..id = word.id
          ..shortDesc = word.shortDesc
          ..longDesc = word.longDesc
          ..pronounce = word.pronounce
          ..americaPronounce = word.americaPronounce
          ..britishPronounce = word.britishPronounce
          ..popularity = word.popularity;
        final meaningItemsQuery = db.select(db.meaningItems)
          ..where((tbl) => tbl.wordId.equals(word.id));
        final meaningItems = await meaningItemsQuery.get();
        List<MeaningItemVo> meaningItemVos = [];
        for (final mi in meaningItems) {
          meaningItemVos.add(MeaningItemVo(
              mi.id, mi.ciXing, mi.meaning, null, null, null));
        }
        wordVo.meaningItems = meaningItemVos;
        final learningWordVo = LearningWordVo(
            userVo,
            lw.addTime,
            lw.addDay,
            lw.lifeValue,
            lw.lastLearningDate,
            lw.learningOrder,
            lw.learnedTimes,
            wordVo);
        learningWordVos.add(learningWordVo);
      }
    }
    final result = PagedResults<LearningWordVo>(total);
    result.rows = learningWordVos;
    return result;
  }

  Future<Result> setLearningWordAsMastered(
      String userId, String wordId, bool deleteLearningWord) async {
    try {
      await MyDatabase.instance.masteredWordsDao
          .setLearningWordAsMastered(userId, wordId, deleteLearningWord);
      await MyDatabase.instance.masteredWordsDao
          .updateUserMasteredWordCount(userId);
      return Result("SUCCESS", "标记单词为已掌握成功", true);
    } catch (e) {
      Global.logger.e('本地化setLearningWordAsMastered失败: $e');
      return Result("ERROR", '标记单词为已掌握失败: $e', false);
    }
  }
}


