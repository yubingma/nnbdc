import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:drift/drift.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:nnbdc/util/app_clock.dart';

class LearningService {
  static const int newLearningWordLifeValue = 5;

  /// 准备今日学习单词
  static Future<Result<List<int>>> prepareTodayStudy(bool addNewWordsIfNotEnough) async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      final result = Result<List<int>>('ERROR', '用户未登录', false);
      result.data = [0, 0];
      return result;
    }

    try {
      final db = MyDatabase.instance;


      // 如果用户的最近学习日期不是今天，重置相关数据
      final today = DateUtils.pureDate(AppClock.now());
      bool isNewDay = user.lastLearningDate == null || !DateUtils.isSameDay(user.lastLearningDate!, today);
      if (isNewDay) {
        Global.logger.d('检测到新的学习日期，开始重置用户数据: userId=${user.id}');

        // 清空用户错词（新的一天开始，清空昨日错词）
        await db.userWrongWordsDao.clearUserWrongWords(user.id, true);
        Global.logger.d('已清空用户错词');

        // 直接通过数据库更新字段
        await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(UsersCompanion(
            lastLearningDate: Value(today),
            learnedDays: Value(user.learnedDays + 1),
            lastLearningPosition: const Value(-1),
            lastLearningMode: const Value(-1),
            learningFinished: const Value(false)));

        // 重新获取更新后的用户信息
        final updatedUser = await db.usersDao.getUserById(user.id);
        if (updatedUser != null) {
          // 清除缓存并重新加载
          Global.clearUserCache();
          await Global.loadUserFromDb();
        }

        Global.logger.d('用户数据重置完成');
      }

      // 尝试从数据库中读取今日学习单词
      List<LearningWord> todayWords = await getTodayLearningWordsFromDb(user.id);

      // 生成今日要学习的单词列表
      bool needAddNewWords = todayWords.isEmpty || (todayWords.length < (user.wordsPerDay) && addNewWordsIfNotEnough);
      bool wordExhausted = false;
      if (needAddNewWords) {
        todayWords = await genTodayWords(user.id, AppClock.now(), todayWords);
        wordExhausted = todayWords.length < (user.wordsPerDay); // 学习中词书单词是否已经耗尽
      }


      // 重新获取今日学习单词（可能有部分被删除）
      todayWords = await getTodayLearningWordsFromDb(user.id);

      // 计算今日新词数
      int newWordCount = 0;
      for (var word in todayWords) {
        if (word.isTodayNewWord) {
          newWordCount++;
        }
      }

      final result = Result<List<int>>(wordExhausted ? 'NNBDC-0012' : '200', wordExhausted ? '未取到足够单词' : '成功', !wordExhausted);
      result.data = [newWordCount, todayWords.length - newWordCount];
      return result;
    } catch (e, stackTrace) {
      Global.logger.e('准备学习时出错: $e', stackTrace: stackTrace);
      ToastUtil.error('准备学习时出错: $e');
      final result = Result<List<int>>('ERROR', '准备学习时出错: $e', false);
      result.data = [0, 0];
      return result;
    }
  }


  /// 从数据库中获取已生成的用户今天要学习的单词列表
  static Future<List<LearningWord>> getTodayLearningWordsFromDb(String userId) async {
    final db = MyDatabase.instance;
    final now = AppClock.now();

    // 获取今天开始和结束的时间
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // 查询今天的学习单词
    try {
      final query = db.select(db.learningWords)
        ..where((lw) => lw.userId.equals(userId) & lw.lastLearningDate.isBiggerOrEqualValue(today) & lw.lastLearningDate.isSmallerThanValue(tomorrow))
        ..orderBy([(lw) => OrderingTerm(expression: lw.learningOrder)]);

      // 使用get()而不是getSingleOrNull()，因为我们需要所有匹配的记录
      return await query.get();
    } catch (e) {
      Global.logger.e('获取今日学习单词失败: $e');
      return [];
    }
  }

  /// 产生今天要学习的单词列表，并把该列表更新到数据库
  static Future<List<LearningWord>> genTodayWords(String userId, DateTime now, List<LearningWord> todayLearningWords) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);

    if (user == null) {
      throw Exception('用户不存在');
    }

    // 获取所有正在学习中的单词(作为备选单词列表)
    final allLearningWords = await (db.select(db.learningWords)..where((lw) => lw.userId.equals(userId) & lw.lifeValue.isBiggerThanValue(0))).get();

    // 从备选单词列表中删除那些已经选为今天学习的单词
    final List<LearningWord> candidateWords = List.from(allLearningWords);
    for (var todayWord in todayLearningWords) {
      candidateWords.removeWhere((word) => word.userId == todayWord.userId && word.wordId == todayWord.wordId);
    }

    // 通过查询最新加入到学习列表的单词，得知今天是第几天添加单词
    LearningWord? latestWord;
    for (var word in candidateWords) {
      if (latestWord == null || word.addTime.isAfter(latestWord.addTime)) {
        latestWord = word;
      }
    }

    int todayDayNumber = 1;
    if (latestWord != null) {
      if (DateUtils.isSameDay(latestWord.addTime, now)) {
        todayDayNumber = latestWord.addDay;
      } else {
        todayDayNumber = latestWord.addDay + 1;
      }
    }

    // 如果需要，添加新单词到learning words（按照后端逻辑传递allLearningWords）
    final newLearningWords = await addNewLearningWords(userId, allLearningWords, todayDayNumber);
    candidateWords.addAll(newLearningWords);

    // 取{ 0, 1, 3, 6, 14 }天之前加入的单词
    final fetchDays = [0, 1, 3, 6, 14];
    for (int day in fetchDays) {
      final learningWordsOfADay = getLearningWordsAddedAtDay(todayDayNumber - day, candidateWords);

      for (var word in learningWordsOfADay) {
        if (!todayLearningWords.any((w) => w.userId == word.userId && w.wordId == word.wordId)) {
          todayLearningWords.add(word);
          candidateWords.removeWhere((w) => w.userId == word.userId && w.wordId == word.wordId);

          // 按照后端逻辑：达到数量就立即返回
          if (todayLearningWords.length >= user.wordsPerDay) {
            await updateTodayLearningWords(todayLearningWords, now);
            return todayLearningWords;
          }
        }
      }
    }

    // 如果没有取到足够单词，则从最早的单词往前取
    while (todayLearningWords.length < user.wordsPerDay) {
      final oldestWord = getOldestLearningWord(candidateWords);

      // 取不到更多单词了，单词书中单词耗尽
      if (oldestWord == null) {
        break;
      }

      if (!todayLearningWords.any((w) => w.userId == oldestWord.userId && w.wordId == oldestWord.wordId)) {
        todayLearningWords.add(oldestWord);
        candidateWords.removeWhere((w) => w.userId == oldestWord.userId && w.wordId == oldestWord.wordId);
      }
    }

    // 将今日的学习单词更新到数据库
    await updateTodayLearningWords(todayLearningWords, now);

    return todayLearningWords;
  }

  /// 获取指定的天数以前的那一天加入的learning words
  static List<LearningWord> getLearningWordsAddedAtDay(int addDay, List<LearningWord> allLearningWords) {
    List<LearningWord> learningWords = [];

    // 获取该天添加的所有单词
    for (var learningWord in allLearningWords) {
      if (learningWord.addDay == addDay) {
        learningWords.add(learningWord);
      }
    }

    // 对该天的单词进行排序，生命值大的排在前面，以便被优先选为本日学习单词
    learningWords.sort((a, b) => b.lifeValue.compareTo(a.lifeValue));

    return learningWords;
  }

  /// 获取最早加入的那些单词
  static LearningWord? getOldestLearningWord(List<LearningWord> allLearningWords) {
    if (allLearningWords.isEmpty) {
      return null;
    }

    LearningWord? oldestWord;
    for (var learningWord in allLearningWords) {
      if (oldestWord == null ||
          (DateUtils.isSameDay(learningWord.addTime, oldestWord.addTime) && learningWord.lifeValue > oldestWord.lifeValue) ||
          (learningWord.addTime.isBefore(oldestWord.addTime) && !DateUtils.isSameDay(learningWord.addTime, oldestWord.addTime))) {
        oldestWord = learningWord;
      }
    }

    return oldestWord;
  }

  /// 将今日的学习单词更新到数据库
  static Future<void> updateTodayLearningWords(List<LearningWord> todayLearningWords, DateTime now) async {
    final db = MyDatabase.instance;

    // 按生命值从大到小排序
    todayLearningWords.sort((a, b) => b.lifeValue.compareTo(a.lifeValue));

    int learningOrder = 1;
    int updatedCount = 0;

    try {
      for (var learningWord in todayLearningWords) {
        // 直接修改现有对象，与后端逻辑一致
        if (learningWord.lastLearningDate == null || !DateUtils.isSameDay(now, learningWord.lastLearningDate!)) {
          // 如果lastLearningDate为null或不是同一天，更新lastLearningDate和isTodayNewWord
          learningWord = learningWord.copyWith(
            lastLearningDate: Value(now),
            isTodayNewWord: learningWord.learnedTimes == 0,
          );
        }
        // 更新学习顺序
        learningWord = learningWord.copyWith(learningOrder: learningOrder);

        learningOrder++;
        await db.learningWordsDao.saveEntity(learningWord, true);
        updatedCount++;
      }

      Global.logger.d('今日学习单词更新完成，共更新 $updatedCount 个单词');

      // 检查数据库日志是否正确记录
      if (todayLearningWords.isNotEmpty) {
        String userId = todayLearningWords.first.userId;
        List<UserDbLog> logs = await db.userDbLogsDao.getUserDbLogs(userId);
        int learningWordsLogCount = logs.where((log) => log.tblName == 'learningWords').length;
        Global.logger.d('更新后的学习单词相关日志数量: $learningWordsLogCount');
      }
    } catch (e, stackTrace) {
      Global.logger.d('更新今日学习单词时出错: $e');
      Global.logger.d('异常堆栈: $stackTrace');
      rethrow;
    }
  }

  /// 添加新单词到正在学习的单词列表
  static Future<List<LearningWord>> addNewLearningWords(String userId, List<LearningWord> currentLearningWords, int todayDayNumber) async {
    final db = MyDatabase.instance;
    final user = await db.usersDao.getUserById(userId);

    if (user == null) {
      throw Exception('用户不存在');
    }

    // 计算目前所有的learning words的总生命值
    int currentLifeValue = 0;
    for (var word in currentLearningWords) {
      currentLifeValue += word.lifeValue;
    }

    // 计算期望的总生命值
    final expectedTotalLifeValue = user.wordsPerDay * 29 ~/ 5;

    // 计算需要添加的新单词数量（以达到期望的总生命值）
    int newWordCount = (expectedTotalLifeValue - currentLifeValue + 0.0).ceil() ~/ newLearningWordLifeValue;

    // 按照后端逻辑：限制不超过每日单词数
    int wordsPerDay = user.wordsPerDay;
    newWordCount = newWordCount <= wordsPerDay ? newWordCount : wordsPerDay;

    // 从词书取新词
    List<LearningWord> newLearningWords = await fetchNewWordsToLearn(userId, todayDayNumber, newWordCount);

    // 更新词书的当前位置
    await updateCurrentPositionForUserDicts(userId);

    return newLearningWords;
  }

  /// 从词书取新词（支持优先级和已掌握过滤）
  static Future<List<LearningWord>> fetchNewWordsToLearn(String userId, int todayDayNumber, int countToFetch) async {
    if (countToFetch <= 0) {
      return [];
    }

    final db = MyDatabase.instance;

    // 获取用户选择的词书，按优先级排序（优先取词的书排在前面）
    final learningDicts = await (db.select(db.learningDicts)
          ..where((ld) => ld.userId.equals(userId))
          ..orderBy([(ld) => OrderingTerm.desc(ld.isPrivileged), (ld) => OrderingTerm.asc(ld.createTime)]))
        .get();

    if (learningDicts.isEmpty) {
      return [];
    }

    // 获取用户已掌握的单词
    final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(userId);
    final masteredWordIds = masteredWords.map((w) => w.wordId).toList();

    // 获取用户已学习的单词ID
    final existingLearningWords = await (db.select(db.learningWords)..where((lw) => lw.userId.equals(userId))).get();
    final existingWordIds = existingLearningWords.map((w) => w.wordId).toSet();

    // 按优先级顺序处理词书
    List<LearningWord> learningWords = [];

    for (var learningDict in learningDicts) {
      if (learningWords.length >= countToFetch) break;

      // 获取词书信息
      final dict = await db.dictsDao.findById(learningDict.dictId);
      if (dict == null) continue;

      // 查询符合条件的单词
      final dictWords = await (db.select(db.dictWords)
            ..where((dw) => dw.dictId.equals(learningDict.dictId) & dw.seq.isBiggerThanValue(learningDict.currentWordSeq ?? 0))
            ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
          .get();

      for (var dictWord in dictWords) {
        if (learningWords.length >= countToFetch) break;

        // 判断该单词是否已经在学习中
        if (existingWordIds.contains(dictWord.wordId)) continue;

        // 判断该单词是否已经掌握（根据fetchMastered设置决定）
        if (!learningDict.fetchMastered && masteredWordIds.contains(dictWord.wordId)) continue;

        // 创建新的LearningWord
        final now = AppClock.now();
        final learningWord = LearningWord(
            userId: userId,
            wordId: dictWord.wordId,
            addTime: now,
            addDay: todayDayNumber,
            lifeValue: newLearningWordLifeValue,
            lastLearningDate: null, // 与后端逻辑一致，初始化为null
            learningOrder: 0,
            isTodayNewWord: false,
            learnedTimes: 0,
            createTime: now,
            updateTime: now);

        // 保存到数据库
        await db.learningWordsDao.saveEntity(learningWord, true);
        learningWords.add(learningWord);
      }
    }

    return learningWords;
  }

  /// 更新用户所有学习中词书的当前已取词位置, 让用户能够观察到词书的取词进度
  static Future<void> updateCurrentPositionForUserDicts(String userId) async {
    final db = MyDatabase.instance;

    // 获取用户选择的词书
    final learningDicts = await (db.select(db.learningDicts)..where((ld) => ld.userId.equals(userId))).get();

    // 获取用户已掌握的单词
    final masteredWords = await db.masteredWordsDao.getMasteredWordsForUser(userId);
    final masteredWordIds = masteredWords.map((w) => w.wordId).toSet();

    // 获取学习中的单词
    final learningWords = await (db.select(db.learningWords)..where((lw) => lw.userId.equals(userId))).get();
    final learningWordIds = learningWords.map((w) => w.wordId).toSet();

    for (var learningDict in learningDicts) {
      // 获取词书信息
      final dict = await db.dictsDao.findById(learningDict.dictId);
      if (dict == null) continue;

      // 获取该词书中的单词，按序号排序
      final List<DictWord> dictWords = await (db.select(db.dictWords)
            ..where((dw) => dw.dictId.equals(learningDict.dictId))
            ..orderBy([(dw) => OrderingTerm.asc(dw.seq)]))
          .get();

      if (dictWords.isEmpty) continue;

      // 找出下一个要取词的位置
      int nextPosition = learningDict.currentWordSeq ?? 0;

      // 从当前位置开始，找到下一个可以取词的位置
      for (int i = 0; i < dictWords.length; i++) {
        var dictWord = dictWords[i];
        // 跳过已经处理过的单词
        if (dictWord.seq <= nextPosition) continue;

        // 检查单词是否已经在学习中
        bool isLearned = learningWordIds.contains(dictWord.wordId);

        // 检查单词是否已经掌握（根据fetchMastered设置决定）
        bool isMastered = masteredWordIds.contains(dictWord.wordId);
        bool shouldSkipMastered = !learningDict.fetchMastered && isMastered;

        // 如果单词可以正常取词（不需要跳过），则更新为上一个位置, 并退出循环
        if (!isLearned && !shouldSkipMastered) {
          nextPosition = dictWord.seq - 1;
          break;
        }

        // 如果单词需要跳过，继续检查下一个
        nextPosition = dictWord.seq + 1;
      }

      // 更新词书的当前已取词位置
      nextPosition = nextPosition >= dictWords.length ? dictWords.length - 1 : nextPosition;
      final updatedLearningDict = learningDict.copyWith(
          currentWordId: Value(dictWords[nextPosition].wordId), currentWordSeq: Value(nextPosition), updateTime: Value(AppClock.now()));

      await db.learningDictsDao.saveEntity(updatedLearningDict, true);
    }
  }
}
