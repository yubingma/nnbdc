import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/word_list/word_list_controller.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class FakeWordsProvider with WordsProvider {
  final List<WordWrapper> _words;
  FakeWordsProvider(this._words);

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

class FakeProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(dynamic wordTag) => 0.0;

  @override
  double getWordProgressMax(dynamic wordTag) => 1.0;
}

class FakeBookMarkProvider implements BookMarkProvider {
  BookMarkVo? _bookMark;
  FakeBookMarkProvider([this._bookMark]);

  @override
  Future<BookMarkVo?> getBookMark() async => _bookMark;

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async {
    _bookMark = bookMark;
    return true;
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => {},
    );
  });

  test('从随身听返回后重新加载：书签与当前词同步到随身听停留的位置', () async {
    final words = List.generate(
      90,
      (i) => WordWrapper(WordVo.c2('word_$i')..id = 'id_$i', null),
    );
    final wordsProvider = FakeWordsProvider(words);
    final bookMarkProvider = FakeBookMarkProvider(BookMarkVo(3, 'word_3'));
    final controller = WordListController(
      args: WordListPageArgs(
        '测试词表',
        wordsProvider,
        true,
        false,
        false,
        '掌握度',
        FakeProgressProvider(),
        bookMarkProvider,
        null,
      ),
      itemScrollController: ItemScrollController(),
      itemPositionsListener: ItemPositionsListener.create(),
      sessionController: StudyAudioSessionController(),
    );
    addTearDown(controller.dispose);

    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    expect(controller.bookMark!.position, 3);
    expect(controller.words[controller.getBookMarkUiPosition()].word.spell, 'word_3');

    // 随身听播放过程中把书签一路推进到第 42 个词（沿用词表排序）
    await bookMarkProvider.saveBookMark(BookMarkVo(42, 'word_42'));

    // 关闭随身听返回词表：页面重新加载（_syncBookMarkAfterWalkman 走的就是这条路径）
    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});

    expect(controller.bookMark!.position, 42);
    expect(controller.bookMark!.spell, 'word_42');
    final uiPosition = controller.getBookMarkUiPosition();
    expect(uiPosition, greaterThanOrEqualTo(0));
    expect(controller.words[uiPosition].word.spell, 'word_42');
  });
}
