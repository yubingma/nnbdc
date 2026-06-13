import 'package:nnbdc/router.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../global.dart';
import '../../util/word_util.dart';
import 'package:nnbdc/db/db.dart';

class MasteredWordsProvider with WordsProvider implements WordModifier {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    var words = await WordBo().getMasteredWordsForAPage(fromIndex, pageSize);
    var results = PagedResults<WordWrapper>(words.total);
    for (var word in words.rows) {
      var wrapper = WordWrapper(word.word, word);
      results.rows.add(wrapper);
    }
    return results;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    var result = await WordBo().deleteMasteredWord(Global.getLoggedInUser()!.id, wordWrapper.word.id!);
    if (result.success) {
      ToastUtil.info("${wordWrapper.word.spell} 已重新加入生词本");
    } else {
      ToastUtil.error(result.msg!);
    }
    return result.success;
  }

  @override
  Future<int> getWordIndex(String spell) async {
    var result = await WordBo().getMasteredWordOrder(spell, Global.getLoggedInUser()!.id);
    if (result.success) {
      var order = result.data!;
      return order == -1 ? -1 : (order - 1);
    } else {
      ToastUtil.error(result.msg!);
      return -1;
    }
  }

  @override
  Future<bool?> getWordLearningStatus(String wordId) async {
    // "已掌握"页面的所有单词都是已掌握的
    return true;
  }

  @override
  Future<Map<String, bool?>> getWordsLearningStatus(List<String> wordIds) async {
    return {for (var id in wordIds) id: true};
  }

  Future<String?> _getMasteredDictId() async {
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return null;
    final dict = await MyDatabase.instance.dictsDao.findUserMasteredDict(userId);
    return dict?.id;
  }

  @override
  String? get targetDictId => null;

  @override
  Future<bool> addWord(String wordId) async {
    final dictId = await _getMasteredDictId();
    if (dictId == null) return false;
    final result = await WordBo().addWordToCustomDict(dictId, wordId);
    if (result.success) return true;
    ToastUtil.error(result.msg ?? '添加失败');
    return false;
  }

  @override
  Future<bool> updateMeanings(String wordId, List<MeaningUpdateItem> meanings) async {
    final dictId = await _getMasteredDictId();
    if (dictId == null) return false;
    final result = await WordBo().updateMeaningForCustomDict(dictId, wordId, meanings);
    if (result.success) return true;
    ToastUtil.error(result.msg ?? '更新失败');
    return false;
  }

  @override
  Future<bool> deleteMeaning(String wordId) async {
    final dictId = await _getMasteredDictId();
    if (dictId == null) return false;
    final result = await WordBo().deleteMeaningForCustomDict(dictId, wordId);
    if (result.success) return true;
    ToastUtil.error(result.msg ?? '操作失败');
    return false;
  }
}

class MasteredWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 5;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 5;
  }
}

class MasteredWordsBookMarkProvider implements BookMarkProvider {
  static const String bookMarkName = 'mastered_words_list';

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

      var result = await BookmarkBo().saveBookMark(bookMarkName, bookMark.spell, bookMark.position, userId, sortAlg: bookMark.sortAlg);
      return result.success;
    } catch (e) {
      Global.logger.e('保存书签异常: $e');
      return false;
    }
  }
}

Future<dynamic>? toMasteredWordsListPage(bool showDelBtn) {
  return goRouter.push('/word_list',
      extra: WordListPageArgs(
          '已掌握', MasteredWordsProvider(), true, showDelBtn, true, '掌握度', MasteredWordsProgressProvider(), MasteredWordsBookMarkProvider(), null)
        ..canAddWord = true
        ..canEditWord = true);
}
