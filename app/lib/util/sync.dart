import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/sync_log_service.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/db_log_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/services/study_cache_manager.dart';

import 'package:nnbdc/util/network_util.dart';
import 'package:nnbdc/util/sys_db_sync.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/api/bo/user_bo.dart';

export 'package:nnbdc/util/sys_db_sync.dart' show syncSysDb;

class DictWordOrderInvalidWarningException implements Exception {
  final String message;
  DictWordOrderInvalidWarningException(this.message);
  @override
  String toString() => message;
}

/// 同步核心业务异常基类，这类异常通常需要在 UI 上直接弹出提示
abstract class SyncCoreException implements Exception {
  final String message;
  SyncCoreException(this.message);
  @override
  String toString() => message;
}

/// 核心数据丢失异常
class CoreDataMissingException extends SyncCoreException {
  CoreDataMissingException(super.message);
}

/// 同步数据解析/类型检查异常
class SyncDataParseException extends SyncCoreException {
  SyncDataParseException(super.message);
}

/// 同步语义/数据安全违规异常
class SyncDataSecurityException extends SyncCoreException {
  SyncDataSecurityException(super.message);
}

// 当前同步日志ID，用于记录同步统计信息
String? _currentSyncLogId;
int _uploadCount = 0;
int _downloadCount = 0;
Map<String, dynamic>? _uploadDetails;
Map<String, dynamic>? _downloadDetails;

/// 设置当前同步日志ID
void setCurrentSyncLogId(String logId) {
  _currentSyncLogId = logId;
  _uploadCount = 0;
  _downloadCount = 0;
  _uploadDetails = null;
  _downloadDetails = null;
}

/// 清除当前同步日志ID
void clearCurrentSyncLogId() {
  _currentSyncLogId = null;
  _uploadCount = 0;
  _downloadCount = 0;
  _uploadDetails = null;
  _downloadDetails = null;
}

/// 记录上行数量
void addUploadCount(int count) {
  _uploadCount += count;
}

/// 记录下行数量
void addDownloadCount(int count) {
  _downloadCount += count;
}

void addUploadDetails(Map<String, dynamic> details) {
  _uploadDetails ??= {};
  details.forEach((tbl, ops) {
    _uploadDetails!.putIfAbsent(tbl, () => <String, dynamic>{});
    (ops as Map<String, dynamic>).forEach((op, count) {
      _uploadDetails![tbl][op] = (_uploadDetails![tbl][op] as int? ?? 0) + (count as int);
    });
  });
}

void addDownloadDetails(Map<String, dynamic> details) {
  _downloadDetails ??= {};
  details.forEach((tbl, ops) {
    _downloadDetails!.putIfAbsent(tbl, () => <String, dynamic>{});
    (ops as Map<String, dynamic>).forEach((op, count) {
      _downloadDetails![tbl][op] = (_downloadDetails![tbl][op] as int? ?? 0) + (count as int);
    });
  });
}

/// 完成同步日志记录
Future<void> completeSyncLog({bool success = true, String? errorMessage, int? dbVersion, int? sysDbVersion}) async {
  if (_currentSyncLogId == null) return;

  final service = SyncLogService();
  if (success) {
    await service.completeSync(
      logId: _currentSyncLogId!,
      uploadCount: _uploadCount,
      downloadCount: _downloadCount,
      uploadDetails: _uploadDetails,
      downloadDetails: _downloadDetails,
      dbVersion: dbVersion,
      sysDbVersion: sysDbVersion,
    );
  } else {
    await service.failSync(
      logId: _currentSyncLogId!,
      errorMessage: errorMessage ?? '同步失败',
    );
  }
  clearCurrentSyncLogId();
}

/// 根据操作类型决定表依赖排序方向
///
/// - INSERT/UPDATE: 正序（优先级小的先执行，即先父后子）
/// - DELETE/BATCH_DELETE: 逆序（优先级大的先执行，即先子后父）
/// - 混合情况: 非删除操作优先于删除操作（确保先完成增改，再执行删除）
int _comparePriorityByOperate(
  String operateA,
  String operateB,
  int priorityA,
  int priorityB,
) {
  bool isDeleteA = operateA == 'DELETE' || operateA == 'BATCH_DELETE';
  bool isDeleteB = operateB == 'DELETE' || operateB == 'BATCH_DELETE';

  if (isDeleteA && isDeleteB) {
    // 两个都是删除：逆序排列（先删子表，即优先级数字大的先执行）
    return priorityB.compareTo(priorityA);
  } else if (!isDeleteA && !isDeleteB) {
    // 两个都不是删除：正序排列（先操作父表，即优先级数字小的先执行）
    return priorityA.compareTo(priorityB);
  } else {
    // 一个删除一个非删除：非删除操作先执行
    return isDeleteA ? 1 : -1;
  }
}

/// 核心数据完整性校验：确保用户的核心词书（生词本、已掌握）存在且唯一
/// 如果发现数据损坏或丢失，直接抛举异常（Fail-Fast）
Future<void> _validateCoreData(String userId) async {
  final db = MyDatabase.instance;
  
  // 校验“生词本” (findUserRawDict 内部已包含多记录校验)
  final rawDict = await db.dictsDao.findUserRawDict(userId);
  if (rawDict == null) {
    throw CoreDataMissingException('核心数据丢失: 用户 [$userId] 缺少 "生词本" 词书！');
  }

  // 校验“已掌握” (findUserMasteredDict 内部已包含多记录校验)
  final masteredDict = await db.dictsDao.findUserMasteredDict(userId);
  if (masteredDict == null) {
    throw CoreDataMissingException('核心数据丢失: 用户 [$userId] 缺少 "已掌握" 词书！');
  }
  
  Global.logger.d('✓ [IntegrityCheck] 核心数据验证通过: userId=$userId');
}

// 同步用户的本地数据库和后端数据库
Future<void> doSyncUserDb(List<UserDbLog> localChanges, List<UserDbLogDto> backendChanges, int backendDbVersion, String userId) async {
  final stopwatch = Stopwatch()..start();
  try {
    // 把后端日志中的表名转化为前端的格式
    for (var change in backendChanges) {
      change.tblName = Util.remoteTableNameToLocal(change.tblName);
    }

    // 把本地日志按表名分组并统计
    var tableStats = <String, int>{};
    for (var log in localChanges) {
      tableStats[log.tblName] = (tableStats[log.tblName] ?? 0) + 1;
    }

    // 把DbLogs转换为Map<String, dynamic>
    List<Map<String, dynamic>> localChangesMap = [];
    for (var change in localChanges) {
      var changeJson = change.toJson();

      // 把本地日志中的时间戳由数字时间戳（毫秒）转换为DateTime
      assert(changeJson['updateTime'] != null, "本地数据库日志 updateTime 不能为空，表：${change.tblName}, ID: ${change.id}");
      assert(changeJson['createTime'] != null, "本地数据库日志 createTime 不能为空，表：${change.tblName}, ID: ${change.id}");
      changeJson['updateTime'] = DateTime.fromMillisecondsSinceEpoch(changeJson['updateTime']);
      changeJson['createTime'] = DateTime.fromMillisecondsSinceEpoch(changeJson['createTime']);

      localChangesMap.add(changeJson);
    }

    List<Map<String, dynamic>> backendChangesMap = [];
    for (var change in backendChanges) {
      var changeJson = change.toJson();

      // 把后端日志中的时间戳(iso8601 String)转换为DateTime
      assert(changeJson["updateTime"] != null, "后端同步日志中的 updateTime 不能为空，表：${change.tblName}, ID: ${change.id}");
      assert(changeJson["createTime"] != null, "后端同步日志中的 createTime 不能为空，表：${change.tblName}, ID: ${change.id}");
      changeJson['updateTime'] = Util.iso8601ToTimestamp(changeJson["updateTime"]);
      changeJson['createTime'] = Util.iso8601ToTimestamp(changeJson["createTime"]);
      backendChangesMap.add(changeJson);
    }

    // 同步
    var result = mergeChanges(localChangesMap, backendChangesMap);

    // 【关键修复】检查并补全缺失的父级词书日志
    // 防止因预置数据库缺失日志导致服务端出现 "dict_word violates foreign key constraint" 错误
    await _ensureParentDictsLogs(result.first, userId);

    // 定义表的优先级(数字越小优先级越高,越先同步)
    int getPriority(String tableName) {
      switch (tableName) {
        case 'users':
          return 1;
        case 'dicts':
          return 2; // dicts必须在dictWords之前
        case 'dictWords':
          return 3; // dictWords依赖dicts
        case 'learningDicts':
          return 4; // learningDicts依赖dicts
        case 'learningWords':
          return 5;
        case 'masteredWords': // 已废弃，但保留case以避免unknown table warning
          return 5;
        case 'userWrongWords':
          return 5;
        case 'bookMarks':
          return 5;
        case 'userStudySteps':
          return 5;
        case 'dakas':
          return 5;
        case 'userOpers':
          return 5;
        case 'userCowDungLogs':
          return 5;
        case 'meaningItems':
          return 5;
        case 'learningLogs':
          return 5;
        case 'userStudyDailyStats':
          return 5;
        default:
          throw Exception('Unknown table name: $tableName');
      }
    }

    // 对本地同步到后端的日志进行排序,确保：
    // - INSERT/UPDATE: 父表在子表之前（正序依赖）
    // - DELETE/BATCH_DELETE: 子表在父表之前（逆序依赖）
    
    // 【强制校验】严禁同步核心/系统词书的插入操作 (Fail-Fast)
    for (final log in result.first) {
      if (log['tblName'] == 'dicts' && log['operate'] == 'INSERT') {
        final record = jsonDecode(log['record'] as String);
        final name = record['name'];
        final ownerId = record['ownerId'];
        
        if (name == '生词本' || name == '已掌握' || ownerId == Global.sysUserId) {
          throw SyncDataSecurityException('数据安全违规: 禁止通过同步创建核心/系统词书！名称=[$name], 拥有者=[$ownerId]。请检查本地数据生成逻辑。');
        }
      }
    }

    result.first.sort((a, b) {
      // 这里的 a, b 是 Map<String, dynamic>，tblName 还是本地格式
      int timeCompare = (a['createTime'] as DateTime).compareTo(b['createTime'] as DateTime);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return _comparePriorityByOperate(
        a['operate'] as String,
        b['operate'] as String,
        getPriority(a['tblName'] as String),
        getPriority(b['tblName'] as String),
      );
    });

    // 把发送到后端的日志进行兼容性处理
    List<UserDbLogDto> localToBackend = [];
    for (var change in result.first /* to backend */) {
      // 这里的 change 还是 Map<String, dynamic>
      if (change['createTime'] != null) {
        change['createTime'] = (change['createTime'] as DateTime).toUtc().toIso8601String();
      }
      if (change['updateTime'] != null) {
        change['updateTime'] = (change['updateTime'] as DateTime).toUtc().toIso8601String();
      }
      String oldTable = change['tblName'] as String;
      change['tblName'] = Util.localTableNameToRemote(oldTable);

      localToBackend.add(UserDbLogDto.fromJson(change));
    }

    List<UserDbLog> backendToLocal = [];
    for (var change in result.second) {
      backendToLocal.add(UserDbLog.fromJson(change));
    }

    // 对远端同步到本地的日志也要按同样的规则进行排序
    backendToLocal.sort((a, b) {
      int timeCompare = a.createTime.compareTo(b.createTime);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return _comparePriorityByOperate(
        a.operate,
        b.operate,
        getPriority(a.tblName),
        getPriority(b.tblName),
      );
    });

    // 分别保存本地数据库和后端数据库(用事务保证一致性)
    DictWordOrderInvalidWarningException? warningExcept;
    var db = MyDatabase.instance;
    int successCount = 0;
    int failCount = 0;

    await db.transaction(() async {
      try {
        final List<LearningWord> updatedLearningWords = [];
        final List<String> newMasteredWordIds = [];
        final List<String> removedLearningWordIds = [];
        
        final masteredDict = await db.dictsDao.findUserMasteredDict(userId);

        for (var log in backendToLocal) {
          try {
            // 处理BATCH_DELETE操作类型
            if (log.operate == 'BATCH_DELETE') {
              await _handleBatchDeleteUserRecords(log, userId);
              successCount++;
              continue;
            }

            Map<String, dynamic> entityJson = jsonDecode(log.record);
            
            // 【容错改造】在反序列化前，补全可能缺失的字段，防止由于前后端版本不一致导致的 crash
            _sanitizeEntityJson(log.tblName, entityJson);

            if (log.tblName == 'users') {
              User entity = User.fromJson(entityJson);
              Global.logger.d('📥 [Sync-User] 接收到用户同步: id=${entity.id}, userName=${entity.userName}, '
                  'todayStudyStarted=${entity.todayStudyStarted}, lastLearningDate=${entity.lastLearningDate}, '
                  'totalLearning={${entity.totalLearningSeconds}}, todayLearning={${entity.todayLearningSeconds}}');
                  
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.usersDao.saveUser(entity, false);
                
                // 只要同步到当前用户的修改，立即应用到内存缓存
                if (Global.currentUserId == entity.id) {
                  Global.logger.d('📥 [Sync-User] 更新内存缓存: ${entity.userName}');
                  Global.updateUserCache(entity);
                }
              }
            } else if (log.tblName == 'dicts') {
              Dict entity = Dict.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.dictsDao.saveEntity(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.dictsDao.deleteEntity(entity, false);
              }
            } else if (log.tblName == 'words') {
              Word entity = Word.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.wordsDao.insertEntity(entity);
              }
            } else if (log.tblName == 'learningDicts') {
              LearningDict entity = LearningDict.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.learningDictsDao.saveEntity(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.learningDictsDao.deleteEntity(entity, false);
              }
            } else if (log.tblName == 'learningWords') {
              LearningWord entity = LearningWord.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.learningWordsDao.saveEntity(entity, false);
                updatedLearningWords.add(entity);
              } else if (log.operate == 'DELETE') {
                await db.learningWordsDao.deleteEntity(entity, false);
                removedLearningWordIds.add(entity.wordId);
              }
            } else if (log.tblName == 'masteredWords') {
              // 已废弃：mastered_word 已迁移到 dict + dict_word 体系
              // 忽略来自后端的旧格式日志
              Global.logger.i('忽略已废弃的 masteredWords 同步日志: operate=${log.operate}');
            } else if (log.tblName == 'userWrongWords') {
              final entity = UserWrongWord.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.userWrongWordsDao.saveEntity(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.userWrongWordsDao.deleteEntity(entity, false);
              }
            } else if (log.tblName == 'dictWords') {
              final entity = DictWord.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.dictWordsDao.insertEntity(entity, false);
                if (masteredDict != null && entity.dictId == masteredDict.id) {
                  newMasteredWordIds.add(entity.wordId);
                }
              } else if (log.operate == 'DELETE') {
                await db.dictWordsDao.deleteEntity(entity, false);
              }
            } else if (log.tblName == 'dakas') {
              Daka entity = Daka.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.dakasDao.saveDaka(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.dakasDao.deleteDaka(entity, false);
              }
            } else if (log.tblName == 'userOpers') {
              UserOper entity = UserOper.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.userOpersDao.saveUserOper(entity, false);
              }
            } else if (log.tblName == 'bookMarks') {
              BookMark entity = BookMark.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.bookmarksDao.saveBookmark(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.bookmarksDao.deleteBookmark(entity.id, false);
              }
            } else if (log.tblName == 'userStudySteps') {
              UserStudyStep entity = UserStudyStep.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.userStudyStepsDao.saveUserStudyStep(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.userStudyStepsDao.deleteUserStudyStep(entity.userId, entity.studyStep, false);
              }
            } else if (log.tblName == 'userCowDungLogs') {
              UserCowDungLog entity = UserCowDungLog.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.userCowDungLogsDao.insertEntity(entity, false);
              }
            } else if (log.tblName == 'meaningItems') {
              MeaningItem entity = MeaningItem.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.meaningItemsDao.insertEntity(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.meaningItemsDao.deleteEntity(entity.id, false);
              }
            } else if (log.tblName == 'learningLogs') {
              LearningLog entity = LearningLog.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.learningLogsDao.saveEntity(entity, false);
              }
            } else if (log.tblName == 'userStudyDailyStats') {
              final entity = UserStudyDailyStat.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.userStudyDailyStatsDao.saveEntity(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.userStudyDailyStatsDao.batchDeleteUserRecords(userId, filters: entityJson);
              }
            } else if (log.tblName != 'users' &&
                log.tblName != 'dicts' &&
                log.tblName != 'words' &&
                log.tblName != 'learningDicts' &&
                log.tblName != 'learningWords' &&
                log.tblName != 'masteredWords' &&
                log.tblName != 'userWrongWords' &&
                log.tblName != 'dictWords' &&
                log.tblName != 'dakas' &&
                log.tblName != 'userOpers' &&
                log.tblName != 'bookMarks' &&
                log.tblName != 'userStudySteps' &&
                log.tblName != 'userCowDungLogs' &&
                log.tblName != 'meaningItems' &&
                log.tblName != 'learningLogs' &&
                log.tblName != 'userStudyDailyStats') {
              Global.logger.w("⚠️ 不支持的表: ${log.tblName}");
              // 不弹出错误提示，只记录日志
            }
            successCount++;
          } catch (e) {
            failCount++;
            Global.logger.e("❌ 处理单条同步记录失败 (已跳过): 表=${log.tblName}, ID=${log.recordId}, 错误=$e");
            // 对于严重的数据解析错误，我们仅在开发/调试模式下抛出，生产环境选择跳过损坏记录以保证同步流程不中断
            if (kDebugMode) {
               // ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: '处理表数据失败: ${log.tblName}', showToast: false);
               // throw SyncDataParseException(...); 
               // 暂时统一不抛出，改为记录日志并继续，实现生产级容错
            }
          }
        }

        // 保存后端数据库，返回后端数据库版本
        if (localToBackend.isNotEmpty) {
          Result<int> result = await Api.client.syncUserDb(backendDbVersion, userId, localToBackend);
          if (!result.success) {
              // 若是后端特殊应答，要求进行全量修改日志”，由下次同步自然覆盖
              if ((result.code).contains('DICT_WORD_ORDER_INVALID')) {
                // message 格式可能是: DICT_WORD_ORDER_INVALID: dictId|具体错误信息
                String dictId = '';
                final msg = result.msg ?? '';
                final parts = msg.split('|');
                if (parts.length > 1) {
                  final prefixParts = parts[0].split(':');
                  if (prefixParts.length > 1) {
                    dictId = prefixParts[1].trim();
                  } else {
                    dictId = parts[0].trim();
                  }
                }

                if (dictId.isNotEmpty) {
                  Global.logger.w('⚠️ 服务端检测到词书($dictId)顺序异常，生成本地全量修改日志，等待下次同步覆盖');

                  // 清理掉所有关于这个字典的单词的旧同步日志，包括可能存在的过旧的 BATCH_DELETE
                  await (MyDatabase.instance.delete(MyDatabase.instance.userDbLogs)
                        ..where((l) => l.userId.equals(userId) & l.tblName.equals('dictWords') & (l.recordId.like('$dictId-%') | l.operate.equals('BATCH_DELETE'))))
                      .go();

                  await DbLogUtil.logDeleteAllTableRecords(userId, 'dictWords', filters: {'dictId': dictId});

                  // 休眠以确保时间戳先后顺序，避免排序时全量修改的 UPDATE 日志先于 BATCH_DELETE 执行而导致后端数据被清空
                  await Future.delayed(const Duration(milliseconds: 100));

                  // 修复本地词书顺序
                  await MyDatabase.instance.dictWordsDao.fixDictOrder(dictId, false);

                  // 生成本地词书全量修改日志, 使得在下次同步到服务端时, 能够让服务端和本地词书完全一致
                  await MyDatabase.instance.dictWordsDao.generateFullDictRewriteLogs(userId, dictId);
                }

              // 记录特定异常，使其能被捕获为警告状态。我们在这里不直接抛出以免回滚前面的成功操作（特别是已经写入的日志记录修复）
              warningExcept = DictWordOrderInvalidWarningException("下次修复");
              
              // 更新本地数据库版本（虽然本地未成功提交给后端，但我们已经接收了后端的变动应当更新本地的后端进度）
              await db.userDbVersionsDao
                  .saveEntity(UserDbVersion(userId: userId, version: backendDbVersion, createTime: AppClock.now(), updateTime: AppClock.now()));
              
              // 提前退出此事务处理过程：保留其余所有待上传的日志，不要走到最后的清空环节, 等待下次重推
              return;
            } else {
              Global.logger.e("❌ 上传到远程数据库失败: ${result.msg}");
              // 不弹出错误提示，只记录日志
              throw Exception(result.msg);
            }
          } else {
            backendDbVersion = result.data!;
          }
        }

        // 更新本地数据库版本，使其与后端数据库版本一致
        await db.userDbVersionsDao
            .saveEntity(UserDbVersion(userId: userId, version: backendDbVersion, createTime: AppClock.now(), updateTime: AppClock.now()));

        // 清空本地日志
        await db.userDbLogsDao.deleteUserDbLogs(userId);

        // 多端增量同步内存缓存更新
        if (updatedLearningWords.isNotEmpty || newMasteredWordIds.isNotEmpty || removedLearningWordIds.isNotEmpty) {
          StudyCacheManager().mergeSyncData(db, userId,
            updatedLearningWords: updatedLearningWords,
            newMasteredWordIds: newMasteredWordIds,
            removedLearningWordIds: removedLearningWordIds,
          );
          Global.logger.d('📥 [Sync-Cache] 已将多端同步增量数据合并至 StudyCacheManager');
        }

        // 同步完成后，再次验证核心数据完整性
        await _validateCoreData(userId);
      } catch (e) {
        rethrow; // 重新抛出异常，让事务回滚
      }
    });

    if (warningExcept != null) {
      throw warningExcept!;
    }

    stopwatch.stop();
    Global.logger.i("✅ 用户数据库同步操作完成 - 耗时: ${stopwatch.elapsedMilliseconds}ms, 成功: $successCount, 失败: $failCount");
    if (failCount > 0) {
      Global.logger.w("⚠️ 注意：同步过程中跳过了 $failCount 条解析失败的记录。建议检查网络或联系客服。");
    }
  } catch (e, stackTrace) {
    stopwatch.stop();
    Global.logger.e("❌ 执行用户数据库同步失败: $e - 耗时: ${stopwatch.elapsedMilliseconds}ms", error: e, stackTrace: stackTrace);
    await ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: 'doSyncUserDb', showToast: false);
    rethrow;
  }
}

/// 处理删除用户某个表所有记录的操作
Future<void> _handleBatchDeleteUserRecords(UserDbLog log, String userId) async {
  try {
    final db = MyDatabase.instance;
    final table = log.tblName;

    // 解析过滤条件 - log.record本身就是过滤条件
    Map<String, dynamic>? filters;
    try {
      filters = jsonDecode(log.record) as Map<String, dynamic>?;
    } catch (e) {
      Global.logger.w('解析删除记录过滤条件失败: $e');
    }

    Global.logger.i('🗑️ 开始批量删除用户的数据: $table, 用户ID: $userId, 过滤条件: $filters');

    switch (table) {
      case 'learningDicts':
        await db.learningDictsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'learningWords':
        await db.learningWordsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'masteredWords':
        // 已废弃：mastered_word 已迁移到 dict + dict_word 体系
        Global.logger.i('忽略已废弃的 masteredWords 批量删除日志');
        break;
      case 'userWrongWords':
        await db.userWrongWordsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'dictWords':
        await db.dictWordsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'dakas':
        await db.dakasDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'userOpers':
        await db.userOpersDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'bookMarks':
        await db.bookmarksDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'userStudySteps':
        await db.userStudyStepsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'userCowDungLogs':
        await db.userCowDungLogsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'learningLogs':
        await db.learningLogsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      case 'userStudyDailyStats':
        await db.userStudyDailyStatsDao.batchDeleteUserRecords(userId, filters: filters);
        break;
      default:
        Global.logger.w('⚠️ 不支持批量删除用户的数据的表: $table');
        // 不弹出错误提示，只记录日志
        return;
    }

    Global.logger.i('✅ 成功批量删除用户的数据: $table, 用户ID: $userId');
  } catch (e, stackTrace) {
    Global.logger.e('❌ 批量删除用户的数据失败: ${log.tblName} - $e');
    ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: '批量删除用户的数据失败: ${log.tblName}', showToast: false);
    rethrow;
  }
}

Pair<List<Map<String, dynamic>>, List<Map<String, dynamic>>> mergeChanges(
    List<Map<String, dynamic>> localChanges, List<Map<String, dynamic>> backendChanges) {
  List<Map<String, dynamic>> localToBackend = []; // 本地数据库需要更新到后端的记录集
  List<Map<String, dynamic>> backToLocalLogs = []; // 后端数据库需要更新到本地的记录集

  // 将本地变化和后端变化按 tblName|recordId 建立字典
  Map<String, Map<String, dynamic>> localLogs = {for (var log in localChanges) '${log['tblName']}|${log['recordId']}': log};
  Map<String, Map<String, dynamic>> backendLogs = {for (var log in backendChanges) '${log['tblName']}|${log['recordId']}': log};

  // 1. 比较后端变化和本地变化，找出需要更新本地数据库的记录
  for (var backLog in backendChanges) {
    var backendId = '${backLog['tblName']}|${backLog['recordId']}';
    if (localLogs.containsKey(backendId)) {
      var localLog = localLogs[backendId];
      if (backLog['operate'] == 'UPDATE' && localLog!['operate'] == 'UPDATE') {
        if ((backLog['updateTime'] as DateTime).isAfter(localLog['updateTime'] as DateTime)) {
          backToLocalLogs.add(backLog); // B -> A
        } else {
          localToBackend.add(localLog); // A -> B
        }
      } else if (backLog['operate'] == 'UPDATE' && localLog!['operate'] == 'INSERT') {
        if ((backLog['updateTime'] as DateTime).isAfter(localLog['updateTime'] as DateTime)) {
          backLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          backToLocalLogs.add(backLog); // B -> A
        } else {
          localLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          localToBackend.add(localLog); // A -> B
        }
      } else if (backLog['operate'] == 'UPDATE' && localLog!['operate'] == 'DELETE') {
        if ((backLog['updateTime'] as DateTime).isAfter(localLog['updateTime'] as DateTime)) {
          backLog['operate'] = 'INSERT'; // 强制为 INSERT
          backToLocalLogs.add(backLog); // B -> A
        } else {
          localToBackend.add(localLog); // A -> B
        }
      } else if (backLog['operate'] == 'INSERT' && localLog!['operate'] == 'INSERT') {
        if ((backLog['updateTime'] as DateTime).isAfter(localLog['updateTime'] as DateTime)) {
          backLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          backToLocalLogs.add(backLog); // B -> A
        } else {
          localLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          localToBackend.add(localLog); // A -> B
        }
      } else if (backLog['operate'] == 'INSERT' && localLog!['operate'] == 'DELETE') {
        if ((backLog['updateTime'] as DateTime).isAfter(localLog['updateTime'] as DateTime)) {
          backToLocalLogs.add(backLog); // B -> A
        } else {
          localToBackend.add(localLog); // A -> B
        }
      }
    } else {
      backToLocalLogs.add(backLog); // 后端记录在本地不存在，需要同步到本地
    }
  }

  // 2. 比较本地变化和后端变化，找出需要更新后端数据库的记录
  for (var localLog in localChanges) {
    var localId = '${localLog['tblName']}|${localLog['recordId']}';
    if (backendLogs.containsKey(localId)) {
      var backLog = backendLogs[localId];
      if (localLog['operate'] == 'UPDATE' && backLog!['operate'] == 'UPDATE') {
        if ((localLog['updateTime'] as DateTime).isAfter(backLog['updateTime'] as DateTime)) {
          localToBackend.add(localLog); // A -> B
        } else {
          backToLocalLogs.add(backLog); // B -> A
        }
      } else if (localLog['operate'] == 'UPDATE' && backLog!['operate'] == 'INSERT') {
        if ((localLog['updateTime'] as DateTime).isAfter(backLog['updateTime'] as DateTime)) {
          localLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          localToBackend.add(localLog); // A -> B
        } else {
          backLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          backToLocalLogs.add(backLog); // B -> A
        }
      } else if (localLog['operate'] == 'UPDATE' && backLog!['operate'] == 'DELETE') {
        if ((localLog['updateTime'] as DateTime).isAfter(backLog['updateTime'] as DateTime)) {
          localLog['operate'] = 'INSERT'; // 强制为 INSERT
          localToBackend.add(localLog); // A -> B
        } else {
          backToLocalLogs.add(backLog); // B -> A
        }
      } else if (localLog['operate'] == 'INSERT' && backLog!['operate'] == 'INSERT') {
        if ((localLog['updateTime'] as DateTime).isAfter(backLog['updateTime'] as DateTime)) {
          localLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          localToBackend.add(localLog); // A -> B
        } else {
          backLog['operate'] = 'UPDATE'; // 强制为 UPDATE
          backToLocalLogs.add(backLog); // B -> A
        }
      } else if (localLog['operate'] == 'INSERT' && backLog!['operate'] == 'DELETE') {
        if ((localLog['updateTime'] as DateTime).isAfter(backLog['updateTime'] as DateTime)) {
          localToBackend.add(localLog); // A -> B
        } else {
          backToLocalLogs.add(backLog); // B -> A
        }
      }
    } else {
      localToBackend.add(localLog); // 本地记录在后端不存在，需要同步到后端
    }
  }

  // 去除重复项，确保每个记录的同一种操作只出现一次, 减小数据库操作次数和网络包体积
  localToBackend = List.from({for (var log in localToBackend) '${log['tblName']}|${log['recordId']}|${log['operate']}': log}.values);
  backToLocalLogs = List.from({for (var log in backToLocalLogs) '${log['tblName']}|${log['recordId']}|${log['operate']}': log}.values);

  return Pair(localToBackend, backToLocalLogs);
}

void printFormattedChanges(String label, List<Map<String, dynamic>> changes) {
  // 格式化输出变更记录（已移除日志）
}

// 同步指定用户的用户数据库
Future<void> syncUserDb(String userId) async {
  final stopwatch = Stopwatch()..start();
  try {
    // 获取本地数据库版本
    UserDbVersion? userDbVersion = await MyDatabase.instance.userDbVersionsDao.getUserDbVersionByUserId(userId);
    int localDbVersion = userDbVersion?.version ?? Global.localDbVersionForNewlyInstalled;

    // 同步开始前验证核心数据完整性。
    // 注意：如果是首次同步 (localDbVersion == 0)，由于本地尚无任何数据，校验必定失败，因此跳过。
    // 此时应当直接进行同步，等同步完成后会再次调用 _validateCoreData 进行验证。
    if (localDbVersion > 0) {
      await _validateCoreData(userId);
    }

    // 获取服务端数据库版本
    var remoteDbVersion = -1;
    var remoteDbVersionResult = await Api.client.getUserDbVersion(userId);
    if (remoteDbVersionResult.success) {
      remoteDbVersion = remoteDbVersionResult.data!;
    } else {
      Global.logger.e("❌ 获取服务端数据库版本失败: ${remoteDbVersionResult.msg}");
      // 不再弹出错误提示
      throw Exception(remoteDbVersionResult.msg ?? '获取服务端数据库版本失败');
    }

    // 获取本地数据库变更日志
    List<UserDbLog> localLogs = await MyDatabase.instance.userDbLogsDao.getUserDbLogs(userId);

    Global.logger.i("✅ 获取本地变更日志成功 - 耗时: ${stopwatch.elapsedMilliseconds}ms, 本地变更: ${localLogs.length}");

    // 与后端同步用户数据库
    if (localDbVersion != remoteDbVersion || localLogs.isNotEmpty) {
      var result1 = await Api.client.getDbLogsFromVersion(localDbVersion, userId);
      if (result1.success) {
        List<UserDbLogDto> remoteLogs = result1.data!;
        Global.logger.i("✅ 获取远程变更日志成功 - 耗时: ${stopwatch.elapsedMilliseconds}ms, 本地变更: ${localLogs.length}, 远程变更: ${remoteLogs.length}");

        // 记录上下行数量
        addUploadCount(localLogs.length);
        addDownloadCount(remoteLogs.length);

        Map<String, dynamic> uDetails = {};
        for (var log in localLogs) {
          uDetails.putIfAbsent(log.tblName, () => <String, dynamic>{});
          uDetails[log.tblName][log.operate] = (uDetails[log.tblName][log.operate] as int? ?? 0) + 1;
        }
        addUploadDetails(uDetails);
        
        Map<String, dynamic> dDetails = {};
        for (var log in remoteLogs) {
          String tblName = Util.remoteTableNameToLocal(log.tblName);
          dDetails.putIfAbsent(tblName, () => <String, dynamic>{});
          dDetails[tblName][log.operate] = (dDetails[tblName][log.operate] as int? ?? 0) + 1;
        }
        addDownloadDetails(dDetails);

        await doSyncUserDb(localLogs, remoteLogs, remoteDbVersion, userId);
        
        // 动态推导并纠正打卡天数统计，防止多端数据冲突
        try {
          await UserBo().updateAndSyncUserDakaStats(userId);
        } catch (e) {
          Global.logger.e("纠正打卡天数统计失败: $e");
        }

        stopwatch.stop();
        Global.logger.i("✅ 用户数据库同步完成 - 耗时: ${stopwatch.elapsedMilliseconds}ms, 本地变更: ${localLogs.length}, 远程变更: ${remoteLogs.length}");
      } else {
        Global.logger.e("❌ 获取远程变更日志失败: ${result1.msg}");
        // 不再弹出错误提示
        throw Exception(result1.msg ?? '获取远程变更日志失败');
      }
    } else {
      stopwatch.stop();
      Global.logger.i("✅ 用户数据库已是最新状态 - 耗时: ${stopwatch.elapsedMilliseconds}ms");
    }
  } catch (e, stackTrace) {
    stopwatch.stop();
    Global.logger.e("❌ 同步用户数据库失败: $e - 耗时: ${stopwatch.elapsedMilliseconds}ms", error: e, stackTrace: stackTrace);
    // 不再调用 ErrorHandler 显示错误提示，只抛出异常让上层处理
    // await ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: 'syncUserDb', showToast: true);
    rethrow;
  }
}

// 同步当前登录用户的用户数据库和系统数据库
Future<void> syncDb() async {
  final stopwatch = Stopwatch()..start();
  String? syncLogId;
  UserVo? loggedInUser;

  try {
    Global.logger.i("🔄 开始数据库同步流程");

    // 检查网络连接
    final networkUtil = NetworkUtil();
    bool isConnected = await networkUtil.isConnected();
    if (!isConnected) {
      Global.logger.d("🌐 网络连接不可用，静默跳过同步操作");
      return;
    }

    // 获取当前登录用户
    loggedInUser = await Global.refreshLoggedInUser();
    if (loggedInUser == null) {
      Global.logger.e("❌ 用户未登录，同步终止");
      // 不再弹出错误提示，只记录日志
      return;
    }

    // 开始记录同步日志
    syncLogId = await SyncLogService().startSync(
      userId: loggedInUser.id,
      appVersion: Global.version,
    );
    setCurrentSyncLogId(syncLogId);

    // 先同步所有系统数据（静态元数据 + UGC内容）
    await syncSysDb();

    // 再同步用户数据（游客不需要同步用户数据）
    if (!Global.isGuest) {
      await syncUserDb(loggedInUser.id!);
    }

    stopwatch.stop();
    Global.logger.i("🎉 数据库同步完成 - 总耗时: ${stopwatch.elapsedMilliseconds}ms");

    // 完成同步日志记录
    int? dbVersion;
    if (!Global.isGuest && loggedInUser.id != null) {
      final userDbVersion = await MyDatabase.instance.userDbVersionsDao.getUserDbVersionByUserId(loggedInUser.id!);
      dbVersion = userDbVersion?.version;
    }
    final sysVersionData = await MyDatabase.instance.sysDbVersionDao.getVersion();
    int? sysDbVersion = sysVersionData?.version;
    await completeSyncLog(success: true, dbVersion: dbVersion, sysDbVersion: sysDbVersion);
  } on DictWordOrderInvalidWarningException catch (e) {
    stopwatch.stop();
    Global.logger.w("⚠️ 数据库同步中止(进入修复计划): $e - 耗时: ${stopwatch.elapsedMilliseconds}ms");
    
    int? dbVersion;
    if (!Global.isGuest && loggedInUser?.id != null) {
      final userDbVersion = await MyDatabase.instance.userDbVersionsDao.getUserDbVersionByUserId(loggedInUser!.id!);
      dbVersion = userDbVersion?.version;
    }
    final sysVersionData = await MyDatabase.instance.sysDbVersionDao.getVersion();
    int? sysDbVersion = sysVersionData?.version;
    await completeSyncLog(success: false, errorMessage: e.message, dbVersion: dbVersion, sysDbVersion: sysDbVersion);
    rethrow;
  } catch (e, stackTrace) {
    stopwatch.stop();
    Global.logger.e("❌ 数据库同步失败: $e - 耗时: ${stopwatch.elapsedMilliseconds}ms", error: e, stackTrace: stackTrace);

    // 记录同步失败，不再弹出错误提示
    await completeSyncLog(success: false, errorMessage: e.toString());

    // 不再调用 ErrorHandler 显示错误提示
    // await ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: 'syncDb', showToast: true);
    rethrow;
  }
}

/// 确保待同步日志中包含词书（Dict）的 INSERT 日志，用于容错。
///
/// 扫描待同步日志，提取所有涉及的词书 ID（包括 dicts 记录本身及子表引用的 ID）。
/// 只要发现词书属于当前用户，就总是构造一条 INSERT 日志，最后通过去重机制保留一份。
/// 这样可以确保后端在处理子表记录前，数据库中一定已经存在对应的父表记录，防止外键约束错误。
///
/// 注意：仅处理 ownerId 等于当前 userId 的词书。系统词书不由用户同步。
Future<void> _ensureParentDictsLogs(List<Map<String, dynamic>> logsToBackend, String userId) async {
  // 1. 收集所有相关的 dictId (包括 dicts 本身和引用的子表)
  final referencedDictIds = <String>{};
  for (var log in logsToBackend) {
    if (log['tblName'] == 'dicts') {
      referencedDictIds.add(log['recordId']);
    } else if (log['tblName'] == 'dictWords' || log['tblName'] == 'learningDicts') {
      try {
        final recordMap = jsonDecode(log['record']) as Map<String, dynamic>;
        final dictId = recordMap['dictId'];
        if (dictId != null) referencedDictIds.add(dictId.toString());
      } catch (_) {}
    }
  }

  if (referencedDictIds.isEmpty) return;

  // 2. 只要发现是自己的词书，就总是补充一条 INSERT 日志
  final db = MyDatabase.instance;
  for (var dictId in referencedDictIds) {
    try {
      final dict = await db.dictsDao.findById(dictId);
      if (dict != null && dict.ownerId == userId) {
        // 【强制约束】拦截核心词书：生词本和已掌握禁止由客户端通过同步方式“补全”
        // 这两本词书必须由后端在账户创建时初始化
        if (dict.name == '生词本' || dict.name == '已掌握' || dict.ownerId == Global.sysUserId) {
          continue;
        }

        logsToBackend.add(<String, dynamic>{
          'id': Util.uuid(),
          'userId': dict.ownerId,
          'operate': 'INSERT',
          'tblName': 'dicts',
          'recordId': dict.id,
          'record': jsonEncode(dict.toJson()),
          'version': 0,
          'createTime': dict.createTime,
          'updateTime': dict.createTime,
        });
      }
    } catch (e) {
      Global.logger.e('❌ 补全词书日志失败 (ID: $dictId): $e');
    }
  }

  // 3. 去重：确保每个 (表名, 记录ID, 操作类型) 唯一，优先保留先前的日志
  final seen = <String>{};
  logsToBackend.retainWhere((log) => seen.add("${log['tblName']}|${log['recordId']}|${log['operate']}"));
}
/// 同步数据 JSON 补全工具
/// 
/// 当服务端返回的数据缺少某些前端定义的非空字段时，在此处提供默认值。
/// 这种改造能有效防止由于前后端版本不一致导致的同步崩溃。
void _sanitizeEntityJson(String tableName, Map<String, dynamic> json) {
  // 通用处理：如果缺少 updateTime，则尝试用 createTime 补齐，防止非空约束导致反序列化或写入失败
  if (json.containsKey('createTime')) {
    json['updateTime'] ??= json['createTime'];
  }

  switch (tableName) {
    case 'users':
      json['todayStudyStarted'] ??= false;
      json['todayLearningSeconds'] ??= 0;
      json['totalLearningSeconds'] ??= 0;
      break;
    case 'dicts':
      json['editable'] ??= true;
      json['deletable'] ??= true;
      json['visible'] ??= true;
      json['isReady'] ??= true;
      json['isShared'] ??= false;
      json['wordCount'] ??= 0;
      break;
    case 'dictWords':
      json['unit'] ??= 0;
      json['seq'] ??= 1;
      break;
    case 'learningDicts':
      json['isCurrent'] ??= false;
      json['isFinished'] ??= false;
      break;
    case 'learningWords':
      json['difficulty'] ??= 5;
      json['status'] ??= 0;
      break;
    case 'meaningItems':
      json['popularity'] ??= 1;
      break;
    case 'dakas':
      json['totalStudyCount'] ??= 0;
      json['newStudyCount'] ??= 0;
      json['reviewCount'] ??= 0;
      break;
  }
}
