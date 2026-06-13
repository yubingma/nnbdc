import 'package:drift/drift.dart' hide Value;
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../constants.dart';
import '../../global.dart';
import '../../util/word_util.dart';

class StageWordsProvider with WordsProvider {
  List<LearningWordVo>? _cachedWords;

  Future<List<LearningWordVo>> _getAllWords() async {
    return _cachedWords ??= await StudyBo().getCurrentBatchCache();
  }

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final sw = Stopwatch()..start();
    var allWords = await _getAllWords();
    var results = PagedResults<WordWrapper>(allWords.length);
    
    if (fromIndex < 0) fromIndex = 0;
    int end = (fromIndex + pageSize) > allWords.length ? allWords.length : (fromIndex + pageSize);
    
    for (var i = fromIndex; i < end; i++) {
      var word = allWords[i];
      results.rows.add(WordWrapper(word.word, word));
    }
    Global.logger.d('StageWordsProvider: getAPageOfWords(from=$fromIndex) completed in ${sw.elapsedMilliseconds}ms');
    return results;
  }

  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
    var result = await WordBo().setLearningWordAsMastered(Global.getLoggedInUser()!.id, wordWrapper.word.id!, true);
    if (result.success) {
    } else {
      ToastUtil.error(result.msg!);
    }
    return result.success;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    return await masterWord(wordWrapper);
  }

  @override
  Future<int> getWordIndex(String spell) async {
    final sw = Stopwatch()..start();
    // 获取当批次的所有单词
    var words = await _getAllWords();

    // 查找指定单词的位置
    for (int i = 0; i < words.length; i++) {
      if (words[i].word.spell == spell) {
        return i;
      }
    }

    Global.logger.d('StageWordsProvider: getWordIndex($spell) completed in ${sw.elapsedMilliseconds}ms');
    return -1; // 单词不在当前批次中
  }

  @override
  Future<bool?> getWordLearningStatus(String wordId) async {
    final user = Global.getLoggedInUser();
    if (user == null) return null;

    final db = MyDatabase.instance;

    // 检查是否已掌握
    final isMastered = await db.masteredWordsDao.isWordMastered(user.id, wordId);
    if (isMastered) return true; // 已掌握

    // 检查是否在学习中（掌握度 < 5）
    final learningQuery = db.select(db.learningWords)
      ..where((lw) => lw.userId.equals(user.id) & lw.wordId.equals(wordId) & (lw.stability.isNull() | lw.stability.isSmallerThanValue(Constants.graduationStability)));
    final learning = await learningQuery.getSingleOrNull();
    if (learning != null) return false; // 学习中

    return null; // 未学习
  }
}

class StageWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return (wordTag as LearningWordVo).stability ?? 0.0;
  }

  @override
  double getWordProgressMax(wordTag) {
    return Constants.graduationStability;
  }
}

class StageWordsBookMarkProvider implements BookMarkProvider {
  final int? batchId;
  final int? batchStartIndex;

  StageWordsBookMarkProvider({this.batchId, this.batchStartIndex});

  Future<String> _getBookMarkName() async {
    int? finalBatchId = batchId;
    int? finalStartIndex = batchStartIndex;

    if (finalBatchId == null || finalStartIndex == null) {
      try {
        final words = await StudyBo().getCurrentBatchCache();
        if (words.isNotEmpty) {
          finalBatchId ??= words.first.batchId;
          final learningOrder = words.first.learningOrder;
          if (learningOrder != null) {
            finalStartIndex ??= learningOrder - 1;
          }
        }
      } catch (e) {
        Global.logger.e('获取当前批次信息失败: $e');
      }
    }

    if (finalBatchId != null) {
      final startIndexStr = finalStartIndex != null ? '_$finalStartIndex' : '';
      return 'batch_word_list_$finalBatchId$startIndexStr';
    }
    return 'batch_word_list';
  }

  @override
  Future<BookMarkVo?> getBookMark() async {
    final name = await _getBookMarkName();
    var result = await BookmarkBo().getBookMark(name);
    return result.data;
  }

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async {
    try {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        Global.logger.e('保存书签失败：用户未登录');
        return false;
      }

      final name = await _getBookMarkName();
      var result = await BookmarkBo().saveBookMark(name, bookMark.spell, bookMark.position, userId, sortAlg: bookMark.sortAlg);
      return result.success;
    } catch (e) {
      Global.logger.e('保存书签异常: $e');
      return false;
    }
  }
}

Future<dynamic>? toBatchWordsListPage(String title, bool showDelBtn, Widget nextWorkBtn, BuildContext context, {int? batchId, int? batchStartIndex}) {
  return context.push('/word_list',
      extra: WordListPageArgs(
          title,
          StageWordsProvider(),
          true,
          showDelBtn,
          true,
          '掌握度',
          StageWordsProgressProvider(),
          StageWordsBookMarkProvider(batchId: batchId, batchStartIndex: batchStartIndex),
          nextWorkBtn,
          showAiStory: true));
}
