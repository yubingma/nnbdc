import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/sort_alg.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/page/walkman.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/util/study_audio_session_controller.dart';
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

  /// 当前已保存的书签（供测试断言）
  BookMarkVo? get saved => _bookMark;

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

    test('WalkmanConfig serialization and defaults work correctly', () {
      final config = WalkmanConfig();
      expect(config.showSpell, isTrue);
      expect(config.repeatCount, equals(1));
      expect(config.playSentenceCount, equals(1));

      config.repeatCount = 3;
      config.showMeaning = true;
      config.playInterval = 2000;
      config.scene = 'rain';
      config.ambientVolume = 0.5;
      config.ambientMuted = true;
      final json = config.toJson();
      expect(json['repeatCount'], equals(3));
      expect(json['showMeaning'], isTrue);
      expect(json['playInterval'], equals(2000));
      expect(json['scene'], equals('rain'));
      expect(json['ambientVolume'], equals(0.5));
      expect(json['ambientMuted'], isTrue);

      final restored = WalkmanConfig.fromJson(json);
      expect(restored.repeatCount, equals(3));
      expect(restored.showMeaning, isTrue);
      expect(restored.playInterval, equals(2000));
      expect(restored.scene, equals('rain'));
      expect(restored.ambientVolume, equals(0.5));
      expect(restored.ambientMuted, isTrue);
    });

    test('WalkmanScene enum properties and assets configuration', () {
      expect(WalkmanScene.values.length, equals(5));
      expect(WalkmanScene.none.hasVideo, isFalse);
      expect(WalkmanScene.none.hasImage, isFalse);
      expect(WalkmanScene.none.hasAudio, isFalse);

      expect(WalkmanScene.rain.title, equals('闲时听雨'));
      expect(WalkmanScene.rain.hasVideo, isTrue);
      expect(WalkmanScene.rain.hasImage, isFalse);
      expect(WalkmanScene.rain.hasAudio, isTrue);
      expect(WalkmanScene.rain.videoAsset, equals('assets/video/scenes/rain.mp4'));
      expect(WalkmanScene.rain.audioAsset, equals('assets/audio/scenes/rain.mp3'));

      expect(WalkmanScene.night.title, equals('夏夜虫鸣'));
      expect(WalkmanScene.night.hasVideo, isFalse);
      expect(WalkmanScene.night.hasImage, isTrue);
      expect(WalkmanScene.night.hasAudio, isTrue);
      expect(WalkmanScene.night.imageAsset, equals('assets/images/scenes/night.jpg'));
      expect(WalkmanScene.night.audioAsset, equals('assets/audio/scenes/night.mp3'));

      expect(WalkmanScene.mist.title, equals('空谷晨雾'));
      expect(WalkmanScene.mist.hasVideo, isFalse);
      expect(WalkmanScene.mist.hasImage, isTrue);
      expect(WalkmanScene.mist.hasAudio, isTrue);
      expect(WalkmanScene.mist.imageAsset, equals('assets/images/scenes/mist.jpg'));
      expect(WalkmanScene.mist.audioAsset, equals('assets/audio/scenes/mist.mp3'));

      expect(WalkmanScene.river.title, equals('湖光水镜'));
      expect(WalkmanScene.river.hasVideo, isFalse);
      expect(WalkmanScene.river.hasImage, isTrue);
      expect(WalkmanScene.river.hasAudio, isTrue);
      expect(WalkmanScene.river.imageAsset, equals('assets/images/scenes/river.jpg'));
      expect(WalkmanScene.river.audioAsset, equals('assets/audio/scenes/river.mp3'));
    });
  });

  group('随身听书签写入', () {
    test('推进位置时写入词表书签，并沿用词表当前的排序', () async {
      final bookMarkProvider = MockBookMarkProvider(
        BookMarkVo(5, 'apple', WordSortAlg.alphabetical.code),
      );
      final state = WalkmanPageState();
      state.params = WalkmanParams(MockWordsProvider([]), bookMarkProvider: bookMarkProvider);
      state.bookMarkSortAlg = WordSortAlg.alphabetical.code; // loadData 从书签读到的词表排序

      await state.saveCurrentPosition(42, WordWrapper(WordVo.c2('banana'), null));

      expect(bookMarkProvider.saved!.position, 42);
      expect(bookMarkProvider.saved!.spell, 'banana');
      // 关键：不能把词表排序改回默认，否则回到词表后顺序会整体改变
      expect(bookMarkProvider.saved!.sortAlg, WordSortAlg.alphabetical.code);
    });

    test('没有书签提供者或单词为空时安全跳过', () async {
      final state = WalkmanPageState();
      expect(state.params, isNull);
      await state.saveCurrentPosition(1, null);
      await state.saveCurrentPosition(1, WordWrapper(WordVo.c2('apple'), null));
    });
  });

  group('Walkman 暂停/恢复状态机', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (MethodCall methodCall) async => {},
      );
      StudyAudioSessionController.instance.resetForTesting();
    });

    test('暂停后播放循环彻底停住（不再自动续播），恢复播放会清除暂停态', () async {
      final state = WalkmanPageState();
      addTearDown(() => state.playWordTimer?.cancel());

      state.ambientVolume = 0.65; // 用户设定的环境白噪音音量

      // 开始播放
      state.resetPlayState();
      expect(state.isPaused, isFalse);
      expect(state.ambientEffectiveVolume, 0.65);
      state.playWordTimer?.cancel(); // 清掉开始播放时挂的计时器，使下面只反映暂停后的行为

      // 暂停：立即进入暂停态，当前单词标记为已停止，环境白噪音一并静音
      state.pausePlayback();
      expect(state.isPaused, isTrue);
      expect(state.currentWordPlayingStopped, isTrue);
      expect(state.playWordTimer?.isActive, isFalse);
      expect(state.ambientEffectiveVolume, 0.0);

      // 暂停期间即使计时器被驱动，也不允许再排下一个计时器（旧实现在这里会自动续播）
      await state.playWordTick();
      expect(state.playWordTimer?.isActive, isFalse);

      // 用户自己按了静音：恢复播放也不该出声
      state.ambientMuted = true;

      // 恢复播放：清除暂停态、重新开启播放循环
      state.resetPlayState();
      expect(state.isPaused, isFalse);
      expect(state.playWordTimer?.isActive, isTrue);
      expect(state.ambientEffectiveVolume, 0.0);

      // 取消静音后回到用户设定音量
      state.ambientMuted = false;
      expect(state.ambientEffectiveVolume, 0.65);
    });
  });
}
