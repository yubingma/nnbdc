import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/network_util.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/tts.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/socket_io.dart';

/// 进度回调函数类型
typedef ProgressCallback = void Function(int step, String message, {IntegrityCheckResult? result});

/// 数据完整性检查器
class DataIntegrityChecker {
  static final DataIntegrityChecker _instance = DataIntegrityChecker._internal();
  factory DataIntegrityChecker() => _instance;
  DataIntegrityChecker._internal();

  /// 注意：不要缓存 `MyDatabase.instance`。
  /// 数据库在 `wipeAllTables()` / `closeDatabase()` 后会重建实例，
  /// 若缓存旧实例会导致 "Can't re-open a database after closing it"。
  MyDatabase get _db => MyDatabase.instance;

  /// 执行完整的数据完整性检查
  Future<IntegrityCheckResult> performFullCheck() async {
    final result = IntegrityCheckResult();

    try {
      // 1. 检查词典单词序号连续性
      await _checkDictWordSequences(result);

      // 2. 检查词典单词数量一致性
      await _checkDictWordCounts(result);

    
      // 4. 检查用户数据库版本一致性
      await _checkAllUserDbVersions(result);

      // 5. 检查通用词典完整性
      await _checkCommonDictIntegrity(result);
    } catch (e, stackTrace) {
      Global.logger.e('完整性检查过程中出现错误', error: e, stackTrace: stackTrace);
      result.addError('完整性检查过程中出现错误: $e');
    }

    return result;
  }

  /// 执行用户特定的数据完整性检查
  /// [onProgress] 进度回调函数，参数为(步骤数, 消息)
  Future<IntegrityCheckResult> performUserCheck(String userId, {ProgressCallback? onProgress}) async {
    final result = IntegrityCheckResult();
    final stopwatch = Stopwatch()..start();

    try {
      onProgress?.call(0, '开始健康检查...');
      await Future.delayed(const Duration(milliseconds: 200)); // 给UI一点时间显示
      Global.logger.d('开始健康检查...');

      // 1. 检查用户词典单词序号连续性
      onProgress?.call(1, '检查词典单词序号连续性...');
      await Future.delayed(const Duration(milliseconds: 100)); // 给UI一点时间显示
      final timer1 = Stopwatch()..start();
      await _checkUserDictWordSequences(result, userId);
      timer1.stop();
      Global.logger.d('✓ 检查序号连续性: ${timer1.elapsedMilliseconds}ms');
      onProgress?.call(1, '检查词典单词序号连续性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200)); // 给UI时间显示结果

      // 2. 检查用户词典单词数量一致性
      onProgress?.call(2, '检查词典单词数量一致性...');
      await Future.delayed(const Duration(milliseconds: 100)); // 给UI一点时间显示
      final timer2 = Stopwatch()..start();
      await _checkUserDictWordCounts(result, userId);
      timer2.stop();
      Global.logger.d('✓ 检查单词数量一致性: ${timer2.elapsedMilliseconds}ms');
      onProgress?.call(2, '检查词典单词数量一致性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200)); // 给UI时间显示结果

      // 3. 检查用户学习步骤完整性
      onProgress?.call(3, '检查学习步骤完整性...');
      await Future.delayed(const Duration(milliseconds: 100)); // 给UI一点时间显示
      final timer3 = Stopwatch()..start();
      await _checkUserStudySteps(result, userId);
      timer3.stop();
      Global.logger.d('✓ 检查学习步骤完整性: ${timer3.elapsedMilliseconds}ms');
      onProgress?.call(3, '检查学习步骤完整性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200)); // 给UI时间显示结果

      // 4. 检查用户数据库版本一致性
      onProgress?.call(4, '检查数据库版本一致性...');
      await Future.delayed(const Duration(milliseconds: 100)); // 给UI一点时间显示
      final timer4 = Stopwatch()..start();
      await _checkUserDbVersions(result, userId);
      timer4.stop();
      Global.logger.d('✓ 检查数据库版本一致性: ${timer4.elapsedMilliseconds}ms');
      onProgress?.call(4, '检查数据库版本一致性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200)); // 给UI时间显示结果

      // 5. 检查通用词典完整性
      onProgress?.call(5, '检查通用词典完整性...');
      await Future.delayed(const Duration(milliseconds: 100)); // 给UI一点时间显示
      final timer5 = Stopwatch()..start();
      await _checkCommonDictIntegrity(result);
      timer5.stop();
      Global.logger.d('✓ 检查通用词典完整性: ${timer5.elapsedMilliseconds}ms');
      onProgress?.call(5, '检查通用词典完整性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200)); // 给UI时间显示结果

      // 6. 检查用户词书完整性（生词本 + 已掌握）
      onProgress?.call(6, '检查用户词书完整性...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer6 = Stopwatch()..start();
      await _checkUserDicts(result, userId);
      timer6.stop();
      Global.logger.d('✓ 检查用户词书完整性: ${timer6.elapsedMilliseconds}ms');
      onProgress?.call(6, '检查用户词书完整性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));

      // 7. 检查书桌系统词库底层托底
      onProgress?.call(7, '检查书桌系统词库底层托底...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer7 = Stopwatch()..start();
      await _checkDeskSystemDictWordFallback(result, userId);
      timer7.stop();
      Global.logger.d('✓ 检查书桌系统词库底层托底: ${timer7.elapsedMilliseconds}ms');
      onProgress?.call(7, '检查书桌系统词库底层托底...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));

      // 8. 检查正在学习单词的释义完整性
      onProgress?.call(8, '检查正在学习单词的释义完整性...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer8 = Stopwatch()..start();
      await _checkLearningWordsMeanings(result, userId);
      timer8.stop();
      Global.logger.d('✓ 检查正在学习单词的释义: ${timer8.elapsedMilliseconds}ms');
      onProgress?.call(8, '检查正在学习单词的释义完整性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));

      // 9. 检查网络连接
      onProgress?.call(9, '检查网络连接...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer9 = Stopwatch()..start();
      await _checkNetworkConnectivity(result);
      timer9.stop();
      Global.logger.d('✓ 检查网络连接: ${timer9.elapsedMilliseconds}ms');
      onProgress?.call(9, '检查网络连接...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));

      // 10. 检查后端服务器连通性
      onProgress?.call(10, '检查后端服务器连通性...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer10 = Stopwatch()..start();
      await _checkBackendServer(result);
      timer10.stop();
      Global.logger.d('✓ 检查后端服务器: ${timer10.elapsedMilliseconds}ms');
      onProgress?.call(10, '检查后端服务器连通性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));

      // 11. 检查游戏服务器连通性
      onProgress?.call(11, '检查游戏服务器连通性...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer11 = Stopwatch()..start();
      await _checkGameServer(result);
      timer11.stop();
      Global.logger.d('✓ 检查游戏服务器: ${timer11.elapsedMilliseconds}ms');
      onProgress?.call(11, '检查游戏服务器连通性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));

      // 12. 检查本地TTS功能
      onProgress?.call(12, '检查本地TTS功能...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer12 = Stopwatch()..start();
      await _checkTtsFunctionality(result);
      timer12.stop();
      Global.logger.d('✓ 检查本地TTS: ${timer12.elapsedMilliseconds}ms');
      onProgress?.call(12, '检查本地TTS功能...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));

      stopwatch.stop();
      Global.logger.d('✓ 健康检查完成，总耗时: ${stopwatch.elapsedMilliseconds}ms');
      onProgress?.call(12, '检查完成！', result: result);
      await Future.delayed(const Duration(milliseconds: 200)); // 给UI时间显示最后一项的结果
    } catch (e, stackTrace) {
      stopwatch.stop();
      Global.logger.e('✗ 用户数据完整性检查过程中出现错误', error: e, stackTrace: stackTrace);
      result.addError('用户数据完整性检查过程中出现错误: $e');
    }

    return result;
  }

  /// 检查用户词典单词序号连续性
  Future<void> _checkUserDictWordSequences(IntegrityCheckResult result, String userId) async {
    try {
      // 获取用户拥有的词典
      final userDicts = await (_db.dictsDao.select(_db.dicts)..where((d) => d.ownerId.equals(userId))).get();

      for (final dict in userDicts) {
        final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
              ..where((dw) => dw.dictId.equals(dict.id))
              ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
            .get();
        if (wordsList.isEmpty) continue;

        // 检查序号是否从1开始
        if (wordsList.first.seq != 1) {
          result.addIssue('序号不连续', '词典 "${dict.name}" 第一个单词序号不是1', 'dict_word_sequence');
        }

        // 检查序号是否连续
        for (int i = 0; i < wordsList.length; i++) {
          if (wordsList[i].seq != i + 1) {
            result.addIssue('序号不连续', '词典 "${dict.name}" 位置${i + 1}的单词序号不正确', 'dict_word_sequence');
            break;
          }
        }

        // 检查最大序号是否等于总单词数
        if (wordsList.last.seq != wordsList.length) {
          result.addIssue('序号不连续', '词典 "${dict.name}" 最大序号不等于总单词数', 'dict_word_sequence');
        }
      }
    } catch (e, stack) {
      Global.logger.e('检查用户词典单词序号时出错', error: e, stackTrace: stack);
      result.addError('检查用户词典单词序号时出错: $e');
    }
  }

  /// 检查词典单词序号连续性
  Future<void> _checkDictWordSequences(IntegrityCheckResult result) async {
    try {
      // 获取所有词典
      final allDicts = await _db.dictsDao.select(_db.dicts).get();

      for (final dict in allDicts) {
        final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
              ..where((dw) => dw.dictId.equals(dict.id))
              ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
            .get();
        if (wordsList.isEmpty) continue;

        // 检查序号是否从1开始
        if (wordsList.first.seq != 1) {
          result.addIssue('序号不连续', '词典 "${dict.name}" 第一个单词序号不是1', 'dict_word_sequence');
        }

        // 检查序号是否连续
        for (int i = 0; i < wordsList.length; i++) {
          if (wordsList[i].seq != i + 1) {
            result.addIssue('序号不连续', '词典 "${dict.name}" 位置${i + 1}的单词序号不正确', 'dict_word_sequence');
            break;
          }
        }

        // 检查最大序号是否等于总单词数
        if (wordsList.last.seq != wordsList.length) {
          result.addIssue('序号不连续', '词典 "${dict.name}" 最大序号不等于总单词数', 'dict_word_sequence');
        }
      }
    } catch (e, stack) {
      Global.logger.e('检查词典单词序号时出错', error: e, stackTrace: stack);
      result.addError('检查词典单词序号时出错: $e');
    }
  }

  /// 检查用户词典单词数量一致性
  Future<void> _checkUserDictWordCounts(IntegrityCheckResult result, String userId) async {
    try {
      // 获取用户拥有的词典
      final userDicts = await (_db.dictsDao.select(_db.dicts)..where((d) => d.ownerId.equals(userId))).get();

      for (final dict in userDicts) {
        final actualCount = await _db.dictWordsDao.getDictWordCount(dict.id);
        if (dict.wordCount != actualCount) {
          result.addIssue('单词数量不匹配', '词典 "${dict.name}" 元数据(Metadata)记录数: ${dict.wordCount}, 数据库实际关联单词数: $actualCount', 'dict_word_count');
        }
      }
    } catch (e, stack) {
      Global.logger.e('检查用户词典单词数量时出错', error: e, stackTrace: stack);
      result.addError('检查用户词典单词数量时出错: $e');
    }
  }

  /// 检查词典单词数量一致性
  Future<void> _checkDictWordCounts(IntegrityCheckResult result) async {
    try {
      final allDicts = await _db.dictsDao.select(_db.dicts).get();

      for (final dict in allDicts) {
        final actualCount = await _db.dictWordsDao.getDictWordCount(dict.id);
        if (dict.wordCount != actualCount) {
          result.addIssue('单词数量不匹配', '词典 "${dict.name}" 元数据(Metadata)记录数: ${dict.wordCount}, 数据库实际关联单词数: $actualCount', 'dict_word_count');
        }
      }
    } catch (e, stack) {
      Global.logger.e('检查词典单词数量时出错', error: e, stackTrace: stack);
      result.addError('检查词典单词数量时出错: $e');
    }
  }

    
  /// 检查用户学习步骤完整性
  Future<void> _checkUserStudySteps(IntegrityCheckResult result, String userId) async {
    try {
      // 获取用户的所有学习步骤
      final steps = await _db.userStudyStepsDao.getUserStudySteps(userId);

      // 检查是否缺少 En2Ch
      final hasEn2Ch = steps.any((step) => step.studyStep == 'En2Ch');
      if (!hasEn2Ch) {
        result.addIssue('学习步骤缺失', '用户缺少学习步骤：En2Ch', 'user_study_steps');
      }

      // 检查是否缺少 Ch2En
      final hasCh2En = steps.any((step) => step.studyStep == 'Ch2En');
      if (!hasCh2En) {
        result.addIssue('学习步骤缺失', '用户缺少学习步骤：Ch2En', 'user_study_steps');
      }
    } catch (e, stack) {
      Global.logger.e('检查用户学习步骤时出错', error: e, stackTrace: stack);
      result.addError('检查用户学习步骤时出错: $e');
    }
  }

  /// 检查用户是否拥有必要的词书（生词本 和 已掌握），并验证唯一性
  Future<void> _checkUserDicts(IntegrityCheckResult result, String userId) async {
    try {
      // 获取用户拥有的所有词典
      final userDicts = await (_db.dictsDao.select(_db.dicts)..where((d) => d.ownerId.equals(userId))).get();

      // 1. 检查生词本
      final rawDicts = userDicts.where((d) => d.name == '生词本').toList();
      if (rawDicts.isEmpty) {
        result.addIssue('用户词书缺失', '用户缺少词书：生词本', 'missing_user_dict');
      } else if (rawDicts.length > 1) {
        final ids = rawDicts.map((d) => d.id).join(', ');
        result.addIssue('用户词书冗余', '用户拥有 ${rawDicts.length} 本"生词本"词书 (IDs: $ids)', 'missing_user_dict');
      }

      // 2. 检查已掌握词书
      final masteredDicts = userDicts.where((d) => d.name == '已掌握').toList();
      if (masteredDicts.isEmpty) {
        result.addIssue('用户词书缺失', '用户缺少词书：已掌握', 'missing_user_dict');
      } else if (masteredDicts.length > 1) {
        final ids = masteredDicts.map((d) => d.id).join(', ');
        result.addIssue('用户词书冗余', '用户拥有 ${masteredDicts.length} 本"已掌握"词书 (IDs: $ids)', 'missing_user_dict');
      }
    } catch (e, stack) {
      Global.logger.e('检查用户词书时出错', error: e, stackTrace: stack);
      result.addError('检查用户词书时出错: $e');
    }
  }

  /// 检查书桌上的系统词书，确保每个单词都有通用词典托底
  Future<void> _checkDeskSystemDictWordFallback(IntegrityCheckResult result, String userId) async {
    try {
      // 获取用户书桌上（LearningDict）的所有词书
      final learningDicts = await (_db.select(_db.learningDicts)..where((ld) => ld.userId.equals(userId))).get();
      if (learningDicts.isEmpty) return;

      final dictIds = learningDicts.map((e) => e.dictId).toList();
      
      // 获取这些词书的详细信息，过滤出系统词书（ownerId 不同于当前用户）
      final dicts = await (_db.dictsDao.select(_db.dicts)..where((d) => d.id.isIn(dictIds) & d.ownerId.isNotValue(userId))).get();
      
      if (dicts.isEmpty) return;

      for (final dict in dicts) {
         // 忽略特殊内置词书
         if (dict.name == '生词本' || dict.name == '已掌握') continue;

         // 获取当前系统词书的所有单词
         final wordsInSysDict = await (_db.dictWordsDao.select(_db.dictWords)..where((dw) => dw.dictId.equals(dict.id))).get();
         if (wordsInSysDict.isEmpty) continue;

         final sysWordIdsList = wordsInSysDict.map((dw) => dw.wordId).toSet().toList();
         
         // 分批查询，防止超长 IN 崩溃
         const batchSize = 900;
         final missingWords = <String>[];

         for (int i = 0; i < sysWordIdsList.length; i += batchSize) {
           final batch = sysWordIdsList.skip(i).take(batchSize).toList();
           final existingInCommon = await (_db.dictWordsDao.select(_db.dictWords)
             ..where((dw) => dw.dictId.equals(Global.commonDictId) & dw.wordId.isIn(batch)))
           .get();
           final existingIds = existingInCommon.map((dw) => dw.wordId).toSet();

           for (final id in batch) {
             if (!existingIds.contains(id)) {
               missingWords.add(id);
             }
           }
         }

         if (missingWords.isNotEmpty) {
           result.addIssue(
             '系统词书单词缺失托底', 
             '词书 "${dict.name}" 有 ${missingWords.length} 个单词在底层通用词典中查无释义 (示例: ${missingWords.take(5).join(', ')})', 
             'sys_dict_missing_fallback'
           );
         }
      }
    } catch (e, stack) {
      Global.logger.e('检查书桌系统词库底层托底时出错', error: e, stackTrace: stack);
      result.addError('检查书桌系统词库底层托底时出错: $e');
    }
  }

    
  /// 检查用户数据库版本一致性
  Future<void> _checkUserDbVersions(IntegrityCheckResult result, String userId) async {
    try {
      final userVersion = await _db.userDbVersionsDao.getUserDbVersionByUserId(userId);
      if (userVersion == null) return;

      // 检查是否有版本号大于当前版本的日志
      final allLogs = await _db.userDbLogsDao.getUserDbLogs(userId);
      final invalidLogs = allLogs.where((log) => log.version > userVersion.version).toList();

      if (invalidLogs.isNotEmpty) {
        result.addIssue('版本号异常', '用户有 ${invalidLogs.length} 条版本号异常的日志', 'user_db_version');
      }
    } catch (e, stack) {
      Global.logger.e('检查用户数据库版本时出错', error: e, stackTrace: stack);
      result.addError('检查用户数据库版本时出错: $e');
    }
  }

  /// 检查所有用户数据库版本一致性
  Future<void> _checkAllUserDbVersions(IntegrityCheckResult result) async {
    try {
      final allUsers = await _db.usersDao.allUsers;

      for (final user in allUsers) {
        final userVersion = await _db.userDbVersionsDao.getUserDbVersionByUserId(user.id);
        if (userVersion == null) continue;

        // 检查是否有版本号大于当前版本的日志
        final allLogs = await _db.userDbLogsDao.getUserDbLogs(user.id);
        final invalidLogs = allLogs.where((log) => log.version > userVersion.version).toList();

        if (invalidLogs.isNotEmpty) {
          result.addIssue('版本号异常', '用户 ${user.userName} 有 ${invalidLogs.length} 条版本号异常的日志', 'user_db_version');
        }
      }
    } catch (e, stack) {
      Global.logger.e('检查用户数据库版本时出错', error: e, stackTrace: stack);
      result.addError('检查用户数据库版本时出错: $e');
    }
  }

  /// 检查通用词典完整性
  Future<void> _checkCommonDictIntegrity(IntegrityCheckResult result) async {
    try {
      final commonDict = await _db.dictsDao.findById(Global.commonDictId);
      if (commonDict != null) {
        // 1. 检查记录数量一致性
        final actualCount = await _db.dictWordsDao.getDictWordCount(Global.commonDictId);
        if (commonDict.wordCount != actualCount) {
          result.addIssue('系统单词数量不匹配', '通用兜底词书元数据(Metadata)记录数: ${commonDict.wordCount}, 数据库实际关联单词数: $actualCount', 'common_dict_integrity');
        }

        // 2. 检查序号连续性
        final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
              ..where((dw) => dw.dictId.equals(Global.commonDictId))
              ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
            .get();
        if (wordsList.isNotEmpty) {
          if (wordsList.first.seq != 1 || wordsList.last.seq != wordsList.length) {
            result.addIssue('系统单词序号不连续', '通用兜底词书序号发生断层或未从1开始', 'common_dict_integrity');
          } else {
            for (int i = 0; i < wordsList.length; i++) {
              if (wordsList[i].seq != i + 1) {
                result.addIssue('系统单词序号不连续', '通用兜底词书序号在位置 ${i + 1} 断层', 'common_dict_integrity');
                break;
              }
            }
          }
        }
      }

      // 检查通用词典中的单词是否有释义项
      final wordsList = await (_db.dictWordsDao.select(_db.dictWords)..where((dw) => dw.dictId.equals(Global.commonDictId))).get();

      Global.logger.d('开始检查通用词典完整性，共 ${wordsList.length} 个单词');

      // 使用批量查询提高效率
      final wordIds = wordsList.map((w) => w.wordId).toList();

      // 批量查询所有单词的释义项
      // SQLite 的 IN 子句最多支持 999 个参数，需要分批查询
      const int batchSize = 900; // 保守起见使用 900
      Global.logger.d('查询 ${wordIds.length} 个单词的释义项（分批查询）...');

      final allMeanings = <MeaningItem>[];
      for (int i = 0; i < wordIds.length; i += batchSize) {
        final batch = wordIds.skip(i).take(batchSize).toList();
        final batchMeanings =
            await (_db.meaningItemsDao.select(_db.meaningItems)..where((mi) => mi.wordId.isIn(batch) & mi.dictId.equals(Global.commonDictId))).get();
        allMeanings.addAll(batchMeanings);
      }
      Global.logger.d('查询到 ${allMeanings.length} 条释义项');

      // 按单词分组
      final meaningsMap = <String, List<MeaningItem>>{};
      for (final meaning in allMeanings) {
        (meaningsMap[meaning.wordId] ??= []).add(meaning);
      }

      // 检查缺少释义项的单词
      final wordsWithoutMeanings = wordIds.where((id) => !meaningsMap.containsKey(id) || meaningsMap[id]!.isEmpty).toList();
      for (final wordId in wordsWithoutMeanings) {
        result.addIssue('通用词典不完整', '单词 "$wordId" 缺少释义项', 'common_dict_integrity');
      }

      // 批量查询所有释义项的例句
      final meaningIds = allMeanings.map((m) => m.id).toList();
      Global.logger.d('查询 ${meaningIds.length} 个释义项的例句（分批查询）...');

      final allSentences = <Sentence>[];
      for (int i = 0; i < meaningIds.length; i += batchSize) {
        final batch = meaningIds.skip(i).take(batchSize).toList();
        final batchSentences = await (_db.sentencesDao.select(_db.sentences)..where((s) => s.meaningItemId.isIn(batch))).get();
        allSentences.addAll(batchSentences);
      }
      Global.logger.d('查询到 ${allSentences.length} 条例句');

      // 按释义项分组
      final sentencesMap = <String, List<Sentence>>{};
      for (final sentence in allSentences) {
        (sentencesMap[sentence.meaningItemId] ??= []).add(sentence);
      }

      // 检查缺少例句的释义项
      int meaningsWithoutSentences = 0;
      for (final meaning in allMeanings) {
        if (!sentencesMap.containsKey(meaning.id) || sentencesMap[meaning.id]!.isEmpty) {
          meaningsWithoutSentences++;
          result.addIssue('通用词典不完整', '释义项 "${meaning.id}" 缺少例句', 'common_dict_integrity');
        }
      }

      Global.logger.d('通用词典完整性检查完成，检查了 ${wordsList.length} 个单词，发现 ${wordsWithoutMeanings.length} 个单词缺少释义项，$meaningsWithoutSentences 个释义项缺少例句');
    } catch (e, stackTrace) {
      Global.logger.e('检查通用词典完整性时出错', error: e, stackTrace: stackTrace);
      result.addError('检查通用词典完整性时出错: $e');
    }
  }

  /// 自动修复发现的问题
  /// [userId] 当前登录用户 ID，用于权限验证
  Future<IntegrityFixResult> autoFix(IntegrityCheckResult checkResult, String userId) async {
    final fixResult = IntegrityFixResult();

    try {
      // 修复序号不连续问题
      if (checkResult.hasIssue('dict_word_sequence')) {
        try {
          await _fixDictWordSequences(fixResult, userId);
        } catch (e, stack) {
          Global.logger.e('修复词典序号时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复词典序号失败: $e');
        }
      }

      // 修复单词数量不匹配问题
      if (checkResult.hasIssue('dict_word_count')) {
        try {
          await _fixDictWordCounts(fixResult, userId);
        } catch (e, stack) {
          Global.logger.e('修复单词数量时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复单词数量失败: $e');
        }
      }

    
      // 修复学习步骤缺失问题
      if (checkResult.hasIssue('user_study_steps')) {
        try {
          await _fixUserStudySteps(fixResult, userId);
        } catch (e, stack) {
          Global.logger.e('修复学习步骤时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复学习步骤失败: $e');
        }
      }

      // 修复用户词书缺失问题
      if (checkResult.hasIssue('missing_user_dict')) {
        try {
          await _fixMissingUserDicts(fixResult, userId);
        } catch (e, stack) {
          Global.logger.e('修复基础词书时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复基础词书失败: $e');
        }
      }

      // 修复单词托底缺失问题 (点对点向云端索取本地查无释义的丢失数据)
      if (checkResult.hasIssue('sys_dict_missing_fallback')) {
        try {
          await _fixSysDictMissingFallback(fixResult, userId);
        } catch (e, stack) {
          Global.logger.e('修复底层托底时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复底层托底失败: $e');
        }
      }

      // 修复正在学习单词的释义缺失问题
      if (checkResult.hasIssue('learning_word_missing_meaning')) {
        try {
          await _fixLearningWordMissingMeaning(fixResult, userId);
        } catch (e, stack) {
          Global.logger.e('修复学习单词释义时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复学习单词释义失败: $e');
        }
      }

      // 系统级字典（主要是通用词典 ID=0）如果有数据不完整的问题
      if (checkResult.hasIssue('common_dict_integrity')) {
        try {
          // 策略：不再通过同步流（Version 0）重刷，因为同步流不包含释义和例句。
          // 而是通过专项词书下载接口（downloadADict）进行靶向增量修复。
          Global.logger.i('💡 [修复] 检测到系统通用词典数据不完整，正在启动专项增量拉取修复...');
          
          final commonDict = await _db.dictsDao.findById(Global.commonDictId);
          if (commonDict != null) {
            // 找到本地实际的单词列表，计算断层位置
            final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
                  ..where((dw) => dw.dictId.equals(Global.commonDictId))
                  ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
                .get();
            
            int fromSeq = 1;
            // 寻找第一个断层
            for (int i = 0; i < wordsList.length; i++) {
              if (wordsList[i].seq != i + 1) {
                fromSeq = i + 1;
                break;
              }
              if (i == wordsList.length - 1) {
                fromSeq = wordsList.length + 1;
              }
            }

            if (fromSeq <= commonDict.wordCount) {
              Global.logger.i('💡 [修复] 通用词典缺失序号范围: $fromSeq - ${commonDict.wordCount}，开始专项增量拉取...');
              final response = await Api.client.getDictResRange(
                Global.commonDictId,
                fromSeq,
                commonDict.wordCount,
              );

              if (response.success && response.data != null) {
                await _importDictRes(response.data!);
                fixResult.addFixed('系统通用词典已通过专项修复接口（Range: $fromSeq - ${commonDict.wordCount}）成功修复并缝合！');
              } else {
                fixResult.addError('系统通用词典增量修复拉取失败: ${response.msg}');
              }
            } else {
              fixResult.addFixed('系统通用词典序号检查通过，无需增量修复。');
            }
          }
        } catch (e, stack) {
          Global.logger.e('修复通用系统数据时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复通用系统数据失败: $e');
        }
      }

      // 修复版本号异常问题
      if (checkResult.hasIssue('user_db_version')) {
        try {
          await _fixUserDbVersions(fixResult, userId);
        } catch (e, stack) {
          Global.logger.e('修复版本号异常时发生中断性错误', error: e, stackTrace: stack);
          fixResult.addError('修复版本号异常失败: $e');
        }
      }

      // 提示TTS修复方案
      if (checkResult.hasIssue('local_tts')) {
        fixResult.addFixed('请检查您的系统设置 -> 辅助功能/语言与输入 -> 文字转语音输出，确保已下载对应的中文/英文语音包。');
      }
    } catch (e, stack) {
      Global.logger.e('自动修复过程中出现未捕获的全局错误', error: e, stackTrace: stack);
      fixResult.addError('自动修复过程中出现全局错误：$e');
    }

    return fixResult;
  }

  /// 通过非全局大喇叭的“点对点私房补件”策略，向后端索取缺失的基础托底数据，直接静默入库
  Future<void> _fixSysDictMissingFallback(IntegrityFixResult fixResult, String userId) async {
    try {
      final learningDicts = await (_db.select(_db.learningDicts)..where((ld) => ld.userId.equals(userId))).get();
      if (learningDicts.isEmpty) return;

      final dictIds = learningDicts.map((e) => e.dictId).toList();
      final dicts = await (_db.dictsDao.select(_db.dicts)..where((d) => d.id.isIn(dictIds) & d.ownerId.isNotValue(userId))).get();
      if (dicts.isEmpty) return;

      final allMissingWords = <String>{};

      for (final dict in dicts) {
         if (dict.name == '生词本' || dict.name == '已掌握') continue;
         final wordsInSysDict = await (_db.dictWordsDao.select(_db.dictWords)..where((dw) => dw.dictId.equals(dict.id))).get();
         if (wordsInSysDict.isEmpty) continue;

         final sysWordIdsList = wordsInSysDict.map((dw) => dw.wordId).toSet().toList();
         const batchSize = 900;
         for (int i = 0; i < sysWordIdsList.length; i += batchSize) {
           final batch = sysWordIdsList.skip(i).take(batchSize).toList();
           final existingInCommon = await (_db.dictWordsDao.select(_db.dictWords)
             ..where((dw) => dw.dictId.equals(Global.commonDictId) & dw.wordId.isIn(batch)))
           .get();
           final existingIds = existingInCommon.map((dw) => dw.wordId).toSet();

           for (final id in batch) {
             if (!existingIds.contains(id)) {
               allMissingWords.add(id);
             }
           }
         }
      }

      if (allMissingWords.isNotEmpty) {
        String jsonStr = jsonEncode(allMissingWords.toList());
        final response = await Api.client.getFallbackWordsData(jsonStr);
        if (response.success && response.data != null) {
           final data = response.data!.data;
           int dwCount = 0, mCount = 0, sCount = 0;

           await _db.transaction(() async {
             // 1. 恢复 DictWord
             final dwList = data['dictWords'] as List<dynamic>? ?? [];
             for (final item in dwList) {
               final Map<String, dynamic> dictWordMap = Map<String, dynamic>.from(item as Map);
               final dw = DictWord.fromJson(dictWordMap);
               await _db.dictWordsDao.insertEntity(dw, false);
               dwCount++;
             }

             // 2. 恢复 MeaningItem
             final mList = data['meaningItems'] as List<dynamic>? ?? [];
             for (final item in mList) {
               final Map<String, dynamic> mMap = Map<String, dynamic>.from(item as Map);
               final m = MeaningItem.fromJson(mMap);
               await _db.meaningItemsDao.insertEntity(m, false);
               mCount++;
             }

             // 3. 恢复 Sentence
             final sList = data['sentences'] as List<dynamic>? ?? [];
             for (final item in sList) {
               final Map<String, dynamic> sMap = Map<String, dynamic>.from(item as Map);
               final s = Sentence.fromJson(sMap);
               await _db.sentencesDao.insertEntity(s);
               sCount++;
             }
           });

           fixResult.addFixed('成功向云端获取并静默缝合了 ${allMissingWords.length} 个查无释义的丢失托底数据包！(包含 $dwCount 条物理连结，$mCount 条释义，$sCount 条例句)');
        } else {
           fixResult.addError('请求云端补件接口失败: ${response.msg}');
        }
      }
    } catch (e, stack) {
      Global.logger.e('靶向修复底层字典托底碎片时出错', error: e, stackTrace: stack);
      fixResult.addError('靶向修复底层字典托底碎片时出错: $e');
    }
  }

  /// 检查用户正在学习的单词是否都有释义
  Future<void> _checkLearningWordsMeanings(IntegrityCheckResult result, String userId) async {
    try {
      // 1. 获取用户正在学习的所有单词
      final learningWordsList = await (_db.select(_db.learningWords)..where((lw) => lw.userId.equals(userId))).get();
      if (learningWordsList.isEmpty) return;

      final wordIds = learningWordsList.map((lw) => lw.wordId).toSet().toList();
      
      // 2. 分批查询这些单词是否有释义（不限词典）
      const batchSize = 900;
      final wordsWithMeanings = <String>{};

      for (int i = 0; i < wordIds.length; i += batchSize) {
        final batch = wordIds.skip(i).take(batchSize).toList();
        final existingMeanings = await (_db.meaningItemsDao.select(_db.meaningItems)
          ..where((mi) => mi.wordId.isIn(batch)))
        .get();
        
        for (final m in existingMeanings) {
          wordsWithMeanings.add(m.wordId);
        }
      }

      // 3. 找出缺失释义的单词及其所属词典
      final missingMeanings = wordIds.where((id) => !wordsWithMeanings.contains(id)).toList();

      if (missingMeanings.isNotEmpty) {
        final List<String> details = [];
        for (final wordId in missingMeanings.take(10)) {
          // 获取单词拼写
          final word = await (_db.wordsDao.select(_db.words)..where((w) => w.id.equals(wordId))).getSingleOrNull();
          final spelling = word?.spell ?? "未知拼写";
          final shortId = wordId.length > 6 ? wordId.substring(0, 6) : wordId;

          // 反查所属词典
          final dictWords = await (_db.dictWordsDao.select(_db.dictWords)..where((dw) => dw.wordId.equals(wordId))).get();
          final dictNames = <String>[];
          for (final dw in dictWords) {
            final dict = await _db.dictsDao.findById(dw.dictId);
            if (dict != null) dictNames.add(dict.name);
          }
          details.add('"$spelling" (ID: $shortId, 来自词典: ${dictNames.isEmpty ? "未知" : dictNames.join(", ")})');
        }

        String description = '您正在学习的单词中有 ${missingMeanings.length} 个在本地查无释义。';
        if (details.isNotEmpty) {
          description += '\n示例：\n${details.join("\n")}';
          if (missingMeanings.length > 10) {
            description += '\n... 等共 ${missingMeanings.length} 个单词';
          }
        }

        result.addIssue(
          '学习单词缺少释义', 
          description, 
          'learning_word_missing_meaning'
        );
      }
    } catch (e, stack) {
      Global.logger.e('检查学习单词释义完整性时出错', error: e, stackTrace: stack);
      result.addError('检查学习单词释义完整性时出错: $e');
    }
  }

  /// 修复正在学习单词缺失释义的问题
  Future<void> _fixLearningWordMissingMeaning(IntegrityFixResult fixResult, String userId) async {
    try {
      final learningWordsList = await (_db.select(_db.learningWords)..where((lw) => lw.userId.equals(userId))).get();
      if (learningWordsList.isEmpty) return;

      final wordIds = learningWordsList.map((lw) => lw.wordId).toSet().toList();
      const batchSize = 900;
      final missingWordIds = <String>[];

      for (int i = 0; i < wordIds.length; i += batchSize) {
        final batch = wordIds.skip(i).take(batchSize).toList();
        final existingMeanings = await (_db.meaningItemsDao.select(_db.meaningItems)
          ..where((mi) => mi.wordId.isIn(batch)))
        .get();
        final existingIds = existingMeanings.map((mi) => mi.wordId).toSet();

        for (final id in batch) {
          if (!existingIds.contains(id)) {
            missingWordIds.add(id);
          }
        }
      }

      if (missingWordIds.isNotEmpty) {
        String jsonStr = jsonEncode(missingWordIds);
        final response = await Api.client.getFallbackWordsData(jsonStr);
        if (response.success && response.data != null) {
           final data = response.data!.data;
           int dwCount = 0, mCount = 0, sCount = 0;

           await _db.transaction(() async {
             try {
               Global.logger.i('【修复】开始持久化从云端获取的学习单词数据...');
               
               // 1. 恢复 DictWord (为了能让单词在词典中显示)
               final dwList = data['dictWords'] as List<dynamic>? ?? [];
               for (final item in dwList) {
                 final Map<String, dynamic> dictWordMap = Map<String, dynamic>.from(item as Map);
                 final dw = DictWord.fromJson(dictWordMap);
                 await _db.dictWordsDao.insertEntity(dw, false);
                 dwCount++;
               }

               // 2. 恢复 MeaningItem
               final mList = data['meaningItems'] as List<dynamic>? ?? [];
               for (final item in mList) {
                 final Map<String, dynamic> mMap = Map<String, dynamic>.from(item as Map);
                 final m = MeaningItem.fromJson(mMap);
                 await _db.meaningItemsDao.insertEntity(m, false);
                 mCount++;
               }

               // 3. 恢复 Sentence
               final sList = data['sentences'] as List<dynamic>? ?? [];
               for (final item in sList) {
                 final Map<String, dynamic> sMap = Map<String, dynamic>.from(item as Map);
                 final s = Sentence.fromJson(sMap);
                 await _db.sentencesDao.insertEntity(s);
                 sCount++;
               }
             } catch (e, stack) {
               Global.logger.i('【修复】!!! 事务内部发生错误 (info级别打印以防过滤) !!!: $e');
               Global.logger.i('【修复】堆栈: $stack');
               rethrow;
             }
           });

           Global.logger.i('【修复】本地数据入库完成: dw=$dwCount, m=$mCount, s=$sCount');
           fixResult.addFixed('成功向云端获取并补全了 ${missingWordIds.length} 个学习单词的释义数据！(包含 $dwCount 条物理连结，$mCount 条释义，$sCount 条例句)');
        } else {
           fixResult.addError('请求云端补全学习单词数据失败: ${response.msg}');
        }
      }
    } catch (e, stack) {
      Global.logger.e('修复学习单词释义缺失时出错', error: e, stackTrace: stack);
      fixResult.addError('修复学习单词释义缺失时出错: $e');
    }
  }

  /// 修复词典单词序号
  Future<void> _fixDictWordSequences(IntegrityFixResult fixResult, String currentUserId) async {
    try {
      final allDicts = await _db.dictsDao.select(_db.dicts).get();

      for (final dict in allDicts) {
        // 安全验证：只修复当前用户的词典
        if (dict.ownerId != currentUserId) {
          Global.logger.w('⚠️ 跳过非当前用户的词典：dictId=${dict.id}, ownerId=${dict.ownerId}, currentUserId=$currentUserId');
          continue;
        }

        final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
              ..where((dw) => dw.dictId.equals(dict.id))
              ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
            .get();
        if (wordsList.isEmpty) continue;

        // 检查是否需要修复
        bool needsFix = false;
        for (int i = 0; i < wordsList.length; i++) {
          if (wordsList[i].seq != i + 1) {
            needsFix = true;
            break;
          }
        }

        // 如果需要修复，调用重新排序方法
        if (needsFix) {
          // 判断是否为生词本
          bool genLog = dict.name == '生词本';
          await _db.dictWordsDao.fixDictOrder(dict.id, genLog);
          fixResult.addFixed('修复词典 "${dict.name}" 单词序号');
        }
      }
    } catch (e, stack) {
      Global.logger.e('修复词典单词序号时出错', error: e, stackTrace: stack);
      fixResult.addError('修复词典单词序号时出错：$e');
    }
  }

  /// 修复词典单词数量
  Future<void> _fixDictWordCounts(IntegrityFixResult fixResult, String currentUserId) async {
    try {
      final allDicts = await _db.dictsDao.select(_db.dicts).get();

      for (final dict in allDicts) {
        // 安全验证：只修复当前用户的词典
        if (dict.ownerId != currentUserId) {
          Global.logger.w('⚠️ 跳过非当前用户的词典：dictId=${dict.id}, ownerId=${dict.ownerId}, currentUserId=$currentUserId');
          continue;
        }

        final actualCount = await _db.dictWordsDao.getDictWordCount(dict.id);
        if (dict.wordCount != actualCount) {
          await _db.dictsDao.updateWordCount(dict.id, true);
          fixResult.addFixed('修复词典 "${dict.name}" 单词数量：$actualCount');
        }
      }
    } catch (e, stack) {
      Global.logger.e('修复词典单词数量时出错', error: e, stackTrace: stack);
      fixResult.addError('修复词典单词数量时出错：$e');
    }
  }


  /// 从后端拉取用户基础数据（包括缺失的词书、学习步骤等）
  Future<bool> _fetchAndSaveBaseData(String currentUserId, IntegrityFixResult fixResult) async {
    try {
      final response = await Api.client.getUserBaseData(currentUserId);
      if (response.success && response.data != null) {
        final data = response.data!;
        
        // 恢复词书 (检测冲突并立刻报错)
        if (data.rawDict != null) {
          final dictDto = data.rawDict!;
          final existingById = await _db.dictsDao.findById(dictDto.id);
          final existingByName = await _db.dictsDao.findUserRawDict(currentUserId);
          
          if (existingById == null) {
            if (existingByName != null) {
              throw Exception('数据完整性损坏: 本地已存在名为 "${dictDto.name}" 的词书但 ID 不匹配 (本地 ID: ${existingByName.id}, 服务端 ID: ${dictDto.id})');
            }
            final dict = Dict(
              id: dictDto.id,
              name: dictDto.name,
              ownerId: dictDto.ownerId,
              isShared: dictDto.isShared,
              isReady: dictDto.isReady,
              visible: dictDto.visible,
              wordCount: dictDto.wordCount,
              popularityLimit: dictDto.popularityLimit ?? 0,
              editable: dictDto.editable ?? true,
              deletable: dictDto.deletable ?? false,
              createTime: dictDto.createTime,
              updateTime: dictDto.updateTime,
            );
            await _db.dictsDao.saveEntity(dict, false);
          }
        }

        if (data.masteredDict != null) {
          final dictDto = data.masteredDict!;
          final existingById = await _db.dictsDao.findById(dictDto.id);
          final existingByName = await _db.dictsDao.findUserMasteredDict(currentUserId);
          
          if (existingById == null) {
            if (existingByName != null) {
              throw Exception('数据完整性损坏: 本地已存在名为 "${dictDto.name}" 的词书但 ID 不匹配 (本地 ID: ${existingByName.id}, 服务端 ID: ${dictDto.id})');
            }
            final dict = Dict(
              id: dictDto.id,
              name: dictDto.name,
              ownerId: dictDto.ownerId,
              isShared: dictDto.isShared,
              isReady: dictDto.isReady,
              visible: dictDto.visible,
              wordCount: dictDto.wordCount,
              popularityLimit: dictDto.popularityLimit ?? 0,
              editable: dictDto.editable ?? true,
              deletable: dictDto.deletable ?? false,
              createTime: dictDto.createTime,
              updateTime: dictDto.updateTime,
            );
            await _db.dictsDao.saveEntity(dict, false);
          }
        }

        // 恢复学习步骤
        if (data.studySteps != null) {
          final existingSteps = await _db.userStudyStepsDao.getUserStudySteps(currentUserId);
          final existingStepNames = existingSteps.map((e) => e.studyStep).toSet();
          
          final stepsToInsert = data.studySteps!
              .where((stepDto) => !existingStepNames.contains(stepDto.studyStep))
              .map((stepDto) => UserStudyStep(
                userId: stepDto.userId,
                studyStep: stepDto.studyStep,
                seq: stepDto.seq,
                state: stepDto.state,
                createTime: stepDto.createTime,
                updateTime: stepDto.updateTime,
              )).toList();
          
          if (stepsToInsert.isNotEmpty) {
            await _db.batch((batch) {
              batch.insertAll(_db.userStudySteps, stepsToInsert, mode: InsertMode.insertOrIgnore);
            });
          }
        }
        return true;
      } else {
        fixResult.addError('从服务端获取基础数据失败: ${response.msg}');
        return false;
      }
    } catch (e, stack) {
      Global.logger.e('请求服务端基础数据时发生异常', error: e, stackTrace: stack);
      fixResult.addError('请求服务端基础数据时发生异常: $e');
      return false;
    }
  }

  /// 修复用户学习步骤缺失问题
  /// 通过拉取服务端的基础数据自动恢复
  Future<void> _fixUserStudySteps(IntegrityFixResult fixResult, String currentUserId) async {
    try {
      final steps = await _db.userStudyStepsDao.getUserStudySteps(currentUserId);
      final hasEn2Ch = steps.any((step) => step.studyStep == 'En2Ch');
      final hasCh2En = steps.any((step) => step.studyStep == 'Ch2En');
      final hasList = steps.any((step) => step.studyStep == 'List');

      List<String> missing = [];
      if (!hasEn2Ch) missing.add('En2Ch');
      if (!hasCh2En) missing.add('Ch2En');
      if (!hasList) missing.add('List');

      if (missing.isNotEmpty) {
        // 先尝试通过常规的 syncUserDb 恢复
        try {
          await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
          
          // 同步后重新检查是否成功恢复
          final newSteps = await _db.userStudyStepsDao.getUserStudySteps(currentUserId);
          final newHasEn2Ch = newSteps.any((step) => step.studyStep == 'En2Ch');
          final newHasCh2En = newSteps.any((step) => step.studyStep == 'Ch2En');
          final newHasList = newSteps.any((step) => step.studyStep == 'List');

          missing.clear();
          if (!newHasEn2Ch) missing.add('En2Ch');
          if (!newHasCh2En) missing.add('Ch2En');
          if (!newHasList) missing.add('List');

          if (missing.isEmpty) {
            fixResult.addFixed('通过数据同步成功补全了学习步骤');
            return;
          }
        } catch (e) {
          Global.logger.e('尝试通过数据同步恢复学习步骤时出错', error: e);
        }

        bool ok = await _fetchAndSaveBaseData(currentUserId, fixResult);
        if (ok) {
           fixResult.addFixed('成功拉取服务端同步补全了缺失的学习步骤: ${missing.join(", ")}');
        } else {
           fixResult.addError('用户缺少学习步骤: ${missing.join(", ")}. 同步恢复失败。');
        }
      }
    } catch (e, stack) {
      Global.logger.e('检查用户学习步骤时出错', error: e, stackTrace: stack);
      fixResult.addError('检查用户学习步骤时出错：$e');
    }
  }

  /// 修复用户缺失的词书（生词本 / 已掌握）
  /// 通过拉取服务端的基础数据自动恢复
  Future<void> _fixMissingUserDicts(IntegrityFixResult fixResult, String currentUserId) async {
    try {
      final userDicts = await (_db.dictsDao.select(_db.dicts)..where((d) => d.ownerId.equals(currentUserId))).get();
      final hasRawWordDict = userDicts.any((dict) => dict.name == '生词本');
      final hasMasteredDict = userDicts.any((dict) => dict.name == '已掌握');

      List<String> missing = [];
      if (!hasRawWordDict) missing.add('生词本');
      if (!hasMasteredDict) missing.add('已掌握');

      if (missing.isNotEmpty) {
        // 先尝试通过常规的 syncUserDb 恢复
        try {
          await ThrottledDbSyncService().requestSyncAndWait(immediate: true);

          // 同步后重新检查
          final newUserDicts = await (_db.dictsDao.select(_db.dicts)..where((d) => d.ownerId.equals(currentUserId))).get();
          final newHasRawWordDict = newUserDicts.any((dict) => dict.name == '生词本');
          final newHasMasteredDict = newUserDicts.any((dict) => dict.name == '已掌握');

          missing.clear();
          if (!newHasRawWordDict) missing.add('生词本');
          if (!newHasMasteredDict) missing.add('已掌握');

          if (missing.isEmpty) {
            fixResult.addFixed('通过数据同步成功补全了基础词书');
            return;
          }
        } catch (e) {
          Global.logger.e('尝试通过数据同步恢复基础词书时出错', error: e);
        }

        bool ok = await _fetchAndSaveBaseData(currentUserId, fixResult);
        if (ok) {
           fixResult.addFixed('成功拉取服务端同步补全了缺失的基础词书: ${missing.join(", ")}');
        } else {
           fixResult.addError('用户缺少基础词书: ${missing.join(", ")}. 同步恢复失败。');
        }
      }
    } catch (e, stack) {
      Global.logger.e('检查用户词书时出错', error: e, stackTrace: stack);
      fixResult.addError('检查用户词书时出错: $e');
    }
  }



  /// 修复用户数据库版本
  Future<void> _fixUserDbVersions(IntegrityFixResult fixResult, String currentUserId) async {
    try {
      // 安全验证：只修复当前用户的版本信息
      final userVersion = await _db.userDbVersionsDao.getUserDbVersionByUserId(currentUserId);
      if (userVersion == null) {
        Global.logger.w('⚠️ 当前用户没有数据库版本记录：userId=$currentUserId');
        return;
      }

      // 删除版本号大于当前版本的日志
      final allLogs = await _db.userDbLogsDao.getUserDbLogs(currentUserId);
      final invalidLogs = allLogs.where((log) => log.version > userVersion.version).toList();

      if (invalidLogs.isNotEmpty) {
        // 使用现有的删除方法
        await _db.userDbLogsDao.deleteUserDbLogs(currentUserId);
        fixResult.addFixed('删除当前用户的 ${invalidLogs.length} 条异常日志');
      }
    } catch (e, stack) {
      Global.logger.e('修复用户数据库版本时出错', error: e, stackTrace: stack);
      fixResult.addError('修复用户数据库版本时出错：$e');
    }
  }

  /// 检查网络连接
  Future<void> _checkNetworkConnectivity(IntegrityCheckResult result) async {
    try {
      final networkUtil = NetworkUtil();
      final isConnected = await networkUtil.isConnected();

      if (!isConnected) {
        result.addIssue('网络不可用', '设备未连接到网络或无法访问互联网', 'network_connectivity');
      } else {
        final connectionType = await networkUtil.getConnectionType();
        Global.logger.d('网络连接正常，连接类型: $connectionType');
      }
    } catch (e, stack) {
      Global.logger.e('检查网络连接时出错', error: e, stackTrace: stack);
      result.addIssue('网络检查失败', '无法检查网络连接状态: $e', 'network_connectivity');
    }
  }

  /// 检查后端服务器连通性
  Future<void> _checkBackendServer(IntegrityCheckResult result) async {
    try {
      // 使用 Dio 直接调用API
      final dio = Dio(BaseOptions(
        baseUrl: Config.serviceUrl,
        connectTimeout: const Duration(seconds: 5),
      ));

      // 尝试调用一个简单的API来检查后端连通性
      final response = await dio.get(
        '/getGameHallData.do',
        options: Options(validateStatus: (status) => status! < 500), // 允许非200状态码
      );

      if (response.statusCode != null && response.statusCode! < 500) {
        Global.logger.d('后端服务器连通性正常，状态码: ${response.statusCode}');
      } else {
        result.addIssue('后端服务器无响应', '后端服务器返回错误状态: ${response.statusCode}', 'backend_server');
      }
    } catch (e, stack) {
      Global.logger.e('检查后端服务器时出错', error: e, stackTrace: stack);
      result.addIssue('后端服务器连接失败', '无法连接到后端服务器: ${e.toString().substring(0, e.toString().length > 50 ? 50 : e.toString().length)}', 'backend_server');
    }
  }

  /// 检查游戏服务器连通性
  Future<void> _checkGameServer(IntegrityCheckResult result) async {
    try {
      // 检查 socket.io 连接状态
      final socketClient = SocketIoClient.instance;

      // 尝试连接socket服务器
      socketClient.connect();

      // 等待一小段时间让连接建立
      await Future.delayed(const Duration(seconds: 2));

      // 检查连接状态
      if (socketClient.isConnectedToSocketServer) {
        Global.logger.d('游戏服务器连接正常');
        // 检查完后立即断开
        socketClient.disconnect();
      } else {
        result.addIssue('游戏服务器连接失败', '无法建立WebSocket连接到游戏服务器', 'game_server');
        socketClient.disconnect();
      }
    } catch (e, stack) {
      Global.logger.e('检查游戏服务器时出错', error: e, stackTrace: stack);
      result.addIssue('游戏服务器检查失败', '检查游戏服务器连接时出错: ${e.toString().substring(0, e.toString().length > 50 ? 50 : e.toString().length)}', 'game_server');
      // 确保断开连接
      try {
        SocketIoClient.instance.disconnect();
      } catch (e, stackTrace) {
        Global.logger.w('断开Socket连接失败', error: e, stackTrace: stackTrace);
      }
    }
  }

  /// 检查本地TTS（文字转语音）功能
  Future<void> _checkTtsFunctionality(IntegrityCheckResult result) async {
    try {
      if (!PlatformUtils.isTtsSupported()) {
        result.addIssue('TTS不支持', '当前设备平台不支持本地TTS语音功能', 'local_tts');
        return;
      }

      final tts = Tts();
      bool ready = await tts.isReady();
      if (!ready) {
        result.addIssue('TTS初始化失败', '本地TTS引擎初始化失败，请检查系统语音设置', 'local_tts');
        return;
      }

      // 检查中文支持（用户反馈的重点）
      bool hasChinese = await tts.checkLanguageSupport('zh-CN');
      if (hasChinese) {
        // 尝试实地播放一段中文语音，验证引擎是否真的能出声
        try {
          await tts.speak('您的词典本地TTS语音功能正常');
        } catch (e) {
          result.addIssue('TTS播放失败', '虽然系统报告支持中文TTS，但实际播放时发生错误: $e', 'local_tts');
        }
      } else {
        result.addIssue('缺少中文语音', '本地TTS引擎不支持中文（zh-CN），请在系统设置中下载中文语音包', 'local_tts');
      }

      // 检查英文支持
      bool hasEnglish = await tts.checkLanguageSupport('en-US');
      if (hasEnglish) {
        try {
          await tts.speak('Your local TTS is working');
        } catch (e) {
          result.addIssue('TTS播放失败', '虽然系统报告支持英文TTS，但实际播放时发生错误: $e', 'local_tts');
        }
      } else {
        result.addIssue('缺少英文语音', '本地TTS引擎不支持英文（en-US），请在系统设置中下载英文语音包', 'local_tts');
      }
    } catch (e, stack) {
      Global.logger.e('检查本地TTS功能时出错', error: e, stackTrace: stack);
      result.addError('检查本地TTS功能时出错: $e');
    }
  }

  /// 将从后端获取的 DictRes 集合静默缝合进本地数据库
  Future<void> _importDictRes(DictRes res) async {
    await _db.transaction(() async {
      // 0. 更新词书元数据 (如果有)
      if (res.dict != null) {
        final d = res.dict!;
        await _db.dictsDao.saveAll([
          Dict(
            id: d.id,
            isReady: d.isReady,
            isShared: d.isShared,
            name: d.name,
            wordCount: d.wordCount,
            ownerId: d.ownerId,
            visible: d.visible,
            editable: d.editable ?? false,
            deletable: d.deletable ?? true,
            popularityLimit: d.popularityLimit,
            domain: d.domain,
            baseDictId: d.baseDictId,
            coverUrl: d.coverUrl,
            sortAlg: d.sortAlg,
            description: d.description,
            createTime: d.createTime,
            updateTime: d.updateTime,
          )
        ]);
      }

      // 1. 单词
      if (res.words != null && res.words!.isNotEmpty) {
        final List<Word> words = res.words!.map((w) => Word(
          id: w.id,
          spell: w.spell,
          pronounce: w.pronounce,
          americaPronounce: w.americaPronounce,
          britishPronounce: w.britishPronounce,
          popularity: w.popularity,
          shortDesc: w.shortDesc,
          longDesc: w.longDesc,
          groupInfo: w.groupInfo,
          createTime: w.createTime,
          updateTime: w.updateTime,
        )).toList();
        await _db.wordsDao.insertEntities(words);
      }

      // 2. 词书-单词关系
      if (res.dictWords != null && res.dictWords!.isNotEmpty) {
        final List<DictWord> dictWords = res.dictWords!.map((dw) => DictWord(
          dictId: dw.dictId.toString(),
          wordId: dw.wordId,
          seq: dw.seq,
          unit: dw.unit,
          createTime: dw.createTime,
          updateTime: dw.updateTime,
        )).toList();
        await _db.dictWordsDao.insertEntities(dictWords, false);
      }

      // 3. 释义项
      if (res.meaningItems != null && res.meaningItems!.isNotEmpty) {
        final List<MeaningItem> items = res.meaningItems!.map((m) => MeaningItem(
          id: m.id,
          wordId: m.wordId,
          dictId: m.dictId,
          ciXing: m.ciXing,
          meaning: m.meaning,
          popularity: m.popularity,
          ownerId: m.ownerId ?? Global.sysUserId,
          createTime: m.createTime,
          updateTime: m.updateTime,
        )).toList();
        await _db.meaningItemsDao.insertEntities(items);
      }

      // 4. 例句
      if (res.sentences != null && res.sentences!.isNotEmpty) {
        final List<Sentence> sentences = res.sentences!.map((s) => Sentence(
          id: s.id,
          english: s.english,
          chinese: s.chinese,
          englishDigest: s.englishDigest,
          theType: s.theType,
          handCount: s.handCount,
          footCount: s.footCount,
          authorId: s.authorId ?? Global.sysUserId,
          ownerId: s.ownerId ?? Global.sysUserId,
          meaningItemId: s.meaningItemId,
          wordMeaning: s.wordMeaning,
          createTime: s.createTime,
          updateTime: s.updateTime,
        )).toList();
        await _db.sentencesDao.insertEntities(sentences);
      }

      // 5. 同义词
      if (res.synonyms != null && res.synonyms!.isNotEmpty) {
        final List<Synonym> synonyms = res.synonyms!.map((s) => Synonym(
          meaningItemId: s.meaningItemId,
          wordId: s.wordId,
          spell: s.spell,
          createTime: s.createTime,
          updateTime: s.updateTime,
        )).toList();
        await _db.synonymsDao.insertEntities(synonyms);
      }

      // 6. 形近词
      if (res.similarWords != null && res.similarWords!.isNotEmpty) {
        final List<SimilarWord> sws = res.similarWords!.map((sw) => SimilarWord(
          wordId: sw.wordId,
          similarWordId: sw.similarWordId,
          similarWordSpell: sw.similarWordSpell,
          distance: sw.distance,
          createTime: sw.createTime,
          updateTime: sw.updateTime,
        )).toList();
        await _db.similarWordsDao.insertEntities(sws);
      }

      // 7. 图片
      if (res.images != null && res.images!.isNotEmpty) {
        final List<WordImage> images = res.images!.map((im) => WordImage(
          id: im.id,
          wordId: im.wordId,
          imageFile: im.imageFile,
          foot: im.foot,
          hand: im.hand,
          authorId: im.authorId ?? Global.sysUserId,
          ownerId: im.ownerId ?? Global.sysUserId,
          createTime: im.createTime,
          updateTime: im.updateTime,
        )).toList();
        await _db.wordImagesDao.insertEntities(images);
      }
    });
  }
}

/// 完整性检查结果
class IntegrityCheckResult {
  final List<String> errors = [];
  final List<IntegrityIssue> issues = [];

  void addError(String error) {
    errors.add(error);
  }

  void addIssue(String type, String description, String category, {String? stackTrace, String? logMessage}) {
    issues.add(IntegrityIssue(type, description, category, stackTrace: stackTrace, logMessage: logMessage));
  }

  bool hasIssue(String category) {
    return issues.any((issue) => issue.category == category);
  }

  bool get hasErrors => errors.isNotEmpty;
  bool get hasIssues => issues.isNotEmpty;
  bool get isHealthy => !hasErrors && !hasIssues;

  int get totalIssues => errors.length + issues.length;
}

/// 完整性修复结果
class IntegrityFixResult {
  final List<String> errors = [];
  final List<String> fixed = [];

  void addError(String error) {
    errors.add(error);
  }

  void addFixed(String fix) {
    fixed.add(fix);
  }

  bool get hasErrors => errors.isNotEmpty;
  bool get hasFixed => fixed.isNotEmpty;
}

/// 完整性问题
class IntegrityIssue {
  final String type;
  final String description;
  final String category;
  final String? stackTrace;
  final String? logMessage;

  IntegrityIssue(this.type, this.description, this.category, {this.stackTrace, this.logMessage});
}
