import 'package:get/get.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../global.dart';
import '../../util/word_util.dart';

class TodayWordsProvider implements WordsProvider {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    var words = await WordBo().getTodayWordsForAPage(fromIndex, pageSize, Global.getLoggedInUser()!.id);
    var results = PagedResults<WordWrapper>(words.total);
    for (var word in words.rows) {
      var wrapper = WordWrapper(word.word, word);
      results.rows.add(wrapper);
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
    var result = await WordBo().getTodayWordOrder(spell, Global.getLoggedInUser()!.id);
    if (result.success) {
      var order = result.data!;
      return order == -1 ? -1 : (order - 1);
    } else {
      ToastUtil.error(result.msg!);
      return -1;
    }
  }
}

class TodayWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 5.0 - (wordTag as LearningWordVo).lifeValue;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 5.0;
  }
}

class TodayWordsBookMarkProvider implements BookMarkProvider {
  static const String bookMarkName = 'today_words_list';

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

Future<dynamic>? toTodayWordsListPage(bool showDelBtn) {
  return Get.toNamed('/word_list',
      arguments: WordListPageArgs(
          '今日单词', TodayWordsProvider(), true, showDelBtn, true, '掌握度', TodayWordsProgressProvider(), TodayWordsBookMarkProvider(), null));
}
