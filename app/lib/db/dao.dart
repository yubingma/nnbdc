import 'package:drift/drift.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/table.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/db_log_util.dart';
import 'package:nnbdc/util/oper_type.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';

import '../global.dart';
import '../services/throttled_sync_service.dart';
import '../util/error_handler.dart';
import 'db.dart';
import '../constants.dart';

part 'dao.g.dart';

// the _TodosDaoMixin will be created by drift. It contains all the necessary
// fields for the tables. The <MyDatabase> type annotation is the database class
// that should use this dao.
@DriftAccessor(tables: [Users])
class UsersDao extends DatabaseAccessor<MyDatabase> with _$UsersDaoMixin {
  // this constructor is required so that the main database can create an instance
  // of this object.
  UsersDao(super.db);

  // loads all user entries
  Future<List<User>> get allUsers => select(users).get();

  // watches all user entries in a given category. The stream will automatically
  // emit new items whenever the underlying data changes.
  Stream<List<User>> watchUsers() {
    return select(users).watch();
  }

  Future<User?> getUserById(String id) {
    return (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();
  }

  // 根据用户名查询用户
  Future<User?> getUserByUserName(String userName) {
    return (select(users)..where((u) => u.userName.equals(userName))).getSingleOrNull();
  }

  // 根据邮箱查询用户
  Future<User?> getUserByEmail(String email) {
    return (select(users)..where((u) => u.email.equals(email))).getSingleOrNull();
  }

  // 添加带日志记录的更新方法
  Future<void> saveUser(User entry, bool genLog) async {
    var user = await getUserById(entry.id);
    try {
      if (user == null) {
        await into(users).insert(entry);
        if (genLog) {
          await DbLogUtil.logOperation(entry.id, 'INSERT', 'users', entry.id, entry);
          ThrottledDbSyncService().requestSync();
        }
      } else {
        // [优化] 仅在数据真实发生变化时才更新数据库并产生同步日志
        if (user != entry) {
          await update(users).replace(entry);
          if (genLog) {
            await DbLogUtil.logOperation(entry.id, 'UPDATE', 'users', entry.id, entry);
            ThrottledDbSyncService().requestSync();
          }
        }
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'saveUser', showToast: false);
      rethrow;
    }
  }

  // 更新每日单词数并记录日志
  Future<void> updateWordsPerDay(String userId, int wordsPerDay) async {
    var user = await getUserById(userId);
    if (user != null) {
      var updatedUser = user.copyWith(wordsPerDay: wordsPerDay);
      await saveUser(updatedUser, true);
    }
  }

  Future<User?> getLastLoggedInUser() async {
    var result = await (select(users)..orderBy([(u) => OrderingTerm(expression: u.lastLoginTime, mode: OrderingMode.desc)])).get();
    return result.isEmpty ? null : result.first;
  }

  // 删除用户记录
  Future<void> deleteUser(String userId) async {
    await (delete(users)..where((u) => u.id.equals(userId))).go();
  }
}

@DriftAccessor(tables: [LocalParams])
class LocalParamsDao extends DatabaseAccessor<MyDatabase> with _$LocalParamsDaoMixin {
  LocalParamsDao(super.db);

  Future<LocalParam> getParamByName(String paramName) {
    return (select(localParams)..where((e) => e.name.equals(paramName))).getSingle();
  }

  Future<bool> getIsDarkMode() async {
    try {
      var param = await (select(localParams)..where((e) => e.name.equals('isDarkMode'))).getSingleOrNull();
      return param?.value == 'true';
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'getIsDarkMode', showToast: false);
      return false; // 默认返回非夜间模式
    }
  }

  Future<void> saveIsDarkMode(bool isDarkMode) async {
    try {
      final existing = await (select(localParams)..where((e) => e.name.equals('isDarkMode'))).getSingleOrNull();
      final value = isDarkMode ? 'true' : 'false';
      if (existing == null) {
        await into(localParams).insert(LocalParamsCompanion.insert(name: 'isDarkMode', value: value));
      } else {
        await (update(localParams)..where((e) => e.name.equals('isDarkMode'))).write(LocalParamsCompanion(value: Value(value)));
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'saveIsDarkMode', showToast: false);
      rethrow;
    }
  }



  /// 获取是否已显示过单词列表新手引导
  Future<bool> getWordListGuideShown() async {
    try {
      var param = await (select(localParams)..where((e) => e.name.equals('wordListGuideShown'))).getSingleOrNull();
      return param?.value == 'true';
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'getWordListGuideShown', showToast: false);
      return false;
    }
  }

  /// 设置单词列表新手引导已显示
  Future<void> setWordListGuideShown(bool shown) async {
    try {
      final existing = await (select(localParams)..where((e) => e.name.equals('wordListGuideShown'))).getSingleOrNull();
      if (existing == null) {
        await into(localParams).insert(LocalParamsCompanion.insert(name: 'wordListGuideShown', value: shown ? 'true' : 'false'));
      } else {
        await (update(localParams)..where((e) => e.name.equals('wordListGuideShown')))
            .write(LocalParamsCompanion(value: Value(shown ? 'true' : 'false')));
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'setWordListGuideShown', showToast: false);
      rethrow;
    }
  }
}

@DriftAccessor(tables: [VotedSentences])
class VotedSentencesDao extends DatabaseAccessor<MyDatabase> with _$VotedSentencesDaoMixin {
  VotedSentencesDao(super.db);

  Future<VotedSentence?> getVotedSentenceById(String userId, String sentenceId) {
    return (select(votedSentences)..where((vs) => vs.userId.equals(userId) & vs.sentenceId.equals(sentenceId))).getSingleOrNull();
  }

  Future<void> createEntity(VotedSentence entry) async {
    var votedSentence = await getVotedSentenceById(entry.userId, entry.sentenceId);
    if (votedSentence == null) {
      await into(votedSentences).insert(entry);
    } else {
      ToastUtil.error('不能对例句重复投票');
    }
  }
}

@DriftAccessor(tables: [VotedWordImages])
class VotedWordImagesDao extends DatabaseAccessor<MyDatabase> with _$VotedWordImagesDaoMixin {
  VotedWordImagesDao(super.db);

  Future<VotedWordImage?> getVotedWordImageById(String userId, String wordImageId) {
    return (select(votedWordImages)..where((vs) => vs.userId.equals(userId) & vs.imageId.equals(wordImageId))).getSingleOrNull();
  }

  Future<void> createEntity(VotedWordImage entry) async {
    var votedSentence = await getVotedWordImageById(entry.userId, entry.imageId);
    if (votedSentence == null) {
      await into(votedWordImages).insert(entry);
    } else {
      ToastUtil.error('不能对例句翻译重复投票');
    }
  }
}

@DriftAccessor(tables: [LearningDicts])
class LearningDictsDao extends DatabaseAccessor<MyDatabase> with _$LearningDictsDaoMixin {
  LearningDictsDao(super.db);

  Future<LearningDict?> findById(String userId, String dictId) {
    return (select(learningDicts)..where((ld) => ld.userId.equals(userId) & ld.dictId.equals(dictId))).getSingleOrNull();
  }

  Future<List<LearningDict>> getLearningDictsOfUser(String userId) {
    return (select(learningDicts)..where((ld) => ld.userId.equals(userId))).get();
  }

  Future<void> deleteEntity(LearningDict entity, bool genLog) async {
    await delete(learningDicts).delete(entity);
    if (genLog) {
      await DbLogUtil.logOperation(entity.userId, 'DELETE', 'learningDicts', '${entity.userId}-${entity.dictId}', entity);
    }
  }

  Future<void> saveEntity(LearningDict entry, bool genLog) async {
    try {
      var dict = await findById(entry.userId, entry.dictId);
      if (dict == null) {
        await into(learningDicts).insert(entry);
        if (genLog) {
          await DbLogUtil.logOperation(entry.userId, 'INSERT', 'learningDicts', '${entry.userId}-${entry.dictId}', entry);
        }
      } else {
        // [优化] 仅在数据真实发生变化时才更新数据库并产生同步日志
        if (dict != entry) {
          await update(learningDicts).replace(entry);
          if (genLog) {
            await DbLogUtil.logOperation(entry.userId, 'UPDATE', 'learningDicts', '${entry.userId}-${entry.dictId}', entry);
          }
        }
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'saveEntity(LearningDict)', showToast: false);
      rethrow;
    }
  }

  Future<bool> togglePrivileged(String userId, String dictId, bool genLog) async {
    var dict = await findById(userId, dictId);
    if (dict == null) {
      return false;
    }

    final newPrivilegedStatus = !dict.isPrivileged;

    await (update(learningDicts)..where((ld) => ld.userId.equals(userId) & ld.dictId.equals(dictId))).write(LearningDictsCompanion(
      isPrivileged: Value(newPrivilegedStatus),
    ));

    if (genLog) {
      final updatedDict = dict.copyWith(isPrivileged: newPrivilegedStatus);
      await DbLogUtil.logOperation(userId, 'UPDATE', 'learningDicts', '$userId-$dictId', updatedDict);
    }

    return newPrivilegedStatus;
  }

  /// 删除用户的所有学习词典记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(learningDicts)..where((ld) => ld.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'dictId':
            query = query..where((ld) => ld.dictId.equals(fieldValue.toString()));
            break;
          case 'isPrivileged':
            query = query..where((ld) => ld.isPrivileged.equals(fieldValue == true));
            break;
          default:
            Global.logger.w('⚠️ LearningDictsDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }
}

@DriftAccessor(tables: [Dicts])
class DictsDao extends DatabaseAccessor<MyDatabase> with _$DictsDaoMixin {
  DictsDao(super.db);

  Future<Dict?> findById(String dictId) {
    return (select(dicts)..where((d) => d.id.equals(dictId))).getSingleOrNull();
  }

  Future<void> createEntity(Dict entry) async {
    var dict = await findById(entry.id);
    if (dict == null) {
      await into(dicts).insert(entry);
    }
  }

  /// 保存词典（支持INSERT和UPDATE，支持日志）
  Future<void> saveEntity(Dict entry, bool genLog) async {
    try {
      var existing = await findById(entry.id);
      if (existing == null) {
        await into(dicts).insert(entry);
        if (genLog) {
          await DbLogUtil.logOperation(entry.ownerId, 'INSERT', 'dicts', entry.id, entry);
        }
      } else {
        await update(dicts).replace(entry);
        if (genLog) {
          await DbLogUtil.logOperation(entry.ownerId, 'UPDATE', 'dicts', entry.id, entry);
        }
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'saveEntity(Dict)', showToast: false);
      rethrow;
    }
  }

  /// 更新词书的wordCount字段（并生成日志）
  /// 根据dictWords表的实际数据重新计算wordCount
  Future<void> updateWordCount(String dictId, bool genLog) async {
    try {
      // 获取词书
      final dict = await findById(dictId);
      if (dict == null) {
        Global.logger.w('词书不存在，无法更新wordCount: dictId=$dictId');
        return;
      }

      // 计算实际的单词数量
      final actualCount = await MyDatabase.instance.dictWordsDao.getDictWordCount(dictId);

      // 如果wordCount不一致，则更新
      if (dict.wordCount != actualCount) {
        final now = AppClock.now();

        // 直接更新，避免在saveEntity中再次查询
        await (update(dicts)..where((d) => d.id.equals(dictId))).write(DictsCompanion(
          wordCount: Value(actualCount),
          updateTime: Value(now),
        ));

        // 如果需要生成日志
        if (genLog) {
          // 创建更新后的dict对象用于日志
          final updatedDict = Dict(
            id: dict.id,
            isReady: dict.isReady,
            isShared: dict.isShared,
            name: dict.name,
            wordCount: actualCount,
            ownerId: dict.ownerId,
            visible: dict.visible,
            editable: dict.editable,
            deletable: dict.deletable,
            createTime: dict.createTime,
            updateTime: now,
          );
          await DbLogUtil.logOperation(dict.ownerId, 'UPDATE', 'dicts', dictId, updatedDict);
        }

        Global.logger.d('已更新词书wordCount: dictId=$dictId, 旧值=${dict.wordCount}, 新值=$actualCount');
      }
    } catch (e, stackTrace) {
      Global.logger.e('更新词书wordCount失败: dictId=$dictId, error=$e', stackTrace: stackTrace);
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'updateWordCount', showToast: false);
      rethrow;
    }
  }

  Future<void> deleteAll() async {
    await delete(dicts).go();
  }

  Future<void> saveAll(List<Dict> entries) async {
    await batch((batch) {
      batch.insertAll(dicts, entries, mode: InsertMode.insertOrReplace);
    });
  }

  /// 根据所有者查找词典
  Future<List<Dict>> findByOwnerId(String ownerId) async {
    return (select(dicts)..where((d) => d.ownerId.equals(ownerId))).get();
  }

  /// 查找指定用户的"生词本"词书
  Future<Dict?> findUserRawDict(String userId) async {
    try {
      final query = select(dicts)
        ..where((d) => d.ownerId.equals(userId))
        ..where((d) => d.name.equals('生词本'));
      final results = await query.get();

      if (results.length > 1) {
        final details = results.map((d) => 'ID: ${d.id}, 创建于: ${d.createTime}').join('\n  - ');
        throw Exception('核心数据异常: 用户 [$userId] 拥有 ${results.length} 本"生词本"词书！\n  - $details');
      }

      return results.isEmpty ? null : results.first;
    } catch (e, stackTrace) {
      Global.logger.e('查询"生词本"词书时崩溃', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Dict?> findUserMasteredDict(String userId) async {
    try {
      final query = select(dicts)
        ..where((d) => d.ownerId.equals(userId))
        ..where((d) => d.name.equals('已掌握'));

      final results = await query.get();

      if (results.length > 1) {
        final details = results.map((d) => 'ID: ${d.id}, 创建于: ${d.createTime}').join('\n  - ');
        throw Exception('核心数据异常: 用户 [$userId] 拥有 ${results.length} 本"已掌握"词书！\n  - $details');
      }

      return results.isEmpty ? null : results.first;
    } catch (e, stackTrace) {
      Global.logger.e('查询"已掌握"词书时崩溃', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 删除词典（支持日志）
  Future<void> deleteEntity(Dict entry, bool genLog) async {
    try {
      await (delete(dicts)..where((d) => d.id.equals(entry.id))).go();
      if (genLog) {
        await DbLogUtil.logOperation(entry.ownerId, 'DELETE', 'dicts', entry.id, entry);
      }
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'deleteEntity(Dict)', showToast: false);
      rethrow;
    }
  }
}

@DriftAccessor(tables: [Words])
class WordsDao extends DatabaseAccessor<MyDatabase> with _$WordsDaoMixin {
  WordsDao(super.db);

  Future<Word?> getWordById(String wordId) {
    return (select(words)..where((d) => d.id.equals(wordId))).getSingleOrNull();
  }

  Future<void> insertEntity(Word entry) async {
    try {
      await into(words).insertOnConflictUpdate(entry);
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'insertEntity(Word)', showToast: false);
      rethrow;
    }
  }

  Future<void> insertEntities(List<Word> entries) async {
    try {
      if (entries.isEmpty) return;

      Global.logger.d('🔍 开始插入 ${entries.length} 个单词');

      // 直接插入所有数据，如果主键冲突则替换
      await batch((batch) {
        batch.insertAll(words, entries, mode: InsertMode.insertOrReplace);
      });

      Global.logger.d('✅ 单词插入完成, 总数: ${entries.length}');
    } catch (e, stackTrace) {
      ErrorHandler.handleDatabaseError(e, stackTrace, db: this, operation: 'insertEntities(Word)', showToast: false);
      rethrow;
    }
  }

  Future<int> getWordCount() async {
    final countQuery = selectOnly(words)..addColumns([countAll()]);
    final count = await countQuery.getSingle();
    return count.read(countAll()) ?? 0;
  }
  Future<List<Word>> getWordsByIds(List<String> wordIds) {
    return (select(words)..where((w) => w.id.isIn(wordIds))).get();
  }
}

@DriftAccessor(tables: [UserDbLogs])
class UserDbLogsDao extends DatabaseAccessor<MyDatabase> with _$UserDbLogsDaoMixin {
  UserDbLogsDao(super.db);

  Future<List<UserDbLog>> getUserDbLogs(String userId) {
    return (select(userDbLogs)
          ..where((lg) => lg.userId.equals(userId))
          ..orderBy([(lg) => OrderingTerm(expression: lg.createTime, mode: OrderingMode.asc)]))
        .get();
  }

  Future<UserDbLog?> getUserDbLogById(String id) {
    return (select(userDbLogs)..where((lg) => lg.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertEntity(UserDbLog entry) async {
    var dbLog = await getUserDbLogById(entry.id);
    if (dbLog == null) {
      await into(userDbLogs).insert(entry);
    } else {
      ToastUtil.error('不能重复创建用户db日志');
    }
  }

  Future<void> updateEntity(UserDbLog entry) async {
    await update(userDbLogs).replace(entry);
  }

  Future<UserDbLog?> getLatestLog(String userId, String tblName, String recordId) {
    return (select(userDbLogs)
          ..where((lg) => lg.userId.equals(userId) & lg.tblName.equals(tblName) & lg.recordId.equals(recordId))
          ..orderBy([(lg) => OrderingTerm(expression: lg.createTime, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
  }

  // 清空指定用户的所有日志
  Future<void> deleteUserDbLogs(String userId) async {
    await (delete(userDbLogs)..where((lg) => lg.userId.equals(userId))).go();
  }
}

@DriftAccessor(tables: [UserDbVersions])
class UserDbVersionsDao extends DatabaseAccessor<MyDatabase> with _$UserDbVersionsDaoMixin {
  UserDbVersionsDao(super.db);

  Future<UserDbVersion?> getUserDbVersionByUserId(String id) {
    return (select(userDbVersions)..where((lg) => lg.userId.equals(id))).getSingleOrNull();
  }

  Future<void> saveEntity(UserDbVersion entry) async {
    await into(userDbVersions).insertOnConflictUpdate(entry);
  }
}

@DriftAccessor(tables: [DictWords])
class DictWordsDao extends DatabaseAccessor<MyDatabase> with _$DictWordsDaoMixin {
  DictWordsDao(super.db);

  Future<DictWord?> getById(String dictId, String wordId) {
    return (select(dictWords)..where((dw) => dw.dictId.equals(dictId) & dw.wordId.equals(wordId))).getSingleOrNull();
  }

  Future<void> insertEntity(DictWord entry, bool genLog) async {
    var existing = await getById(entry.dictId, entry.wordId);
    if (existing == null) {
      DictWord entryToInsert = entry;

      if (genLog) {
        // 获取词书中单词最大的seq
        final maxSeqQuery = selectOnly(dictWords)
          ..addColumns([dictWords.seq.max()])
          ..where(dictWords.dictId.equals(entry.dictId));

        final maxSeqResult = await maxSeqQuery.getSingle();
        final maxSeq = maxSeqResult.read(dictWords.seq.max()) ?? 0;

        // 创建新的entry，seq为最大值+1
        entryToInsert = entry.copyWith(seq: maxSeq + 1);
        Global.logger.d('词书添加单词: wordId=${entry.wordId}, 新seq=${maxSeq + 1}');
      }

      await into(dictWords).insert(entryToInsert);
      if (genLog) {
        var dict = await MyDatabase.instance.dictsDao.findById(entry.dictId);
        var owner = dict?.ownerId;
        await DbLogUtil.logOperation(owner!, 'INSERT', 'dictWords', '${entry.dictId}-${entry.wordId}', entryToInsert);

        await _validateDictWordsOrder(entry.dictId);
      }
    }
  }

  // 删除词书中的单词（单纯删除数据，不处理序号，仅供同步或已有清理逻辑的包装方法使用）
  Future<void> deleteEntity(DictWord entry, bool genLog) async {
    if (genLog) {
      var dict = await MyDatabase.instance.dictsDao.findById(entry.dictId);
      var owner = dict?.ownerId;
      // 先生成删除日志
      await DbLogUtil.logOperation(owner!, 'DELETE', 'dictWords', '${entry.dictId}-${entry.wordId}', entry);
    }
    // 删除数据
    await delete(dictWords).delete(entry);
  }

  /// 完整删除词典单词（包括后续序号调整、wordCount更新、学习进度修复）
  /// [dictId] 词典ID
  /// [wordId] 单词ID
  /// [userId] 用户ID（用于修复特定用户的学习进度，如果为null则修复所有用户）
  /// [genLog] 是否生成日志
  Future<void> deleteDictWordWithCleanup(String dictId, String wordId, String? userId, bool genLog) async {
    final dictWord = await getById(dictId, wordId);
    if (dictWord == null) {
      Global.logger.w('词书中无该单词: dictId=$dictId, wordId=$wordId');
      return;
    }

    final seqNo = dictWord.seq;

    // 生成删除日志（如果需要）
    if (genLog) {
      var dict = await MyDatabase.instance.dictsDao.findById(dictId);
      var owner = dict?.ownerId;
      await DbLogUtil.logOperation(owner!, 'DELETE', 'dictWords', '$dictId-$wordId', dictWord);
    }

    // 删除记录
    await delete(dictWords).delete(dictWord);


    // 更新词书的wordCount
    await MyDatabase.instance.dictsDao.updateWordCount(dictId, genLog);

    // 学习进度已改为基于状态计算，不再需要维护 currentWordSeq
    Global.logger.d('已删除词典单词并完成清理: dictId=$dictId, wordId=$wordId, seqNo=$seqNo');
  }

  // 批量插入词书中的单词
  Future<void> insertEntities(List<DictWord> entries, bool genLog) async {
    if (entries.isEmpty) return;

    // 直接插入所有数据，如果主键冲突则替换
    await batch((batch) {
      batch.insertAll(dictWords, entries, mode: InsertMode.insertOrReplace);
    });

    // 生成日志（如果需要）
    if (genLog) {
      for (var entry in entries) {
        var dict = await MyDatabase.instance.dictsDao.findById(entry.dictId);
        var owner = dict?.ownerId;
        await DbLogUtil.logOperation(owner!, 'INSERT', 'dictWords', '${entry.dictId}-${entry.wordId}', entry);
      }
    }

    Global.logger.d('✅ 词书单词关联插入完成, 总数: ${entries.length}');
  }

  // 检查词书中是否包含单词
  Future<bool> hasDictWords(String dictId) async {
    final countQuery = selectOnly(dictWords)
      ..addColumns([countAll()])
      ..where(dictWords.dictId.equals(dictId));

    final count = await countQuery.getSingle();
    return (count.read(countAll()) ?? 0) > 0;
  }

  // 获取词书中单词的数量
  Future<int> getDictWordCount(String dictId) async {
    final countQuery = selectOnly(dictWords)
      ..addColumns([countAll()])
      ..where(dictWords.dictId.equals(dictId));

    final count = await countQuery.getSingle();
    return count.read(countAll()) ?? 0;
  }

  // 清空词书中的单词（适用于生词本）
  Future<void> clearDictWord(String dictId, bool genLog) async {
    final dict = await MyDatabase.instance.dictsDao.findById(dictId);
    if (dict == null) {
      Global.logger.w('词书不存在: dictId=$dictId');
      return;
    }

    if (genLog) {
      var owner = dict.ownerId;
      // 先查询要删除的数据，用于生成日志
      List<DictWord> entries = await (select(dictWords)..where((dw) => dw.dictId.equals(dictId))).get();
      // 删除数据
      await (delete(dictWords)..where((dw) => dw.dictId.equals(dictId))).go();
      // 生成删除日志
      for (var entry in entries) {
        await DbLogUtil.logOperation(owner, 'DELETE', 'dictWords', '${entry.dictId}-${entry.wordId}', entry);
      }
    } else {
      // 不生成日志时直接删除
      await (delete(dictWords)..where((dw) => dw.dictId.equals(dictId))).go();
    }

    // 更新词书的wordCount（并生成日志用于同步）
    await MyDatabase.instance.dictsDao.updateWordCount(dictId, genLog);

    // 如果是生词本，清空后需要重置排序
    if (dict.name == '生词本') {
      Global.logger.d('生词本已清空，排序已重置，wordCount已更新为0');
    }
  }

  /// 删除用户的词书单词记录
  /// [userId] 用户ID（用于验证词典所有权）
  /// [filters] 过滤条件，必须包含dictId字段
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    // 验证待删除的词典是否属于指定用户
    filters ??= {};
    String? dictId;
    if (filters.containsKey('dictId')) {
      dictId = filters['dictId'];
      final dict = await MyDatabase.instance.dictsDao.findById(dictId!);
      if (dict?.ownerId != userId) {
        Global.logger.w('⚠️ 词典不属于用户: dictId=$dictId, userId=$userId, ownerId=${dict?.ownerId}');
        return;
      }
    }

    // 删除指定词典中的单词记录
    var query = delete(dictWords);

    // 应用其他过滤条件
    for (final entry in filters.entries) {
      final fieldName = entry.key;
      final fieldValue = entry.value;

      switch (fieldName) {
        case 'dictId':
          query = query..where((dw) => dw.dictId.equals(fieldValue.toString()));
          break;

        default:
          Global.logger.w('⚠️ DictWordsDao不支持过滤字段: $fieldName');
      }
    }

    await query.go();

    // 批量删除后，更新词书的wordCount（并生成日志用于同步）
    final finalDictId = dictId;
    if (finalDictId != null) {
      await MyDatabase.instance.dictsDao.updateWordCount(finalDictId, true);
    }
  }

  // 重新排序词书的seq
  Future<void> _reorderDictWords(String dictId, bool genLog) async {
    // 获取词书中所有单词，按seq排序
    final dictWordsList = await (select(dictWords)
          ..where((dw) => dw.dictId.equals(dictId))
          ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
        .get();

    if (dictWordsList.isEmpty) return;

    // 重新分配seq，从1开始
    for (int i = 0; i < dictWordsList.length; i++) {
      final oldEntry = dictWordsList[i];
      final newSeq = i + 1;

      if (oldEntry.seq != newSeq) {
        // 更新seq
        final newEntry = oldEntry.copyWith(seq: newSeq);
        await (update(dictWords)..where((dw) => dw.dictId.equals(dictId) & dw.wordId.equals(oldEntry.wordId)))
            .write(DictWordsCompanion(seq: Value(newSeq)));

        // 生成更新日志
        if (genLog) {
          var dict = await MyDatabase.instance.dictsDao.findById(dictId);
          var owner = dict?.ownerId;
          await DbLogUtil.logOperation(owner!, 'UPDATE', 'dictWords', '$dictId-${oldEntry.wordId}', newEntry);
        }
      }
    }

    // 验证词书顺序号 (不自动修复以防无限循环)
    await _validateDictWordsOrder(dictId, autoFix: false);
  }

  // 验证词书顺序号的完整性
  Future<void> _validateDictWordsOrder(String dictId, {bool autoFix = true}) async {
    // 获取词书中所有单词，按seq排序
    final dictWordsList = await (select(dictWords)
          ..where((dw) => dw.dictId.equals(dictId))
          ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
        .get();

    if (dictWordsList.isEmpty) return;

    final totalCount = dictWordsList.length;
    final minSeq = dictWordsList.first.seq;
    final maxSeq = dictWordsList.last.seq;

    bool needsFix = false;

    // 检查1: 最小序号是1，最大顺序号是总单词数量
    if (minSeq != 1 || maxSeq != totalCount) {
      final errorMsg = '⛔ 词书($dictId)顺序号异常: 最小序号=$minSeq, 最大序号=$maxSeq, 总数量=$totalCount';
      Global.logger.e(errorMsg);
      needsFix = true;
    }

    if (!needsFix) {
      // 检查2: 序号是否连续
      for (int i = 0; i < dictWordsList.length; i++) {
        if (dictWordsList[i].seq != i + 1) {
          final errorMsg = '⛔ 词书($dictId)序号不连续: 期望=${i + 1}, 实际=${dictWordsList[i].seq}, 单词ID: ${dictWordsList[i].wordId}';
          Global.logger.e(errorMsg);
          needsFix = true;
          break;
        }
      }
    }

    if (needsFix) {
      if (autoFix) {
        Global.logger.i('🔧 检测到词书顺序异常，将静默重排(dictId=$dictId)...');
        await _reorderDictWords(dictId, false);
      }
      return;
    }

    Global.logger.d('词书顺序号验证成功: 总数=$totalCount');
  }

  // 对外公开的校验方法，供同步前调用
  Future<void> validateDictWordsOrder(String dictId) async {
    await _validateDictWordsOrder(dictId);
  }

  // 通用修复方法，供同步时调用
  Future<void> fixDictOrder(String dictId, bool genLog) async {
    await _reorderDictWords(dictId, genLog);
  }

  // 通用生成本地全量日志：直接生成UPDATE日志，覆盖后端数据
  Future<void> generateFullDictRewriteLogs(String userId, String dictId) async {
    final words = await (select(dictWords)
          ..where((dw) => dw.dictId.equals(dictId))
          ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
        .get();

    for (final w in words) {
      await DbLogUtil.logOperation(userId, 'UPDATE', 'dictWords', '${w.dictId}-${w.wordId}', w);
    }
  }
}

@DriftAccessor(tables: [WordImages])
class WordImagesDao extends DatabaseAccessor<MyDatabase> with _$WordImagesDaoMixin {
  WordImagesDao(super.db);

  Future<WordImage?> getById(String id) {
    return (select(wordImages)..where((wi) => wi.id.equals(id))).getSingleOrNull();
  }

  Future<List<WordImage>> getImagesByWordId(String wordId) {
    return (select(wordImages)..where((wi) => wi.wordId.equals(wordId))).get();
  }

  Future<void> insertEntity(WordImage entry) async {
    await into(wordImages).insertOnConflictUpdate(entry);
  }

  Future<void> insertEntities(List<WordImage> entries) async {
    if (entries.isEmpty) return;

    // 直接插入所有数据，如果主键冲突则替换
    await batch((batch) {
      batch.insertAll(wordImages, entries, mode: InsertMode.insertOrReplace);
    });

    Global.logger.d('✅ 单词图片插入完成, 总数: ${entries.length}');
  }
}

@DriftAccessor(tables: [VerbTenses])
class VerbTensesDao extends DatabaseAccessor<MyDatabase> with _$VerbTensesDaoMixin {
  VerbTensesDao(super.db);

  Future<VerbTense?> getById(String id) {
    return (select(verbTenses)..where((vt) => vt.id.equals(id))).getSingleOrNull();
  }

  Future<void> saveEntity(VerbTense entry) async {
    await into(verbTenses).insertOnConflictUpdate(entry);
  }
}

@DriftAccessor(tables: [Synonyms])
class SynonymsDao extends DatabaseAccessor<MyDatabase> with _$SynonymsDaoMixin {
  SynonymsDao(super.db);

  Future<Synonym?> getById(String meaningItemId, String wordId) {
    return (select(synonyms)..where((vt) => vt.meaningItemId.equals(meaningItemId) & vt.wordId.equals(wordId))).getSingleOrNull();
  }

  Future<void> insertEntity(Synonym entry) async {
    await into(synonyms).insertOnConflictUpdate(entry);
  }

  Future<void> insertEntities(List<Synonym> entries) async {
    if (entries.isEmpty) return;

    // 直接插入所有数据，如果主键冲突则替换
    await batch((batch) {
      batch.insertAll(synonyms, entries, mode: InsertMode.insertOrReplace);
    });

    Global.logger.d('✅ 同义词插入完成, 总数: ${entries.length}');
  }
}

@DriftAccessor(tables: [SimilarWords])
class SimilarWordsDao extends DatabaseAccessor<MyDatabase> with _$SimilarWordsDaoMixin {
  SimilarWordsDao(super.db);

  Future<SimilarWord?> getById(String wordId, String similarWordId) {
    return (select(similarWords)..where((sw) => sw.wordId.equals(wordId) & sw.similarWordId.equals(similarWordId))).getSingleOrNull();
  }

  Future<void> insertEntity(SimilarWord entry) async {
    await into(similarWords).insertOnConflictUpdate(entry);
  }

  Future<void> insertEntities(List<SimilarWord> entries) async {
    if (entries.isEmpty) return;

    // 直接插入所有数据，如果主键冲突则替换
    await batch((batch) {
      batch.insertAll(similarWords, entries, mode: InsertMode.insertOrReplace);
    });

    Global.logger.d('✅ 形近词插入完成, 总数: ${entries.length}');
  }
}

@DriftAccessor(tables: [Cigens])
class CigensDao extends DatabaseAccessor<MyDatabase> with _$CigensDaoMixin {
  CigensDao(super.db);

  Future<Cigen?> getById(String id) {
    return (select(cigens)..where((sw) => sw.id.equals(id))).getSingleOrNull();
  }

  Future<void> saveEntity(Cigen entry) async {
    await into(cigens).insertOnConflictUpdate(entry);
  }
}

@DriftAccessor(tables: [CigenWordLinks])
class CigenWordLinksDao extends DatabaseAccessor<MyDatabase> with _$CigenWordLinksDaoMixin {
  CigenWordLinksDao(super.db);

  Future<CigenWordLink?> getById(String cigenId, String wordId) {
    return (select(cigenWordLinks)..where((link) => link.cigenId.equals(cigenId) & link.wordId.equals(wordId))).getSingleOrNull();
  }

  Future<List<CigenWordLink>> getLinksByWordId(String wordId) {
    return (select(cigenWordLinks)..where((link) => link.wordId.equals(wordId))).get();
  }

  Future<void> saveEntity(CigenWordLink entry) async {
    await into(cigenWordLinks).insertOnConflictUpdate(entry);
  }
}

@DriftAccessor(tables: [MeaningItems])
class MeaningItemsDao extends DatabaseAccessor<MyDatabase> with _$MeaningItemsDaoMixin {
  MeaningItemsDao(super.db);

  Future<MeaningItem?> getById(String id) {
    return (select(meaningItems)..where((mi) => mi.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertEntity(MeaningItem entry, bool genLog) async {
    await into(meaningItems).insertOnConflictUpdate(entry);
    if (genLog && entry.dictId != null) {
      var dict = await MyDatabase.instance.dictsDao.findById(entry.dictId!);
      var owner = dict?.ownerId;
      if (owner != null) {
        await DbLogUtil.logOperation(owner, 'INSERT', 'meaningItems', entry.id, entry);
      }
    }
  }

  Future<void> deleteEntity(String id, bool genLog) async {
    // 先获取要删除的实体，以便记录日志
    var entry = await getById(id);
    await (delete(meaningItems)..where((mi) => mi.id.equals(id))).go();
    if (genLog && entry != null && entry.dictId != null) {
      var dict = await MyDatabase.instance.dictsDao.findById(entry.dictId!);
      var owner = dict?.ownerId;
      if (owner != null) {
        await DbLogUtil.logOperation(owner, 'DELETE', 'meaningItems', entry.id, entry);
      }
    }
  }

  Future<void> insertEntities(List<MeaningItem> entries) async {
    if (entries.isEmpty) return;

    // 直接插入所有数据，如果主键冲突则替换
    await batch((batch) {
      batch.insertAll(meaningItems, entries, mode: InsertMode.insertOrReplace);
    });

    Global.logger.d('✅ 释义项插入完成, 总数: ${entries.length}');
  }
}

@DriftAccessor(tables: [Sentences])
class SentencesDao extends DatabaseAccessor<MyDatabase> with _$SentencesDaoMixin {
  SentencesDao(super.db);

  Future<Sentence?> getById(String id) {
    return (select(sentences)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertEntity(Sentence entry) async {
    await into(sentences).insertOnConflictUpdate(entry);
  }

  Future<void> insertEntities(List<Sentence> entries) async {
    if (entries.isEmpty) return;

    // 直接插入所有数据，如果主键冲突则替换
    await batch((batch) {
      batch.insertAll(sentences, entries, mode: InsertMode.insertOrReplace);
    });

    Global.logger.d('✅ 例句插入完成, 总数: ${entries.length}');
  }

  Future<void> updateHandCount(String sentenceId, int handCount) async {
    await (update(sentences)..where((s) => s.id.equals(sentenceId))).write(SentencesCompanion(handCount: Value(handCount)));
  }

  Future<void> updateFootCount(String sentenceId, int footCount) async {
    await (update(sentences)..where((s) => s.id.equals(sentenceId))).write(SentencesCompanion(footCount: Value(footCount)));
  }
}

@DriftAccessor(tables: [LearningWords])
class LearningWordsDao extends DatabaseAccessor<MyDatabase> with _$LearningWordsDaoMixin {
  LearningWordsDao(super.db);

  Future<LearningWord?> getById(String userId, String wordId) {
    return (select(learningWords)..where((lw) => lw.userId.equals(userId) & lw.wordId.equals(wordId))).getSingleOrNull();
  }

  Future<void> saveEntity(LearningWord entry, bool genLog) async {
    try {
      var existing = await getById(entry.userId, entry.wordId);
      if (existing == null) {
        await into(learningWords).insertOnConflictUpdate(entry);
        if (genLog) {
          await DbLogUtil.logOperation(entry.userId, 'INSERT', 'learningWords', '${entry.userId}-${entry.wordId}', entry);
        }
      } else {
        // [优化] 仅在数据真实发生变化时才更新数据库并产生同步日志，极大节省带宽
        if (existing != entry) {
          await into(learningWords).insertOnConflictUpdate(entry);
          if (genLog) {
            await DbLogUtil.logOperation(entry.userId, 'UPDATE', 'learningWords', '${entry.userId}-${entry.wordId}', entry);
          }
        }
      }
    } catch (e, stackTrace) {
      Global.logger.d('保存学习单词异常: $e');
      Global.logger.d('异常堆栈: $stackTrace');
      rethrow;
    }
  }

  Future<void> deleteEntity(LearningWord entity, bool genLog) async {
    await delete(learningWords).delete(entity);
    if (genLog) {
      await DbLogUtil.logOperation(entity.userId, 'DELETE', 'learningWords', '${entity.userId}-${entity.wordId}', entity);
    }
  }

  /// 删除用户的所有学习单词记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(learningWords)..where((lw) => lw.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'wordId':
            query = query..where((lw) => lw.wordId.equals(fieldValue.toString()));
            break;
          case 'stability':
            query = query..where((lw) => lw.stability.equals(fieldValue is double ? fieldValue : double.tryParse(fieldValue.toString()) ?? 0.0));
            break;
          case 'lastLearningDate':
            if (fieldValue is DateTime) {
              query = query..where((lw) => lw.lastLearningDate.equals(fieldValue));
            }
            break;
          default:
            Global.logger.w('⚠️ LearningWordsDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }

  /// 删除用户已经掌握的单词（从"已掌握"词书推导）
  Future<void> deleteMasteredWords(String userId) async {
    final db = MyDatabase.instance;
    // 获取用户已掌握的所有单词ID
    final masteredWordIds = await db.masteredWordsDao.getMasteredWordIdSet(userId);

    if (masteredWordIds.isNotEmpty) {
      // 从 learning_words 表中批量删除这些已掌握的词
      await (delete(learningWords)
            ..where((lw) => lw.userId.equals(userId) & lw.wordId.isIn(masteredWordIds.toList())))
          .go();
      Global.logger.d('已从 learningWords 中删除 ${masteredWordIds.length} 个已掌握单词');
    }
  }

  /// 删除已掌握的学习中单词（掌握度为5）
  Future<int> deleteMasteredLearningWords(String userId) async {
    final query = delete(learningWords)
      ..where((lw) => lw.userId.equals(userId) & lw.stability.isBiggerOrEqualValue(Constants.graduationStability));
    final deletedCount = await query.go();
    if (deletedCount > 0) {
      Global.logger.d('已从 learningWords 中删除 $deletedCount 个已掌握（掌握度为5）的单词');
    }
    return deletedCount;
  }

  /// 获取用于记忆云图展示的数据
  Future<List<Map<String, dynamic>>> getLearningWordsForCloud(String userId) async {
    final query = select(learningWords).join([
      innerJoin(db.words, db.words.id.equalsExp(learningWords.wordId)),
      leftOuterJoin(db.cigenWordLinks, db.cigenWordLinks.wordId.equalsExp(learningWords.wordId)),
      leftOuterJoin(db.cigens, db.cigens.id.equalsExp(db.cigenWordLinks.cigenId)),
    ])
      ..where(learningWords.userId.equals(userId) & (learningWords.stability.isNull() | learningWords.stability.isSmallerThanValue(Constants.graduationStability)));

    final results = await query.get();
    return results.map((row) {
      final lw = row.readTable(learningWords);
      final word = row.readTable(db.words);
      final cigen = row.readTableOrNull(db.cigens);

      return {
        'word': word.spell,
        'stability': lw.stability,
        'difficulty': lw.difficulty,
        'scheduledDays': lw.scheduledDays,
        'lastLearningDate': lw.lastLearningDate,
        'popularity': word.popularity,
        'reps': lw.reps,
        'state': lw.state,
        'category': cigen?.description ?? '',
      };
    }).toList();
  }
}


@DriftAccessor(tables: [DictGroups])
class DictGroupsDao extends DatabaseAccessor<MyDatabase> with _$DictGroupsDaoMixin {
  DictGroupsDao(super.db);

  Future<void> deleteAll() => delete(dictGroups).go();

  Future<void> saveAll(List<DictGroupsCompanion> entries) async {
    await batch((batch) {
      batch.insertAll(dictGroups, entries, mode: InsertMode.insertOrReplace);
    });
  }

  Future<void> saveEntity(DictGroup entry) async {
    await into(dictGroups).insertOnConflictUpdate(entry);
  }
}

@DriftAccessor(tables: [GroupAndDictLinks])
class GroupAndDictLinksDao extends DatabaseAccessor<MyDatabase> with _$GroupAndDictLinksDaoMixin {
  GroupAndDictLinksDao(super.db);

  Future<void> saveAll(List<GroupAndDictLinksCompanion> entries) async {
    await batch((batch) {
      batch.insertAll(groupAndDictLinks, entries, mode: InsertMode.insertOrReplace);
    });
  }

  Future<void> saveEntity(GroupAndDictLink entry) async {
    await into(groupAndDictLinks).insertOnConflictUpdate(entry);
  }

  Future<void> deleteAll() async {
    await delete(groupAndDictLinks).go();
  }
}

@DriftAccessor(tables: [UserStudySteps])
class UserStudyStepsDao extends DatabaseAccessor<MyDatabase> with _$UserStudyStepsDaoMixin {
  UserStudyStepsDao(super.db);

  // 获取用户的所有学习步骤，按index顺序排列
  Future<List<UserStudyStep>> getUserStudySteps(String userId) {
    return (select(userStudySteps)
          ..where((s) => s.userId.equals(userId))
          ..orderBy([(s) => OrderingTerm(expression: s.seq)]))
        .get();
  }

  // 获取用户的激活状态的学习步骤，按index顺序排列
  Future<List<UserStudyStep>> getActiveUserStudySteps(String userId) {
    return (select(userStudySteps)
          ..where((s) => s.userId.equals(userId) & s.state.equals('Active'))
          ..orderBy([(s) => OrderingTerm(expression: s.seq)]))
        .get();
  }

  // 保存用户的学习步骤，若存在则更新(会判断是否真正发生了变化)，不存在则创建
  Future<void> saveUserStudyStep(UserStudyStep step, bool genLog) async {
    final UserStudyStep? existing =
        await (select(userStudySteps)..where((s) => s.userId.equals(step.userId) & s.studyStep.equals(step.studyStep))).getSingleOrNull();

    if (existing == null) {
      await into(userStudySteps).insert(step);
      if (genLog) {
        await DbLogUtil.logOperation(step.userId, 'INSERT', 'userStudySteps', '${step.userId}-${step.studyStep}', step);
      }
    } else {
      // 更新
      step = step.copyWith(updateTime: Value(AppClock.now()));
      if (existing.state != step.state || existing.seq != step.seq) {
        await update(userStudySteps).replace(step);
        if (genLog) {
          await DbLogUtil.logOperation(step.userId, 'UPDATE', 'userStudySteps', '${step.userId}-${step.studyStep}', step);
        }
      }
    }
  }

  // 批量保存用户的学习步骤(会判断是否真正发生了变化)
  Future<void> saveUserStudySteps(List<UserStudyStep> steps, String userId, bool genLog) async {
    for (final step in steps) {
      await saveUserStudyStep(step, genLog);
    }
  }

  // 删除特定的学习步骤
  Future<void> deleteUserStudyStep(String userId, String studyStep, bool genLog) async {
    await (delete(userStudySteps)..where((s) => s.userId.equals(userId) & s.studyStep.equals(studyStep))).go();
    if (genLog) {
      await DbLogUtil.logOperation(userId, 'DELETE', 'userStudySteps', '$userId-$studyStep', null);
    }
  }



  /// 删除用户的所有学习步骤记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(userStudySteps)..where((s) => s.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'studyStep':
            query = query..where((s) => s.studyStep.equals(fieldValue.toString()));
            break;
          case 'state':
            query = query..where((s) => s.state.equals(fieldValue.toString()));
            break;
          case 'index':
            query = query..where((s) => s.seq.equals(fieldValue is int ? fieldValue : int.tryParse(fieldValue.toString()) ?? 0));
            break;
          default:
            Global.logger.w('⚠️ UserStudyStepsDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }

  /// 删除所有用户的听音选意模式数据
  /// 这个方法用于彻底移除听音选意功能
  Future<void> deleteAllPronounceModeData() async {
    // 删除所有studyStep为'Pronounce'的记录
    await (delete(userStudySteps)..where((s) => s.studyStep.equals('Pronounce'))).go();

    Global.logger.d('已删除所有听音选意模式的用户数据');
  }
}

@DriftAccessor(tables: [Dakas])
class DakasDao extends DatabaseAccessor<MyDatabase> with _$DakasDaoMixin {
  DakasDao(super.db);

  // 通过复合主键查找打卡记录
  Future<Daka?> findById(String userId, DateTime forLearningDate) {
    return (select(dakas)..where((d) => d.userId.equals(userId) & d.forLearningDate.equals(forLearningDate))).getSingleOrNull();
  }

  // 获取用户的所有打卡记录
  Future<List<Daka>> getDakaRecords(String userId) {
    return (select(dakas)
          ..where((d) => d.userId.equals(userId))
          ..orderBy([(d) => OrderingTerm(expression: d.forLearningDate, mode: OrderingMode.desc)]))
        .get();
  }

  // 保存打卡记录
  Future<void> saveDaka(Daka record, bool genLog) async {
    var existing = await findById(record.userId, record.forLearningDate);
    if (existing == null) {
      await into(dakas).insert(record);
      if (genLog) {
        await DbLogUtil.logOperation(record.userId, 'INSERT', 'dakas', '${record.userId}-${Util.formatDate(record.forLearningDate)}', record);
      }
    } else {
      // [优化] 仅在数据真实发生变化时才更新数据库并产生同步日志
      if (existing != record) {
        await update(dakas).replace(record);
        if (genLog) {
          await DbLogUtil.logOperation(
              record.userId, 'UPDATE', 'dakas', '${record.userId}-${Util.formatDate(record.forLearningDate)}', record);
        }
      }
    }
  }

  // 删除打卡记录
  Future<void> deleteDaka(Daka record, bool genLog) async {
    await delete(dakas).delete(record);
    if (genLog) {
      await DbLogUtil.logOperation(
          record.userId, 'DELETE', 'dakas', '${record.userId}-${Util.formatDate(record.forLearningDate)}', record);
    }
  }

  /// 删除用户的所有打卡记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(dakas)..where((d) => d.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'forLearningDate':
            if (fieldValue is DateTime) {
              query = query..where((d) => d.forLearningDate.equals(fieldValue));
            }
            break;
          case 'textContent':
            query = query..where((d) => d.textContent.equals(fieldValue.toString()));
            break;
          default:
            Global.logger.w('⚠️ DakasDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }
}

@DriftAccessor(tables: [UserOpers])
class UserOpersDao extends DatabaseAccessor<MyDatabase> with _$UserOpersDaoMixin {
  UserOpersDao(super.db);

  // 获取用户的所有操作历史记录
  Future<List<UserOper>> getUserOpers(String userId) {
    return (select(userOpers)
          ..where((h) => h.userId.equals(userId))
          ..orderBy([(h) => OrderingTerm(expression: h.operTime, mode: OrderingMode.desc)]))
        .get();
  }

  // 根据操作类型获取用户的操作历史记录
  Future<List<UserOper>> getUserOpersByType(String userId, OperType operType) {
    return (select(userOpers)
          ..where((h) => h.userId.equals(userId) & h.operType.equals(operType.value))
          ..orderBy([(h) => OrderingTerm(expression: h.operTime, mode: OrderingMode.desc)]))
        .get();
  }

  // 添加用户操作记录
  Future<void> saveUserOper(UserOper record, bool genLog) async {
    // 先检查记录是否已存在，避免UNIQUE constraint错误
    final existingRecord = await getById(record.id);
    if (existingRecord != null) {
      // 记录已存在，执行更新
      await (update(userOpers)..where((u) => u.id.equals(record.id))).write(UserOpersCompanion(
        userId: Value(record.userId),
        operType: Value(record.operType),
        operTime: Value(record.operTime),
        remark: Value(record.remark),
        updateTime: Value(record.updateTime),
      ));
    } else {
      // 记录不存在，执行插入
      await into(userOpers).insert(record);
    }

    if (genLog) {
      await DbLogUtil.logOperation(record.userId, 'INSERT', 'userOpers', record.id, record);
    }
  }

  // 创建登录操作记录
  Future<void> recordLogin(String userId, {String? remark}) async {
    var now = AppClock.now();
    var record = UserOper(
      id: Util.uuid(),
      userId: userId,
      operType: OperType.login.value,
      operTime: now,
      remark: remark,
      createTime: now,
      updateTime: now,
    );
    await saveUserOper(record, true);
  }

  // 创建开始学习操作记录
  Future<void> recordStartLearn(String userId, {String? remark}) async {
    var now = AppClock.now();
    var record = UserOper(
      id: Util.uuid(),
      userId: userId,
      operType: OperType.startLearn.value,
      operTime: now,
      remark: remark,
      createTime: now,
      updateTime: now,
    );
    await saveUserOper(record, true);
  }

  // 创建打卡操作记录
  Future<void> recordDaka(String userId, {String? remark}) async {
    var now = AppClock.now();
    var record = UserOper(
      id: Util.uuid(),
      userId: userId,
      operType: OperType.daka.value,
      operTime: now,
      remark: remark,
      createTime: now,
      updateTime: now,
    );
    await saveUserOper(record, true);
  }

  // 根据ID获取单个操作历史记录
  Future<UserOper?> getById(String id) {
    return (select(userOpers)..where((h) => h.id.equals(id))).getSingleOrNull();
  }

  // 根据用户ID和日期查询操作记录
  Future<List<UserOper>> getByUserIdAndDate(String userId, DateTime date, OperType operType) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      return await (select(userOpers)
            ..where((h) =>
                h.userId.equals(userId) &
                h.operTime.isBiggerOrEqualValue(startOfDay) &
                h.operTime.isSmallerOrEqualValue(endOfDay) &
                h.operType.equals(operType.value))
            ..orderBy([(h) => OrderingTerm(expression: h.operTime, mode: OrderingMode.desc)]))
          .get();
    } catch (e, stackTrace) {
      Global.logger.d('查询用户操作记录时出错: $e');
      Global.logger.d('异常堆栈: $stackTrace');
      Global.logger.d('查询参数: userId=$userId, date=$date, operType=${operType.value}');
      rethrow;
    }
  }

  /// 删除用户的所有操作记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(userOpers)..where((u) => u.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'operType':
            query = query..where((u) => u.operType.equals(fieldValue.toString()));
            break;
          case 'operTime':
            if (fieldValue is DateTime) {
              query = query..where((u) => u.operTime.equals(fieldValue));
            }
            break;
          case 'remark':
            query = query..where((u) => u.remark.equals(fieldValue.toString()));
            break;
          default:
            Global.logger.w('⚠️ UserOpersDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }
}

@DriftAccessor(tables: [DictWords, Dicts])
class MasteredWordsDao extends DatabaseAccessor<MyDatabase> with _$MasteredWordsDaoMixin {
  MasteredWordsDao(super.db);

  /// 获取用户的"已掌握"词书的dictId
  /// "已掌握"词书只允许在创建用户时创建（后端createNewUser或前端loginAsGuest）
  Future<String?> _getMasteredDictId(String userId) async {
    final existing = await db.dictsDao.findUserMasteredDict(userId);
    if (existing != null) return existing.id;
    return null;
  }

  /// 获取用户所有已掌握单词（从"已掌握"词书的dict_word获取）
  Future<List<DictWord>> getMasteredWordsForUser(String userId) async {
    final dictId = await _getMasteredDictId(userId);
    if (dictId == null) return [];
    return (select(db.dictWords)
          ..where((dw) => dw.dictId.equals(dictId))
          ..orderBy([(dw) => OrderingTerm(expression: dw.seq, mode: OrderingMode.asc)]))
        .get();
  }

  /// 获取用户已掌握单词的wordId集合（高效接口，只返回wordId）
  Future<Set<String>> getMasteredWordIdSet(String userId) async {
    final dictId = await _getMasteredDictId(userId);
    if (dictId == null) return {};
    final rows = await (selectOnly(db.dictWords)
          ..addColumns([db.dictWords.wordId])
          ..where(db.dictWords.dictId.equals(dictId)))
        .get();
    return rows.map((row) => row.read(db.dictWords.wordId)!).toSet();
  }

  // 检查单词是否已被掌握（在"已掌握"词书中）
  Future<bool> isWordMastered(String userId, String wordId) async {
    final dictId = await _getMasteredDictId(userId);
    if (dictId == null) return false;
    final existing = await (select(db.dictWords)
          ..where((dw) => dw.dictId.equals(dictId) & dw.wordId.equals(wordId)))
        .getSingleOrNull();
    return existing != null;
  }

  // 将单词添加到"已掌握"词书
  Future<void> saveMasteredWord(String userId, String wordId, bool genLog, bool updateUser) async {
    final dictId = await _getMasteredDictId(userId);
    if (dictId == null) {
      Global.logger.w('用户的"已掌握"词书不存在，无法保存记录: userId=$userId');
      return;
    }

    // 检查是否已存在
    final existing = await (select(db.dictWords)
          ..where((dw) => dw.dictId.equals(dictId) & dw.wordId.equals(wordId)))
        .getSingleOrNull();

    if (existing != null) {
      Global.logger.d('单词已在已掌握词书中: wordId=$wordId');
      return;
    }

    // 获取最大seq
    final maxSeqResult = await (selectOnly(db.dictWords)
          ..addColumns([db.dictWords.seq.max()])
          ..where(db.dictWords.dictId.equals(dictId)))
        .getSingle();
    final maxSeq = maxSeqResult.read(db.dictWords.seq.max()) ?? 0;

    final now = AppClock.now();
    final newDictWord = DictWord(
      dictId: dictId,
      wordId: wordId,
      seq: maxSeq + 1,
      unit: 0,
      createTime: now,
      updateTime: now,
    );

    await db.dictWordsDao.insertEntity(newDictWord, genLog);

    // 更新词书wordCount
    await db.dictsDao.updateWordCount(dictId, genLog);

    if (updateUser) {
      await updateUserMasteredWordCount(userId);
    }
  }

  // 删除掌握的单词（从"已掌握"词书中移除，并移动到生词本）
  Future<void> deleteMasteredWord(String userId, String wordId, bool genLog, bool updateUser) async {
    try {
      final dictId = await _getMasteredDictId(userId);
      if (dictId == null) return;

      final existing = await (select(db.dictWords)
            ..where((dw) => dw.dictId.equals(dictId) & dw.wordId.equals(wordId)))
          .getSingleOrNull();
      if (existing == null) {
        Global.logger.w('要删除的已掌握单词不在词书中: userId=$userId, wordId=$wordId');
        return;
      }

      // 1. 从已掌握词书中删除
      await db.dictWordsDao.deleteEntity(existing, genLog);

      // 2. 更新词书wordCount
      await db.dictsDao.updateWordCount(dictId, genLog);

      // 3. 将单词添加到生词本
      await _addWordToRawWordDict(userId, wordId, genLog);

      // 4. 更新用户已掌握单词数量
      if (updateUser) {
        await updateUserMasteredWordCount(userId);
      }

      Global.logger.d('已掌握单词删除成功并移动到生词本: userId=$userId, wordId=$wordId');
    } catch (e) {
      Global.logger.e('删除已掌握单词失败: userId=$userId, wordId=$wordId, error=$e');
      rethrow;
    }
  }

  // 将单词添加到生词本的私有方法
  Future<void> _addWordToRawWordDict(String userId, String wordId, bool genLog) async {
    try {
      final word = await (select(db.words)..where((w) => w.id.equals(wordId))).getSingleOrNull();
      if (word == null) {
        Global.logger.e('单词不存在: wordId=$wordId');
        return;
      }
      final result = await WordBo().addRawWord(word.spell, '重学添加');
      if (!result.success) {
        Global.logger.e('添加单词到生词本失败: ${result.msg}');
      } else {
        Global.logger.d('单词已添加到生词本: wordId=$wordId, spell=${word.spell}');
      }
    } catch (e) {
      Global.logger.e('添加单词到生词本失败: userId=$userId, wordId=$wordId, error=$e');
    }
  }

  // 将学习中的单词标记为已掌握
  // 将学习中的单词标记为已掌握
  Future<void> setLearningWordAsMastered(String userId, String wordId, bool deleteLearningWord) async {
    final db = MyDatabase.instance;
    final learningWord = await db.learningWordsDao.getById(userId, wordId);

    // 1. 添加到已掌握词书
    await saveMasteredWord(userId, wordId, true, true);

    if (learningWord != null) {
      final now = AppClock.now();
      // 2. 处理学习中记录
      final user = await db.usersDao.getUserById(userId);
      if (user?.todayStudyStarted ?? false) {
        final steps = await db.userStudyStepsDao.getActiveUserStudySteps(userId);
        await db.learningWordsDao.saveEntity(
            learningWord.copyWith(
              stability: Value(Constants.graduationStability),
              lastLearningDate: Value(now),
              learnedTimes: learningWord.learnedTimes + 1,
              todayLearnedTimes: steps.length,
            ),
            true);
      } else {
        if (deleteLearningWord) {
          await db.learningWordsDao.deleteEntity(learningWord, true);
        } else {
          await db.learningWordsDao.saveEntity(learningWord.copyWith(stability: Value(Constants.graduationStability)), true);
        }
      }
    }
  }


  // 查询已掌握词书中的单词数, 并据此更新用户已掌握单词数量
  Future<void> updateUserMasteredWordCount(String userId) async {
    final dictId = await _getMasteredDictId(userId);
    if (dictId == null) return;
    final masteredCount = await db.dictWordsDao.getDictWordCount(dictId);

    final user = await db.usersDao.getUserById(userId);
    if (user != null) {
      await db.usersDao.saveUser(user.copyWith(masteredWordsCount: masteredCount), true);
    }
  }

  // 获取已掌握单词在列表中的位置
  Future<int> getMasteredWordOrder(String userId, String spell) async {
    try {
      final word = await (select(db.words)..where((w) => w.spell.equals(spell))).getSingleOrNull();
      if (word == null) return -1;

      final dictId = await _getMasteredDictId(userId);
      if (dictId == null) return -1;

      final dictWord = await (select(db.dictWords)
            ..where((dw) => dw.dictId.equals(dictId) & dw.wordId.equals(word.id)))
          .getSingleOrNull();
      if (dictWord == null) return -1;

      final count = await (selectOnly(db.dictWords)
            ..addColumns([countAll()])
            ..where(db.dictWords.dictId.equals(dictId) &
                db.dictWords.seq.isSmallerOrEqualValue(dictWord.seq)))
          .getSingle();

      return count.read(countAll()) ?? 0;
    } catch (e) {
      Global.logger.e('获取已掌握单词位置失败: $e');
      return -1;
    }
  }

  /// 删除用户的所有已掌握单词记录（从"已掌握"词书中清空）
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    final dictId = await _getMasteredDictId(userId);
    if (dictId == null) return;

    await (delete(db.dictWords)..where((dw) => dw.dictId.equals(dictId))).go();
    await db.dictsDao.updateWordCount(dictId, false);
  }
}



@DriftAccessor(tables: [BookMarks])
class BookmarksDao extends DatabaseAccessor<MyDatabase> with _$BookmarksDaoMixin {
  BookmarksDao(super.db);

  // 根据ID查询书签
  Future<BookMark?> getById(String id) {
    return (select(bookMarks)..where((b) => b.id.equals(id))).getSingleOrNull();
  }

  // 根据用户ID和书签名称查询书签
  Future<BookMark?> findByUserIdAndName(String userId, String name) {
    return (select(bookMarks)..where((b) => b.userId.equals(userId) & b.bookMarkName.equals(name))).getSingleOrNull();
  }

  // 获取用户的所有书签
  Future<List<BookMark>> getBookmarksForUser(String userId) {
    return (select(bookMarks)..where((b) => b.userId.equals(userId))).get();
  }

  // 保存书签（新增或更新）
  Future<void> saveBookmark(BookMark entity, bool genLog) async {
    // 优先通过逻辑唯一键（用户ID + 书签名称）进行查找，避免 UUID 冲突导致的唯一性约束失败
    final existingByLogicalKey = await findByUserIdAndName(entity.userId, entity.bookMarkName);

    if (existingByLogicalKey != null) {
      if (existingByLogicalKey.id != entity.id) {
        // 如果逻辑上是同一个书签但 ID 不同（通常发生在多端同步时），先删除本地旧 ID 的书签再插入新的，以保证与服务端 ID 同步
        await (delete(bookMarks)..where((b) => b.id.equals(existingByLogicalKey.id))).go();
        await into(bookMarks).insert(entity);
      } else {
        await update(bookMarks).replace(entity);
      }

      if (genLog) {
        await DbLogUtil.logOperation(entity.userId, 'UPDATE', 'bookMarks', entity.id, entity);
      }
    } else {
      // 如果按逻辑键没查到，再按物理主键查找一次（兜底逻辑）
      final bookmark = await getById(entity.id);
      if (bookmark == null) {
        await into(bookMarks).insert(entity);
        if (genLog) {
          await DbLogUtil.logOperation(entity.userId, 'INSERT', 'bookMarks', entity.id, entity);
        }
      } else {
        await update(bookMarks).replace(entity);
        if (genLog) {
          await DbLogUtil.logOperation(entity.userId, 'UPDATE', 'bookMarks', entity.id, entity);
        }
      }
    }
  }

  // 删除书签
  Future<void> deleteBookmark(String bookmarkId, bool genLog) async {
    final bookmark = await getById(bookmarkId);
    if (bookmark != null) {
      await (delete(bookMarks)..where((b) => b.id.equals(bookmarkId))).go();

      if (genLog) {
        await DbLogUtil.logOperation(bookmark.userId, 'DELETE', 'bookMarks', bookmarkId, bookmark);
      }
    }
  }

  /// 删除用户的所有书签记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(bookMarks)..where((b) => b.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'bookMarkName':
            query = query..where((b) => b.bookMarkName.equals(fieldValue.toString()));
            break;
          case 'spell':
            query = query..where((b) => b.spell.equals(fieldValue.toString()));
            break;
          case 'createTime':
            if (fieldValue is DateTime) {
              query = query..where((b) => b.createTime.equals(fieldValue));
            }
            break;
          default:
            Global.logger.w('⚠️ BookmarksDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }
}

@DriftAccessor(tables: [UserCowDungLogs])
class UserCowDungLogsDao extends DatabaseAccessor<MyDatabase> with _$UserCowDungLogsDaoMixin {
  UserCowDungLogsDao(super.db);

  Future<void> insertEntity(UserCowDungLog log, bool genLog) async {
    await into(userCowDungLogs).insertOnConflictUpdate(log);
    if (genLog) {
      await DbLogUtil.logOperation(
        log.userId,
        'INSERT',
        'userCowDungLogs',
        log.id,
        log,
      );
    }
  }

  /// 删除用户的所有牛粪日志记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(userCowDungLogs)..where((u) => u.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'delta':
            query = query..where((u) => u.delta.equals(fieldValue is int ? fieldValue : int.tryParse(fieldValue.toString()) ?? 0));
            break;
          case 'cowDung':
            query = query..where((u) => u.cowDung.equals(fieldValue is int ? fieldValue : int.tryParse(fieldValue.toString()) ?? 0));
            break;
          case 'theTime':
            if (fieldValue is DateTime) {
              query = query..where((u) => u.theTime.equals(fieldValue));
            }
            break;
          case 'reason':
            query = query..where((u) => u.reason.equals(fieldValue.toString()));
            break;
          default:
            Global.logger.w('⚠️ UserCowDungLogsDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }
}

// UserBatchWordsDao has been removed - BatchWord functionality is no longer used

@DriftAccessor(tables: [UserWrongWords])
class UserWrongWordsDao extends DatabaseAccessor<MyDatabase> with _$UserWrongWordsDaoMixin {
  UserWrongWordsDao(super.db);

  Future<UserWrongWord?> getEntity(String userId, String wordId) {
    return (select(userWrongWords)..where((uw) => uw.userId.equals(userId) & uw.wordId.equals(wordId))).getSingleOrNull();
  }

  Future<void> saveEntity(UserWrongWord entry, bool genLog) async {
    var entity = await getEntity(entry.userId, entry.wordId);
    if (entity == null) {
      await into(userWrongWords).insert(entry);
      if (genLog) {
        await DbLogUtil.logOperation(entry.userId, 'INSERT', 'userWrongWords', '${entry.userId}-${entry.wordId}', entry);
        ThrottledDbSyncService().requestSync();
      }
    } else {
      await update(userWrongWords).replace(entry);
      if (genLog) {
        await DbLogUtil.logOperation(entry.userId, 'UPDATE', 'userWrongWords', '${entry.userId}-${entry.wordId}', entry);
        ThrottledDbSyncService().requestSync();
      }
    }
  }

  Future<void> deleteEntity(UserWrongWord entry, bool genLog) async {
    await (delete(userWrongWords)..where((uw) => uw.userId.equals(entry.userId) & uw.wordId.equals(entry.wordId))).go();
    if (genLog) {
      await DbLogUtil.logOperation(entry.userId, 'DELETE', 'userWrongWords', '${entry.userId}-${entry.wordId}', entry);
      ThrottledDbSyncService().requestSync();
    }
  }

  Future<List<UserWrongWord>> getTodayWrongWords(String userId) async {
    final now = AppClock.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    return (select(userWrongWords)
          ..where((uw) => uw.userId.equals(userId) & uw.createTime.isBiggerOrEqualValue(startOfDay) & uw.createTime.isSmallerOrEqualValue(endOfDay))
          ..orderBy([(uw) => OrderingTerm(expression: uw.createTime, mode: OrderingMode.desc)]))
        .get();
  }

  /// 删除用户的所有错词记录
  /// [userId] 用户ID
  /// [filters] 可选的过滤条件，Map<字段名, 字段值>，只删除匹配的记录
  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(userWrongWords)..where((uw) => uw.userId.equals(userId));

    // 应用过滤条件
    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'wordId':
            query = query..where((uw) => uw.wordId.equals(fieldValue.toString()));
            break;
          case 'createTime':
            if (fieldValue is DateTime) {
              query = query..where((uw) => uw.createTime.equals(fieldValue));
            }
            break;
          default:
            Global.logger.w('⚠️ UserWrongWordsDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }

  // 清空用户的所有错词
  Future<void> clearUserWrongWords(String userId, bool genLog) async {
    final wrongWords = await (select(userWrongWords)..where((uw) => uw.userId.equals(userId))).get();

    for (final wrongWord in wrongWords) {
      await deleteEntity(wrongWord, genLog);
    }

    Global.logger.d('已清空用户错词: userId=$userId, 清空数量=${wrongWords.length}');
  }
}

@DriftAccessor(tables: [SysDbVersion])
class SysDbVersionDao extends DatabaseAccessor<MyDatabase> with _$SysDbVersionDaoMixin {
  SysDbVersionDao(super.db);

  /// 获取本地UGC版本（单例）
  Future<SysDbVersionData?> getVersion() async {
    return (select(sysDbVersion)..where((t) => t.id.equals('singleton'))).getSingleOrNull();
  }

  /// 保存版本（单例，自动更新）
  Future<void> saveVersion(SysDbVersionData version) async {
    await into(sysDbVersion).insertOnConflictUpdate(version);
  }
}



@DriftAccessor(tables: [LocalExceptions])
class LocalExceptionsDao extends DatabaseAccessor<MyDatabase> with _$LocalExceptionsDaoMixin {
  LocalExceptionsDao(super.db);

  /// 插入异常记录
  Future<void> insertException(LocalException exception) async {
    await into(localExceptions).insert(exception);
  }

  /// 获取所有异常记录（按时间倒序）
  Future<List<LocalException>> getAllExceptions({int? limit}) async {
    var query = select(localExceptions)..orderBy([(e) => OrderingTerm(expression: e.createTime, mode: OrderingMode.desc)]);
    if (limit != null) {
      query = query..limit(limit);
    }
    return query.get();
  }

  /// 根据ID获取异常记录
  Future<LocalException?> getExceptionById(String id) async {
    return (select(localExceptions)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  /// 删除异常记录
  Future<void> deleteException(String id) async {
    await (delete(localExceptions)..where((e) => e.id.equals(id))).go();
  }

  /// 删除所有异常记录
  Future<void> deleteAllExceptions() async {
    await delete(localExceptions).go();
  }

  /// 获取异常记录数量
  Future<int> getExceptionCount() async {
    final result = await (selectOnly(localExceptions)..addColumns([localExceptions.id.count()])).getSingle();
    return result.read(localExceptions.id.count()) ?? 0;
  }
}

@DriftAccessor(tables: [LearningLogs])
class LearningLogsDao extends DatabaseAccessor<MyDatabase> with _$LearningLogsDaoMixin {
  LearningLogsDao(super.db);

  Future<void> saveEntity(LearningLog entity, bool genLog) async {
    await into(learningLogs).insertOnConflictUpdate(entity);
    if (genLog) {
      await DbLogUtil.logOperation(entity.userId, 'INSERT', 'learningLogs', entity.id, entity);
    }
  }

  Future<List<LearningLog>> getHistory(String userId, String wordId) {
    return (select(learningLogs)
          ..where((l) => l.userId.equals(userId) & l.wordId.equals(wordId))
          ..orderBy([(l) => OrderingTerm(expression: l.createTime, mode: OrderingMode.desc)]))
        .get();
  }

  Future<void> batchDeleteUserRecords(String userId, {Map<String, dynamic>? filters}) async {
    var query = delete(learningLogs)..where((l) => l.userId.equals(userId));

    if (filters != null && filters.isNotEmpty) {
      for (final entry in filters.entries) {
        final fieldName = entry.key;
        final fieldValue = entry.value;

        switch (fieldName) {
          case 'wordId':
            query = query..where((l) => l.wordId.equals(fieldValue.toString()));
            break;
          default:
            Global.logger.w('⚠️ LearningLogsDao不支持过滤字段: $fieldName');
        }
      }
    }

    await query.go();
  }
}
