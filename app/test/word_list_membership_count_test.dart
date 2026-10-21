import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/word_list/word_list_controller.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
import 'package:nnbdc/util/word_util.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 词表把单词移出当前视图（重学 / 掌握 / 移出）时，顶部的词表单词数量必须跟着变。
///
/// 这些虚拟词表的数据源是「一次读全量、内存切片补页」，若移出后不更新内存快照，
/// 补页会从旧快照把词拉回来并把总数覆盖回旧值，用户看到的就是「重学后词数没变化」。
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => {},
    );
  });

  WordListController buildController(FakeMutableProvider provider,
      {String title = '已掌握'}) {
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

  Future<FakeMutableProvider> loadList(WordListController controller) async {
    await controller.loadData(
        checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    // 越过两次查询的最小间隔，让移出后的补页真正发生
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return controller.args.wordsProvider as FakeMutableProvider;
  }

  test('「已掌握」单条重学：词数减一，补页不会把词拉回来', () async {
    final controller = buildController(FakeMutableProvider.withWords(100));
    final provider = await loadList(controller);
    expect(controller.totalWordCount, 100);

    // 移出当前页最后一个词：补页正好从这个位置往后取，旧快照会把它重新拉回来
    final lastWord = controller.words.last;
    await controller.deleteWord(lastWord, controller.words.length - 1);

    expect(provider.all.length, 99);
    expect(controller.totalWordCount, 99);
    expect(controller.words.any((w) => w.word.id == lastWord.word.id), false,
        reason: '重学走的词不能被补页重新拉回');
  });

  test('「已掌握」批量重学：词数按实际移出数量减少', () async {
    final controller = buildController(FakeMutableProvider.withWords(100));
    final provider = await loadList(controller);
    final removed = controller.words.sublist(controller.words.length - 3);
    controller.enterSelection(removed[0]);
    controller.toggleSelection(removed[1]);
    controller.toggleSelection(removed[2]);

    final changed = await controller.applySelection();

    expect(changed, 3);
    expect(provider.all.length, 97);
    expect(controller.totalWordCount, 97);
    final removedIds = removed.map((w) => w.word.id).toSet();
    expect(controller.words.any((w) => removedIds.contains(w.word.id)), false);
  });

  test('「今日错词」标记掌握：同一套内存快照，词数同样要减一', () async {
    final controller =
        buildController(FakeMutableProvider.withWords(100), title: '今日错词');
    final provider = await loadList(controller);
    expect(controller.totalWordCount, 100);

    final lastWord = controller.words.last;
    await controller.masterWord(lastWord, controller.words.length - 1);

    expect(provider.all.length, 99);
    expect(controller.totalWordCount, 99);
    expect(controller.words.any((w) => w.word.id == lastWord.word.id), false);
  });
}

class FakeMutableProvider with WordsProvider {
  FakeMutableProvider.withWords(int count)
      : all = List.generate(
          count,
          (i) => WordWrapper(WordVo.c2('word$i')..id = 'id$i', null),
        );

  final List<WordWrapper> all;

  @override
  Future<PagedResults<WordWrapper>> getAPageOfWords(
      int fromIndex, int pageSize) async {
    final results = PagedResults<WordWrapper>(all.length);
    if (fromIndex < all.length) {
      final end = (fromIndex + pageSize) > all.length
          ? all.length
          : (fromIndex + pageSize);
      results.rows.addAll(all.sublist(fromIndex, end));
    }
    return results;
  }

  @override
  Future<bool> deleteWord(WordWrapper word) async {
    all.remove(word);
    return true;
  }

  @override
  Future<bool> masterWord(WordWrapper word) async {
    all.remove(word);
    return true;
  }

  @override
  Future<int> masterWords(List<String> wordIds) async {
    all.removeWhere((w) => wordIds.contains(w.word.id));
    return wordIds.length;
  }

  @override
  Future<int> unmasterWords(List<String> wordIds) async {
    all.removeWhere((w) => wordIds.contains(w.word.id));
    return wordIds.length;
  }

  @override
  Future<bool?> getWordLearningStatus(String wordId) async => null;

  @override
  Future<List<String>?> getSelectableWordIds() async =>
      all.map((w) => w.word.id!).toList();

  @override
  Future<int> getWordIndex(String spell) async =>
      all.indexWhere((w) => w.word.spell == spell);
}

class FakeProgressProvider implements WordProgressProvider {
  @override
  double getWordProgress(dynamic wordTag) => 5;

  @override
  double getWordProgressMax(dynamic wordTag) => 5;
}

class FakeBookMarkProvider implements BookMarkProvider {
  @override
  String? get bookMarkName => 'word_list_membership_count_test';

  @override
  Future<BookMarkVo?> getBookMark() async => null;

  @override
  Future<bool> saveBookMark(BookMarkVo bookMark) async => true;
}
