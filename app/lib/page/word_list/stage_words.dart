import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../global.dart';
import '../../util/word_util.dart';

class StageWordsProvider implements WordsProvider {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    var words = await StudyBo().getCurrentStageCache();
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
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    var result = await WordBo().setLearningWordAsMastered(Global.getLoggedInUser()!.id, wordWrapper.word.id!, true);
    if (result.success) {
      ToastUtil.info("${wordWrapper.word.spell} 标记为已掌握");
    } else {
      ToastUtil.error(result.msg!);
    }
    return result.success;
  }

  @override
  Future<int> getWordIndex(String spell) async {
    // 获取当前阶段的所有单词
    var words = await StudyBo().getCurrentStageCache();

    // 查找指定单词的位置
    for (int i = 0; i < words.length; i++) {
      if (words[i].word.spell == spell) {
        return i;
      }
    }

    return -1; // 单词不在当前阶段中
  }
}

class StageWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 5.0 - (wordTag as LearningWordVo).lifeValue;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 5.0;
  }
}

class StageWordsBookMarkProvider implements BookMarkProvider {
  static const String bookMarkName = 'stage_words_list';

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

Future<dynamic>? toStageWordsListPage(bool showDelBtn, Widget nextWorkBtn, BuildContext context) {
  return Get.toNamed('/word_list',
      arguments: WordListPageArgs(
          '阶段复习', StageWordsProvider(), true, showDelBtn, true, '掌握度', StageWordsProgressProvider(), StageWordsBookMarkProvider(), nextWorkBtn));
}
