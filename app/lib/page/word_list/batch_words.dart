import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:drift/drift.dart' hide Value;
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../global.dart';
import '../../util/word_util.dart';
import '../../constants.dart';

class StageWordsProvider with WordsProvider {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    var words = await StudyBo().getCurrentBatchCache();
    var results = PagedResults<WordWrapper>(words.length);
    for (var i = 0; i < words.length; i++) {
      var word = words[i];
      if (i >= fromIndex && i < fromIndex + pageSize) {
        var wrapper = WordWrapper(word.word, word);
        results.rows.add(wrapper);
      }
    }
    return results;
  }

  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
    var result = await WordBo().setLearningWordAsMastered(Global.getLoggedInUser()!.id, wordWrapper.word.id!, true);
    if (result.success) {
      SoundUtil.playAssetSoundConcurrent('bubble-pop.mp3', 1.0, 0.5);
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
    // 获取当批次的所有单词
    var words = await StudyBo().getCurrentBatchCache();

    // 查找指定单词的位置
    for (int i = 0; i < words.length; i++) {
      if (words[i].word.spell == spell) {
        return i;
      }
    }

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
  static const String bookMarkName = 'batch_word_list';

  @override
  Future<BookMarkVo?> getBookMark() async {
    var result = await BookmarkBo().getBookMark(bookMarkName);
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

      var result = await BookmarkBo().saveBookMark(bookMarkName, bookMark.spell, bookMark.position, userId);
      return result.success;
    } catch (e) {
      Global.logger.e('保存书签异常: $e');
      return false;
    }
  }
}

Future<dynamic>? toBatchWordsListPage(String title, bool showDelBtn, Widget nextWorkBtn, BuildContext context) {
  return Get.toNamed('/word_list',
      arguments: WordListPageArgs(
          title, StageWordsProvider(), true, showDelBtn, true, '掌握度', StageWordsProgressProvider(), StageWordsBookMarkProvider(), nextWorkBtn));
}
