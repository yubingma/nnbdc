import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/walkman_launcher.dart';
import 'package:nnbdc/page/word_list/learning_words.dart';
import 'package:nnbdc/page/word_list/root_family_words.dart';
import 'package:nnbdc/page/word_list/today_words.dart';
import 'package:nnbdc/page/word_list/wrong_words.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 随身听独立启动：这次该听哪个词表
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('随身听独立启动的数据源解析', () {
    test('首次使用（没有上次记录）播今日任务', () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect(params.wordsProvider, isA<TodayWordsProvider>());
      expect(params.bookMarkProvider, isA<TodayWordsBookMarkProvider>());
    });

    test('有上次记录时，续播那次听的数据源', () async {
      SharedPreferences.setMockInitialValues({
        WalkmanLauncher.lastSourceKey: 'learning_words_list',
      });
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect(params.wordsProvider, isA<LearningWordsProvider>());
      expect(params.bookMarkProvider, isA<LearningWordsBookMarkProvider>());
    });

    test('历史错词与普通错词是两个数据源，续播时不能互相串', () async {
      SharedPreferences.setMockInitialValues({
        WalkmanLauncher.lastSourceKey: 'history_wrong_words_list',
      });
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect((params.wordsProvider as WrongWordsProvider).isHistory, isTrue);
      expect((params.bookMarkProvider as WrongWordsBookMarkProvider).isHistory, isTrue);
    });

    test('上次的数据源已认不出来时，回落今日任务', () async {
      SharedPreferences.setMockInitialValues({
        WalkmanLauncher.lastSourceKey: 'some_removed_words_list',
      });
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect(params.wordsProvider, isA<TodayWordsProvider>());
      expect(params.bookMarkProvider, isA<TodayWordsBookMarkProvider>());
    });

    test('同根词也能续播：书签已落库，与形近词一致', () async {
      SharedPreferences.setMockInitialValues({
        WalkmanLauncher.lastSourceKey: 'root_family_words_list',
      });
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect(params.wordsProvider, isA<RootFamilyWordsProvider>());
      expect(params.bookMarkProvider, isA<RootFamilyWordsBookMarkProvider>());
    });

    test('书签不持久化的数据源（如批次学习）不会被记成可续播的源', () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.init();

      await WalkmanLauncher.remember(null, null);

      expect(Prefs.read<String>(WalkmanLauncher.lastSourceKey), isNull);
    });

    test('回落今日任务时带上词表名称', () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect(params.title, '今日单词');
    });

    test('上次的数据源已认不出来时，名称也跟着回落今日任务', () async {
      SharedPreferences.setMockInitialValues({
        WalkmanLauncher.lastSourceKey: 'some_removed_words_list',
        WalkmanLauncher.lastSourceTitleKey: '某个已消失的词表',
      });
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect(params.wordsProvider, isA<TodayWordsProvider>());
      expect(params.title, '今日单词');
    });

    test('数据源仍然有效时，词表名称原样带过来', () async {
      SharedPreferences.setMockInitialValues({
        WalkmanLauncher.lastSourceKey: 'root_family_words_list',
        WalkmanLauncher.lastSourceTitleKey: '同根词',
      });
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();
      expect(params.wordsProvider, isA<RootFamilyWordsProvider>());
      expect(params.title, '同根词');
    });

    test('只有数据源、没有名称记录时（老版本升级上来），名称必须能兜底', () async {
      SharedPreferences.setMockInitialValues({
        WalkmanLauncher.lastSourceKey: 'root_family_words_list',
        // 刻意不写 lastSourceTitleKey：旧版本只会记下数据源，没有名称这一列
      });
      await Prefs.init();

      final params = await WalkmanLauncher.resolveParams();

      expect(params.wordsProvider, isA<RootFamilyWordsProvider>());
      expect(params.title, isNotNull);
    });
  });
}
