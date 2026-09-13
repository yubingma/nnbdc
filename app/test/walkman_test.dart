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
      expect(WalkmanScene.values.length, equals(7));
      expect(WalkmanScene.none.hasVideo, isFalse);
      expect(WalkmanScene.none.hasAudio, isFalse);

      expect(WalkmanScene.rain.title, equals('闲时听雨'));
      expect(WalkmanScene.rain.hasVideo, isTrue);
      expect(WalkmanScene.rain.hasAudio, isTrue);
      expect(WalkmanScene.rain.videoAsset, equals('assets/video/scenes/rain.mp4'));
      expect(WalkmanScene.rain.audioAsset, equals('assets/audio/scenes/rain.mp3'));

      expect(WalkmanScene.night.title, equals('夏夜虫鸣'));
      expect(WalkmanScene.night.hasVideo, isTrue);
      expect(WalkmanScene.night.hasAudio, isTrue);
      expect(WalkmanScene.night.videoAsset, equals('assets/video/scenes/night.mp4'));
      expect(WalkmanScene.night.audioAsset, equals('assets/audio/scenes/night.mp3'));

      expect(WalkmanScene.river.title, equals('清幽山溪'));
      expect(WalkmanScene.river.hasVideo, isTrue);
      expect(WalkmanScene.river.hasAudio, isTrue);
      expect(WalkmanScene.river.videoAsset, equals('assets/video/scenes/river.mp4'));
      expect(WalkmanScene.river.audioAsset, equals('assets/audio/scenes/river.mp3'));

      expect(WalkmanScene.waves.title, equals('潮汐海浪'));
      expect(WalkmanScene.waves.hasVideo, isTrue);
      expect(WalkmanScene.waves.hasAudio, isTrue);
      expect(WalkmanScene.waves.videoAsset, equals('assets/video/scenes/waves.mp4'));
      expect(WalkmanScene.waves.audioAsset, equals('assets/audio/scenes/waves.mp3'));

      expect(WalkmanScene.campfire.title, equals('温暖炉火'));
      expect(WalkmanScene.campfire.hasVideo, isTrue);
      expect(WalkmanScene.campfire.hasAudio, isTrue);
      expect(WalkmanScene.campfire.videoAsset, equals('assets/video/scenes/campfire.mp4'));
      expect(WalkmanScene.campfire.audioAsset, equals('assets/audio/scenes/campfire.mp3'));

      expect(WalkmanScene.forest.title, equals('禅意林野'));
      expect(WalkmanScene.forest.hasVideo, isTrue);
      expect(WalkmanScene.forest.hasAudio, isTrue);
      expect(WalkmanScene.forest.videoAsset, equals('assets/video/scenes/forest.mp4'));
      expect(WalkmanScene.forest.audioAsset, equals('assets/audio/scenes/forest.mp3'));
    });
  });
}
