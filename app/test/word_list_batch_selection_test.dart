import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/word_list/word_list_controller.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 多选模式：勾选、全选、批量收尾（这里的写库由 FakeBatchProvider 代替真实 DAO）。
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => {},
    );
  });

  FakeBatchProvider buildProvider() {
    final words = List.generate(10, (i) => WordWrapper(WordVo.c2('word_$i')..id = 'id_$i', null));
    final statuses = <String, bool?>{
      for (var i = 0; i < 7; i++) 'id_$i': null,
      for (var i = 7; i < 10; i++) 'id_$i': true,
    };
    return FakeBatchProvider(words, statuses);
  }

  WordListController buildController(FakeBatchProvider provider, {String title = '测试词书'}) {
    final controller = WordListController(
      args: WordListPageArgs(
        title,
        provider,
        true,
        false,
        false,
        '',
        FakeProgressProvider(),
        FakeBookMarkProvider(),
        null,
      ),
      itemScrollController: ItemScrollController(),
      itemPositionsListener: ItemPositionsListener.create(),
      sessionController: StudyAudioSessionController(),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('长按进入多选：选中该词，再点另一行切换勾选', () async {
    final provider = buildProvider();
    final controller = buildController(provider);
    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});

    controller.enterSelection(controller.words.first);
    expect(controller.selectionMode, true);
    expect(controller.selectedCount, 1);
    expect(controller.isWordSelected(controller.words.first), true);

    controller.toggleSelection(controller.words[1]);
    expect(controller.selectedCount, 2);
    controller.toggleSelection(controller.words[1]);
    expect(controller.selectedCount, 1);
  });

  test('全选 = 当前筛选下全部未掌握词，不是已加载的那一页', () async {
    final provider = buildProvider();
    final controller = buildController(provider);
    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});

    controller.enterSelection();
    expect(await controller.selectAll(), true);
    expect(controller.selectedCount, 7, reason: '7 个未掌握，3 个已掌握不在全选范围');
    expect(controller.canSelectAll, true);

    controller.clearSelection();
    expect(controller.selectedCount, 0);
  });

  test('批量标记掌握：整批一次提交，列表即时移除并退出多选', () async {
    final provider = buildProvider();
    final controller = buildController(provider);
    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    controller.enterSelection();
    await controller.selectAll();
    final changed = await controller.applySelection();

    expect(changed, 7);
    expect(provider.masterWordsCalls.length, 1, reason: '整批只提交一次');
    expect(provider.masterWordsCalls.single.length, 7);
    expect(controller.selectionMode, false);
    expect(controller.selectedCount, 0);
    expect(
      controller.words.every((w) => provider.statuses[w.word.id] == true),
      true,
      reason: '被掌握的 7 个词已移出当前视图，补页后剩下的只能是已掌握词',
    );
  });

  test('「已掌握」词表的主操作是重学：走批量取消掌握', () async {
    final provider = buildProvider();
    final controller = buildController(provider, title: '已掌握');
    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    expect(controller.batchActionIsUnmaster, true);

    controller.enterSelection(controller.words.first);
    final changed = await controller.applySelection();

    expect(changed, 1);
    expect(provider.unmasterWordsCalls.length, 1);
    expect(provider.masterWordsCalls, isEmpty);
  });
}

class FakeBatchProvider with WordsProvider {
  final List<WordWrapper> allWords;
  final Map<String, bool?> statuses;
  final List<List<String>> masterWordsCalls = [];
  final List<List<String>> unmasterWordsCalls = [];

  FakeBatchProvider(this.allWords, this.statuses);

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(int fromIndex, int pageSize) async {
    final results = PagedResults<WordWrapper>(allWords.length);
    if (fromIndex < allWords.length) {
      final end = (fromIndex + pageSize > allWords.length) ? allWords.length : fromIndex + pageSize;
      results.rows.addAll(allWords.sublist(fromIndex, end));
    }
    return results;
  }

  @override
  Future<bool> deleteWord(WordWrapper wordWrapper) async => true;

  @override
  Future<int> getWordIndex(String spell) async =>
      allWords.indexWhere((w) => w.word.spell == spell);

  @override
  Future<bool?> getWordLearningStatus(String wordId) async => statuses[wordId];

  @override
  Future<int> masterWords(List<String> wordIds) async {
    masterWordsCalls.add(List.of(wordIds));
    for (final id in wordIds) {
      statuses[id] = true;
    }
    return wordIds.length;
  }

  @override
  Future<int> unmasterWords(List<String> wordIds) async {
    unmasterWordsCalls.add(List.of(wordIds));
    for (final id in wordIds) {
      statuses[id] = null;
    }
    return wordIds.length;
  }

  @override
  Future<List<String>?> getSelectableWordIds() async =>
      allWords.map((w) => w.word.id!).where((id) => statuses[id] != true).toList(growable: false);
}

class FakeProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(dynamic wordTag) => 0.0;

  @override
  double getWordProgressMax(dynamic wordTag) => 1.0;
}

class FakeBookMarkProvider implements BookMarkProvider {
  BookMarkVo? bookMark;

  @override
  String? get bookMarkName => null;

  @override
  Future<BookMarkVo?> getBookMark() async => bookMark;

  @override
  Future<bool> saveBookMark(BookMarkVo value) async {
    bookMark = value;
    return true;
  }
}
