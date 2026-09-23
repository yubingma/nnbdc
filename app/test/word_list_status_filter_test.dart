import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/word_status_filter.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/word_list/word_list_controller.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 支持"学习状态筛选"的假数据源：可见集合 = 命中当前筛选的单词
class FakeFilterableProvider with WordsProvider {
  final List<WordWrapper> allWords;
  final Map<String, bool?> statuses;
  WordStatusFilter filter = WordStatusFilter.all;

  FakeFilterableProvider(this.allWords, this.statuses);

  List<WordWrapper> get _visible =>
      allWords.where((w) => filter.allows(statuses[w.word.id])).toList();

  @override
  bool get canFilterStatus => true;

  @override
  bool get keepWordsOnMaster => true;

  @override
  Future<WordStatusFilter> getStatusFilter() async => filter;

  @override
  Future<void> saveStatusFilter(WordStatusFilter value) async {
    filter = value;
  }

  @override
  bool isStatusVisible(bool? learningStatus) => filter.allows(learningStatus);

  @override
  Future<WordStatusCounts> getStatusCounts() async {
    var unlearned = 0;
    var learning = 0;
    var mastered = 0;
    for (final word in allWords) {
      switch (statuses[word.word.id]) {
        case true:
          mastered++;
        case false:
          learning++;
        case null:
          unlearned++;
      }
    }
    return WordStatusCounts(unlearned: unlearned, learning: learning, mastered: mastered);
  }

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final visible = _visible;
    final results = PagedResults<WordWrapper>(visible.length);
    if (fromIndex < visible.length) {
      final end = (fromIndex + pageSize > visible.length) ? visible.length : fromIndex + pageSize;
      results.rows.addAll(visible.sublist(fromIndex, end));
    }
    return results;
  }

  @override
  Future<int> getWordIndex(String spell) async =>
      _visible.indexWhere((w) => w.word.spell == spell);

  @override
  Future<bool?> getWordLearningStatus(String wordId) async => statuses[wordId];

  @override
  Future<Map<String, bool?>> getWordsLearningStatus(List<String> wordIds) async =>
      {for (final id in wordIds) id: statuses[id]};

  @override
  Future<bool> masterWord(WordWrapper wordWrapper) async {
    statuses[wordWrapper.word.id!] = true;
    return true;
  }

  @override
  Future<bool> unmasterWord(WordWrapper wordWrapper) async {
    statuses[wordWrapper.word.id!] = false;
    return true;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async => true;
}

class FakeProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(dynamic wordTag) => 0.0;

  @override
  double getWordProgressMax(dynamic wordTag) => 1.0;
}

class FakeBookMarkProvider implements BookMarkProvider {
  BookMarkVo? bookMark;

  FakeBookMarkProvider(this.bookMark);

  @override
  Future<BookMarkVo?> getBookMark() async => bookMark;

  @override
  Future<bool> saveBookMark(BookMarkVo value) async {
    bookMark = value;
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

  /// w0~w4 未学习 / w5~w7 学习中 / w8~w9 已掌握
  ({FakeFilterableProvider provider, FakeBookMarkProvider bookMarks, WordListController controller})
      buildController() {
    final words = List.generate(
      10,
      (i) => WordWrapper(WordVo.c2('word_$i')..id = 'id_$i', null),
    );
    final statuses = <String, bool?>{
      for (var i = 0; i < 5; i++) 'id_$i': null,
      for (var i = 5; i < 8; i++) 'id_$i': false,
      for (var i = 8; i < 10; i++) 'id_$i': true,
    };
    final provider = FakeFilterableProvider(words, statuses);
    final bookMarks = FakeBookMarkProvider(BookMarkVo(6, 'word_6'));
    final controller = WordListController(
      args: WordListPageArgs(
        '测试词书',
        provider,
        true,
        false,
        false,
        '',
        FakeProgressProvider(),
        bookMarks,
        null,
      ),
      itemScrollController: ItemScrollController(),
      itemPositionsListener: ItemPositionsListener.create(),
      sessionController: StudyAudioSessionController(),
    );
    addTearDown(controller.dispose);
    return (provider: provider, bookMarks: bookMarks, controller: controller);
  }

  test('切到"只看未学习"：只保留未学习单词，书签单词被筛掉时记 -1 且保留单词本身', () async {
    final (:provider, :bookMarks, :controller) = buildController();

    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    expect(controller.totalWordCount, 10);
    expect(controller.bookMark!.position, 6);
    expect(controller.isBookMarkHidden, isFalse);

    await controller.changeStatusFilter(WordStatusFilter.fromCode('UNLEARNED'));

    expect(controller.words.map((w) => w.word.spell).toList(),
        ['word_0', 'word_1', 'word_2', 'word_3', 'word_4']);
    expect(controller.totalWordCount, 5);
    expect(provider.filter.code, 'UNLEARNED', reason: '筛选偏好要落到数据源（按词书记忆）');
    expect(controller.isBookMarkHidden, isTrue, reason: '书签单词 word_6 属于"学习中"，被筛掉');
    expect(controller.bookMark!.spell, 'word_6', reason: '书签单词本身必须保留，不能改写成列表首词');
    expect(controller.bookMark!.position, -1);
    expect(bookMarks.bookMark!.spell, 'word_6');

    // 取消筛选 → 书签回到原序号，位置不漂移
    await controller.changeStatusFilter(WordStatusFilter.all);
    expect(controller.totalWordCount, 10);
    expect(controller.isBookMarkHidden, isFalse);
    expect(controller.bookMark!.position, 6);
    expect(controller.bookMark!.spell, 'word_6');
    expect(controller.words[controller.getBookMarkUiPosition()].word.spell, 'word_6');
  });

  test('标题计数：筛选生效时显示"可见 / 总数"', () async {
    final (:provider, bookMarks: _, :controller) = buildController();

    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    expect(controller.titleCountLabel, '10');

    await controller.changeStatusFilter(WordStatusFilter.fromCode('MASTERED'));
    expect(controller.words.length, 2);
    expect(controller.titleCountLabel, '2 / 10');
  });

  test('筛选生效时标记掌握：该词不再属于当前视图，立即移出列表', () async {
    final (:provider, bookMarks: _, :controller) = buildController();

    await controller.changeStatusFilter(WordStatusFilter.fromCode('UNLEARNED,LEARNING'));
    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    expect(controller.totalWordCount, 8);

    final target = controller.words.first;
    expect(target.word.spell, 'word_0');

    await controller.masterWord(target, 0);

    expect(controller.words.any((w) => w.word.spell == 'word_0'), isFalse,
        reason: '"只看未学习+学习中"下掌握该词后应立刻移出');
    expect(provider.statuses['id_0'], isTrue);
  });
}
