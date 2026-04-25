import 'dart:math';
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
        String? targetCiXing;
        if (meaningItemVos.isNotEmpty && meaningItemVos.first.ciXing != null) {
          targetCiXing = meaningItemVos.first.ciXing!;
        } else {
          Global.logger.w('Target word has no meaningItems or first ciXing is null, cannot use targetCiXing for otherWords filtering.');
        }

        // 用于跟踪已选择的单词ID，避免重复
        final selectedWordIds = <String>{};

        // 1. 首先尝试从今日单词中获取混淆单词
        if (todayWords.isNotEmpty && todayWords.length > 1) {
          final random = Random();
          final startIndex = random.nextInt(todayWords.length);
          int currentLoopIndex = startIndex;
          int checkedCount = 0;
          int iterations = 0;

          while (otherWords.length < 2 && checkedCount < todayWords.length && iterations < todayWords.length * 2) {
            iterations++;
            final candidateLearningWord = todayWords[currentLoopIndex];
            currentLoopIndex = (currentLoopIndex + 1) % todayWords.length;
            checkedCount++;

            if (candidateLearningWord.wordId == targetWordLearningData.wordId || selectedWordIds.contains(candidateLearningWord.wordId)) {
              continue;
            }

            try {
              final candidateWordDetails = await db.wordsDao.getWordById(candidateLearningWord.wordId);
              assert(candidateWordDetails?.spell != null);

              // 检查词性匹配(仅判断第一个词性)
              bool ciXingMatch = false;

              // 获取候选单词的详细信息
              final wordDetails = await db.wordsDao.getWordById(candidateLearningWord.wordId);

              // 获取单词的释义项（优先使用学习中词书）
              final meaningItems = await WordBo().getWordMeaningItems(wordDetails!.id, targetWordLearningData.userId);

              for (final meaningItem in meaningItems) {
                if (meaningItem.ciXing == targetCiXing) {
                  ciXingMatch = true;
                  break;
                }
              }

              if (ciXingMatch) {
                final otherWordVo = WordVo.c2(wordDetails.spell);
                otherWordVo.id = wordDetails.id;
                otherWordVo.shortDesc = wordDetails.shortDesc;
                otherWordVo.longDesc = wordDetails.longDesc;
                otherWordVo.pronounce = wordDetails.pronounce;
                otherWordVo.americaPronounce = wordDetails.americaPronounce;
                otherWordVo.britishPronounce = wordDetails.britishPronounce;
                otherWordVo.popularity = wordDetails.popularity;
                otherWordVo.meaningItems = meaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
                otherWords.add(otherWordVo);
                selectedWordIds.add(candidateLearningWord.wordId);
              }
            } catch (e) {
              Global.logger.e('Error processing candidate word ${candidateLearningWord.wordId}: $e');
              continue;
            }
          }
        }

        // 2. 如果今日单词中找不到足够的混淆单词，从所有学习中单词(不包括今日单词)中查找词性相同的
        if (otherWords.length < 2) {
          // 获取用户的所有学习单词（不包括今日单词，即 batchId 为空的单词）
          final allLearningWordsQuery = db.select(db.learningWords)
            ..where((lw) => lw.userId.equals(targetWordLearningData.userId) & (lw.batchId.isNull() | lw.batchId.equals(0)));
          final allLearningWords = await allLearningWordsQuery.get();

          // 从所有学习单词中查找词性相同的混淆单词
          int checkCount = 0;
          for (final learningWord in allLearningWords) {
            if (checkCount >= 30) {
              Global.logger.d('RecentlyLearnedDistractorStrategy Step 2: 已遍历检查 30 个学习中的候选词，为防止 N+1 查询卡顿提前中止。');
              break;
            }
            if (learningWord.wordId == targetWordLearningData.wordId || selectedWordIds.contains(learningWord.wordId)) {
              continue;
            }
            checkCount++;

            try {
              // 获取候选单词的详细信息
              final wordDetails = await db.wordsDao.getWordById(learningWord.wordId);
              if (wordDetails == null) continue;

              // 获取单词的释义项（优先使用学习中词书）
              final meaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);

              // 检查词性匹配
              bool ciXingMatch = false;
              for (final meaningItem in meaningItems) {
                if (meaningItem.ciXing == targetCiXing) {
                  ciXingMatch = true;
                  break;
                }
              }

              if (ciXingMatch) {
                final otherWordVo = WordVo.c2(wordDetails.spell);
                otherWordVo.id = wordDetails.id;
                otherWordVo.shortDesc = wordDetails.shortDesc;
                otherWordVo.longDesc = wordDetails.longDesc;
                otherWordVo.pronounce = wordDetails.pronounce;
                otherWordVo.americaPronounce = wordDetails.americaPronounce;
                otherWordVo.britishPronounce = wordDetails.britishPronounce;
                otherWordVo.popularity = wordDetails.popularity;
                otherWordVo.meaningItems = meaningItems.map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();
                otherWords.add(otherWordVo);
                selectedWordIds.add(learningWord.wordId);

                if (otherWords.length >= 2) break;
              }
            } catch (e) {
              Global.logger.e('Error processing learning word ${learningWord.wordId}: $e');
              continue;
            }
          }
        }

        // 3. 如果仍然找不到足够的混淆单词，从所有学习中单词随机选择以补足
        if (otherWords.length < 2) {
          // 重新获取所有学习单词（包括今日单词）用于随机选择
          final allLearningWordsForRandomQuery = db.select(db.learningWords)..where((lw) => lw.userId.equals(targetWordLearningData.userId));
          final allLearningWordsForRandom = await allLearningWordsForRandomQuery.get();

          // 随机打乱所有学习单词的顺序
          final shuffledLearningWords = List<LearningWord>.from(allLearningWordsForRandom);
          shuffledLearningWords.shuffle(Random());

          int checkCount = 0;
          for (final learningWord in shuffledLearningWords) {
            if (checkCount >= 30) {
              Global.logger.d('RecentlyLearnedDistractorStrategy Step 3: 已遍历检查 30 个随机学习中候选词，为防止 N+1 查询卡顿提前中止。');
              break;
            }
            if (learningWord.wordId == targetWordLearningData.wordId || selectedWordIds.contains(learningWord.wordId)) {
              continue;
            }
            checkCount++;

            try {
              final wordDetails = await db.wordsDao.getWordById(learningWord.wordId);
              if (wordDetails == null) continue;

              final otherWordVo = WordVo.c2(wordDetails.spell);
              otherWordVo.id = wordDetails.id;
              otherWordVo.shortDesc = wordDetails.shortDesc;
              otherWordVo.longDesc = wordDetails.longDesc;
              otherWordVo.pronounce = wordDetails.pronounce;
              otherWordVo.americaPronounce = wordDetails.americaPronounce;
              otherWordVo.britishPronounce = wordDetails.britishPronounce;
              otherWordVo.popularity = wordDetails.popularity;

              // 获取基本释义项（优先使用学习中词书）
              final meaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
              otherWordVo.meaningItems = meaningItems.take(3).map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();

              otherWords.add(otherWordVo);
              selectedWordIds.add(learningWord.wordId);

              if (otherWords.length >= 2) break;
            } catch (e) {
              Global.logger.e('Error processing random learning word ${learningWord.wordId}: $e');
              continue;
            }
          }
        }

        // 4. 如果仍然找不到足够的混淆单词（例如整个库中只有一个单词），从全局单词表随机补足
        if (otherWords.length < 2) {
          final needed = 2 - otherWords.length;
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

            // 获取基本释义项
            final meaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
            otherWordVo.meaningItems = meaningItems.take(3).map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();

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

        // 3. 过滤出「用户当前正在学习的范围之内」的单词
        final validLearningWordsQuery = db.select(db.learningWords)
          ..where((tbl) => tbl.userId.equals(targetWordLearningData.userId) & tbl.wordId.isIn(candidateIds));
        final validLearningWords = await validLearningWordsQuery.get();

        // 4. 组装这些匹配到的候选词
        for (final lw in validLearningWords) {
          if (otherWords.length >= 2) break;
          if (lw.wordId == targetWordLearningData.wordId || selectedWordIds.contains(lw.wordId)) {
            continue;
          }

          try {
            final wordDetails = await db.wordsDao.getWordById(lw.wordId);
            if (wordDetails == null) continue;

            final otherWordVo = WordVo.c2(wordDetails.spell);
            otherWordVo.id = wordDetails.id;
            otherWordVo.shortDesc = wordDetails.shortDesc;
            otherWordVo.longDesc = wordDetails.longDesc;
            otherWordVo.pronounce = wordDetails.pronounce;
            otherWordVo.americaPronounce = wordDetails.americaPronounce;
            otherWordVo.britishPronounce = wordDetails.britishPronounce;
            otherWordVo.popularity = wordDetails.popularity;

            // 获取并装载词书详细释义项
            final meaningItems = await WordBo().getWordMeaningItems(wordDetails.id, targetWordLearningData.userId);
            otherWordVo.meaningItems = meaningItems.take(3).map((e) => MeaningItemVo(e.id, e.ciXing, e.meaning, null, null, null)).toList();

            otherWords.add(otherWordVo);
            selectedWordIds.add(wordDetails.id);
          } catch (e) {
            Global.logger.e('ShapeSimilarDistractorStrategy processing candidate word ${lw.wordId}: $e');
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
