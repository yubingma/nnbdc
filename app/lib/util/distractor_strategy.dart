import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:drift/drift.dart' as drift;

abstract class DistractorStrategy {
  Future<List<WordVo>> getTwoOtherWords({
    required List<UserStudyStep> steps,
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
    required List<UserStudyStep> steps,
    required int learningMode,
    required List<MeaningItemVo> meaningItemVos,
    required List<LearningWord> todayWords,
    required LearningWord targetWordLearningData,
    required MyDatabase db,
  }) async {
    try {
      List<WordVo> otherWords = [];
      if ([StudyStep.en2Ch.json, StudyStep.ch2En.json].contains(steps[learningMode].studyStep)) {
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
          
          for (final wordDetails in finalCandidates) {
            final otherWordVo = WordVo.c2(wordDetails.spell);
            otherWordVo.id = wordDetails.id;
            otherWordVo.shortDesc = wordDetails.shortDesc;
            otherWordVo.longDesc = wordDetails.longDesc;
            otherWordVo.pronounce = wordDetails.pronounce;
            otherWordVo.americaPronounce = wordDetails.americaPronounce;
            otherWordVo.britishPronounce = wordDetails.britishPronounce;
            otherWordVo.popularity = wordDetails.popularity;
            final realMeaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
            otherWordVo.meaningItems = realMeaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();            
            otherWords.add(otherWordVo);
            if (otherWords.length >= 2) break;
          }
        }

        // 最终极兜底
        if (otherWords.length < 2) {
          final int needed = 2 - otherWords.length;
          final excludeIds = selectedWordIds.toList()..add(targetWordLearningData.wordId);

          final wordsQuery = db.select(db.words)
            ..where((tbl) => tbl.id.isNotIn(excludeIds))
            ..orderBy([(t) => drift.OrderingTerm.random()])
            ..limit(needed);

          final globalWords = await wordsQuery.get();

          for (final wordDetails in globalWords) {
            final otherWordVo = WordVo.c2(wordDetails.spell);
            otherWordVo.id = wordDetails.id;
            otherWordVo.shortDesc = wordDetails.shortDesc;
            otherWordVo.longDesc = wordDetails.longDesc;
            otherWordVo.pronounce = wordDetails.pronounce;
            otherWordVo.americaPronounce = wordDetails.americaPronounce;
            otherWordVo.britishPronounce = wordDetails.britishPronounce;
            otherWordVo.popularity = wordDetails.popularity;

            final realMeaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
            otherWordVo.meaningItems = realMeaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();

            otherWords.add(otherWordVo);
            selectedWordIds.add(wordDetails.id);
            if (otherWords.length >= 2) break;
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
  @override
  Future<List<WordVo>> getTwoOtherWords({
    required List<UserStudyStep> steps,
    required int learningMode,
    required List<MeaningItemVo> meaningItemVos,
    required List<LearningWord> todayWords,
    required LearningWord targetWordLearningData,
    required MyDatabase db,
  }) async {
    try {
      final List<WordVo> otherWords = [];
      if (![StudyStep.en2Ch.json, StudyStep.ch2En.json].contains(steps[learningMode].studyStep)) {
        return otherWords;
      }

      // 获取当前目标单词的拼写
      final targetWords = await db.wordsDao.getWordsByIds([targetWordLearningData.wordId]);
      String targetSpell = '';
      if (targetWords.isNotEmpty) {
        targetSpell = targetWords.first.spell;
      }

      final candidateIds = <String>[];
      final selectedWordIds = <String>{targetWordLearningData.wordId};

      // 1. 获取数据库预设的形近词
      final similarWordsQuery = db.select(db.similarWords)
        ..where((tbl) => tbl.wordId.equals(targetWordLearningData.wordId));
      final presetSimilarWords = await similarWordsQuery.get();
      
      final presetCandidateIds = <String>[];
      for (final sw in presetSimilarWords) {
        if (!selectedWordIds.contains(sw.similarWordId)) {
          presetCandidateIds.add(sw.similarWordId);
          selectedWordIds.add(sw.similarWordId);
        }
      }
      // 预设形近词内部随机打乱
      presetCandidateIds.shuffle();
      candidateIds.addAll(presetCandidateIds);

      // 2. 动态形近词补充：【只有当预设形近词不足 2 个时】，才去动态查找邻近词补足
      if (candidateIds.length < 2 && targetSpell.isNotEmpty) {
        final fallbackCandidateIds = <String>[];
        // 拼写更大的（向后取 10 个）
        final largerWordsQuery = db.select(db.words)
          ..where((tbl) => tbl.spell.isBiggerThanValue(targetSpell) & tbl.id.equals(targetWordLearningData.wordId).not())
          ..orderBy([(tbl) => drift.OrderingTerm(expression: tbl.spell)])
          ..limit(10);
        final largerWords = await largerWordsQuery.get();
        for (final w in largerWords) {
          if (!selectedWordIds.contains(w.id)) {
            fallbackCandidateIds.add(w.id);
            selectedWordIds.add(w.id);
          }
        }

        // 拼写更小的（向前取 10 个）
        final smallerWordsQuery = db.select(db.words)
          ..where((tbl) => tbl.spell.isSmallerThanValue(targetSpell) & tbl.id.equals(targetWordLearningData.wordId).not())
          ..orderBy([(tbl) => drift.OrderingTerm(expression: tbl.spell, mode: drift.OrderingMode.desc)])
          ..limit(10);
        final smallerWords = await smallerWordsQuery.get();
        for (final w in smallerWords) {
          if (!selectedWordIds.contains(w.id)) {
            fallbackCandidateIds.add(w.id);
            selectedWordIds.add(w.id);
          }
        }
        
        // 邻近词内部随机打乱后追加到末尾
        fallbackCandidateIds.shuffle();
        candidateIds.addAll(fallbackCandidateIds);
      }

      // 4. 加载备选词的基础数据
      if (candidateIds.isNotEmpty) {
        // 取前 10 个来加载，避免 IN 语句过大
        final topCandidateIds = candidateIds.take(10).toList();
        final wordsList = await db.wordsDao.getWordsByIds(topCandidateIds);
        
        // 详情列表也随机打乱一下
        wordsList.shuffle();

        for (final wordDetails in wordsList) {
          final otherWordVo = WordVo.c2(wordDetails.spell);
          otherWordVo.id = wordDetails.id;
          otherWordVo.shortDesc = wordDetails.shortDesc;
          otherWordVo.longDesc = wordDetails.longDesc;
          otherWordVo.pronounce = wordDetails.pronounce;
          otherWordVo.americaPronounce = wordDetails.americaPronounce;
          otherWordVo.britishPronounce = wordDetails.britishPronounce;
          otherWordVo.popularity = wordDetails.popularity;
          final realMeaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
          otherWordVo.meaningItems = realMeaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
          
          otherWords.add(otherWordVo);
          if (otherWords.length >= 2) break;
        }
      }

      // 5. 如果不足 2 个（理论上拼写排序必然够，除非词库极小），使用“学习中单词”策略补足
      if (otherWords.length < 2) {
        final fallbackWords = await LearningWordsDistractorStrategy().getTwoOtherWords(
          steps: steps,
          learningMode: learningMode,
          meaningItemVos: meaningItemVos,
          todayWords: todayWords,
          targetWordLearningData: targetWordLearningData,
          db: db,
        );
        for (var fw in fallbackWords) {
          if (otherWords.length >= 2) break;
          // 确保不和目标单词重复，也不和已选单词重复
          if (fw.id != targetWordLearningData.wordId && !otherWords.any((w) => w.id == fw.id)) {
            otherWords.add(fw);
          }
        }
      }

      return otherWords;
    } catch (e, stackTrace) {
      Global.logger.e('Error in ShapeSimilarDistractorStrategy: $e', stackTrace: stackTrace);
      // 降级执行 LearningWords 策略
      return await LearningWordsDistractorStrategy().getTwoOtherWords(
        steps: steps,
        learningMode: learningMode,
        meaningItemVos: meaningItemVos,
        todayWords: todayWords,
        targetWordLearningData: targetWordLearningData,
        db: db,
      );
    }
  }


}

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
