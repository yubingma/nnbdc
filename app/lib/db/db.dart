import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:nnbdc/db/dao.dart';
import 'package:nnbdc/db/table.dart';
import 'package:nnbdc/db/shared.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';

part 'db.g.dart';

@DriftDatabase(tables: [
  Users,
  LocalParams,
  Levels,
  VotedSentences,
  VotedChineses,
  VotedWordImages,
  LearningDicts,
  Dicts,
  Words,
  UserDbLogs,
  UserDbVersions,
  DictWords,
  WordImages,
  VerbTenses,
  Synonyms,
  SimilarWords,
  Cigens,
  CigenWordLinks,
  MeaningItems,
  Sentences,
  LearningWords,
  BookMarks,
  DictGroups,
  GroupAndDictLinks,
  UserStudySteps,
  Dakas,
  UserOpers,
  MasteredWords,
  UserCowDungLogs,
  UserWrongWords,
  SysDbVersion,
  WordShortDescChineses,
], daos: [
  UsersDao,
  LocalParamsDao,
  VotedSentencesDao,
  VotedChinesesDao,
  VotedWordImagesDao,
  LearningDictsDao,
  DictsDao,
  WordsDao,
  UserDbLogsDao,
  UserDbVersionsDao,
  DictWordsDao,
  WordImagesDao,
  VerbTensesDao,
  SynonymsDao,
  SimilarWordsDao,
  CigensDao,
  CigenWordLinksDao,
  MeaningItemsDao,
  SentencesDao,
  LearningWordsDao,
  LevelsDao,
  DictGroupsDao,
  GroupAndDictLinksDao,
  UserStudyStepsDao,
  DakasDao,
  UserOpersDao,
  MasteredWordsDao,
  BookmarksDao,
  UserCowDungLogsDao,
  UserWrongWordsDao,
  SysDbVersionDao,
  WordShortDescChinesesDao,
])
class MyDatabase extends _$MyDatabase {
  MyDatabase(super.e);

  static MyDatabase? _instance;

  static MyDatabase get instance {
    _instance ??= constructDb();
    return _instance!;
  }

  static void closeDatabase() {
    if (_instance != null) {
      _instance!.close();
      _instance = null;
    }
  }

  // we tell the database where to store the data with this constructor
  //MyDatabase() : super(_openConnection());

  // you should bump this number whenever you change or add a table definition. Migrations
  // are covered later in this readme.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // 创建表、索引和初始化数据
        await _initializeDatabaseSchema(m);
      },
      onUpgrade: (Migrator m, int from, int to) async {
        try {
          // 从版本 1 升级到版本 2：更新 studyStep 字段值
          if (from < 2) {
            await _migrateStudyStepFromV1ToV2();
          }
          // 从版本 2 升级到版本 3：修复 dicts 表中 popularityLimit 的 0 值
          if (from < 3) {
            await _migratePopularityLimitFromV2ToV3();
          }
        } catch (e, stackTrace) {
          // 升级失败，记录错误日志
          Global.logger.e('❌ 数据库升级失败，将删除所有表并重建: $e', error: e, stackTrace: stackTrace);

          // 给用户提示
          _showDatabaseRebuildNotification();

          // 删除所有表并重建
          await _recreateDatabaseOnUpgradeFailure(m);

          // 重建完成后提示用户
          _showDatabaseRebuildSuccessNotification();
        }
      },
      beforeOpen: (details) async {},
    );
  }

  /// 从版本 1 升级到版本 2 的迁移逻辑
  /// 1. 首先执行字段重命名（统一命名规范）
  /// 2. 更新 studyStep 字段：'Word' -> 'En2Ch', 'Meaning' -> 'Ch2En'
  Future<void> _migrateStudyStepFromV1ToV2() async {
    await transaction(() async {
      // ========== 第二步：更新 studyStep 字段值 ==========
      // 2.1 更新 user_study_steps 表中的 studyStep 字段
      await customStatement('''
        UPDATE user_study_steps 
        SET study_step = 'En2Ch' 
        WHERE study_step = 'Word'
      ''');

      await customStatement('''
        UPDATE user_study_steps 
        SET study_step = 'Ch2En' 
        WHERE study_step = 'Meaning'
      ''');

      // 2.2 更新 user_db_logs 表中的 JSON 记录
      // 获取所有需要更新的日志记录
      // 注意：这里使用 Drift 的字段名 tblName
      final logsToUpdate = await (select(userDbLogs)..where((log) => log.tblName.equals('userStudySteps'))).get();

      for (final log in logsToUpdate) {
        // 解析 JSON
        final recordJson = jsonDecode(log.record) as Map<String, dynamic>;

        // 检查并更新 studyStep 字段
        if (recordJson.containsKey('studyStep')) {
          final studyStep = recordJson['studyStep'] as String;
          if (studyStep == 'Word') {
            recordJson['studyStep'] = 'En2Ch';
          } else if (studyStep == 'Meaning') {
            recordJson['studyStep'] = 'Ch2En';
          } else {
            // 已经是新值，跳过
            continue;
          }

          // 更新记录
          await (update(userDbLogs)..where((l) => l.id.equals(log.id))).write(UserDbLogsCompanion(
            record: Value(jsonEncode(recordJson)),
          ));
        }
      }
    });
  }

  /// 从版本 2 升级到版本 3 的迁移逻辑
  /// 修复 dicts 表中 popularityLimit 字段的 0 值，将其修正为 null
  Future<void> _migratePopularityLimitFromV2ToV3() async {
    await transaction(() async {
      // 将 popularity_limit 为 0 的记录更新为 null
      // 注意：SQLite 中需要使用 CASE 语句或者直接 SET popularity_limit = NULL
      await customStatement('''
        UPDATE dicts 
        SET popularity_limit = 5 
        WHERE popularity_limit = 0
      ''');

      // 同时需要更新 user_db_logs 表中 dicts 相关的 JSON 记录
      // 获取所有需要更新的日志记录
      final logsToUpdate = await (select(userDbLogs)..where((log) => log.tblName.equals('dicts'))).get();

      for (final log in logsToUpdate) {
        // 解析 JSON
        final recordJson = jsonDecode(log.record) as Map<String, dynamic>;

        // 检查并更新 popularityLimit 字段
        if (recordJson.containsKey('popularityLimit')) {
          final popularityLimit = recordJson['popularityLimit'];
          // 如果值为 0，将其设置为 null
          if (popularityLimit == 0) {
            recordJson['popularityLimit'] = 5;

            // 更新记录
            await (update(userDbLogs)..where((l) => l.id.equals(log.id))).write(UserDbLogsCompanion(
              record: Value(jsonEncode(recordJson)),
            ));
          }
        }
      }
    });
  }

  /// 初始化数据库架构（创建表、索引和基础数据）
  ///
  /// 此方法会：
  /// 1. 创建所有表
  /// 2. 创建性能优化索引
  /// 3. 初始化基础数据
  Future<void> _initializeDatabaseSchema(Migrator m) async {
    // 1. 创建系统所有表
    await m.createAll();
    Global.logger.i('✅ 创建所有表完成');

    // 2. 创建性能优化索引
    await _createPerformanceIndexes();
    Global.logger.i('✅ 创建性能优化索引完成');

    // 3. 初始化基础数据
    await batch((b) {
      b.insertAll(localParams, [
        LocalParamsCompanion.insert(name: 'isDarkMode', value: 'false'),
      ]);
    });
    Global.logger.i('✅ 初始化基础数据完成');
  }

  /// 创建性能优化索引的共用方法
  /// 注意：Drift会自动将驼峰命名转换为下划线命名
  Future<void> _createPerformanceIndexes() async {
    // 为learning_words表添加复合索引以优化常见查询
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_user_life 
      ON learning_words (user_id, life_value)
    ''');

    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_user_learning_date 
      ON learning_words (user_id, last_learning_date)
    ''');

    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_user_today_new 
      ON learning_words (user_id, is_today_new_word, last_learning_date)
    ''');

    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_add_time_life 
      ON learning_words (add_time, life_value, word_id)
    ''');

    // 为meaning_items表添加索引以优化释义查询
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_meaning_items_word_dict 
      ON meaning_items (word_id, dict_id)
    ''');

    // 为dict_words表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_dict_words_dict_seq 
      ON dict_words (dict_id, seq)
    ''');

    // 为learning_dicts表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_learning_dicts_user 
      ON learning_dicts (user_id)
    ''');

    // 为mastered_words表添加索引（现在统一使用下划线格式）
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_mastered_words_user 
      ON mastered_words (user_id)
    ''');

    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_mastered_words_user_time 
      ON mastered_words (user_id, master_at_time)
    ''');

    // 为sentences表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_sentences_meaning_item 
      ON sentences (meaning_item_id)
    ''');

    // UserStageWords table has been removed

    // 为words表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_words_spell 
      ON words (spell)
    ''');
  }

  /// 清空本地数据（彻底清空，等同于重新安装）
  ///
  /// 将会清空数据库中所有表的数据，包括登录信息与本地设置。
  /// 注意：调用后应用将回到近似初始安装状态。
  Future<void> wipeLocalData() async {
    // 直接复用全清逻辑，保持与“重新安装”效果一致
    await wipeAllTables();
  }

  /// 清空数据库中所有表的数据（包括用户与本地设置）
  /// 使用后应用将回到近似初始安装状态
  Future<void> wipeAllTables() async {
    await transaction(() async {
      await customStatement('PRAGMA foreign_keys = OFF');

      // 先清理强依赖子表（按依赖层级从深到浅）
      await delete(votedSentences).go(); // 依赖 users, sentences
      await delete(votedChineses).go(); // 依赖 users, wordShortDescChineses
      await delete(votedWordImages).go(); // 依赖 users, wordImages
      await delete(synonyms).go(); // 依赖 meaningItems, words
      await delete(sentences).go(); // 依赖 meaningItems
      await delete(meaningItems).go(); // 依赖 words, dicts(可选)
      await delete(dictWords).go(); // 依赖 dicts, words
      await delete(wordImages).go(); // 依赖 words
      await delete(verbTenses).go(); // 依赖 words
      await delete(similarWords).go(); // 依赖 words
      await delete(cigenWordLinks).go(); // 依赖 cigens, words
      await delete(cigens).go();
      await delete(wordShortDescChineses).go(); // 依赖 words

      await delete(learningWords).go();
      await delete(masteredWords).go();
      await delete(userWrongWords).go();
      await delete(bookMarks).go();
      await delete(userStudySteps).go();
      await delete(dakas).go();
      await delete(userOpers).go();
      await delete(userCowDungLogs).go();

      await delete(learningDicts).go();
      await delete(groupAndDictLinks).go(); // 依赖 dictGroups 和 dicts，需先删
      await delete(dicts).go();

      await delete(userDbLogs).go();
      await delete(userDbVersions).go();

      await delete(words).go();
      await delete(levels).go();
      await delete(dictGroups).go();
      await delete(sysDbVersion).go();
      await delete(localParams).go();
      await delete(users).go();

      await customStatement('PRAGMA foreign_keys = ON');
    });
  }

  /// 在升级失败时，删除所有表并重建数据库
  ///
  /// 此方法会：
  /// 1. 删除所有现有的表（包括表结构）
  /// 2. 重新创建所有表
  /// 3. 创建性能优化索引
  /// 4. 初始化基础数据
  Future<void> _recreateDatabaseOnUpgradeFailure(Migrator m) async {
    Global.logger.i('🔄 开始重建数据库...');

    try {
      // 1. 获取所有表名并删除
      final tables = await customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        readsFrom: {},
      ).get();

      await transaction(() async {
        // 关闭外键约束
        await customStatement('PRAGMA foreign_keys = OFF');

        // 删除所有表（使用 IF EXISTS 避免表不存在时的错误）
        for (final table in tables) {
          final tableName = table.data['name'] as String;
          if (tableName.isEmpty) continue;

          // 使用参数化查询避免 SQL 注入（虽然表名来自系统表，但为了安全还是使用引号）
          await customStatement('DROP TABLE IF EXISTS "$tableName"');
          Global.logger.d('🗑️ 删除表: $tableName');
        }

        // 重新启用外键约束
        await customStatement('PRAGMA foreign_keys = ON');
      });

      // 2. 重新创建表、索引和初始化数据
      await _initializeDatabaseSchema(m);

      Global.logger.i('🎉 数据库重建完成');
    } catch (e, stackTrace) {
      Global.logger.e('❌ 重建数据库失败: $e', error: e, stackTrace: stackTrace);
      // 重建失败时也提示用户
      _showDatabaseRebuildFailureNotification();
      rethrow;
    }
  }

  /// 显示数据库重建通知（开始重建时）
  void _showDatabaseRebuildNotification() {
    // 使用 Future.microtask 确保在 UI 初始化完成后再显示提示
    Future.microtask(() {
      ToastUtil.info('数据库升级失败，正在重建本地数据库...');
    });
  }

  /// 显示数据库重建成功通知
  void _showDatabaseRebuildSuccessNotification() {
    // 使用 Future.microtask 确保在 UI 初始化完成后再显示提示
    Future.microtask(() {
      ToastUtil.success('本地数据库重建完成，请重新登录以同步数据');
    });
  }

  /// 显示数据库重建失败通知
  void _showDatabaseRebuildFailureNotification() {
    // 使用 Future.microtask 确保在 UI 初始化完成后再显示提示
    Future.microtask(() {
      ToastUtil.error('数据库重建失败，请重启应用');
    });
  }
}
