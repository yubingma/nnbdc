import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/walkman.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/word_util.dart';

class MockWordsProvider with WordsProvider {
  final List<WordWrapper> _words;
  MockWordsProvider(this._words);

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final results = PagedResults<WordWrapper>(_words.length);
    if (fromIndex < _words.length) {
      final end = (fromIndex + pageSize > _words.length) ? _words.length : fromIndex + pageSize;
      results.rows.addAll(_words.sublist(fromIndex, end));
    }
    return results;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async => true;

  @override
  Future<int> getWordIndex(String spell) async {
    return _words.indexWhere((w) => w.word.spell == spell);
  }
}

class MockBookMarkProvider implements BookMarkProvider {
  BookMarkVo? _bookMark;
  MockBookMarkProvider([this._bookMark]);

  @override
  Future<BookMarkVo?> getBookMark() async => _bookMark;

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async {
    _bookMark = bookMark;
    return true;
  }
}

void main() {
  group('WalkmanParams & Position Memory Tests', () {
    test('WalkmanParams correctly holds wordsProvider, bookMarkProvider, and initialWordIndex', () {
      final wordsProvider = MockWordsProvider([]);
      final bookmarkProvider = MockBookMarkProvider(BookMarkVo(15, 'apple'));
      final params = WalkmanParams(
        wordsProvider,
        bookMarkProvider: bookmarkProvider,
        initialWordIndex: 15,
      );

      expect(params.wordsProvider, equals(wordsProvider));
      expect(params.bookMarkProvider, equals(bookmarkProvider));
      expect(params.initialWordIndex, equals(15));
      expect(params.toString(), contains('initialWordIndex: 15'));
    });

    test('MockWordsProvider paginated retrieval handles arbitrary offsets correctly', () async {
      final words = List.generate(
        50,
        (i) => WordWrapper(WordVo.c2('word_$i')..id = 'id_$i', null),
      );
      final provider = MockWordsProvider(words);

      final page0 = await provider.getAPageOfWords(0, 20);
      expect(page0.total, equals(50));
      expect(page0.rows.length, equals(20));
      expect(page0.rows.first.word.spell, equals('word_0'));

      final page2 = await provider.getAPageOfWords(40, 20);
      expect(page2.total, equals(50));
      expect(page2.rows.length, equals(10));
      expect(page2.rows.first.word.spell, equals('word_40'));
      expect(page2.rows.last.word.spell, equals('word_49'));
    });

    test('BookMarkProvider saves and returns updated position', () async {
      final bookmarkProvider = MockBookMarkProvider();
      expect(await bookmarkProvider.getBookMark(), isNull);

      await bookmarkProvider.saveBookMark(BookMarkVo(25, 'banana'));
      final saved = await bookmarkProvider.getBookMark();
      expect(saved, isNotNull);
      expect(saved!.position, equals(25));
      expect(saved.spell, equals('banana'));
    });
  });
}
