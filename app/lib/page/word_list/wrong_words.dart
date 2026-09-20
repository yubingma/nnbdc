import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/router.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../util/word_util.dart';

class WrongWordsProvider with WordsProvider {
  final bool isHistory;

  WrongWordsProvider({this.isHistory = false});

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final userId = Global.getLoggedInUser()!.id;
    final allWords = isHistory
        ? await WordBo().getHistoryWrongWords(userId)
        : await WordBo().getAnswerWrongWords(userId);
    var results = PagedResults<WordWrapper>(allWords.length);

    if (fromIndex < 0) fromIndex = 0;
    int end = (fromIndex + pageSize) > allWords.length ? allWords.length : (fromIndex + pageSize);

    for (var i = fromIndex; i < end; i++) {
      var word = allWords[i];
      results.rows.add(WordWrapper(word, word));
    }
    return results;
  }

  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
    var result = await WordBo().setLearningWordAsMastered(Global.getLoggedInUser()!.id, wordWrapper.word.id!, true);
    if (!result.success) {
      ToastUtil.error(result.msg ?? '标记掌握失败');
    }
    return result.success;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    // 错题本的删除行为：移出错题本
    final result = await WordBo().removeWrongWord(Global.getLoggedInUser()!.id, wordWrapper.word.id!);
    if (result.success) {
      ToastUtil.success('已移出错题本');
      return true;
    } else {
      ToastUtil.error(result.msg ?? '移出失败');
      return false;
    }
  }

  @override
  Future<int> getWordIndex(String spell) async {
    var result = await WordBo().getWrongWordOrder(spell, Global.getLoggedInUser()!.id, isHistory: isHistory);
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
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return false;
    // 检查单词是否已在 mastered_words 表中达成掌握
    return await MyDatabase.instance.masteredWordsDao.isWordMastered(userId, wordId);
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
  final bool isHistory;

  WrongWordsBookMarkProvider({this.isHistory = false});

  String get bookMarkName => isHistory ? 'history_wrong_words_list' : 'wrong_words_list';

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

Future<dynamic>? toWrongWordsListPage({bool isHistory = false}) {
  final title = isHistory ? '历史错词' : '今日错词';
  return goRouter.push('/word_list',
      extra: WordListPageArgs(
        title,
        WrongWordsProvider(isHistory: isHistory),
        true,
        true,
        false,
        '掌握度',
        WrongWordsProgressProvider(),
        WrongWordsBookMarkProvider(isHistory: isHistory),
        null,
      ));
}

Future<dynamic>? toHistoryWrongWordsListPage() => toWrongWordsListPage(isHistory: true);
