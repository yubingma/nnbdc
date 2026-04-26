import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/constants.dart';
import 'package:drift/drift.dart';

class StudyCacheManager {
  static final StudyCacheManager _instance = StudyCacheManager._internal();
  factory StudyCacheManager() => _instance;
  StudyCacheManager._internal();

  String? _cachedUserId;
  Set<String>? _cachedMasteredWordIds;
  Set<String>? _cachedLearningWordIds;
  List<LearningWord>? _cachedTodayWords;
  void clear() {
    _cachedUserId = null;
    _cachedMasteredWordIds = null;
    _cachedLearningWordIds = null;
    _cachedTodayWords = null;
  }
  void _checkUser(MyDatabase db, String userId) {
    if (_cachedUserId != userId) {
      _cachedUserId = userId;
      _cachedMasteredWordIds = null;
      _cachedLearningWordIds = null;
      _cachedTodayWords = null;
    }
  }

  Future<Set<String>> getLearningWordIds(MyDatabase db, String userId) async {
    _checkUser(db, userId);
    if (_cachedLearningWordIds == null) {
      final query = db.select(db.learningWords)..where((tbl) => tbl.userId.equals(userId));
      final words = await query.get();
      _cachedLearningWordIds = words.map((e) => e.wordId).toSet();
    }
    return _cachedLearningWordIds!;
  }

  Future<Set<String>> getMasteredWordIds(MyDatabase db, String userId) async {
    _checkUser(db, userId);
    if (_cachedMasteredWordIds == null) {
      final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(userId);
      _cachedMasteredWordIds = masteredWords.map((e) => e.wordId).toSet();
    }
    return _cachedMasteredWordIds!;
  }

  Future<List<LearningWord>> getTodayWords(MyDatabase db, String userId) async {
    _checkUser(db, userId);
    if (_cachedTodayWords == null) {
      final query = db.select(db.learningWords)
        ..where((tbl) => tbl.userId.equals(userId) & tbl.batchId.isBiggerThanValue(0))
        ..orderBy([
          (tbl) => OrderingTerm(expression: tbl.batchId),
          (tbl) => OrderingTerm(expression: tbl.learningOrder),
        ]);
      _cachedTodayWords = await query.get();
    }
    return _cachedTodayWords!;
  }

  /// 保存单词状态并同步缓存（核心：保证数据库与缓存一致）
  Future<void> saveAndSyncWordState(MyDatabase db, LearningWord updatedWord) async {
    _checkUser(db, updatedWord.userId);
    
    // 1. 落库
    await db.learningWordsDao.saveEntity(updatedWord, true);

    // 2. 同步更新 _cachedTodayWords
    if (_cachedTodayWords != null) {
      final idx = _cachedTodayWords!.indexWhere((w) => w.wordId == updatedWord.wordId);
      if (idx != -1) {
        _cachedTodayWords![idx] = updatedWord;
      }
    }

    // 3. 同步维护 ID 集合缓存
    final isGraduated = updatedWord.stability != null && updatedWord.stability! >= Constants.graduationStability;
    if (isGraduated) {
      _cachedMasteredWordIds?.add(updatedWord.wordId);
      _cachedLearningWordIds?.remove(updatedWord.wordId);
    } else {
      _cachedMasteredWordIds?.remove(updatedWord.wordId);
      _cachedLearningWordIds?.add(updatedWord.wordId);
    }

    // 4. 使用 assert 确保一致性（在开发测试阶段提早发现问题）
    assert(_cachedTodayWords == null || _cachedTodayWords!.where((w) => w.wordId == updatedWord.wordId).first.todayLearnedTimes == updatedWord.todayLearnedTimes, '缓存与数据库状态不一致');
  }

  /// 标记已掌握并同步缓存
  Future<void> saveMasteredWordAndSync(MyDatabase db, String userId, String wordId) async {
    _checkUser(db, userId);
    
    await db.masteredWordsDao.saveMasteredWord(userId, wordId, true, true);
    
    _cachedMasteredWordIds?.add(wordId);
    _cachedLearningWordIds?.remove(wordId);
  }

  /// 移除今日单词并同步缓存
  Future<void> deleteAndSyncWordState(MyDatabase db, LearningWord learningWord) async {
    _checkUser(db, learningWord.userId);
    
    await db.learningWordsDao.deleteEntity(learningWord, true);
    
    if (_cachedTodayWords != null) {
      _cachedTodayWords!.removeWhere((w) => w.wordId == learningWord.wordId);
    }
    _cachedLearningWordIds?.remove(learningWord.wordId);
  }

  /// 强制刷新缓存（用于同步等大变动场景）
  Future<void> refreshCache(MyDatabase db, String userId) async {
    _cachedUserId = userId;
    _cachedMasteredWordIds = null;
    _cachedLearningWordIds = null;
    _cachedTodayWords = null;
    
    await getMasteredWordIds(db, userId);
    await getLearningWordIds(db, userId);
    await getTodayWords(db, userId);
  }
  /// 根据多端同步拉取到的增量数据，增量合并到现有缓存中（避免全量刷新破坏性能）
  void mergeSyncData(MyDatabase db, String userId, {
    List<LearningWord>? updatedLearningWords,
    List<String>? newMasteredWordIds,
    List<String>? removedLearningWordIds,
  }) {
    _checkUser(db, userId);
    
    // 1. 增量更新今日背词计划
    if (updatedLearningWords != null && _cachedTodayWords != null) {
      for (final updated in updatedLearningWords) {
        final idx = _cachedTodayWords!.indexWhere((w) => w.wordId == updated.wordId);
        if (idx != -1) {
          _cachedTodayWords![idx] = updated;
        } else if ((updated.batchId ?? 0) > 0) {
          _cachedTodayWords!.add(updated);
        }
      }
      
      // 保持学习顺序排序
      _cachedTodayWords!.sort((a, b) {
        final batchCompare = (a.batchId ?? 0).compareTo(b.batchId ?? 0);
        if (batchCompare != 0) return batchCompare;
        return a.learningOrder.compareTo(b.learningOrder);
      });
    }

    // 2. 增量维护已掌握和学习中 ID
    if (newMasteredWordIds != null) {
      _cachedMasteredWordIds?.addAll(newMasteredWordIds);
      _cachedLearningWordIds?.removeAll(newMasteredWordIds);
    }

    if (removedLearningWordIds != null) {
      _cachedLearningWordIds?.removeAll(removedLearningWordIds);
      _cachedTodayWords?.removeWhere((w) => removedLearningWordIds.contains(w.wordId));
    }
  }
  // 仅供测试使用：获取当前缓存状态以供断言
  Set<String>? get cachedMasteredWordIds => _cachedMasteredWordIds;
  Set<String>? get cachedLearningWordIds => _cachedLearningWordIds;
  List<LearningWord>? get cachedTodayWords => _cachedTodayWords;
}
