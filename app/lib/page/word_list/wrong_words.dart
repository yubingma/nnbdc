import 'package:get/get.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../util/word_util.dart';

class WrongWordsProvider implements WordsProvider {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    var words = await WordBo().getAnswerWrongWords(Global.getLoggedInUser()!.id);
    var results = PagedResults<WordWrapper>(words.length);
    for (var i = 0; i < words.length; i++) {
      var word = words[i];
      if (i >= fromIndex && i < fromIndex + pageSize) {
        var wrapper = WordWrapper(word, word);
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
    var result = await WordBo().getWrongWordOrder(spell, Global.getLoggedInUser()!.id);
    if (result.success) {
      var order = result.data!;
      return order == -1 ? -1 : (order - 1);
    } else {
      ToastUtil.error(result.msg!);
      return -1;
    }
  }
}

class WrongWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 0;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 5.0;
  }
}

class WrongWordsBookMarkProvider implements BookMarkProvider {
  static const String bookMarkName = 'wrong_words_list';

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

Future<dynamic>? toWrongWordsListPage() {
  return Get.toNamed('/word_list',
      arguments:
          WordListPageArgs('今日错词', WrongWordsProvider(), true, true, false, '掌握度', WrongWordsProgressProvider(), WrongWordsBookMarkProvider(), null));
}
