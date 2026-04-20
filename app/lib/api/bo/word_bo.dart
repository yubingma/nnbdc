import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/db_log_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/level_util.dart';

import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/constants.dart';

import '../../services/throttled_sync_service.dart';

class WordBo {
  static final WordBo _instance = WordBo._internal();
  factory WordBo() => _instance;
  WordBo._internal();

  /// 在本地动态生成乱序版的临时的词库表结构
  /// 这里的 DictWord 仅存放在本地数据库提供阅读游览，不上云
  Future<void> generateShuffledDictLocally(String shuffledDictId, String baseDictId) async {
    final db = MyDatabase.instance;
    await db.transaction(() async {
      // 1. 获取原词书的所有单字
      final baseDictWordsQuery = db.select(db.dictWords).join([
        innerJoin(db.words, db.words.id.equalsExp(db.dictWords.wordId))
      ])..where(db.dictWords.dictId.equals(baseDictId));

      final results = await baseDictWordsQuery.get();
      if (results.isEmpty) return;

      // 2. 将它们读取到内存并用 MD5(spell) 排序
      final list = results.map((row) {
        final word = row.readTable(db.words);
        return {
          'wordId': word.id,
          'spell': word.spell,
          'md5': md5.convert(utf8.encode(word.spell)).toString(),
        };
      }).toList();

      list.sort((a, b) => (a['md5'] as String).compareTo(b['md5'] as String));

      // 3. 构造新的 DictWord 列表插入到数据库
      final newDictWords = <DictWord>[];
      final createTime = AppClock.now();
      for (int i = 0; i < list.length; i++) {
        newDictWords.add(DictWord(
          dictId: shuffledDictId,
          wordId: list[i]['wordId'] as String,
          seq: i + 1,
          unit: 0,
          createTime: createTime,
        ));
      }

      // 首先清理可能已经存在的旧词，防止主键冲突
      await (db.delete(db.dictWords)..where((dw) => dw.dictId.equals(shuffledDictId))).go();

      // 批量插入
      await db.dictWordsDao.insertEntities(newDictWords, false);
      Global.logger.i('✅ 本地已生成乱序版词书[$shuffledDictId]，共 ${newDictWords.length} 词');
    });
  }

  // 只做本地查词（包含大小写与词形多变体）
  Future<SearchWordResult> searchWordLocalOnly(String spell, [String? dictId]) async {
    final db = MyDatabase.instance;
    final purifiedSpell = Util.purifySpell(spell);
    try {
      final SearchWordResult? localHit = await _searchLocallyWithVariants(purifiedSpell, db, dictId);
      return localHit ?? SearchWordResult(null, null, null, null, null);
    } catch (e, st) {
      ErrorHandler.handleDatabaseError(e, st, operation: '本地查词');
      return SearchWordResult(null, null, null, null, null);
    }
  }

  // 通用的查询通用词典释义项方法
  Future<List<MeaningItem>> _getCommonDictMeaningItems(String wordId) async {
    final db = MyDatabase.instance;
    final commonQuery = db.select(db.meaningItems)
      ..where((mi) => mi.wordId.equals(wordId) & mi.dictId.equals(Global.commonDictId))
      ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
    final commonMeaningItems = await commonQuery.get();

    // 如果通用词典没有释义项，查询所有可用的释义项
    if (commonMeaningItems.isEmpty) {
      final anyQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.equals(wordId))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      return await anyQuery.get();
    }

    return commonMeaningItems;
  }

  // 通用的查询例句数据并分配给释义项的方法
  Future<void> _loadSentencesForMeaningItems(List<MeaningItemVo> meaningItemVos) async {
    final db = MyDatabase.instance;
    final selectedMeaningItemIds = meaningItemVos.map((mi) => mi.id!).toList();

    if (selectedMeaningItemIds.isEmpty) return;

    final sentenceQuery = db.select(db.sentences)..where((s) => s.meaningItemId.isIn(selectedMeaningItemIds));
    final sentences = await sentenceQuery.get();
    final sentencesMap = <String, List<Sentence>>{};

    for (var s in sentences) {
      if (!sentencesMap.containsKey(s.meaningItemId)) {
        sentencesMap[s.meaningItemId] = [];
      }
      sentencesMap[s.meaningItemId]!.add(s);
    }

    // 将例句分配给对应的释义项
    for (final miVo in meaningItemVos) {
      if (sentencesMap.containsKey(miVo.id)) {
        final sentenceVos = <SentenceVo>[];
        for (final s in sentencesMap[miVo.id!]!) {
          final author = UserVo.c2(s.authorId);
          final sentenceVo = SentenceVo(
              s.id, s.english, s.chinese, s.englishDigest, s.partOfSpeech, s.theType.isEmpty ? 'tts' : s.theType, s.footCount, s.handCount, author);
          sentenceVo.wordMeaning = s.wordMeaning;
          sentenceVos.add(sentenceVo);
        }
        miVo.sentences = sentenceVos;
      }
    }
  }

  // 通用的查询例句数据并返回映射的方法（用于批量处理）
  Future<Map<String, List<Sentence>>> _loadSentencesMap(List<String> meaningItemIds) async {
    final db = MyDatabase.instance;

    if (meaningItemIds.isEmpty) return {};

    final sentenceQuery = db.select(db.sentences)..where((s) => s.meaningItemId.isIn(meaningItemIds));
    final sentences = await sentenceQuery.get();
    final sentencesMap = <String, List<Sentence>>{};

    for (var s in sentences) {
      if (!sentencesMap.containsKey(s.meaningItemId)) {
        sentencesMap[s.meaningItemId] = [];
      }
      sentencesMap[s.meaningItemId]!.add(s);
    }

    return sentencesMap;
  }

  // 根据单词ID和用户ID进行查词，支持词书过滤
  Future<SearchWordResult> searchWordById(String wordId, String? userId, {List<String>? priorityDictIds}) async {
    final db = MyDatabase.instance;
    try {
      final wordQuery = db.select(db.words)..where((w) => w.id.equals(wordId));
      final localWord = await wordQuery.getSingleOrNull();

      if (localWord == null) {
        return SearchWordResult(null, null, null, null, null);
      }

      final wordVo = WordVo.c2(localWord.spell)
        ..id = localWord.id
        ..shortDesc = localWord.shortDesc
        ..longDesc = localWord.longDesc
        ..pronounce = localWord.pronounce
        ..americaPronounce = localWord.americaPronounce
        ..britishPronounce = localWord.britishPronounce
        ..popularity = localWord.popularity
        ..groupInfo = localWord.groupInfo
        ..createTime = localWord.createTime
        ..updateTime = localWord.updateTime;

      // 获取释义项
      List<MeaningItem> meaningItems;
      if ((userId != null && userId.isNotEmpty) || (priorityDictIds != null && priorityDictIds.isNotEmpty)) {
        meaningItems = await getWordMeaningItems(localWord.id, userId, priorityDictIds: priorityDictIds);
      } else {
        // 用户ID和优先词书都为空，直接查询通用词典，不做 popularity limit 过滤
        meaningItems = await _getCommonDictMeaningItems(localWord.id);
      }

      // 构建释义项VO
      final meaningItemVos = <MeaningItemVo>[];
      for (final mi in meaningItems) {
        final miVo = MeaningItemVo(
            mi.id,
            mi.ciXing,
            mi.meaning,
            null, // dict
            null, // synonyms
            null // sentences
            );
        meaningItemVos.add(miVo);
      }
      wordVo.meaningItems = meaningItemVos;

      // 查询例句数据
      await _loadSentencesForMeaningItems(meaningItemVos);

      // 查询形近词数据
      final similarWordsQuery = db.select(db.similarWords)
        ..where((sw) => sw.wordId.equals(localWord.id))
        ..orderBy([(sw) => OrderingTerm(expression: sw.distance)]);
      final similarWords = await similarWordsQuery.get();

      final similarWordVos = <WordVo>[];
      for (final sw in similarWords) {
        final similarWordQuery = db.select(db.words)..where((w) => w.id.equals(sw.similarWordId));
        final similarWord = await similarWordQuery.getSingleOrNull();

        if (similarWord != null) {
          final similarWordVo = WordVo.c2(similarWord.spell)
            ..id = similarWord.id
            ..shortDesc = similarWord.shortDesc
            ..longDesc = similarWord.longDesc
            ..pronounce = similarWord.pronounce
            ..americaPronounce = similarWord.americaPronounce
            ..britishPronounce = similarWord.britishPronounce
            ..popularity = similarWord.popularity
            ..groupInfo = similarWord.groupInfo;

          // 为形近词查询释义项，根据用户ID决定是否进行词书过滤
          List<MeaningItem> similarMeaningItems;
          if ((userId != null && userId.isNotEmpty) || (priorityDictIds != null && priorityDictIds.isNotEmpty)) {
            similarMeaningItems = await getWordMeaningItems(similarWord.id, userId, priorityDictIds: priorityDictIds);
          } else {
            // 无用户信息和优先词书信息，直接查询通用词典
            similarMeaningItems = await _getCommonDictMeaningItems(similarWord.id);
          }

          final similarMeaningItemVos = <MeaningItemVo>[];
          for (final mi in similarMeaningItems) {
            final miVo = MeaningItemVo(
                mi.id,
                mi.ciXing,
                mi.meaning,
                null, // dict
                null, // synonyms
                null // sentences
                );
            similarMeaningItemVos.add(miVo);
          }
          similarWordVo.meaningItems = similarMeaningItemVos;

          similarWordVos.add(similarWordVo);
        }
      }
      wordVo.similarWords = similarWordVos;

      // 查询单词配图
      final images = await db.wordImagesDao.getImagesByWordId(localWord.id);
      wordVo.images = images
          .where((i) {
            final status = (i as dynamic).status;
            final isApproved = status == 'APPROVED' || status == null;
            final isPendingOfUser = status == 'PENDING' && i.authorId == Global.currentUserId;
            return isApproved || isPendingOfUser;
          })
          .map((i) => WordImageVo(i.id, i.imageFile, i.hand, i.foot, UserVo.c2(i.authorId),
              status: (i as dynamic).status, auditReason: (i as dynamic).auditReason))
          .toList();

      // 查询词根解析数据
      await _loadCigenWordLinks(wordVo);

      // 检查是否在用户选择的词书中
      bool isInMySelectedDicts = false;
      if (userId != null && userId.isNotEmpty) {
        final learningDicts = await (db.select(db.learningDicts)..where((tbl) => tbl.userId.equals(userId))).get();
        final selectedDictIds = learningDicts.map((e) => e.dictId).toList();

        if (selectedDictIds.isNotEmpty) {
          final selectedMiCount = await (db.selectOnly(db.meaningItems)
                ..addColumns([countAll()])
                ..where(db.meaningItems.wordId.equals(localWord.id))
                ..where(db.meaningItems.dictId.isIn(selectedDictIds)))
              .getSingle();
          isInMySelectedDicts = (selectedMiCount.read(countAll()) ?? 0) > 0;
        }
      }

      // 检查是否在用户生词本中
      bool isInRawWordDict = false;
      if (userId != null && userId.isNotEmpty) {
        final rawDict = await db.dictsDao.findUserRawDict(userId);
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
        Util.getWordSoundUrl(localWord.spell, word: wordVo),
      );
      return localResult;
    } catch (e, st) {
      ErrorHandler.handleDatabaseError(e, st, operation: '根据ID查词');
      return SearchWordResult(null, null, null, null, null);
    }
  }

  Future<SearchWordResult?> _searchLocallyWithVariants(String purifiedSpell, MyDatabase db, [String? dictId]) async {
    var result = await _searchLocalOnly(purifiedSpell, db, dictId);
    if (result != null) return result;
    if (purifiedSpell.endsWith('s')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 1);
      result = await _searchLocalOnly(base, db, dictId);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('es')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 2);
      result = await _searchLocalOnly(base, db, dictId);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith("'s")) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 2);
      result = await _searchLocalOnly(base, db, dictId);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ies')) {
      var base = "${purifiedSpell.substring(0, purifiedSpell.length - 3)}y";
      result = await _searchLocalOnly(base, db, dictId);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ied')) {
      var base = "${purifiedSpell.substring(0, purifiedSpell.length - 3)}y";
      result = await _searchLocalOnly(base, db, dictId);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ed')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 2);
      result = await _searchLocalOnly(base, db, dictId);
      if (result != null) return result;
      var basePlusE = "${base}e";
      result = await _searchLocalOnly(basePlusE, db, dictId);
      if (result != null) return result;
    }
    if (purifiedSpell.endsWith('ing')) {
      var base = purifiedSpell.substring(0, purifiedSpell.length - 3);
      result = await _searchLocalOnly(base, db, dictId);
      if (result != null) return result;
      var basePlusE = "${base}e";
      result = await _searchLocalOnly(basePlusE, db, dictId);
      if (result != null) return result;
    }
    return null;
  }

  Future<SearchWordResult?> _searchLocalOnly(String spell, MyDatabase db, [String? dictId]) async {
    var result = await _tryBuildLocalResultBySpell(spell, db, dictId);
    if (result != null) return result;

    var lowerSpell = spell.toLowerCase();
    if (lowerSpell != spell) {
      result = await _tryBuildLocalResultBySpell(lowerSpell, db, dictId);
      if (result != null) return result;
    }

    var upperSpell = spell.toUpperCase();
    if (upperSpell != spell) {
      result = await _tryBuildLocalResultBySpell(upperSpell, db, dictId);
      if (result != null) return result;
    }

    if (spell.isNotEmpty) {
      var capSpell = spell.substring(0, 1).toUpperCase() + spell.substring(1).toLowerCase();
      if (capSpell != spell && capSpell != lowerSpell) {
        result = await _tryBuildLocalResultBySpell(capSpell, db, dictId);
        if (result != null) return result;
      }
    }

    return null;
  }

  Future<SearchWordResult?> _tryBuildLocalResultBySpell(String spell, MyDatabase db, [String? dictId]) async {
    final wordQuery = db.select(db.words)..where((w) => w.spell.equals(spell));
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
        ..groupInfo = localWord.groupInfo
        ..createTime = localWord.createTime
        ..updateTime = localWord.updateTime;

      // 加载词根解析数据
      await _loadCigenWordLinks(wordVo);

      // 获取释义项
      final currentUser = await Global.refreshLoggedInUser();
      List<MeaningItem> meaningItems;
      if (dictId != null) {
        final miQuery = db.select(db.meaningItems)..where((mi) => mi.wordId.equals(localWord.id) & mi.dictId.equals(dictId));
        meaningItems = await miQuery.get();
      } else if (currentUser != null && currentUser.id != null) {
        // 有用户ID，使用现有的 getWordMeaningItems 方法（包含 popularity limit 过滤）
        meaningItems = await getWordMeaningItems(localWord.id, currentUser.id!);
      } else {
        // 无用户ID，直接查询通用词典
        meaningItems = await _getCommonDictMeaningItems(localWord.id);
      }

      final meaningItemVos = <MeaningItemVo>[];
      for (final mi in meaningItems) {
        final miVo = MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null);
        meaningItemVos.add(miVo);
      }
      wordVo.meaningItems = meaningItemVos;

      // 查询单词配图
      final images = await db.wordImagesDao.getImagesByWordId(localWord.id);
      wordVo.images = images
          .where((i) {
            final status = (i as dynamic).status;
            final isApproved = status == 'APPROVED' || status == null;
            final isPendingOfUser = status == 'PENDING' && i.authorId == Global.currentUserId;
            return isApproved || isPendingOfUser;
          })
          .map((i) => WordImageVo(i.id, i.imageFile, i.hand, i.foot, UserVo.c2(i.authorId),
              status: (i as dynamic).status, auditReason: (i as dynamic).auditReason))
          .toList();

      bool isInMySelectedDicts = false;
      if (currentUser != null && currentUser.id != null) {
        final learningDicts = await (db.select(db.learningDicts)..where((tbl) => tbl.userId.equals(currentUser.id!))).get();
        final selectedDictIds = learningDicts.map((e) => e.dictId).toList();

        if (selectedDictIds.isNotEmpty) {
          final selectedMiCount = await (db.selectOnly(db.meaningItems)
                ..addColumns([countAll()])
                ..where(db.meaningItems.wordId.equals(localWord.id))
                ..where(db.meaningItems.dictId.isIn(selectedDictIds)))
              .getSingle();
          isInMySelectedDicts = (selectedMiCount.read(countAll()) ?? 0) > 0;
        }
      }

      bool isInRawWordDict = false;
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
        Util.getWordSoundUrl(localWord.spell, word: wordVo),
      );
      return localResult;
    } else {
      return null;
    }
  }

  // 加载词根解析数据
  Future<void> _loadCigenWordLinks(WordVo wordVo) async {
    final db = MyDatabase.instance;
    final links = await db.cigenWordLinksDao.getLinksByWordId(wordVo.id!);
    if (links.isNotEmpty) {
      final linkVos = <CigenWordLinkVo>[];
      for (final link in links) {
        final cigen = await db.cigensDao.getById(link.cigenId);
        if (cigen != null) {
          final cigenVo = CigenVo(cigen.id, cigen.description);
          linkVos.add(CigenWordLinkVo(cigenVo, link.theExplain));
        }
      }
      wordVo.cigenWordLinks = linkVos;
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
    final existingDictWord = await db.dictWordsDao.getById(rawWordDict.id, word.id);
    if (existingDictWord != null) {
      return Result("ERROR", "单词已在生词本中", false);
    }
    final now = AppClock.now();
    final dictWord = DictWord(
      dictId: rawWordDict.id,
      wordId: word.id,
      seq: 0,
      unit: 0,
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

  Future<PagedResults<LearningWordVo>> getLearningWordsForAPage(int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    try {
      final query = db.select(db.learningWords)
        ..where((tbl) => tbl.userId.equals(userId))
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.addTime), (tbl) => OrderingTerm(expression: tbl.wordId)])
        ..limit(pageSize, offset: fromIndex);
      final learningWords = await query.get();

      final countQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(userId));
      final countResult = await countQuery.getSingle();
      final total = countResult.read(countAll()) ?? 0;
      List<LearningWordVo> learningWordVos = [];
      for (final lw in learningWords) {
        final word = await db.wordsDao.getWordById(lw.wordId);
        if (word != null) {
          final userVo = UserVo.c2(userId);
          userVo.level = LevelUtil.getLevelVoByWordCount(user.masteredWordsCount);
          final wordVo = WordVo.c2(word.spell)
            ..id = word.id
            ..shortDesc = word.shortDesc
            ..longDesc = word.longDesc
            ..pronounce = word.pronounce
            ..americaPronounce = word.americaPronounce
            ..britishPronounce = word.britishPronounce
            ..popularity = word.popularity;
          // 使用 getWordMeaningItems 方法进行词书过滤
          final meaningItems = await getWordMeaningItems(word.id, userId);
          List<MeaningItemVo> meaningItemVos = [];
          for (final mi in meaningItems) {
            meaningItemVos.add(MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null));
          }
          wordVo.meaningItems = meaningItemVos;
          final learningWordVo = LearningWordVo(userVo, lw.addTime, lw.addDay, lw.lastLearningDate, lw.learningOrder, lw.learnedTimes, wordVo,
              lw.batchId, lw.stability, lw.difficulty, lw.elapsedDays, lw.scheduledDays, lw.reps, lw.lapses, lw.state);
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

  Future<PagedResults<LearningWordVo>> getTodayNewWordsForAPage(int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    // Remove unused date variables
    final query = db.select(db.learningWords)
      ..where((tbl) => tbl.userId.equals(userId) & tbl.isTodayNewWord.equals(true) & tbl.batchId.isBiggerThanValue(0))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.learningOrder)])
      ..limit(pageSize, offset: fromIndex);
    final learningWords = await query.get();
    final countQuery = db.selectOnly(db.learningWords)
      ..addColumns([countAll()])
      ..where(db.learningWords.userId.equals(userId))
      ..where(db.learningWords.isTodayNewWord.equals(true))
      ..where(db.learningWords.batchId.isBiggerThanValue(0));
    final countResult = await countQuery.getSingle();
    final total = countResult.read(countAll()) ?? 0;
    List<LearningWordVo> learningWordVos = [];
    for (final lw in learningWords) {
      final word = await db.wordsDao.getWordById(lw.wordId);
      if (word != null) {
        final userVo = UserVo.c2(userId);
        userVo.level = LevelUtil.getLevelVoByWordCount(user.masteredWordsCount);
        final wordVo = WordVo.c2(word.spell)
          ..id = word.id
          ..shortDesc = word.shortDesc
          ..longDesc = word.longDesc
          ..pronounce = word.pronounce
          ..americaPronounce = word.americaPronounce
          ..britishPronounce = word.britishPronounce
          ..popularity = word.popularity;
        // 使用 getWordMeaningItems 方法进行词书过滤
        final meaningItems = await getWordMeaningItems(word.id, userId);
        List<MeaningItemVo> meaningItemVos = [];
        for (final mi in meaningItems) {
          meaningItemVos.add(MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null));
        }
        wordVo.meaningItems = meaningItemVos;
        final learningWordVo = LearningWordVo(userVo, lw.addTime, lw.addDay, lw.lastLearningDate, lw.learningOrder, lw.learnedTimes, wordVo,
            lw.batchId, lw.stability, lw.difficulty, lw.elapsedDays, lw.scheduledDays, lw.reps, lw.lapses, lw.state);
        learningWordVos.add(learningWordVo);
      }
    }
    final result = PagedResults<LearningWordVo>(total);
    result.rows = learningWordVos;
    return result;
  }

  Future<PagedResults<LearningWordVo>> getTodayOldWordsForAPage(int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    // Remove unused date variables
    final query = db.select(db.learningWords)
      ..where((tbl) => tbl.userId.equals(userId) & tbl.isTodayNewWord.equals(false) & tbl.batchId.isBiggerThanValue(0))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.learningOrder)])
      ..limit(pageSize, offset: fromIndex);
    final learningWords = await query.get();
    final countQuery = db.selectOnly(db.learningWords)
      ..addColumns([countAll()])
      ..where(db.learningWords.userId.equals(userId))
      ..where(db.learningWords.isTodayNewWord.equals(false))
      ..where(db.learningWords.batchId.isBiggerThanValue(0));
    final countResult = await countQuery.getSingle();
    final total = countResult.read(countAll()) ?? 0;
    List<LearningWordVo> learningWordVos = [];
    for (final lw in learningWords) {
      final word = await db.wordsDao.getWordById(lw.wordId);
      if (word != null) {
        final userVo = UserVo.c2(userId);
        userVo.level = LevelUtil.getLevelVoByWordCount(user.masteredWordsCount);
        final wordVo = WordVo.c2(word.spell)
          ..id = word.id
          ..shortDesc = word.shortDesc
          ..longDesc = word.longDesc
          ..pronounce = word.pronounce
          ..americaPronounce = word.americaPronounce
          ..britishPronounce = word.britishPronounce
          ..popularity = word.popularity;
        // 使用 getWordMeaningItems 方法进行词书过滤
        final meaningItems = await getWordMeaningItems(word.id, userId);
        List<MeaningItemVo> meaningItemVos = [];
        for (final mi in meaningItems) {
          meaningItemVos.add(MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null));
        }
        wordVo.meaningItems = meaningItemVos;
        final learningWordVo = LearningWordVo(userVo, lw.addTime, lw.addDay, lw.lastLearningDate, lw.learningOrder, lw.learnedTimes, wordVo,
            lw.batchId, lw.stability, lw.difficulty, lw.elapsedDays, lw.scheduledDays, lw.reps, lw.lapses, lw.state);
        learningWordVos.add(learningWordVo);
      }
    }
    final result = PagedResults<LearningWordVo>(total);
    result.rows = learningWordVos;
    return result;
  }

  Future<PagedResults<LearningWordVo>> getLearningWordsByBucketForAPage(int bucketKey, int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }

    final now = AppClock.now();
    final nowDate = DateTime(now.year, now.month, now.day);

    // 获取所有正在学习中的单词 (即：尚未毕业的候选人)
    final allLearningWords = await (db.select(db.learningWords)
          ..where((lw) => lw.userId.equals(userId) & (lw.stability.isNull() | lw.stability.isSmallerThanValue(Constants.graduationStability))))
        .get();

    List<LearningWord> bucketWords = [];
    for (var word in allLearningWords) {
      final lastDateRaw = word.lastLearningDate ?? now;
      final scheduledDays = word.scheduledDays ?? 0;
      final nextDateRaw = DateTime(lastDateRaw.year, lastDateRaw.month, lastDateRaw.day).add(Duration(days: scheduledDays));

      final nextDate = DateTime(nextDateRaw.year, nextDateRaw.month, nextDateRaw.day);
      final daysDiff = nextDate.difference(nowDate).inDays;

      int key;
      if (daysDiff >= 0) {
        key = daysDiff;
      } else {
        int overdueDays = -daysDiff;
        key = -((overdueDays + 9) ~/ 10 * 10);
      }

      if (key == bucketKey) {
        bucketWords.add(word);
      }
    }

    // 按上次学习日期排序
    bucketWords.sort((a, b) {
      final aDate = a.lastLearningDate ?? DateTime(2000);
      final bDate = b.lastLearningDate ?? DateTime(2000);
      return aDate.compareTo(bDate);
    });

    final total = bucketWords.length;
    final pagedWords = bucketWords.skip(fromIndex).take(pageSize).toList();

    List<LearningWordVo> learningWordVos = [];
    for (final lw in pagedWords) {
      final word = await db.wordsDao.getWordById(lw.wordId);
      if (word != null) {
        final userVo = UserVo.c2(userId);
        userVo.level = LevelUtil.getLevelVoByWordCount(user.masteredWordsCount);
        final wordVo = WordVo.c2(word.spell)
          ..id = word.id
          ..shortDesc = word.shortDesc
          ..longDesc = word.longDesc
          ..pronounce = word.pronounce
          ..americaPronounce = word.americaPronounce
          ..britishPronounce = word.britishPronounce
          ..popularity = word.popularity;
        // 使用 getWordMeaningItems 方法进行词书过滤
        final meaningItems = await getWordMeaningItems(word.id, userId);
        List<MeaningItemVo> meaningItemVos = [];
        for (final mi in meaningItems) {
          meaningItemVos.add(MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null));
        }
        wordVo.meaningItems = meaningItemVos;
        final learningWordVo = LearningWordVo(userVo, lw.addTime, lw.addDay, lw.lastLearningDate, lw.learningOrder, lw.learnedTimes, wordVo,
            lw.batchId, lw.stability, lw.difficulty, lw.elapsedDays, lw.scheduledDays, lw.reps, lw.lapses, lw.state);
        learningWordVos.add(learningWordVo);
      }
    }
    final result = PagedResults<LearningWordVo>(total);
    result.rows = learningWordVos;
    return result;
  }

  Future<PagedResults<MasteredWordVo>> getMasteredWordsForAPage(int fromIndex, int pageSize) async {
    try {
      final results = PagedResults<MasteredWordVo>(0);
      final db = MyDatabase.instance;
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        return results;
      }

      // 从"已掌握"总集中获取所有单词
      final allMasteredWords = await db.masteredWordsDao.getMasteredWordsForUser(userId);

      results.total = allMasteredWords.length;
      // 手动分页
      final pagedEntries = allMasteredWords.skip(fromIndex).take(pageSize).toList();
      if (pagedEntries.isEmpty) {
        return results;
      }
      final wordIds = pagedEntries.map((dw) => dw.wordId).toList();
      final wordQuery = db.select(db.words)..where((w) => w.id.isIn(wordIds));
      final wordEntries = await wordQuery.get();
      final wordMap = {for (var word in wordEntries) word.id: word};
      // 使用 getWordMeaningItems 方法进行词书过滤
      final meaningItemsMap = <String, List<MeaningItem>>{};
      for (final wordId in wordIds) {
        final meaningItems = await getWordMeaningItems(wordId, userId);
        if (meaningItems.isNotEmpty) {
          meaningItemsMap[wordId] = meaningItems;
        }
      }
      for (var dictWord in pagedEntries) {
        final wordEntry = wordMap[dictWord.wordId];
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
              return MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null);
            }).toList();
          }
          wordVo.meaningItems = meaningItemVos;
          final userVo = UserVo.c2(userId);
          results.rows.add(MasteredWordVo(userVo, wordVo, dictWord.createTime));
        }
      }
      return results;
    } catch (e) {
      Global.logger.e("获取已掌握单词失败: $e");
      return PagedResults<MasteredWordVo>(0);
    }
  }

  Future<PagedResults<DictWordVo>> getDictWordsForAPage(String dictId, int fromIndex, int pageSize) async {
    try {
      // 获取词典单词总数
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
        ..orderBy([(t) => OrderingTerm(expression: t.unit), (t) => OrderingTerm(expression: t.seq)])
        ..limit(pageSize, offset: fromIndex);
      final dictWordEntries = await dictWordQuery.get();
      if (dictWordEntries.isEmpty) {
        return results;
      }
      final wordIds = dictWordEntries.map((dw) => dw.wordId).toList();
      final wordQuery = db.select(db.words)..where((w) => w.id.isIn(wordIds));
      final wordEntries = await wordQuery.get();
      final wordMap = {for (var word in wordEntries) word.id: word};

      final queryDictIds = [dictId];
      final currDict = await db.dictsDao.findById(dictId);
      if (currDict != null && currDict.baseDictId != null && currDict.baseDictId!.isNotEmpty) {
        queryDictIds.add(currDict.baseDictId!);
      }

      // 1) 先取本词书(dictId)或其基础词书的定制释义
      final dictSpecificMeaningQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.isIn(wordIds) & mi.dictId.isIn(queryDictIds))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final dictSpecificMeaningItems = await dictSpecificMeaningQuery.get();
      final meaningItemsMap = <String, List<MeaningItem>>{};
      for (final mi in dictSpecificMeaningItems) {
        (meaningItemsMap[mi.wordId] ??= []).add(mi);
      }

      // 2) 对没有定制释义的单词，回退到通用释义，并按本词书的 popularityLimit 进行过滤
      final wordsWithoutCustom =
          wordIds.where((wordId) => !meaningItemsMap.containsKey(wordId) || (meaningItemsMap[wordId]?.isEmpty ?? true)).toList();
      int? popularityLimit;
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
      final sentencesMap = await _loadSentencesMap(selectedMeaningItemIds);
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
                  final sentenceVo =
                      SentenceVo(s.id, s.english, s.chinese, s.englishDigest, s.partOfSpeech, s.theType, s.footCount, s.handCount, author);
                  sentenceVo.wordMeaning = s.wordMeaning;
                  sentenceVos.add(sentenceVo);
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
    await MyDatabase.instance.masteredWordsDao.deleteMasteredWord(userId, wordId, true, true);
    final result = Result<dynamic>('200', null, true);
    return result;
  }

  Future<Result<int>> getDictWordOrder(String dictId, String spell) async {
    try {
      Global.logger.d('开始本地查询词典单词位置: dictId=$dictId, spell=$spell');
      final db = MyDatabase.instance;
      final wordQuery = db.select(db.words)..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final dictWordQuery = db.select(db.dictWords)..where((tbl) => tbl.dictId.equals(dictId) & tbl.wordId.equals(word.id));
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

  /// 获取用户自定义词典列表
  Future<List<DictVo>> getCustomDicts(String ownerId) async {
    final db = MyDatabase.instance;
    final dicts = await (db.select(db.dicts)
          ..where((d) => d.ownerId.equals(ownerId))
          ..orderBy([(d) => OrderingTerm.desc(d.createTime)]))
        .get();

    // 获取每个词典的实际单词数量，并同步到dict表
    final List<DictVo> results = [];
    for (final d in dicts) {
      final countQuery = db.selectOnly(db.dictWords)
        ..addColumns([countAll()])
        ..where(db.dictWords.dictId.equals(d.id));
      final countResult = await countQuery.getSingle();
      final actualCount = countResult.read(countAll()) ?? 0;

      // 如果dict表中的wordCount与实际不一致，同步更新
      if (d.wordCount != actualCount) {
        await db.dictsDao.updateWordCount(d.id, true);
      }

      results.add(DictVo.c2(d.id)
        ..name = d.name
        ..wordCount = actualCount
        ..isReady = d.isReady
        ..isShared = d.isShared
        ..visible = d.visible
        ..domain = d.domain
        ..owner = UserVo.c2(d.ownerId)
        ..canDelete = d.deletable
        ..canRename = d.deletable);
    }
    return results;
  }

  /// 创建自定义词典
  Future<Result<String>> createCustomDict(String name, String ownerId) async {
    final db = MyDatabase.instance;
    try {
      // 检查重名
      final existing = await (db.select(db.dicts)..where((d) => d.ownerId.equals(ownerId) & d.name.equals(name))).getSingleOrNull();
      if (existing != null) {
        return Result("ERROR", "已存在同名词典", false);
      }

      final id = Util.uuid();
      final now = AppClock.now();
      final dict = Dict(
        id: id,
        isReady: true,
        isShared: false,
        name: name,
        wordCount: 0,
        ownerId: ownerId,
        visible: true,
        editable: true,
        deletable: true,
        createTime: now,
        updateTime: now,
      );

      await db.into(db.dicts).insert(dict);

      // 触发同步
      ThrottledDbSyncService().requestSync();

      return Result<String>("SUCCESS", "创建成功", true)..data = id;
    } catch (e, s) {
      Global.logger.e('创建词典失败: $e', stackTrace: s);
      return Result("ERROR", "创建失败: $e", false);
    }
  }

  /// 向自定义词典添加单词
  Future<Result> addWordToCustomDict(String dictId, String wordId) async {
    final db = MyDatabase.instance;
    try {
      final existing = await db.dictWordsDao.getById(dictId, wordId);
      if (existing != null) {
        return Result("ERROR", "单词已在词典中", false);
      }

      final now = AppClock.now();

      // 获取当前最大seq
      final maxSeqQuery = db.selectOnly(db.dictWords)
        ..addColumns([db.dictWords.seq.max()])
        ..where(db.dictWords.dictId.equals(dictId));
      final maxSeqResult = await maxSeqQuery.getSingle();
      final maxSeq = maxSeqResult.read(db.dictWords.seq.max()) ?? 0;

      final dictWord = DictWord(
        dictId: dictId,
        wordId: wordId,
        seq: maxSeq + 1,
        unit: 0,
        createTime: now,
        updateTime: now,
      );

      await db.transaction(() async {
        await db.dictWordsDao.insertEntity(dictWord, true);
        await db.dictsDao.updateWordCount(dictId, true);
      });

      // 触发同步
      ThrottledDbSyncService().requestSync();

      return Result("SUCCESS", "添加成功", true);
    } catch (e, s) {
      Global.logger.e('添加单词失败: $e', stackTrace: s);
      return Result("ERROR", "添加失败: $e", false);
    }
  }

  /// 更新自定义词典中单词的释义
  /// 用户输入的每个 MeaningUpdateItem.meaning 可以包含多个释义，用分号分隔
  /// 例如: MeaningUpdateItem(ciXing: "n.", meaning: "脸,脸面;面对") 会产生2个释义项
  Future<Result> updateMeaningForCustomDict(String dictId, String wordId, List<MeaningUpdateItem> meanings) async {
    final db = MyDatabase.instance;
    try {
      final now = AppClock.now();
      final userId = Global.getLoggedInUser()?.id;

      await db.transaction(() async {
        // 1. 查询并删除现有定制释义
        final existingQuery = db.select(db.meaningItems)..where((mi) => mi.wordId.equals(wordId) & mi.dictId.equals(dictId));
        final existingItems = await existingQuery.get();

        // 记录删除日志
        for (final item in existingItems) {
          if (userId != null) {
            await DbLogUtil.logOperation(userId, 'DELETE', 'meaningItems', item.id, item);
          }
        }

        // 删除现有定制释义
        await (db.delete(db.meaningItems)..where((mi) => mi.wordId.equals(wordId) & mi.dictId.equals(dictId))).go();

        // 2. 解析用户输入，创建新的释义项
        // 按分号分隔(支持中文和英文分号)
        final semicolonRegex = RegExp(r'[;；]');
        int popularity = 1;

        // 用于去重 (ciXing + meaning 的组合)
        Set<String> seen = {};

        for (final item in meanings) {
          final cixing = item.ciXing;
          final meaningText = item.meaning;

          if (meaningText.isEmpty) continue;

          // 按分号分割
          final parts = meaningText.split(semicolonRegex);

          for (final part in parts) {
            final trimmed = part.trim();
            if (trimmed.isEmpty) continue;

            // 去重
            final key = '$cixing|$trimmed';
            if (seen.contains(key)) continue;
            seen.add(key);

            final newId = Util.uuid();
            final newItem = MeaningItem(
              id: newId,
              wordId: wordId,
              dictId: dictId,
              ciXing: cixing,
              meaning: trimmed,
              popularity: popularity++,
              ownerId: userId!,
              createTime: now,
              updateTime: now,
            );
            await db.meaningItemsDao.insertEntity(newItem, true);
          }
        }
      });

      // 触发同步
      Future.delayed(Duration.zero, () {
        ThrottledDbSyncService().requestSync();
      });

      return Result("SUCCESS", "更新成功", true);
    } catch (e, s) {
      Global.logger.e('更新释义失败: $e', stackTrace: s);
      return Result("ERROR", "更新失败: $e", false);
    }
  }

  /// 删除自定义词典中单词的定制释义，恢复为通用释义
  Future<Result> deleteMeaningForCustomDict(String dictId, String wordId) async {
    final db = MyDatabase.instance;
    try {
      // 先查询现有定制释义，用于记录删除日志
      final existingQuery = db.select(db.meaningItems)..where((mi) => mi.wordId.equals(wordId) & mi.dictId.equals(dictId));
      final existingItems = await existingQuery.get();

      // 记录删除日志
      for (final item in existingItems) {
        final userId = Global.getLoggedInUser()?.id;
        if (userId != null) {
          await DbLogUtil.logOperation(userId, 'DELETE', 'meaningItems', item.id, item);
        }
      }

      // 删除定制释义
      await (db.delete(db.meaningItems)..where((mi) => mi.wordId.equals(wordId) & mi.dictId.equals(dictId))).go();

      // 触发同步
      Future.delayed(Duration.zero, () {
        ThrottledDbSyncService().requestSync();
      });

      return Result("SUCCESS", "已恢复默认释义", true);
    } catch (e, s) {
      Global.logger.e('删除定制释义失败: $e', stackTrace: s);
      return Result("ERROR", "操作失败: $e", false);
    }
  }

  /// 删除自定义词典
  Future<Result> deleteCustomDict(String dictId) async {
    final db = MyDatabase.instance;
    try {
      await db.transaction(() async {
        // 先查询现有定制释义，用于记录删除日志
        final existingMeaningQuery = db.select(db.meaningItems)..where((mi) => mi.dictId.equals(dictId));
        final existingMeaningItems = await existingMeaningQuery.get();

        // 记录删除日志
        for (final item in existingMeaningItems) {
          final userId = Global.getLoggedInUser()?.id;
          if (userId != null) {
            await DbLogUtil.logOperation(userId, 'DELETE', 'meaningItems', item.id, item);
          }
        }

        // 删除定制释义
        await (db.delete(db.meaningItems)..where((mi) => mi.dictId.equals(dictId))).go();
        // 删除关联的单词
        await db.dictWordsDao.clearDictWord(dictId, true);
        // 删除词典
        final dict = await db.dictsDao.findById(dictId);
        if (dict != null) {
          await (db.delete(db.dicts)..where((d) => d.id.equals(dictId))).go();
          await DbLogUtil.logOperation(dict.ownerId, 'DELETE', 'dicts', dictId, dict);
        }
      });
      ThrottledDbSyncService().requestSync();
      return Result("SUCCESS", "删除成功", true);
    } catch (e, s) {
      Global.logger.e('删除词典失败: $e', stackTrace: s);
      return Result("ERROR", "删除失败: $e", false);
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
      final wordQuery = db.select(db.words)..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)..where((tbl) => tbl.userId.equals(userId) & tbl.wordId.equals(word.id));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('用户未在学习单词 $spell');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final beforeTimeCondition = db.learningWords.addTime.isSmallerThanValue(learningWord.addTime);
      final sameTimeSmallerWordIdCondition =
          db.learningWords.addTime.equals(learningWord.addTime) & db.learningWords.wordId.isSmallerThanValue(learningWord.wordId);
      countQuery.where(userIdCondition & (beforeTimeCondition | sameTimeSmallerWordIdCondition));
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
    final order = await MyDatabase.instance.masteredWordsDao.getMasteredWordOrder(userId, spell);
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
      final wordQuery = db.select(db.words)..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)
        ..where((tbl) => tbl.userId.equals(userId) & tbl.wordId.equals(word.id) & tbl.batchId.isBiggerThanValue(0));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('单词 $spell 不在今日单词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final wordCondition = db.learningWords.batchId.isBiggerThanValue(0);
      final beforeOrderCondition = db.learningWords.learningOrder.isSmallerThanValue(learningWord.learningOrder);
      countQuery.where(userIdCondition & wordCondition & beforeOrderCondition);
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
      final wordQuery = db.select(db.words)..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final wrongWordQuery = db.select(db.userWrongWords)..where((tbl) => tbl.userId.equals(userId) & tbl.wordId.equals(word.id));
      final wrongWord = await wrongWordQuery.getSingleOrNull();
      if (wrongWord == null) {
        Global.logger.d('单词 $spell 不在错词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.userWrongWords)
        ..addColumns([countAll()])
        ..where(db.userWrongWords.userId.equals(userId) & db.userWrongWords.createTime.isSmallerOrEqualValue(wrongWord.createTime));
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
      final wordQuery = db.select(db.words)..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)
        ..where((tbl) => tbl.userId.equals(userId) & tbl.wordId.equals(word.id) & tbl.isTodayNewWord.equals(true) & tbl.batchId.isBiggerThanValue(0));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('单词 $spell 不在今日新词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final isNewWordCondition = db.learningWords.isTodayNewWord.equals(true);
      final batchCondition = db.learningWords.batchId.isBiggerThanValue(0);
      final beforeOrderCondition = db.learningWords.learningOrder.isSmallerThanValue(learningWord.learningOrder);
      countQuery.where(userIdCondition & isNewWordCondition & batchCondition & beforeOrderCondition);
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
      final wordQuery = db.select(db.words)..where((tbl) => tbl.spell.equals(spell));
      final word = await wordQuery.getSingleOrNull();
      if (word == null) {
        Global.logger.d('未找到拼写为 $spell 的单词');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final learningWordQuery = db.select(db.learningWords)
        ..where(
            (tbl) => tbl.userId.equals(userId) & tbl.wordId.equals(word.id) & tbl.isTodayNewWord.equals(false) & tbl.batchId.isBiggerThanValue(0));
      final learningWord = await learningWordQuery.getSingleOrNull();
      if (learningWord == null) {
        Global.logger.d('单词 $spell 不在今日旧词列表中');
        return Result("SUCCESS", "获取成功", true)..data = -1;
      }
      final countQuery = db.selectOnly(db.learningWords)..addColumns([countAll()]);
      final userIdCondition = db.learningWords.userId.equals(userId);
      final isOldWordCondition = db.learningWords.isTodayNewWord.equals(false);
      final batchCondition = db.learningWords.batchId.isBiggerThanValue(0);
      final beforeOrderCondition = db.learningWords.learningOrder.isSmallerThanValue(learningWord.learningOrder);
      countQuery.where(userIdCondition & isOldWordCondition & batchCondition & beforeOrderCondition);
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
            ((tbl.createTime.isBiggerOrEqualValue(startOfDay) & tbl.createTime.isSmallerOrEqualValue(endOfDay)) |
                (tbl.updateTime.isBiggerOrEqualValue(startOfDay) & tbl.updateTime.isSmallerOrEqualValue(endOfDay))))
        ..orderBy([
          (tbl) => OrderingTerm(expression: coalesce([tbl.updateTime, tbl.createTime]), mode: OrderingMode.desc)
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
          // 使用 getWordMeaningItems 方法进行词书过滤
          final meaningItems = await getWordMeaningItems(word.id, userId);
          List<MeaningItemVo> meaningItemVos = [];
          for (final mi in meaningItems) {
            meaningItemVos.add(MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null));
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
        sentence.partOfSpeech,
        sentence.theType,
        sentence.footCount,
        sentence.handCount,
        authorVo,
      );
      sentenceVo.wordMeaning = sentence.wordMeaning;
      Global.logger.d('获取句子成功: sentenceId=$sentenceId');
      return sentenceVo;
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '获取句子数据', showToast: false);
      rethrow;
    }
  }

  Future<Result<void>> removeWordFromDict(String dictId, String wordId, String userId) async {
    try {
      Global.logger.d('开始从词典删除单词: dictId=$dictId, wordId=$wordId, userId=$userId');
      final db = MyDatabase.instance;
      final dict = await db.dictsDao.findById(dictId);
      if (dict == null) {
        return Result("ERROR", "词典不存在", false);
      }
      final user = await db.usersDao.getUserById(userId);
      if (user == null) {
        return Result("ERROR", "用户不存在", false);
      }
      if (dict.ownerId != user.id && !(user.isInputor ?? false)) {
        return Result("ERROR", "你只能编辑自己的词书", false);
      }
      final dictWord = await db.dictWordsDao.getById(dictId, wordId);
      if (dictWord == null) {
        return Result("ERROR", "词书中无该单词", false);
      }

      await db.transaction(() async {
        await db.dictWordsDao.deleteDictWordWithCleanup(dictId, wordId, userId, true);
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
      dict.domain = rawWordDict.domain;
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
        ..where((db.userWrongWords.createTime.isBiggerOrEqualValue(startOfDay) & db.userWrongWords.createTime.isSmallerOrEqualValue(endOfDay)) |
            (db.userWrongWords.updateTime.isBiggerOrEqualValue(startOfDay) & db.userWrongWords.updateTime.isSmallerOrEqualValue(endOfDay)));
      final wrongWordsCount = await wrongWordsQuery.getSingle();
      wordLists.add(WordList("今日错词", wrongWordsCount.read(countAll()) ?? 0));
      final newWordsQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id))
        ..where(db.learningWords.isTodayNewWord.equals(true))
        ..where(db.learningWords.batchId.isBiggerThanValue(0));
      final newWordsCount = await newWordsQuery.getSingle();
      wordLists.add(WordList("今日新词", newWordsCount.read(countAll()) ?? 0));
      final oldWordsQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id))
        ..where(db.learningWords.isTodayNewWord.equals(false))
        ..where(db.learningWords.batchId.isBiggerThanValue(0));
      final oldWordsCount = await oldWordsQuery.getSingle();
      wordLists.add(WordList("今日旧词", oldWordsCount.read(countAll()) ?? 0));
      final todayWordsQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id))
        ..where(db.learningWords.batchId.isBiggerThanValue(0));
      final totalWordsCount = await todayWordsQuery.getSingle();
      wordLists.add(WordList("今日单词", totalWordsCount.read(countAll()) ?? 0));
      // 获取全局学习中的单词数量
      final learningWordsCountQuery = db.selectOnly(db.learningWords)
        ..addColumns([countAll()])
        ..where(db.learningWords.userId.equals(user.id));

      final learningWordsCountResult = await learningWordsCountQuery.getSingle();
      wordLists.add(WordList("学习中", learningWordsCountResult.read(countAll()) ?? 0));

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

      // 获取全局已掌握单词数量
      final masteredWordIds = await db.masteredWordsDao.getMasteredWordIdSet(user.id);
      wordLists.add(WordList("已掌握", masteredWordIds.length));
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

  Future<PagedResults<LearningWordVo>> getTodayWordsForAPage(int fromIndex, int pageSize, String userId) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);
    if (user == null) {
      throw Exception('用户不存在');
    }
    // 注意：batchId 可能是 NULL（旧数据），只查询有 batchId 的记录
    final query = db.select(db.learningWords)
      ..where((tbl) => tbl.userId.equals(userId) & tbl.batchId.isBiggerThanValue(0))
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.batchId),
        (tbl) => OrderingTerm(expression: tbl.learningOrder),
      ])
      ..limit(pageSize, offset: fromIndex);
    final learningWords = await query.get();
    final countQuery = db.selectOnly(db.learningWords)
      ..addColumns([countAll()])
      ..where(db.learningWords.userId.equals(userId))
      ..where(db.learningWords.batchId.isBiggerThanValue(0));
    final countResult = await countQuery.getSingle();
    final total = countResult.read(countAll()) ?? 0;
    List<LearningWordVo> learningWordVos = [];
    for (final lw in learningWords) {
      final word = await db.wordsDao.getWordById(lw.wordId);
      if (word != null) {
        final userVo = UserVo.c2(userId);
        userVo.level = LevelUtil.getLevelVoByWordCount(user.masteredWordsCount);
        final wordVo = WordVo.c2(word.spell)
          ..id = word.id
          ..shortDesc = word.shortDesc
          ..longDesc = word.longDesc
          ..pronounce = word.pronounce
          ..americaPronounce = word.americaPronounce
          ..britishPronounce = word.britishPronounce
          ..popularity = word.popularity;
        // 使用 getWordMeaningItems 方法进行词书过滤
        final meaningItems = await getWordMeaningItems(word.id, userId);
        List<MeaningItemVo> meaningItemVos = [];
        for (final mi in meaningItems) {
          meaningItemVos.add(MeaningItemVo(mi.id, mi.ciXing, mi.meaning, null, null, null));
        }
        wordVo.meaningItems = meaningItemVos;
        final learningWordVo = LearningWordVo(userVo, lw.addTime, lw.addDay, lw.lastLearningDate, lw.learningOrder, lw.learnedTimes, wordVo,
            lw.batchId, lw.stability, lw.difficulty, lw.elapsedDays, lw.scheduledDays, lw.reps, lw.lapses, lw.state);
        learningWordVos.add(learningWordVo);
      }
    }
    final result = PagedResults<LearningWordVo>(total);
    result.rows = learningWordVos;
    return result;
  }

  Future<Result> setLearningWordAsMastered(String userId, String wordId, bool deleteLearningWord) async {
    try {
      await MyDatabase.instance.masteredWordsDao.setLearningWordAsMastered(userId, wordId, deleteLearningWord);
      await MyDatabase.instance.masteredWordsDao.updateUserMasteredWordCount(userId);
      return Result("SUCCESS", "标记单词为已掌握成功", true);
    } catch (e) {
      Global.logger.e('本地化setLearningWordAsMastered失败: $e');
      return Result("ERROR", '标记单词为已掌握失败: $e', false);
    }
  }

  /// 获取单词的释义项，遵循如下规则：
  /// 0) 若提供了 priorityDictIds，则优先在这些词书中查找释义
  /// 1) 若单词在用户的任一学习词书中有定制释义，则返回这些定制释义的合集（不做 popularity 过滤）
  /// 2) 否则，使用通用释义，并按最大 popularity limit 进行过滤：
  ///    - 情况1：若该单词存在于用户的一个或多个学习词书中，则以这些词书中的最大 popularity limit 过滤
  ///    - 情况2：若该单词不在任何学习词书中，则以用户所有学习词书的最大 popularity limit 过滤
  Future<List<MeaningItem>> getWordMeaningItems(String wordId, String? userId, {List<String>? priorityDictIds}) async {
    final db = MyDatabase.instance;

    // 先查优先词书（严格排他性查询：若优先词库内有内容，则不再合并父级/通用词库资源，以确保查看到的确实是该词书专有的资源）
    if (priorityDictIds != null && priorityDictIds.isNotEmpty) {
      final priorityMiQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.equals(wordId) & mi.dictId.isIn(priorityDictIds))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final priorityMeaningItems = await priorityMiQuery.get();
      if (priorityMeaningItems.isNotEmpty) {
        return priorityMeaningItems;
      }

      // 如果优先词书里没有，再尝试展开查找其父级词库（如通用词库）
      final expandedPriorityDictIds = <String>{...priorityDictIds};
      final dbDicts = await (db.select(db.dicts)..where((d) => d.id.isIn(priorityDictIds))).get();
      for (final d in dbDicts) {
        if (d.baseDictId != null && d.baseDictId!.isNotEmpty) {
          expandedPriorityDictIds.add(d.baseDictId!);
        }
      }

      final expandedMiQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.equals(wordId) & mi.dictId.isIn(expandedPriorityDictIds))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final expandedMeaningItems = await expandedMiQuery.get();
      if (expandedMeaningItems.isNotEmpty) {
        return expandedMeaningItems;
      }
    }

    // 用户的学习词书
    List<String> selectedDictIds = [];
    if (userId != null && userId.isNotEmpty) {
      final learningDictsQuery = db.select(db.learningDicts)..where((tbl) => tbl.userId.equals(userId));
      final learningDicts = await learningDictsQuery.get();
      selectedDictIds = learningDicts.map((d) => d.dictId).toList();

      if (selectedDictIds.isNotEmpty) {
        final expandedDictIds = <String>{...selectedDictIds};
        final dbDicts = await (db.select(db.dicts)..where((d) => d.id.isIn(selectedDictIds))).get();
        for (final d in dbDicts) {
          if (d.baseDictId != null && d.baseDictId!.isNotEmpty) {
            expandedDictIds.add(d.baseDictId!);
          }
        }
        selectedDictIds = expandedDictIds.toList();

        // 先查定制释义（存在即返回）
        final customMiQuery = db.select(db.meaningItems)
          ..where((mi) => mi.wordId.equals(wordId) & mi.dictId.isIn(selectedDictIds))
          ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
        final customMeaningItems = await customMiQuery.get();
        if (customMeaningItems.isNotEmpty) {
          return customMeaningItems;
        }
      }
    }

    // 未找到定制释义 → 准备过滤通用释义
    final commonDictQuery = db.select(db.meaningItems)
      ..where((mi) => mi.wordId.equals(wordId) & mi.dictId.equals(Global.commonDictId))
      ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
    final commonMeaningItems = await commonDictQuery.get();
    if (commonMeaningItems.isEmpty) {
      // 正常情况下通用释义不应为空，视为数据异常
      Global.logger.e('通用释义缺失: wordId=$wordId');
      throw Exception('通用释义缺失: $wordId');
    }

    // 计算最大 popularity limit
    int? maxPopularityLimit;

    // 检查该单词是否存在于用户的学习词书中（dictWords）
    List<String> relatedDictIds = [];
    if (selectedDictIds.isNotEmpty) {
      final dwQuery = db.select(db.dictWords)..where((dw) => dw.wordId.equals(wordId) & dw.dictId.isIn(selectedDictIds));
      final dictWords = await dwQuery.get();
      relatedDictIds = dictWords.map((e) => e.dictId).toList();
    }

    // 情况1：在学习词书中存在该单词 → 取这些词书的最大 limit
    // 情况2：否则 → 取所有学习词书的最大 limit
    final targetDictIds = relatedDictIds.isNotEmpty ? relatedDictIds : selectedDictIds;
    if (targetDictIds.isNotEmpty) {
      for (final dictId in targetDictIds) {
        final dict = await db.dictsDao.findById(dictId);
        if (dict == null) continue;
        final limit = dict.popularityLimit;
        if (limit == null) {
          // null 视为不限制 → 等价于无限大
          maxPopularityLimit = null;
          break;
        }
        if (maxPopularityLimit == null || limit > maxPopularityLimit) {
          maxPopularityLimit = limit;
        }
      }
    } else {
      // 用户没有学习词书 → 不做限制
      maxPopularityLimit = null;
    }

    // 按最大 popularity limit 过滤通用释义
    if (maxPopularityLimit == null) {
      return commonMeaningItems;
    }
    final intLimit = maxPopularityLimit;
    return commonMeaningItems.where((mi) => mi.popularity <= intLimit).toList();
  }

  /// 提供给UI：根据 wordId 和 userId 获取释义项（封装内部的 popularity limit 逻辑）
  Future<List<MeaningItemVo>> getMeaningItemsForWord(String wordId, String userId) async {
    final items = await getWordMeaningItems(wordId, userId);
    return items.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
  }

  Future<Result<int>> getLearningWordInBucketOrder(String spell, int bucketKey, String userId) async {
    final results = await getLearningWordsByBucketForAPage(bucketKey, 0, 100000, userId);
    for (int i = 0; i < results.rows.length; i++) {
       if (results.rows[i].word.spell == spell) {
         return Result("SUCCESS", "获取成功", true)..data = i + 1;
       }
    }
    return Result("ERROR", "未找到单词", false);
  }
}
