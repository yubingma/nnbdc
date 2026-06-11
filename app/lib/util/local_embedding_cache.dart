import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

/// 高性能本地向量缓存类，用于 1bit 量化的 2048 维向量
class LocalEmbeddingCache {
  static const int vectorBytes = 256; // 2048维 / 8 = 256 字节
  static const int growthChunkSize = 1000; // 扩容步长（以单词个数为单位）

  // 单例模式
  LocalEmbeddingCache._privateConstructor();
  static final LocalEmbeddingCache instance = LocalEmbeddingCache._privateConstructor();

  // 扁平矩阵：大小为 N * 256 字节的连续内存块
  Uint8List? _matrix;

  // 单词ID数组：对应矩阵中的行号
  List<String> _wordIds = [];

  // 快速查找：通过 Word ID 找到其在 _matrix 中的行索引
  Map<String, int> _wordToIndex = {};

  // 当前已使用的槽位数量（等于历史上曾分配的最大索引数 + 1）
  int _allocatedCount = 0;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // popcount 字节查表（Lookup Table）：在 O(1) 内获取任意 byte 中 1 的个数
  static final Uint8List _popCountTable = _initPopCountTable();

  static Uint8List _initPopCountTable() {
    final table = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      int count = 0;
      int temp = i;
      while (temp > 0) {
        count += temp & 1;
        temp >>= 1;
      }
      table[i] = count;
    }
    return table;
  }

  /// 一次性从本地数据库初始化加载扁平向量矩阵
  Future<void> initialize(MyDatabase db) async {
    if (_isInitialized) return;

    try {
      Global.logger.i('🚀 开始初始化高性能本地向量缓存 (LocalEmbeddingCache)...');
      final stopwatch = Stopwatch()..start();

      // 只读取必要的字段（id 和 embedding1bit），避开反序列化为整表 Word 类的巨大开销
      final query = db.customSelect(
        'SELECT id, embedding1bit FROM words WHERE embedding1bit IS NOT NULL'
      );
      final rows = await query.get();

      final int totalWords = rows.length;
      Global.logger.i('🔍 从数据库读取到 $totalWords 个包含 1bit 词嵌入向量的单词。');

      // 预留额外空间（以防同步新插入单词），预分配大小为 (totalWords + 1000) * 256 字节
      final int initialCapacity = totalWords + growthChunkSize;
      _matrix = Uint8List(initialCapacity * vectorBytes);
      _wordIds = List<String>.filled(initialCapacity, '');
      _wordToIndex = {};
      _allocatedCount = totalWords;

      for (int i = 0; i < totalWords; i++) {
        final row = rows[i];
        final String id = row.read<String>('id');
        final Uint8List embedding = row.read<Uint8List>('embedding1bit');

        _wordIds[i] = id;
        _wordToIndex[id] = i;

        // 内存快速拷贝写入扁平矩阵对应区间
        _matrix!.setRange(i * vectorBytes, (i + 1) * vectorBytes, embedding);
      }

      _isInitialized = true;
      stopwatch.stop();
      Global.logger.i('✅ 本地向量缓存初始化完成，耗时: ${stopwatch.elapsedMilliseconds} ms，占用内存约 ${((_matrix?.length ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB');
    } catch (e, stackTrace) {
      Global.logger.e('❌ 初始化本地向量缓存崩溃', error: e, stackTrace: stackTrace);
    }
  }

  /// 局部更新、插入或删除内存中的高维量化向量
  void updateWord(String wordId, Uint8List? embedding) {
    if (!_isInitialized || _matrix == null) {
      Global.logger.w('⚠️ 向量缓存未初始化，忽略此单词更新: wordId=$wordId');
      return;
    }

    final int? existingIdx = _wordToIndex[wordId];

    // 1. 删除操作 (embedding 为空)
    if (embedding == null || embedding.isEmpty) {
      if (existingIdx != null) {
        // 逻辑删除：仅清空对应索引处的 wordId，并从 Map 移除
        _wordIds[existingIdx] = '';
        _wordToIndex.remove(wordId);
        Global.logger.d('🗑️ 向量缓存逻辑删除单词: $wordId');
      }
      return;
    }

    // 确保传入的向量维度正确
    if (embedding.length != vectorBytes) {
      Global.logger.w('⚠️ 传入向量的长度不符合要求: 期望 $vectorBytes, 实际 ${embedding.length} (wordId=$wordId)');
      return;
    }

    // 2. 更新操作
    if (existingIdx != null) {
      final int offset = existingIdx * vectorBytes;
      _matrix!.setRange(offset, offset + vectorBytes, embedding);
      Global.logger.d('📝 向量缓存更新单词向量: $wordId (Index: $existingIdx)');
      return;
    }

    // 3. 插入操作 (existingIdx == null)
    // 检查是否需要扩容
    if (_allocatedCount >= _wordIds.length) {
      _growMatrix();
    }

    final int newIdx = _allocatedCount;
    _wordIds[newIdx] = wordId;
    _wordToIndex[wordId] = newIdx;

    final int offset = newIdx * vectorBytes;
    _matrix!.setRange(offset, offset + vectorBytes, embedding);
    _allocatedCount++;

    Global.logger.d('➕ 向量缓存新增单词向量: $wordId (Index: $newIdx)');
  }

  /// 对矩阵数组及辅助列表进行动态扩容
  void _growMatrix() {
    if (_matrix == null) return;
    final int oldCapacity = _wordIds.length;
    final int newCapacity = oldCapacity + growthChunkSize;
    Global.logger.i('🔄 向量缓存矩阵空间不足，执行扩容：$oldCapacity -> $newCapacity 词位');

    // 扩容矩阵
    final newMatrix = Uint8List(newCapacity * vectorBytes);
    newMatrix.setRange(0, oldCapacity * vectorBytes, _matrix!);
    _matrix = newMatrix;

    // 扩容单词ID列表
    final List<String> newWordIds = List<String>.filled(newCapacity, '');
    for (int i = 0; i < oldCapacity; i++) {
      newWordIds[i] = _wordIds[i];
    }
    _wordIds = newWordIds;
  }

  /// 根据现有的 wordId 检索与其语义相似的单词列表
  Future<List<SearchResult>> findSimilarWords(String wordId, {int limit = 10}) async {
    if (!_isInitialized || _matrix == null) {
      Global.logger.w('⚠️ 向量缓存未就绪，无法进行语义检索');
      return [];
    }

    final targetIdx = _wordToIndex[wordId];
    if (targetIdx == null) {
      Global.logger.w('⚠️ 向量缓存中找不到该单词向量: $wordId');
      return [];
    }

    // 获取目标词的向量
    final targetEmbedding = Uint8List.sublistView(_matrix!, targetIdx * vectorBytes, (targetIdx + 1) * vectorBytes);

    // 将检索计算委派给 Isolate 执行，防止阻塞 UI 主线程
    return await Isolate.run(() => _performSearchOnIsolate(
          matrix: _matrix!,
          wordIds: _wordIds,
          allocatedCount: _allocatedCount,
          targetEmbedding: targetEmbedding,
          targetWordId: wordId,
          limit: limit,
          popCountTable: _popCountTable,
        ));
  }

  /// 根据传入的 1bit 量化向量进行全量相似度检索 (常用于自然语言搜索场景)
  Future<List<SearchResult>> findSimilarByVector(Uint8List queryVector, {int limit = 10}) async {
    if (!_isInitialized || _matrix == null) {
      Global.logger.w('⚠️ 向量缓存未就绪，无法进行语义检索');
      return [];
    }

    if (queryVector.length != vectorBytes) {
      Global.logger.w('⚠️ 查询向量长度不匹配: 期望 $vectorBytes, 实际 ${queryVector.length}');
      return [];
    }

    // 将检索计算委派给 Isolate 执行，防止阻塞 UI 主线程
    return await Isolate.run(() => _performSearchOnIsolate(
          matrix: _matrix!,
          wordIds: _wordIds,
          allocatedCount: _allocatedCount,
          targetEmbedding: queryVector,
          targetWordId: null, // 无排除项
          limit: limit,
          popCountTable: _popCountTable,
        ));
  }

  /// 顶层静态方法，在后台 Isolate 线程中安全执行
  static List<SearchResult> _performSearchOnIsolate({
    required Uint8List matrix,
    required List<String> wordIds,
    required int allocatedCount,
    required Uint8List targetEmbedding,
    required String? targetWordId,
    required int limit,
    required Uint8List popCountTable,
  }) {
    final List<SearchResult> results = [];

    for (int row = 0; row < allocatedCount; row++) {
      final String currentId = wordIds[row];
      // 排除被逻辑删除的项，或目标词本身
      if (currentId.isEmpty || currentId == targetWordId) {
        continue;
      }

      int distance = 0;
      final int rowOffset = row * vectorBytes;

      // Hamming Distance 计算逻辑：位异或后查表累加 1 的位数
      for (int i = 0; i < vectorBytes; i++) {
        final int xorResult = matrix[rowOffset + i] ^ targetEmbedding[i];
        distance += popCountTable[xorResult];
      }

      results.add(SearchResult(currentId, distance));
    }

    // 汉明距离越小代表相似度越高，按升序排序
    results.sort((a, b) => a.distance.compareTo(b.distance));

    return results.take(limit).toList();
  }

  /// 仅用于测试的重置方法
  @visibleForTesting
  void reset() {
    _matrix = null;
    _wordIds = [];
    _wordToIndex = {};
    _allocatedCount = 0;
    _isInitialized = false;
  }
}

/// 语义相似度搜索结果实体
class SearchResult {
  final String wordId;
  final int distance; // 汉明距离得分 (0 ~ 2048)

  SearchResult(this.wordId, this.distance);

  @override
  String toString() => 'SearchResult(wordId: $wordId, distance: $distance)';
}
