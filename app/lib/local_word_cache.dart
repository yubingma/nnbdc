import 'dart:async' show Future;
import 'dart:async';

import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/util/error_handler.dart';

import 'api/vo.dart';

class LocalWordCache {
  static LocalWordCache instance = LocalWordCache();

  LocalWordCache();

  bool _isTargetSpell(String spell) {
    final s = spell.toLowerCase().trim();
    return s == 'in (the) light of';
  }

  /// 单词与内容（中文或英文）的模糊匹配
  /// startWithCount 是否必须以指定内容开头（仅作用于英文）
  bool fuzzyMatch(WordVo wordVo, String content, bool startWithCount) {
    var spell2 = wordVo.spell.toLowerCase();
    var content2 = content.toLowerCase();
    if (startWithCount) {
      var match = spell2.startsWith(content2);
      if (match) {
        return true;
      }
    } else {
      var match = !spell2.startsWith(content2) && spell2.contains(content2);
      if (match) {
        return true;
      }
      if (!Util.isEnglish(content2)) {
        if (wordVo.getMeaningStr().contains(content2)) {
          return true;
        }
      }
    }
    return false;
  }

  // 根据英文或中文在本地数据库中模糊搜索 - 性能优化版本
  Future<List<WordVo>> fuzzySearchWord(String content) async {
    try {
      final db = MyDatabase.instance;
      final currentUser = Global.getLoggedInUser();

      // 如果搜索内容为空，返回空列表
      if (content.trim().isEmpty) {
        return [];
      }

      final searchContent = content.toLowerCase();
      final isEnglish = Util.isEnglish(content);

      // 收集所有匹配的单词ID和对应的Word对象
      final Map<String, Word> allWords = {};
      final List<String> orderedWordIds = [];

      // 1. 拼写匹配搜索（以输入内容开头） - 优先级最高
      final startWithQuery = db.select(db.words)
        ..where((w) => w.spell.like('$searchContent%'))
        ..orderBy([(w) => OrderingTerm(expression: w.spell)])
        ..limit(20);

      final startWithWords = await startWithQuery.get();
      for (final word in startWithWords) {
        if (!allWords.containsKey(word.id)) {
          allWords[word.id] = word;
          orderedWordIds.add(word.id);
        }
      }

      // 2. 包含匹配搜索（如果结果不足）
      if (allWords.length < 30) {
        final containsQuery = db.select(db.words)
          ..where((w) => w.spell.like('%$searchContent%') & w.spell.like('$searchContent%').not())
          ..orderBy([(w) => OrderingTerm(expression: w.spell)])
          ..limit(30 - allWords.length);

        final containsWords = await containsQuery.get();
        for (final word in containsWords) {
          if (!allWords.containsKey(word.id)) {
            allWords[word.id] = word;
            orderedWordIds.add(word.id);
          }
        }
      }

      // 目标词调试：是否进入候选集
      try {
        final hit = allWords.values.any((w) => _isTargetSpell(w.spell));
        if (hit) {
          Global.logger.d('[LocalWordCache] 搜索命中目标词，候选数=${allWords.length}, orderedWordIds=${orderedWordIds.length}');
        }
      } catch (e, stackTrace) {
        // 搜索命中检测失败不影响搜索结果，但需要记录
        Global.logger.w('搜索命中检测失败', error: e, stackTrace: stackTrace);
      }

      // 3. 中文释义匹配搜索（如果是中文搜索且结果不足）
      if (!isEnglish && allWords.length < 30) {
        final meaningQuery = db.select(db.meaningItems)
          ..where((mi) => mi.meaning.like('%$content%'))
          ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)])
          ..limit(30 - allWords.length);

        final meaningItems = await meaningQuery.get();
        final meaningWordIds = meaningItems.map((mi) => mi.wordId).toSet();

        if (meaningWordIds.isNotEmpty) {
          final wordsQuery = db.select(db.words)
            ..where((w) => w.id.isIn(meaningWordIds.toList()))
            ..orderBy([(w) => OrderingTerm(expression: w.spell)]);

          final wordsFromMeaning = await wordsQuery.get();
          for (final word in wordsFromMeaning) {
            if (!allWords.containsKey(word.id)) {
              allWords[word.id] = word;
              orderedWordIds.add(word.id);
              if (allWords.length >= 30) break;
            }
          }
        }
      }

      // 如果没有找到任何单词，直接返回
      if (allWords.isEmpty) {
        return [];
      }

      // 批量构建WordVo对象
      return await _batchBuildWordVos(allWords, orderedWordIds, currentUser?.id);
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '本地搜索单词', showToast: false); // 搜索失败不显示toast，返回空列表即可
      return [];
    }
  }

  /// 批量构建WordVo对象 - 大幅提升性能
  Future<List<WordVo>> _batchBuildWordVos(Map<String, Word> wordsMap, List<String> orderedWordIds, String? userId) async {
    try {
      final db = MyDatabase.instance;
      final wordIds = orderedWordIds;

      // 获取用户选择的词书ID列表（如果用户已登录）
      List<String> selectedDictIds = [];
      if (userId != null) {
        final learningDictsQuery = db.select(db.learningDicts)..where((tbl) => tbl.userId.equals(userId));
        final learningDicts = await learningDictsQuery.get();
        selectedDictIds = learningDicts.map((d) => d.dictId).toList();
      }

      // 目标词调试：记录构建前的上下文
      for (final w in wordsMap.values) {
        if (_isTargetSpell(w.spell)) {
          Global.logger.d('[LocalWordCache] 构建VO，目标词 wordId=${w.id}, spell=${w.spell}, selectedDictIds=$selectedDictIds');
          break;
        }
      }

      // 批量查询所有相关的释义项
      Map<String, List<MeaningItem>> wordMeanings = {};

      if (selectedDictIds.isNotEmpty) {
        // 查询用户选择词书的释义项
        final userMeaningQuery = db.select(db.meaningItems)
          ..where((mi) => mi.wordId.isIn(wordIds) & mi.dictId.isIn(selectedDictIds))
          ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
        final userMeanings = await userMeaningQuery.get();

        for (final meaning in userMeanings) {
          if (!wordMeanings.containsKey(meaning.wordId)) {
            wordMeanings[meaning.wordId] = [];
          }
          wordMeanings[meaning.wordId]!.add(meaning);
        }
      }

      // 查询通用词典释义项（作为备选）
      final commonMeaningQuery = db.select(db.meaningItems)
        ..where((mi) => mi.wordId.isIn(wordIds) & mi.dictId.equals(Global.commonDictId))
        ..orderBy([(mi) => OrderingTerm(expression: mi.popularity)]);
      final commonMeanings = await commonMeaningQuery.get();

      // 如果用户有选择词书，查询这些词书的popularityLimit配置
      Map<String, int?> dictPopularityLimits = {};
      if (selectedDictIds.isNotEmpty && userId != null) {
        // 查询用户选择的词书列表
        final learningDictsQuery = db.select(db.learningDicts)..where((tbl) => tbl.userId.equals(userId));
        final learningDicts = await learningDictsQuery.get();
        
        // 为每个选择的词书查询其popularityLimit
        for (final learningDict in learningDicts) {
          final dict = await db.dictsDao.findById(learningDict.dictId);
          if (dict != null) {
            dictPopularityLimits[dict.id] = dict.popularityLimit;
          }
        }
      }

      for (final meaning in commonMeanings) {
        // 只有当该单词没有用户词书定制释义时，才使用通用释义
        if (!wordMeanings.containsKey(meaning.wordId)) {
          wordMeanings[meaning.wordId] = [];
        }
        if (wordMeanings[meaning.wordId]!.isEmpty) {
          // 检查是否需要过滤通用释义
          bool shouldInclude = true;
          
          // 如果有词书配置了popularityLimit，需要检查
          if (dictPopularityLimits.isNotEmpty) {
            // 检查是否有任何一个词书设置了popularityLimit
            final anyLimit = dictPopularityLimits.values.where((limit) => limit != null).isNotEmpty;
            if (anyLimit) {
              // 获取popularity值，如果为null则使用999作为默认值
              final int popularity = meaning.popularity;
              
              // 检查是否所有词书的popularityLimit都允许该释义
              // 如果有任何一个词书的limit允许该释义，则包含
              shouldInclude = false;
              for (final limit in dictPopularityLimits.values) {
                if (limit == null) {
                  // null表示不限制，允许显示
                  shouldInclude = true;
                  break;
                } else if (popularity <= limit) {
                  // popularity <= limit 表示允许显示
                  shouldInclude = true;
                  break;
                }
              }
            }
          }
          
          if (shouldInclude) {
            wordMeanings[meaning.wordId]!.add(meaning);
          }
        }
      }

      // 目标词调试：记录该词的释义来源与数量
      for (final w in wordsMap.values) {
        if (_isTargetSpell(w.spell)) {
          final wm = wordMeanings[w.id] ?? const <MeaningItem>[];
          final int fromUserDict = wm.where((m) => m.dictId != Global.commonDictId).length;
          final int fromCommon = wm.where((m) => m.dictId == Global.commonDictId).length;
          Global.logger.d('[LocalWordCache] 目标词释义统计 wordId=${w.id}, 总=${wm.length}, 通用=$fromCommon, 用户词书=$fromUserDict');
          if (wm.isNotEmpty) {
            final first = wm.first;
            final String cixing = first.ciXing;
            final String meaning = first.meaning;
            final String dictId = first.dictId ?? '';
            Global.logger.d('[LocalWordCache] 目标词首条释义: ciXing=$cixing, meaning=$meaning, dictId=$dictId');
          }
          break;
        }
      }

      // 不再使用任意词典兜底：仅允许通用词典（dictId = '0'）作为兜底

      // 注意：不使用可替代拼写兜底，释义应由通用词典资源提供

      // 构建WordVo对象列表
      final List<WordVo> result = [];
      for (final wordId in orderedWordIds) {
        final word = wordsMap[wordId];
        if (word == null) continue;

        // 构建WordVo对象
        final wordVo = WordVo.c2(word.spell);
        wordVo.id = word.id;
        wordVo.shortDesc = word.shortDesc;
        wordVo.longDesc = word.longDesc;
        wordVo.pronounce = word.pronounce;
        wordVo.americaPronounce = word.americaPronounce;
        wordVo.britishPronounce = word.britishPronounce;
        wordVo.popularity = word.popularity;

        // 添加释义项
        final meanings = wordMeanings[wordId] ?? [];
        final meaningItemVos = meanings
            .map((mi) => MeaningItemVo(
                mi.id,
                mi.ciXing,
                mi.meaning,
                null, // dict
                null, // synonyms
                null // sentences
                ))
            .toList();

        wordVo.meaningItems = meaningItemVos;
        result.add(wordVo);
      }

      return result;
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, operation: '批量构建WordVo', showToast: false); // 内部处理失败不显示toast
      return [];
    }
  }
}
