import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';

void main() {
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() async {
    await database.close();
  });

  group('WordsDao - getWordsWithCoordinates Unit Tests', () {
    test('retrieves only words with all three coordinates non-null', () async {
      // 1. Insert mock words with different coordinate combinations (now based on embedding1bit)
      await database.wordsDao.insertEntities([
        Word(
          id: 'apple',
          spell: 'apple',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'banana',
          spell: 'banana',
          popularity: 1,
          embedding1bit: null,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'cherry',
          spell: 'cherry',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'date',
          spell: 'date',
          popularity: 1,
          embedding1bit: null,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      // 2. Query words with coordinates
      final results = await database.wordsDao.getWordsWithCoordinates();

      // 3. Verify expectations
      expect(results.length, 2);
      expect(results.any((w) => w.id == 'apple'), true);
      expect(results.any((w) => w.id == 'cherry'), true);
      expect(results.any((w) => w.id == 'banana'), false);
      expect(results.any((w) => w.id == 'date'), false);
    });

    test('respects the limit parameters when queried', () async {
      // 1. Insert 3 words with full coordinates (non-null embedding1bit)
      await database.wordsDao.insertEntities([
        Word(
          id: 'w1',
          spell: 'w1',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'w2',
          spell: 'w2',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'w3',
          spell: 'w3',
          popularity: 1,
          embedding1bit: Uint8List(256),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      // 2. Query with limit = 2
      final results = await database.wordsDao.getWordsWithCoordinates(limit: 2);

      // 3. Verify only 2 results are returned
      expect(results.length, 2);
    });
  });
}
