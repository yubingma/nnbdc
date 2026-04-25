import 'dart:math';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
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

class RecentlyLearnedDistractorStrategy implements DistractorStrategy {
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

        // 1. 获取今日学习单词的 ID，一次性多存几个做候选池
        for (final word in todayWords) {
          if (!selectedWordIds.contains(word.wordId)) {
            candidateIds.add(word.wordId);
            selectedWordIds.add(word.wordId);
          }
        }

        // 2. 如果不足 15 个候选词，补足用户的最近学过词
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

        // 3. 一次性批量用 IN 语句加载候选词的详情属性，绝对杜绝 N+1 读表
        if (candidateIds.isNotEmpty) {
          final wordsList = await db.wordsDao.getWordsByIds(candidateIds);
          
          // 3.1 核心：在纯内存中执行高效词性比对（通过解析 shortDesc）
          final List<Word> matchedWords = [];
          final List<Word> unmatchedWords = [];
          
          for (final wordDetails in wordsList) {
            bool isCiXingMatch = false;
            if (targetCiXing != null && wordDetails.shortDesc != null) {
              final shortDescLower = wordDetails.shortDesc!.toLowerCase();
              final targetLower = targetCiXing.toLowerCase();
              // 如果 shortDesc 包含 'n.'、'v.'、'adj.' 等词性前缀
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

          // 3.2 优先挑词性一致的，凑不够再用词性不同的兜底
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

        // 5. 如果仍然找不到足够的混淆单词（例如整个库中只有一个单词），从全局单词表随机补足
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
          }
        }
      }
      return otherWords;
    } catch (e, stackTrace) {
      Global.logger.e('Error in RecentlyLearnedDistractorStrategy: $e', stackTrace: stackTrace);
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

      // 1. 获取数据库预设的形近词
      final similarWordsQuery = db.select(db.similarWords)
        ..where((tbl) => tbl.wordId.equals(targetWordLearningData.wordId));
      final presetSimilarWords = await similarWordsQuery.get();

      final selectedWordIds = <String>{};

      if (presetSimilarWords.isNotEmpty) {
        // 2. 提取候选词的 ID 集合
        final candidateIds = presetSimilarWords.map((sw) => sw.similarWordId).toList();

        // 3. 过滤出「用户当前正在学习的范围之内」的单词（通过内存缓存加速）
        final userLearningWordIds = await StudyBo.getUserLearningWordIds(db, targetWordLearningData.userId);
        final validCandidateIds = candidateIds.where((id) => userLearningWordIds.contains(id)).toList();

        // 4. 一次性批量用 IN 语句获取备选词的基础数据，绝对杜绝 N+1
        if (validCandidateIds.isNotEmpty) {
          final wordsList = await db.wordsDao.getWordsByIds(validCandidateIds);
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
            selectedWordIds.add(wordDetails.id);
            if (otherWords.length >= 2) break;
          }
        }
      }

      // 5. 如果不足 2 个，使用“最近学习的单词”策略补足
      if (otherWords.length < 2) {
        final fallbackWords = await RecentlyLearnedDistractorStrategy().getTwoOtherWords(
          steps: steps,
          learningMode: learningMode,
          meaningItemVos: meaningItemVos,
          todayWords: todayWords,
          targetWordLearningData: targetWordLearningData,
          db: db,
        );
        for (var fw in fallbackWords) {
          if (otherWords.length >= 2) break;
          if (fw.id != targetWordLearningData.wordId && !selectedWordIds.contains(fw.id)) {
            otherWords.add(fw);
            if (fw.id != null) {
              selectedWordIds.add(fw.id!);
            }
          }
        }
      }

      return otherWords;
    } catch (e, stackTrace) {
      Global.logger.e('Error in ShapeSimilarDistractorStrategy: $e', stackTrace: stackTrace);
      // 发生任何异常，跌落执行默认的 RecentlyLearned 策略
      return await RecentlyLearnedDistractorStrategy().getTwoOtherWords(
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
        return RecentlyLearnedDistractorStrategy();
    }
  }
}
