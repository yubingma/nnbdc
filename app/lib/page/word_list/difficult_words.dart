import 'package:nnbdc/router.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../../util/word_util.dart';

/// 「我的难词」数据提供者（累计做错 3 次及以上词汇）
class DifficultWordsProvider with WordsProvider {
  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final userId = Global.getLoggedInUser()!.id;
    final allWords = await WordBo().getDifficultWords(userId);
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
    } else {
      ToastUtil.success('已标记掌握');
    }
    return result.success;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async {
    // 从错题本/难词列表中移出
    final result = await WordBo().removeWrongWord(Global.getLoggedInUser()!.id, wordWrapper.word.id!);
    if (result.success) {
      ToastUtil.success('已从错题本移出');
      return true;
    } else {
      ToastUtil.error(result.msg ?? '移出失败');
      return false;
    }
  }

  @override
  Future<int> getWordIndex(String spell) async {
    final userId = Global.getLoggedInUser()!.id;
    final allWords = await WordBo().getDifficultWords(userId);
    for (int i = 0; i < allWords.length; i++) {
      if (allWords[i].spell.toLowerCase() == spell.toLowerCase()) {
        return i;
      }
    }
    return -1;
  }

  @override
  Future<bool?> getWordLearningStatus(String wordId) async {
    final userId = Global.getLoggedInUser()?.id;
    if (userId == null) return null;
    return (await WordBo.getWordsLearningStatusBatch(userId, [wordId]))[wordId];
  }
}

class DifficultWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return 0;
  }

  @override
  double getWordProgressMax(wordTag) {
    return 5.0;
  }
}

class DifficultWordsBookMarkProvider implements BookMarkProvider {
  @override
  String get bookMarkName => 'difficult_words_list';

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
        Global.logger.e('保存难词书签失败：用户未登录');
        return false;
      }

      var result = await BookmarkBo().saveBookMark(bookMarkName, bookMark.spell, bookMark.position, userId, sortAlg: bookMark.sortAlg);
      return result.success;
    } catch (e) {
      Global.logger.e('保存难词书签异常: $e');
      return false;
    }
  }
}

/// 打开「我的难词」词表页
Future<dynamic>? toDifficultWordsListPage() {
  return goRouter.push('/word_list',
      extra: WordListPageArgs(
        '我的难词',
        DifficultWordsProvider(),
        true,
        true,
        false,
        '掌握度',
        DifficultWordsProgressProvider(),
        DifficultWordsBookMarkProvider(),
        null,
      ));
}
