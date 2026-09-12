import 'dart:math';

import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/util/word_form.dart';
import 'package:nnbdc/util/edit_distance.dart';
import 'package:drift/drift.dart' as drift;

abstract class DistractorStrategy {
  Future<List<WordVo>> getTwoOtherWords({
    required List<String> trackSteps,
    required int learningMode,
    required List<MeaningItemVo> meaningItemVos,
    required List<LearningWord> todayWords,
    required LearningWord targetWordLearningData,
    required MyDatabase db,
  });
}

class LearningWordsDistractorStrategy implements DistractorStrategy {
  @override
  Future<List<WordVo>> getTwoOtherWords({
    required List<String> trackSteps,
    required int learningMode,
    required List<MeaningItemVo> meaningItemVos,
    required List<LearningWord> todayWords,
    required LearningWord targetWordLearningData,
    required MyDatabase db,
  }) async {
    try {
      List<WordVo> otherWords = [];
      if ([StudyStep.en2Ch.json, StudyStep.ch2En.json].contains(trackSteps[learningMode])) {
        // 用于跟踪已选择的单词ID，避免重复
        final selectedWordIds = <String>{targetWordLearningData.wordId};
        final candidateIds = <String>[];
        
        String? targetCiXing;
        if (meaningItemVos.isNotEmpty && meaningItemVos.first.ciXing != null) {
          targetCiXing = meaningItemVos.first.ciXing!;
        }

        // 1. 优先从今日的单词中取混淆词
        for (final word in todayWords) {
          if (!selectedWordIds.contains(word.wordId)) {
            candidateIds.add(word.wordId);
            selectedWordIds.add(word.wordId);
          }
        }

        // 2. 如果没取到满足要求的（凑不够15个做池子），再从“学习中”单词中去取
        if (candidateIds.length < 15) {
          final allLearningWordsQuery = db.select(db.learningWords)
            ..where((lw) => lw.userId.equals(targetWordLearningData.userId))
            ..orderBy([(tbl) => drift.OrderingTerm(expression: tbl.addTime, mode: drift.OrderingMode.desc)])
            ..limit(30);
          final allLearningWords = await allLearningWordsQuery.get();

          for (final lw in allLearningWords) {
            if (!selectedWordIds.contains(lw.wordId)) {
              candidateIds.add(lw.wordId);
              selectedWordIds.add(lw.wordId);
            }
          }
        }

        // 3. 如果还是取不到，跑到用户当前选择的词书全局范围去找
        if (candidateIds.length < 15) {
          final learningDicts = await db.learningDictsDao.getLearningDictsOfUser(targetWordLearningData.userId);
          if (learningDicts.isNotEmpty) {
            for (final ld in learningDicts) {
              final dictWordsQuery = db.select(db.dictWords)
                ..where((tbl) => tbl.dictId.equals(ld.dictId))
                ..limit(30);
              final dictWords = await dictWordsQuery.get();
              for (final dw in dictWords) {
                if (!selectedWordIds.contains(dw.wordId)) {
                  candidateIds.add(dw.wordId);
                  selectedWordIds.add(dw.wordId);
                }
              }
              if (candidateIds.length >= 15) break;
            }
          }
        }

        // 4. 如果仍然没有，就去通用词典找（words 全局表）
        if (candidateIds.length < 15) {
          try {
            final countQuery = db.customSelect('SELECT COUNT(*) as c FROM words');
            final countRow = await countQuery.getSingle();
            final count = countRow.read<int>('c');
            if (count > 15) {
              final randomOffset = Random().nextInt(count - 15);
              final wordsQuery = db.select(db.words)
                ..limit(15, offset: randomOffset);
              final globalWords = await wordsQuery.get();
              for (final w in globalWords) {
                if (!selectedWordIds.contains(w.id)) {
                  candidateIds.add(w.id);
                  selectedWordIds.add(w.id);
                }
              }
            } else {
              final wordsQuery = db.select(db.words)..limit(15);
              final globalWords = await wordsQuery.get();
              for (final w in globalWords) {
                if (!selectedWordIds.contains(w.id)) {
                  candidateIds.add(w.id);
                  selectedWordIds.add(w.id);
                }
              }
            }
          } catch (e) {
            // 降级原 random 排序，确保容错性
            final wordsQuery = db.select(db.words)
              ..orderBy([(t) => drift.OrderingTerm.random()])
              ..limit(15);
            final globalWords = await wordsQuery.get();
            for (final w in globalWords) {
              if (!selectedWordIds.contains(w.id)) {
                candidateIds.add(w.id);
                selectedWordIds.add(w.id);
              }
            }
          }
        }

        // 加载候选词详情，并优先匹配词性
        if (candidateIds.isNotEmpty) {
          // 随机打乱候选池，保证不固定
          candidateIds.shuffle();

          final wordsList = await db.wordsDao.getWordsByIds(candidateIds.take(15).toList());
          
          final List<Word> matchedWords = [];
          final List<Word> unmatchedWords = [];
          
          for (final wordDetails in wordsList) {
            bool isCiXingMatch = false;
            if (targetCiXing != null && wordDetails.shortDesc != null) {
              final shortDescLower = wordDetails.shortDesc!.toLowerCase();
              final targetLower = targetCiXing.toLowerCase();
              if (shortDescLower.startsWith('$targetLower.') || shortDescLower.contains(' $targetLower.')) {
                isCiXingMatch = true;
              }
            }
            
            if (isCiXingMatch) {
              matchedWords.add(wordDetails);
            } else {
              unmatchedWords.add(wordDetails);
            }
          }

          // 随机打乱两部分，优先挑词性一致的
          matchedWords.shuffle();
          unmatchedWords.shuffle();
          final List<Word> finalCandidates = [...matchedWords, ...unmatchedWords];
          
          // ⚡ 优化：不再使用 N+1 串行加载，而是提取最多 2 个目标候选词，并行进行加载
          final chosenCandidates = <Word>[];
          for (final wordDetails in finalCandidates) {
            chosenCandidates.add(wordDetails);
            if (chosenCandidates.length >= 2) break;
          }

          if (chosenCandidates.isNotEmpty) {
            final meaningResults = await Future.wait(chosenCandidates.map((wordDetails) async {
              final realMeaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
              return MapEntry(wordDetails, realMeaningItems);
            }));

            for (final entry in meaningResults) {
              final wordDetails = entry.key;
              final realMeaningItems = entry.value;
              final otherWordVo = WordVo.c2(wordDetails.spell)
                ..id = wordDetails.id
                ..shortDesc = wordDetails.shortDesc
                ..longDesc = wordDetails.longDesc
                ..pronounce = wordDetails.pronounce
                ..americaPronounce = wordDetails.americaPronounce
                ..britishPronounce = wordDetails.britishPronounce
                ..popularity = wordDetails.popularity
                ..meaningItems = realMeaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
              otherWords.add(otherWordVo);
            }
          }
        }

        // 最终极兜底
        if (otherWords.length < 2) {
          final int needed = 2 - otherWords.length;
          final excludeIds = selectedWordIds.toList()..add(targetWordLearningData.wordId);

          // ⚡ 优化：不再使用低效的数据库 ORDER BY random()，而是只加载前 50 个不重复单词，在内存中进行随机打乱
          final wordsQuery = db.select(db.words)
            ..where((tbl) => tbl.id.isNotIn(excludeIds))
            ..limit(50);

          final globalWords = await wordsQuery.get();
          final shufflableWords = List<Word>.from(globalWords)..shuffle();

          // 并行加载兜底单词的释义
          final chosenGlobalDetailsList = <Word>[];
          for (final wordDetails in shufflableWords) {
            chosenGlobalDetailsList.add(wordDetails);
            selectedWordIds.add(wordDetails.id);
            if (chosenGlobalDetailsList.length >= needed) break;
          }

          if (chosenGlobalDetailsList.isNotEmpty) {
            final globalMeaningResults = await Future.wait(chosenGlobalDetailsList.map((wordDetails) async {
              final realMeaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
              return MapEntry(wordDetails, realMeaningItems);
            }));

            for (final entry in globalMeaningResults) {
              final wordDetails = entry.key;
              final realMeaningItems = entry.value;
              final otherWordVo = WordVo.c2(wordDetails.spell)
                ..id = wordDetails.id
                ..shortDesc = wordDetails.shortDesc
                ..longDesc = wordDetails.longDesc
                ..pronounce = wordDetails.pronounce
                ..americaPronounce = wordDetails.americaPronounce
                ..britishPronounce = wordDetails.britishPronounce
                ..popularity = wordDetails.popularity
                ..meaningItems = realMeaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
              otherWords.add(otherWordVo);
            }
          }
        }
      }
      return otherWords;
    } catch (e, stackTrace) {
      Global.logger.e('Error in LearningWordsDistractorStrategy: $e', stackTrace: stackTrace);
      return [];
    }
  }
}

class ShapeSimilarDistractorStrategy implements DistractorStrategy {
  /// 一次最多取多少个候选词去查释义：要留出被"同词形 / 释义相同"筛掉的余量
  static const int _probeCount = 8;

  @override
  Future<List<WordVo>> getTwoOtherWords({
    required List<String> trackSteps,
    required int learningMode,
    required List<MeaningItemVo> meaningItemVos,
    required List<LearningWord> todayWords,
    required LearningWord targetWordLearningData,
    required MyDatabase db,
  }) async {
    try {
      final List<WordVo> otherWords = [];
      if (![StudyStep.en2Ch.json, StudyStep.ch2En.json].contains(trackSteps[learningMode])) {
        return otherWords;
      }

      // 获取当前目标单词的拼写
      final targetWords = await db.wordsDao.getWordsByIds([targetWordLearningData.wordId]);
      String targetSpell = '';
      if (targetWords.isNotEmpty) {
        targetSpell = targetWords.first.spell;
      }

      // 1. 收集候选：预设形近词中剔除"目标词自身的屈折变形"（confuse → confused/confusing），
      //    这类词的释义与目标词相同，选它用户无从判断
      final candidateIdToSpell = <String, String>{};
      final candidateIdToDistance = <String, int>{};
      final similarWordsQuery = db.select(db.similarWords)
        ..where((tbl) => tbl.wordId.equals(targetWordLearningData.wordId));
      final presetSimilarWords = await similarWordsQuery.get();
      for (final sw in presetSimilarWords) {
        _addCandidate(candidateIdToSpell, candidateIdToDistance, sw.similarWordId,
            sw.similarWordSpell, sw.distance, targetWordLearningData.wordId, targetSpell);
      }

      // 2. 动态形近词补充：【只有当预设形近词不足 2 个时】，才去动态查找邻近词补足
      if (candidateIdToSpell.length < 2 && targetSpell.isNotEmpty) {
        // 拼写更大的（向后取 50 个）
        final largerWordsQuery = db.select(db.words)
          ..where((tbl) => tbl.spell.isBiggerThanValue(targetSpell) & tbl.id.equals(targetWordLearningData.wordId).not())
          ..orderBy([(tbl) => drift.OrderingTerm(expression: tbl.spell)])
          ..limit(50);
        for (final w in await largerWordsQuery.get()) {
          final dist = EditDistance.forStrings(targetSpell.toLowerCase(), w.spell.toLowerCase());
          _addCandidate(candidateIdToSpell, candidateIdToDistance, w.id, w.spell, dist,
              targetWordLearningData.wordId, targetSpell);
        }

        // 拼写更小的（向前取 50 个）
        final smallerWordsQuery = db.select(db.words)
          ..where((tbl) => tbl.spell.isSmallerThanValue(targetSpell) & tbl.id.equals(targetWordLearningData.wordId).not())
          ..orderBy([(tbl) => drift.OrderingTerm(expression: tbl.spell, mode: drift.OrderingMode.desc)])
          ..limit(50);
        for (final w in await smallerWordsQuery.get()) {
          final dist = EditDistance.forStrings(targetSpell.toLowerCase(), w.spell.toLowerCase());
          _addCandidate(candidateIdToSpell, candidateIdToDistance, w.id, w.spell, dist,
              targetWordLearningData.wordId, targetSpell);
        }
      }

      // 3. 排序：学习范围内优先，同层内编辑距离更小优先（同组内随机打乱保持多样性）
      final candidateIds = candidateIdToSpell.keys.toList();
      final inScopeIds =
          await _loadInScopeWordIds(db, targetWordLearningData.userId, candidateIds);
      _orderCandidates(candidateIds, candidateIdToDistance, inScopeIds);

      // 4. 逐个查释义：跳过与目标词释义完全相同的候选（否则各选项释义相同、无从判断）
      final probeIds = candidateIds.take(_probeCount).toList();
      if (probeIds.isNotEmpty) {
        final wordsById = {for (final w in await db.wordsDao.getWordsByIds(probeIds)) w.id: w};
        final orderedWords = [
          for (final id in probeIds)
            if (wordsById[id] != null) wordsById[id]!,
        ];
        // ⚡ 释义加载并行化；单个候选缺释义时跳过该候选，不影响其余候选
        final probeResults = await Future.wait(orderedWords.map((wordDetails) async {
          try {
            final realMeaningItems =
                await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
            return MapEntry(wordDetails, _toMeaningItemVos(realMeaningItems));
          } catch (e) {
            Global.logger.w('形近词候选释义加载失败，跳过 ${wordDetails.spell}: $e');
            return null;
          }
        }));

        for (final entry in probeResults) {
          if (entry == null) continue;
          if (otherWords.length >= 2) break;
          if (_sharesMeaning(meaningItemVos, entry.value)) continue;
          otherWords.add(_buildWordVo(entry.key, entry.value));
        }
      }

      // 5. 如果不足 2 个，使用“学习中单词”策略补足（同样剔除变形词与同义项词）
      if (otherWords.length < 2) {
        final fallbackWords = await LearningWordsDistractorStrategy().getTwoOtherWords(
          trackSteps: trackSteps,
          learningMode: learningMode,
          meaningItemVos: meaningItemVos,
          todayWords: todayWords,
          targetWordLearningData: targetWordLearningData,
          db: db,
        );
        for (final fw in fallbackWords) {
          if (otherWords.length >= 2) break;
          // 确保不和目标单词重复，也不和已选单词重复
          if (fw.id == targetWordLearningData.wordId) continue;
          if (otherWords.any((w) => w.id == fw.id)) continue;
          if (targetSpell.isNotEmpty && isSameWordForm(targetSpell, fw.spell)) continue;
          if (_sharesMeaning(meaningItemVos, fw.meaningItems ?? const [])) continue;
          otherWords.add(fw);
        }
      }

      return otherWords;
    } catch (e, stackTrace) {
      Global.logger.e('Error in ShapeSimilarDistractorStrategy: $e', stackTrace: stackTrace);
      // 降级执行 LearningWords 策略
      return await LearningWordsDistractorStrategy().getTwoOtherWords(
        trackSteps: trackSteps,
        learningMode: learningMode,
        meaningItemVos: meaningItemVos,
        todayWords: todayWords,
        targetWordLearningData: targetWordLearningData,
        db: db,
      );
    }
  }

  /// 收录一个候选词；与目标词同拼写或同词形的屈折变形不入候选
  void _addCandidate(
    Map<String, String> candidateIdToSpell,
    Map<String, int> candidateIdToDistance,
    String wordId,
    String spell,
    int distance,
    String targetWordId,
    String targetSpell,
  ) {
    if (wordId == targetWordId) return;
    if (candidateIdToSpell.containsKey(wordId)) return;
    if (targetSpell.isNotEmpty && isSameWordForm(targetSpell, spell)) return;
    candidateIdToSpell[wordId] = spell;
    candidateIdToDistance[wordId] = distance;
  }

  /// 用户"学习范围"内的单词集合：所选学习词书（含父词库）收录的词，
  /// 以及已有学习记录的词（学习中 / 已掌握）——与详情页「学习范围」标注口径一致。
  Future<Set<String>> _loadInScopeWordIds(
      MyDatabase db, String userId, List<String> wordIds) async {
    if (wordIds.isEmpty) return {};
    final learningDicts = await db.learningDictsDao.getLearningDictsOfUser(userId);
    // 未选学习词书时与详情页一致：不作范围限制
    if (learningDicts.isEmpty) return wordIds.toSet();

    final inScope = <String>{};
    final dictIds = <String>{for (final d in learningDicts) d.dictId};
    final dicts = await (db.select(db.dicts)..where((d) => d.id.isIn(dictIds))).get();
    for (final d in dicts) {
      if (d.baseDictId != null && d.baseDictId!.isNotEmpty) {
        dictIds.add(d.baseDictId!);
      }
    }
    final dictWordRows = await (db.select(db.dictWords)
          ..where((dw) => dw.dictId.isIn(dictIds) & dw.wordId.isIn(wordIds)))
        .get();
    inScope.addAll(dictWordRows.map((r) => r.wordId));

    final learningStatus = await WordBo.getWordsLearningStatusBatch(userId, wordIds);
    learningStatus.forEach((wordId, status) {
      if (status != null) inScope.add(wordId);
    });
    return inScope;
  }

  /// 分层排序（层内随机）：范围内 > 范围外；编辑距离小 > 编辑距离大
  void _orderCandidates(
    List<String> candidateIds,
    Map<String, int> idToDistance,
    Set<String> inScopeIds,
  ) {
    int layerOf(String id) {
      final scopeLayer = inScopeIds.contains(id) ? 0 : 1;
      final dist = idToDistance[id] ?? 2;
      return scopeLayer * 1000 + dist;
    }

    final buckets = <int, List<String>>{};
    for (final id in candidateIds) {
      buckets.putIfAbsent(layerOf(id), () => []).add(id);
    }
    candidateIds.clear();
    for (final layer in buckets.keys.toList()..sort()) {
      candidateIds.addAll(buckets[layer]!..shuffle());
    }
  }

  /// 两个词的义项中是否存在完全相同的一条（忽略空格与标点）
  bool _sharesMeaning(List<MeaningItemVo> a, List<MeaningItemVo> b) {
    final keys = <String>{
      for (final item in a)
        if (_meaningKey(item).isNotEmpty) _meaningKey(item),
    };
    if (keys.isEmpty) return false;
    for (final item in b) {
      if (keys.contains(_meaningKey(item))) return true;
    }
    return false;
  }

  String _meaningKey(MeaningItemVo item) =>
      (item.meaning ?? '').toLowerCase().replaceAll(_meaningNoise, '');

  List<MeaningItemVo> _toMeaningItemVos(List<MeaningItem> items) =>
      [for (final e in items) MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)];

  WordVo _buildWordVo(Word word, List<MeaningItemVo> meaningItems) => WordVo.c2(word.spell)
    ..id = word.id
    ..shortDesc = word.shortDesc
    ..longDesc = word.longDesc
    ..pronounce = word.pronounce
    ..americaPronounce = word.americaPronounce
    ..britishPronounce = word.britishPronounce
    ..popularity = word.popularity
    ..meaningItems = meaningItems;
}

final RegExp _meaningNoise = RegExp("[\\s,，、;；.。!！?？:：'\"“”‘’()（）\\[\\]【】]+");

class DistractorStrategyFactory {
  static DistractorStrategy getStrategy(String strategyName) {
    switch (strategyName) {
      case 'ShapeSimilar':
        return ShapeSimilarDistractorStrategy();
      case 'RecentlyLearned':
      default:
        return LearningWordsDistractorStrategy();
    }
  }
}
