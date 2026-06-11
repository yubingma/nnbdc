import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/local_embedding_cache.dart';

void main() {
  late MyDatabase database;

  setUp(() {
    database = MyDatabase(DatabaseConnection(NativeDatabase.memory()));
    LocalEmbeddingCache.instance.reset();
  });

  tearDown(() async {
    await database.close();
    LocalEmbeddingCache.instance.reset();
  });

  group('LocalEmbeddingCache Tests', () {
    test('Initialization caches vectors into flat matrix', () async {
      // 1. Prepare vectors
      final emb1 = Uint8List(256)..fillRange(0, 256, 0x00);
      final emb2 = Uint8List(256)..fillRange(0, 256, 0xAA); // 10101010

      await database.wordsDao.insertEntities([
        Word(
          id: 'apple',
          spell: 'apple',
          popularity: 1,
          embedding1bit: emb1,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'banana',
          spell: 'banana',
          popularity: 1,
          embedding1bit: emb2,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'cherry',
          spell: 'cherry',
          popularity: 1,
          embedding1bit: null, // Should be ignored in initialization
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      // 2. Initialize
      expect(LocalEmbeddingCache.instance.isInitialized, false);
      await LocalEmbeddingCache.instance.initialize(database);
      expect(LocalEmbeddingCache.instance.isInitialized, true);

      // 3. Search and Verify Sort by Hamming distance
      // If we search similar words for 'apple', the nearest should be 'banana' (since 'cherry' has no vector)
      final results = await LocalEmbeddingCache.instance.findSimilarWords('apple', limit: 5);
      expect(results.length, 1);
      expect(results[0].wordId, 'banana');
      // For 256 bytes, every byte of 0xAA has exactly 4 bits of 1.
      // Total hamming distance = 256 * 4 = 1024
      expect(results[0].distance, 1024);
    });

    test('Logic delete excludes the word from similarity scans', () async {
      final emb1 = Uint8List(256)..fillRange(0, 256, 0x00);
      final emb2 = Uint8List(256)..fillRange(0, 256, 0x01);
      final emb3 = Uint8List(256)..fillRange(0, 256, 0x03);

      await database.wordsDao.insertEntities([
        Word(
          id: 'w1',
          spell: 'w1',
          popularity: 1,
          embedding1bit: emb1,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'w2',
          spell: 'w2',
          popularity: 1,
          embedding1bit: emb2,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'w3',
          spell: 'w3',
          popularity: 1,
          embedding1bit: emb3,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      await LocalEmbeddingCache.instance.initialize(database);

      // Before deletion, w1 similar words should be w2 and w3
      var list = await LocalEmbeddingCache.instance.findSimilarWords('w1', limit: 10);
      expect(list.length, 2);
      expect(list.any((e) => e.wordId == 'w2'), true);
      expect(list.any((e) => e.wordId == 'w3'), true);

      // Perform logical delete
      LocalEmbeddingCache.instance.updateWord('w2', null);

      // After deletion, w2 should be ignored
      list = await LocalEmbeddingCache.instance.findSimilarWords('w1', limit: 10);
      expect(list.length, 1);
      expect(list[0].wordId, 'w3');
    });

    test('INSERT new word and trigger dynamic grow', () async {
      // 1. Setup a small initial cache (to trigger grow faster, we can just insert words exceeding the initial size)
      // Since default growthChunkSize is 1000, we can insert 1005 mock entries to test array expansion
      final emb = Uint8List(256)..fillRange(0, 256, 0x00);
      
      // Let's first initialize with 2 entries
      await database.wordsDao.insertEntities([
        Word(
          id: 'base1',
          spell: 'base1',
          popularity: 1,
          embedding1bit: emb,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'base2',
          spell: 'base2',
          popularity: 1,
          embedding1bit: emb,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      await LocalEmbeddingCache.instance.initialize(database);

      // Now insert 1005 more entries manually through updateWord.
      // This will exceed initialCapacity = 2 + 1000 = 1002, triggering a grow.
      for (int i = 0; i < 1005; i++) {
        LocalEmbeddingCache.instance.updateWord('extra_$i', emb);
      }

      // Check if similar search still works correctly
      final results = await LocalEmbeddingCache.instance.findSimilarWords('base1', limit: 3);
      expect(results.length, 3);
      expect(results.any((r) => r.wordId.startsWith('extra_') || r.wordId == 'base2'), true);
    });

    test('UPDATE updates the existing embedding in place', () async {
      final embZero = Uint8List(256)..fillRange(0, 256, 0x00);
      final embOne = Uint8List(256)..fillRange(0, 256, 0x01);

      await database.wordsDao.insertEntities([
        Word(
          id: 'apple',
          spell: 'apple',
          popularity: 1,
          embedding1bit: embZero,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'banana',
          spell: 'banana',
          popularity: 1,
          embedding1bit: embOne,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      await LocalEmbeddingCache.instance.initialize(database);

      // Before update, Hamming distance between apple (0x00) and banana (0x01)
      // Since 0x01 has 1 bit of 1, 256 * 1 = 256 distance.
      var results = await LocalEmbeddingCache.instance.findSimilarWords('apple', limit: 1);
      expect(results[0].distance, 256);

      // Update banana to have the same vector as apple (0x00)
      LocalEmbeddingCache.instance.updateWord('banana', embZero);

      // After update, distance should be 0
      results = await LocalEmbeddingCache.instance.findSimilarWords('apple', limit: 1);
      expect(results[0].distance, 0);
    });

    test('findSimilarByVector searches correctly with raw query vector', () async {
      final emb0 = Uint8List(256)..fillRange(0, 256, 0x00);
      final emb1 = Uint8List(256)..fillRange(0, 256, 0x01);
      final embF = Uint8List(256)..fillRange(0, 256, 0xFF);

      await database.wordsDao.insertEntities([
        Word(
          id: 'w0',
          spell: 'w0',
          popularity: 1,
          embedding1bit: emb0,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'w1',
          spell: 'w1',
          popularity: 1,
          embedding1bit: emb1,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        Word(
          id: 'wF',
          spell: 'wF',
          popularity: 1,
          embedding1bit: embF,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ]);

      await LocalEmbeddingCache.instance.initialize(database);

      // Search similar words using a query vector identical to w1 (emb1)
      final results = await LocalEmbeddingCache.instance.findSimilarByVector(emb1, limit: 3);

      expect(results.length, 3);
      expect(results[0].wordId, 'w1');
      expect(results[0].distance, 0);

      expect(results[1].wordId, 'w0');
      expect(results[1].distance, 256); // 0x01 ^ 0x00 has 1 bit

      expect(results[2].wordId, 'wF');
      expect(results[2].distance, 256 * 7); // 0x01 ^ 0xFF (0xFE) has 7 bits
    });
  });
}
