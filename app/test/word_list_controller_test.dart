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
  String? get bookMarkName => null;

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

  test('空词表切到另一份词表：整体重载不被上一份词表的词数拦死', () async {
    // 线上现象：历史错词为 0 词时点「今日」切到今日错词，页面永远停在「词单暂无单词」。
    // 根因是 doQuery 的整体重载也拿上一份词表的 totalWordCount 判断"已翻到末尾"：
    // 上一份是 0 词时，fromIndex(0) >= totalWordCount(0) 直接返回，新词表一次都没查。
    final todayWords = List.generate(
      19,
      (i) => WordWrapper(WordVo.c2('word_$i')..id = 'id_$i', null),
    );
    final historyProvider = FakeWordsProvider([]);
    final args = WordListPageArgs(
      '历史错词',
      historyProvider,
      true,
      false,
      false,
      '掌握度',
      FakeProgressProvider(),
      FakeBookMarkProvider(),
      null,
    );
    final controller = WordListController(
      args: args,
      itemScrollController: ItemScrollController(),
      itemPositionsListener: ItemPositionsListener.create(),
      sessionController: StudyAudioSessionController(),
    );
    addTearDown(controller.dispose);

    // 先按历史错词加载：0 词，总数落到 0
    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    expect(controller.totalWordCount, 0);
    expect(controller.words, isEmpty);

    // 点「今日」：页面原地替换数据源为今日错词（今日错词有书签），再整体重载
    args.appBarTitle = '今日错词';
    args.wordsProvider = FakeWordsProvider(todayWords);
    args.bookMarkProvider = FakeBookMarkProvider(BookMarkVo(0, 'word_0'));

    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});

    expect(controller.totalWordCount, 19);
    expect(controller.words.length, 19);
  });
}
