import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/util/network_util.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

/// 进度回调函数类型
typedef ProgressCallback = void Function(int step, String message, {IntegrityCheckResult? result});

/// 数据完整性检查器
class DataIntegrityChecker {
  static final DataIntegrityChecker _instance = DataIntegrityChecker._internal();
  factory DataIntegrityChecker() => _instance;
  DataIntegrityChecker._internal();

  final MyDatabase _db = MyDatabase.instance;

  /// 执行完整的数据完整性检查
  Future<IntegrityCheckResult> performFullCheck() async {
    final result = IntegrityCheckResult();
    
    try {
      // 1. 检查词典单词序号连续性
      await _checkDictWordSequences(result);
      
      // 2. 检查词典单词数量一致性
      await _checkDictWordCounts(result);
      
      // 3. 检查学习进度合理性
      await _checkLearningProgress(result);
      
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
      
      // 3. 检查用户学习进度合理性
      onProgress?.call(3, '检查学习进度合理性...');
      await Future.delayed(const Duration(milliseconds: 100)); // 给UI一点时间显示
      final timer3 = Stopwatch()..start();
      await _checkUserLearningProgress(result, userId);
      timer3.stop();
      Global.logger.d('✓ 检查学习进度合理性: ${timer3.elapsedMilliseconds}ms');
      onProgress?.call(3, '检查学习进度合理性...', result: result);
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
      
      // 6. 检查网络连接
      onProgress?.call(6, '检查网络连接...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer6 = Stopwatch()..start();
      await _checkNetworkConnectivity(result);
      timer6.stop();
      Global.logger.d('✓ 检查网络连接: ${timer6.elapsedMilliseconds}ms');
      onProgress?.call(6, '检查网络连接...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));
      
      // 7. 检查后端服务器连通性
      onProgress?.call(7, '检查后端服务器连通性...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer7 = Stopwatch()..start();
      await _checkBackendServer(result);
      timer7.stop();
      Global.logger.d('✓ 检查后端服务器: ${timer7.elapsedMilliseconds}ms');
      onProgress?.call(7, '检查后端服务器连通性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));
      
      // 8. 检查游戏服务器连通性
      onProgress?.call(8, '检查游戏服务器连通性...');
      await Future.delayed(const Duration(milliseconds: 100));
      final timer8 = Stopwatch()..start();
      await _checkGameServer(result);
      timer8.stop();
      Global.logger.d('✓ 检查游戏服务器: ${timer8.elapsedMilliseconds}ms');
      onProgress?.call(8, '检查游戏服务器连通性...', result: result);
      await Future.delayed(const Duration(milliseconds: 200));
      
      stopwatch.stop();
      Global.logger.d('✓ 健康检查完成，总耗时: ${stopwatch.elapsedMilliseconds}ms');
      onProgress?.call(8, '检查完成！', result: result);
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
      final userDicts = await (_db.dictsDao.select(_db.dicts)
        ..where((d) => d.ownerId.equals(userId))).get();
      
      // 添加通用词典
      final commonDict = await _db.dictsDao.findById(Global.commonDictId);
      if (commonDict != null) {
        userDicts.add(commonDict);
      }
      
      for (final dict in userDicts) {
        final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
          ..where((dw) => dw.dictId.equals(dict.id))
          ..orderBy([(dw) => OrderingTerm.asc(dw.seq)])).get();
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
    } catch (e) {
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
          ..orderBy([(dw) => OrderingTerm.asc(dw.seq)])).get();
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
    } catch (e) {
      result.addError('检查词典单词序号时出错: $e');
    }
  }

  /// 检查用户词典单词数量一致性
  Future<void> _checkUserDictWordCounts(IntegrityCheckResult result, String userId) async {
    try {
      // 获取用户拥有的词典
      final userDicts = await (_db.dictsDao.select(_db.dicts)
        ..where((d) => d.ownerId.equals(userId))).get();
      
      // 添加通用词典
      final commonDict = await _db.dictsDao.findById(Global.commonDictId);
      if (commonDict != null) {
        userDicts.add(commonDict);
      }
      
      for (final dict in userDicts) {
        final actualCount = await _db.dictWordsDao.getDictWordCount(dict.id);
        if (dict.wordCount != actualCount) {
          result.addIssue('单词数量不匹配', 
            '词典 "${dict.name}" 记录数量: ${dict.wordCount}, 实际数量: $actualCount', 
            'dict_word_count');
        }
      }
    } catch (e) {
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
          result.addIssue('单词数量不匹配', 
            '词典 "${dict.name}" 记录数量: ${dict.wordCount}, 实际数量: $actualCount', 
            'dict_word_count');
        }
      }
    } catch (e) {
      result.addError('检查词典单词数量时出错: $e');
    }
  }

  /// 检查用户学习进度合理性
  Future<void> _checkUserLearningProgress(IntegrityCheckResult result, String userId) async {
    try {
      // 获取用户的学习词典
      final userLearningDicts = await (_db.learningDictsDao.select(_db.learningDicts)
        ..where((ld) => ld.userId.equals(userId))).get();
      
      for (final learningDict in userLearningDicts) {
        final dict = await _db.dictsDao.findById(learningDict.dictId);
        if (dict == null) continue;
        
        if (learningDict.currentWordSeq != null && learningDict.currentWordSeq! > dict.wordCount) {
          result.addIssue('学习进度异常', 
            '用户学习进度(${learningDict.currentWordSeq})超过词典单词数(${dict.wordCount})', 
            'learning_progress');
        }
      }
    } catch (e) {
      result.addError('检查用户学习进度时出错: $e');
    }
  }

  /// 检查学习进度合理性
  Future<void> _checkLearningProgress(IntegrityCheckResult result) async {
    try {
      final allLearningDicts = await _db.learningDictsDao.select(_db.learningDicts).get();
      
      for (final learningDict in allLearningDicts) {
        final dict = await _db.dictsDao.findById(learningDict.dictId);
        if (dict == null) continue;
        
        if (learningDict.currentWordSeq != null && learningDict.currentWordSeq! > dict.wordCount) {
          result.addIssue('学习进度异常', 
            '用户学习进度(${learningDict.currentWordSeq})超过词典单词数(${dict.wordCount})', 
            'learning_progress');
        }
      }
    } catch (e) {
      result.addError('检查学习进度时出错: $e');
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
        result.addIssue('版本号异常', 
          '用户有 ${invalidLogs.length} 条版本号异常的日志', 
          'user_db_version');
      }
    } catch (e) {
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
          result.addIssue('版本号异常', 
            '用户 ${user.userName} 有 ${invalidLogs.length} 条版本号异常的日志', 
            'user_db_version');
        }
      }
    } catch (e) {
      result.addError('检查用户数据库版本时出错: $e');
    }
  }

  /// 检查通用词典完整性
  Future<void> _checkCommonDictIntegrity(IntegrityCheckResult result) async {
    try {
      // 检查通用词典中的单词是否有释义项
      final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
        ..where((dw) => dw.dictId.equals(Global.commonDictId))).get();
      
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
        final batchMeanings = await (_db.meaningItemsDao.select(_db.meaningItems)
          ..where((mi) => mi.wordId.isIn(batch) & mi.dictId.equals(Global.commonDictId))).get();
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
        result.addIssue('通用词典不完整', 
          '单词 "$wordId" 缺少释义项', 
          'common_dict_integrity');
      }
      
      // 批量查询所有释义项的例句
      final meaningIds = allMeanings.map((m) => m.id).toList();
      Global.logger.d('查询 ${meaningIds.length} 个释义项的例句（分批查询）...');
      
      final allSentences = <Sentence>[];
      for (int i = 0; i < meaningIds.length; i += batchSize) {
        final batch = meaningIds.skip(i).take(batchSize).toList();
        final batchSentences = await (_db.sentencesDao.select(_db.sentences)
          ..where((s) => s.meaningItemId.isIn(batch))).get();
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
          result.addIssue('通用词典不完整', 
            '释义项 "${meaning.id}" 缺少例句', 
            'common_dict_integrity');
        }
      }
      
      Global.logger.d('通用词典完整性检查完成，检查了 ${wordsList.length} 个单词，发现 ${wordsWithoutMeanings.length} 个单词缺少释义项，$meaningsWithoutSentences 个释义项缺少例句');
    } catch (e, stackTrace) {
      Global.logger.e('检查通用词典完整性时出错: $e');
      Global.logger.e('错误堆栈: $stackTrace');
      result.addError('检查通用词典完整性时出错: $e');
    }
  }

  /// 自动修复发现的问题
  Future<IntegrityFixResult> autoFix(IntegrityCheckResult checkResult) async {
    final fixResult = IntegrityFixResult();
    
    try {
      // 修复序号不连续问题
      if (checkResult.hasIssue('dict_word_sequence')) {
        await _fixDictWordSequences(fixResult);
      }
      
      // 修复单词数量不匹配问题
      if (checkResult.hasIssue('dict_word_count')) {
        await _fixDictWordCounts(fixResult);
      }
      
      // 修复学习进度异常问题
      if (checkResult.hasIssue('learning_progress')) {
        await _fixLearningProgress(fixResult);
      }
      
      // 修复版本号异常问题
      if (checkResult.hasIssue('user_db_version')) {
        await _fixUserDbVersions(fixResult);
      }
      
    } catch (e) {
      fixResult.addError('自动修复过程中出现错误: $e');
    }
    
    return fixResult;
  }

  /// 修复词典单词序号
  Future<void> _fixDictWordSequences(IntegrityFixResult fixResult) async {
    try {
      final allDicts = await _db.dictsDao.select(_db.dicts).get();
      
      for (final dict in allDicts) {
        final wordsList = await (_db.dictWordsDao.select(_db.dictWords)
          ..where((dw) => dw.dictId.equals(dict.id))
          ..orderBy([(dw) => OrderingTerm.asc(dw.seq)])).get();
        if (wordsList.isEmpty) continue;
        
        // 重新分配序号
        for (int i = 0; i < wordsList.length; i++) {
          if (wordsList[i].seq != i + 1) {
            // 使用现有的重新排序方法
            await _db.dictWordsDao.validateRawWordDictOrder(dict.id);
            fixResult.addFixed('修复词典 "${dict.name}" 单词序号');
            break;
          }
        }
      }
    } catch (e) {
      fixResult.addError('修复词典单词序号时出错: $e');
    }
  }

  /// 修复词典单词数量
  Future<void> _fixDictWordCounts(IntegrityFixResult fixResult) async {
    try {
      final allDicts = await _db.dictsDao.select(_db.dicts).get();
      
      for (final dict in allDicts) {
        final actualCount = await _db.dictWordsDao.getDictWordCount(dict.id);
        if (dict.wordCount != actualCount) {
          await _db.dictsDao.updateWordCount(dict.id, true);
          fixResult.addFixed('修复词典 "${dict.name}" 单词数量: $actualCount');
        }
      }
    } catch (e) {
      fixResult.addError('修复词典单词数量时出错: $e');
    }
  }

  /// 修复学习进度
  Future<void> _fixLearningProgress(IntegrityFixResult fixResult) async {
    try {
      final allLearningDicts = await _db.learningDictsDao.select(_db.learningDicts).get();
      
      for (final learningDict in allLearningDicts) {
        final dict = await _db.dictsDao.findById(learningDict.dictId);
        if (dict == null) continue;
        
        if (learningDict.currentWordSeq != null && learningDict.currentWordSeq! > dict.wordCount) {
          // 使用现有的更新方法
          await _db.learningDictsDao.saveEntity(
            learningDict.copyWith(currentWordSeq: Value(dict.wordCount)), 
            true
          );
          fixResult.addFixed('修复用户学习进度: ${dict.wordCount}');
        }
      }
    } catch (e) {
      fixResult.addError('修复学习进度时出错: $e');
    }
  }

  /// 修复用户数据库版本
  Future<void> _fixUserDbVersions(IntegrityFixResult fixResult) async {
    try {
      final allUsers = await _db.usersDao.allUsers;
      
      for (final user in allUsers) {
        final userVersion = await _db.userDbVersionsDao.getUserDbVersionByUserId(user.id);
        if (userVersion == null) continue;
        
        // 删除版本号大于当前版本的日志
        final allLogs = await _db.userDbLogsDao.getUserDbLogs(user.id);
        final invalidLogs = allLogs.where((log) => log.version > userVersion.version).toList();
        
        if (invalidLogs.isNotEmpty) {
          // 使用现有的删除方法
          await _db.userDbLogsDao.deleteUserDbLogs(user.id);
          fixResult.addFixed('删除用户 ${user.userName} 的 ${invalidLogs.length} 条异常日志');
        }
      }
    } catch (e) {
      fixResult.addError('修复用户数据库版本时出错: $e');
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
    } catch (e) {
      Global.logger.e('检查网络连接时出错: $e');
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
    } catch (e) {
      Global.logger.e('检查后端服务器时出错: $e');
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
    } catch (e) {
      Global.logger.e('检查游戏服务器时出错: $e');
      result.addIssue('游戏服务器检查失败', '检查游戏服务器连接时出错: ${e.toString().substring(0, e.toString().length > 50 ? 50 : e.toString().length)}', 'game_server');
      // 确保断开连接
      try {
        SocketIoClient.instance.disconnect();
      } catch (e, stackTrace) {
        // 断开连接失败不影响检查结果，但需要记录
        Global.logger.w('断开Socket连接失败', error: e, stackTrace: stackTrace);
      }
    }
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
