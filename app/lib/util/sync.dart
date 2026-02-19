import 'dart:async';
import 'dart:convert';

import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/services/sync_log_service.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/db_log_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/network_util.dart';
import 'package:nnbdc/util/sys_db_sync.dart';
import 'package:nnbdc/util/utils.dart';

export 'package:nnbdc/util/sys_db_sync.dart' show syncSysDb;

// 当前同步日志ID，用于记录同步统计信息
String? _currentSyncLogId;
int _uploadCount = 0;
int _downloadCount = 0;

/// 设置当前同步日志ID
void setCurrentSyncLogId(String logId) {
  _currentSyncLogId = logId;
  _uploadCount = 0;
  _downloadCount = 0;
}

/// 清除当前同步日志ID
void clearCurrentSyncLogId() {
  _currentSyncLogId = null;
  _uploadCount = 0;
  _downloadCount = 0;
}

/// 记录上行数量
void addUploadCount(int count) {
  _uploadCount += count;
}

/// 记录下行数量
void addDownloadCount(int count) {
  _downloadCount += count;
}

/// 完成同步日志记录
Future<void> completeSyncLog({bool success = true, String? errorMessage}) async {
  if (_currentSyncLogId == null) return;
  
  final service = SyncLogService();
  if (success) {
    await service.completeSync(
      logId: _currentSyncLogId!,
      uploadCount: _uploadCount,
      downloadCount: _downloadCount,
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
  String operateA, String operateB,
  int priorityA, int priorityB,
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
      changeJson['updateTime'] = DateTime.fromMillisecondsSinceEpoch(changeJson['updateTime']);
      changeJson['createTime'] = DateTime.fromMillisecondsSinceEpoch(changeJson['createTime']);

      localChangesMap.add(changeJson);
    }

    List<Map<String, dynamic>> backendChangesMap = [];
    for (var change in backendChanges) {
      var changeJson = change.toJson();

      // 把后端日志中的时间戳(iso8601 String)转换为DateTime
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
        case 'masteredWords':
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
        default:
          throw Exception('Unknown table name: $tableName');
      }
    }

    // 对本地同步到后端的日志进行排序,确保：
    // - INSERT/UPDATE: 父表在子表之前（正序依赖）
    // - DELETE/BATCH_DELETE: 子表在父表之前（逆序依赖）
    // 首先按创建时间排序,保持操作的时间顺序
    // 当创建时间相同时,根据操作类型决定依赖排序方向
    result.first.sort((a, b) {
      // 这里的 a, b 是 Map<String, dynamic>，tblName 还是本地格式
      int timeCompare = (a['createTime'] as DateTime).compareTo(b['createTime'] as DateTime);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return _comparePriorityByOperate(
        a['operate'] as String, b['operate'] as String,
        getPriority(a['tblName'] as String), getPriority(b['tblName'] as String),
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
        a.operate, b.operate,
        getPriority(a.tblName), getPriority(b.tblName),
      );
    });

    // 分别保存本地数据库和后端数据库(用事务保证一致性)
    var db = MyDatabase.instance;
    await db.transaction(() async {
      try {
        for (var log in backendToLocal) {
          try {
            // 处理BATCH_DELETE操作类型
            if (log.operate == 'BATCH_DELETE') {
              await _handleBatchDeleteUserRecords(log, userId);
              continue;
            }

            Map<String, dynamic> entityJson = jsonDecode(log.record);
            if (log.tblName == 'users') {
              User entity = User.fromJson(entityJson);
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.usersDao.saveUser(entity, false);
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
              } else if (log.operate == 'DELETE') {
                await db.learningWordsDao.deleteEntity(entity, false);
              }
            } else if (log.tblName == 'masteredWords') {
              final entity = MasteredWord.fromJson(jsonDecode(log.record));
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.masteredWordsDao.saveMasteredWord(entity, false, false);
              } else if (log.operate == 'DELETE') {
                await db.masteredWordsDao.deleteMasteredWord(entity.userId, entity.wordId, false, false);
              }
            } else if (log.tblName == 'userWrongWords') {
              final entity = UserWrongWord.fromJson(jsonDecode(log.record));
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.userWrongWordsDao.saveEntity(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.userWrongWordsDao.deleteEntity(entity, false);
              }
            } else if (log.tblName == 'dictWords') {
              final entity = DictWord.fromJson(jsonDecode(log.record));
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.dictWordsDao.insertEntity(entity, false);
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
              MeaningItem entity = MeaningItem.fromJson(jsonDecode(log.record));
              if (log.operate == 'INSERT' || log.operate == 'UPDATE') {
                await db.meaningItemsDao.insertEntity(entity, false);
              } else if (log.operate == 'DELETE') {
                await db.meaningItemsDao.deleteEntity(entity.id, false);
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
                log.tblName != 'meaningItems') {
              Global.logger.w("⚠️ 不支持的表: ${log.tblName}");
              // 不弹出错误提示，只记录日志
            }
          } catch (e, stackTrace) {
            Global.logger.e("❌ 处理表数据失败: ${log.tblName} - $e");
            ErrorHandler.handleDatabaseError(e, stackTrace, db: MyDatabase.instance.usersDao, operation: '处理表数据失败: ${log.tblName}', showToast: false);
          }
        }

        // 保存后端数据库，返回后端数据库版本
        if (localToBackend.isNotEmpty) {
          Result<int> result = await Api.client.syncUserDb(backendDbVersion, userId, localToBackend);
          if (!result.success) {
            // 若是后端特殊应答，要求进行“本地生成生词本全量修改日志”，由下次同步自然覆盖
            if ((result.code).contains('RAW_WORD_ORDER_INVALID')) {
              Global.logger.w('⚠️ 服务端检测到生词本顺序异常，生成本地全量修改日志，等待下次同步覆盖');

              // 生成批量删除生词日志, 使得在下次同步到服务端时, 能够首先清空用户生词本中的单词
              final rawDict = await MyDatabase.instance.dictsDao.findByOwnerId(userId).then((value) => value.first);
              await DbLogUtil.logDeleteAllTableRecords(userId, 'dictWords', filters: {'dictId': rawDict.id});

              // 修复本地生词本顺序
              await MyDatabase.instance.dictWordsDao.fixUserRawDictOrder(userId, false);

              // 生成本地生词本全量修改日志, 使得在下次同步到服务端时, 能够是服务端和本地生词本完全一致
              await MyDatabase.instance.dictWordsDao.generateFullRawDictRewriteLogs(userId);

              // 直接返回，由其他用户操作触发下一次同步(这里不直接触发同步, 是因为当前代码已经在同步中了)
              // 注意, 因为是直接返回, 没有抛异常, 所以[服务端==>本地]是同步成功的, 但是[本地==>服务端]是同步失败的
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
      } catch (e) {
        rethrow; // 重新抛出异常，让事务回滚
      }
    });
    stopwatch.stop();
    Global.logger.i("✅ 用户数据库同步操作完成 - 耗时: ${stopwatch.elapsedMilliseconds}ms, 处理记录数: ${backendToLocal.length}");
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
        await db.masteredWordsDao.batchDeleteUserRecords(userId, filters: filters);
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

  // 去除重复项，确保每个 ID 只出现一次
  localToBackend = List.from({for (var log in localToBackend) '${log['tblName']}|${log['recordId']}': log}.values);
  backToLocalLogs = List.from({for (var log in backToLocalLogs) '${log['tblName']}|${log['recordId']}': log}.values);

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
        
        await doSyncUserDb(localLogs, remoteLogs, remoteDbVersion, userId);
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
    UserVo? loggedInUser = await Global.refreshLoggedInUser();
    if (loggedInUser == null) {
      Global.logger.e("❌ 用户未登录，同步终止");
      // 不再弹出错误提示，只记录日志
      return;
    }

    // 开始记录同步日志
    syncLogId = await SyncLogService().startSync(userId: loggedInUser.id);
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
    await completeSyncLog(success: true);
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

/// 检查并补全缺失的父级词书（Dict）日志, 用于容错
///
/// 扫描待同步日志中的子表（dictWords, learningDicts），如果发现其引用的 dictId 在当前同步批次中
/// 没有对应的 dicts 日志，则尝试从本地数据库加载该 Dict 并生成补充的 INSERT 日志。
///
/// 注意：仅补全 ownerId 等于当前 userId 的词书日志。系统词书不由用户同步。
Future<void> _ensureParentDictsLogs(List<Map<String, dynamic>> logsToBackend, String userId) async {
  // 1. 收集所有被引用的 dictId
  final referencedDictIds = <String>{};

  // 记录当前同步批次中已存在的 dictId（避免重复添加）
  final existingDictLogIds = <String>{};

  for (var log in logsToBackend) {
    if (log['tblName'] == 'dicts') {
      // 尝试解析 recordId 或直接从 json 中提取 id
      // 注意：dicts 表的主键就是 id，通常 recordId 就是 dictId
      existingDictLogIds.add(log['recordId']);
    } else if (log['tblName'] == 'dictWords') {
      try {
        // dictWords 的 record 是 JSON，包含 dictId
        final recordMap = jsonDecode(log['record']) as Map<String, dynamic>;
        if (recordMap.containsKey('dictId')) {
          referencedDictIds.add(recordMap['dictId']);
        }
      } catch (e) {
        // 忽略解析错误
      }
    } else if (log['tblName'] == 'learningDicts') {
      try {
        // learningDicts 的 record 是 JSON，包含 dictId
        final recordMap = jsonDecode(log['record']) as Map<String, dynamic>;
        if (recordMap.containsKey('dictId')) {
          referencedDictIds.add(recordMap['dictId']);
        }
      } catch (e) {
        // 忽略解析错误
      }
    }
  }

  // 2. 找出缺失的 dictId
  final missingDictIds = referencedDictIds.difference(existingDictLogIds);

  if (missingDictIds.isEmpty) {
    return;
  }

  Global.logger.i('🔍 检测到同步日志中引用了 ${missingDictIds.length} 个未包含创建日志的词书，尝试补全...');

  final db = MyDatabase.instance;

  // 3. 从本地数据库获取缺失的 Dict 并生成日志
  for (var dictId in missingDictIds) {
    try {
      // 使用 DAO 获取
      final dict = await db.dictsDao.findById(dictId);
      if (dict != null) {
        // 【重要】只补全属于当前用户的词书日志。系统词书或他人词书不能由当前用户同步，
        // 否则后端会校验 ownerId 失败导致同步报错。
        if (dict.ownerId != userId) {
          Global.logger.d('ℹ️ 词书 $dictId 的 Owner ${dict.ownerId} 与当前用户 $userId 不符，跳过日志补全');
          continue;
        }

        // 构造虚拟的 INSERT 日志
        // 使用 Dict 的真实创建时间，确保排序正确（通常早于子表）
        final now = AppClock.now();
        final logId = Util.uuid(); // 生成临时 ID

        // 将 Dict 转换为 JSON Map
        final dictJson = dict.toJson();
        
        // 构造符合 local logs 格式的 Map
        // 注意：createTime/updateTime 必须是 DateTime 对象，因为后续代码会进行排序
        final newLog = <String, dynamic>{
          'id': logId,
          'userId': dict.ownerId,
          'operate': 'INSERT',
          'tblName': 'dicts',
          'recordId': dict.id,
          'record': jsonEncode(dictJson),
          'version': 0,
          'createTime': dict.createTime, // DateTime 类型
          'updateTime': dict.updateTime ?? now, // DateTime 类型
        };

        logsToBackend.add(newLog);
        Global.logger.i('✅ 补全了缺失的词书创建日志: ${dict.name} (ID: ${dict.id})');
      } else {
        Global.logger.w('⚠️ 无法补全词书日志: 本地也找不到 ID 为 $dictId 的词书，可能已被删除');
      }
    } catch (e) {
      Global.logger.e('❌ 补全词书日志失败 (ID: $dictId): $e');
    }
  }
}
