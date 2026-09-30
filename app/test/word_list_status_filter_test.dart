import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/word_status_filter.dart';
import 'package:nnbdc/page/word_list/learning_words.dart';
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

  /// 掌握/取消掌握后是否把词留在当前列表里（词书词表为 true，今日任务等为 false）
  bool keepOnMaster = true;

  FakeFilterableProvider(this.allWords, this.statuses);

  List<WordWrapper> get _visible =>
      allWords.where((w) => filter.allows(statuses[w.word.id])).toList();

  @override
  bool get canFilterStatus => true;

  @override
  bool get keepWordsOnMaster => keepOnMaster;

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
    // 真实语义（WordBo.deleteMasteredWord）：移出「已掌握」词书 + 删除学习进度记录
    // → 该词没有任何学习进度记录，学习状态回到「未学习」（null）
    statuses[wordWrapper.word.id!] = null;
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

  test('取消掌握：呈现「未学习」且掌握度归零，稳定度置"无"而不是伪值 0.0', () async {
    // 今日任务列表里的已掌握词：带着毕业时的哨兵稳定度 120.0 进入列表
    final mastered = LearningWordVo(
      UserVo.c2('u1'),
      DateTime.now(),
      1,
      DateTime.now(),
      1,
      3,
      WordVo.c2('cat')..id = 'id_0',
      null,
      120.0,
      5.0,
      0,
      30,
      3,
      0,
      2,
    );
    final wrapper = WordWrapper(mastered.word, mastered);
    final provider = FakeFilterableProvider([wrapper], {'id_0': true})..keepOnMaster = false;
    final controller = WordListController(
      args: WordListPageArgs(
        '今日单词',
        provider,
        true,
        false,
        true,
        '掌握度',
        LearningWordsProgressProvider(),
        FakeBookMarkProvider(null),
        null,
      ),
      itemScrollController: ItemScrollController(),
      itemPositionsListener: ItemPositionsListener.create(),
      sessionController: StudyAudioSessionController(),
    );
    addTearDown(controller.dispose);

    await controller.loadData(checkAndShowGuide: () {}, restoreAsrIfNeeded: (_) {});
    expect(controller.words.length, 1);

    await controller.unmasterWord(wrapper, 0);

    expect(provider.statuses['id_0'] == null, isTrue,
        reason: '假数据源按真实语义把状态改成「未学习」（学习进度记录已被删除）');
    expect(wrapper.currentLearningStatus == null, isTrue,
        reason: '取消掌握 = 从零重学，列表必须按「未学习」呈现，不能是"学习中 0%"');
    expect(wrapper.currentProgress, 0.0,
        reason: '没有学习进度记录 → 掌握度进度为 0');
    expect(LearningWordsProgressProvider().getWordProgress(wrapper.tag), 0.0,
        reason: '渲染时按稳定度推导掌握度：没有学习进度记录就必须是 0，'
            '不能被展示模型里残留的毕业哨兵值 120.0 顶成满环');
    // 没有学习进度记录就没有记忆强度：稳定度必须是"无"（null），不能是伪值 0.0
    // 反向验证：把 `stability = null` 改回 `stability = 0.0`，本断言即失败
    expect(mastered.stability == null, isTrue,
        reason: '取消掌握后该词没有任何记忆强度可言，不能臆造 0.0 这个伪值');
  });
}
