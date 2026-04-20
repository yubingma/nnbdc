import 'package:get/get.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/sound.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/constants.dart';
import 'package:nnbdc/api/bo/bookmark_bo.dart';
import 'package:nnbdc/util/word_util.dart';

class BucketWordsProvider with WordsProvider {
  final int bucketKey;

  BucketWordsProvider(this.bucketKey);

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final user = Global.getLoggedInUser();
    if (user == null) return PagedResults<WordWrapper>(0);

    final words = await WordBo().getLearningWordsByBucketForAPage(bucketKey, fromIndex, pageSize, user.id);
    final results = PagedResults<WordWrapper>(words.total);
    for (var word in words.rows) {
      final wrapper = WordWrapper(word.word, word);
      results.rows.add(wrapper);
    }
    return results;
  }

  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
     final user = Global.getLoggedInUser();
     if (user == null) return false;

    final result = await WordBo().setLearningWordAsMastered(user.id, wordWrapper.word.id!, true);
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
    final user = Global.getLoggedInUser();
    if (user == null) return -1;

    final result = await WordBo().getLearningWordInBucketOrder(spell, bucketKey, user.id);
    if (result.success) {
      return result.data! - 1;
    } else {
      ToastUtil.error(result.msg!);
      return -1;
    }
  }

  @override
  Future<bool?> getWordLearningStatus(String wordId) async {
    return false; // Still learning
  }
}

class BucketWordsProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(wordTag) {
    return (wordTag as LearningWordVo).stability ?? 0.0;
  }

  @override
  double getWordProgressMax(wordTag) {
    return Constants.graduationStability;
  }
}

class BucketWordsBookMarkProvider implements BookMarkProvider {
  final int bucketKey;
  late final String bookMarkName;

  BucketWordsBookMarkProvider(this.bucketKey) {
    bookMarkName = 'bucket_words_list_$bucketKey';
  }

  @override
  Future<BookMarkVo?> getBookMark() async {
    var result = await BookmarkBo().getBookMark(bookMarkName);
    return result.data;
  }

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async {
     final user = Global.getLoggedInUser();
     if (user == null) return false;
    var result = await BookmarkBo().saveBookMark(bookMarkName, bookMark.spell, bookMark.position, user.id);
    return result.success;
  }
}

Future<dynamic>? toBucketWordsListPage(int bucketKey, String title) {
  return Get.toNamed('/word_list',
      arguments: WordListPageArgs(
          title,
          BucketWordsProvider(bucketKey),
          true,
          true,
          true,
          '掌握度',
          BucketWordsProgressProvider(),
          BucketWordsBookMarkProvider(bucketKey),
          null));
}
