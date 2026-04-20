import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:drift/drift.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:nnbdc/db/dao.dart';
import 'package:nnbdc/db/table.dart';
import 'package:nnbdc/db/shared.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/toast_util.dart';

part 'db.g.dart';

@DriftDatabase(tables: [
  Users,
  LocalParams,
  VotedSentences,
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
  MasteredWords, // 已废弃，保留在列表中仅为了让 Drift 生成 deleteTable 迁移所需的引用
  UserCowDungLogs,
  UserWrongWords,
  SysDbVersion,
  LocalExceptions,
  LearningLogs,
], daos: [
  UsersDao,
  LocalParamsDao,
  VotedSentencesDao,
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
  LocalExceptionsDao,
  LearningLogsDao,
])
class MyDatabase extends _$MyDatabase {
  MyDatabase(super.e);

  static MyDatabase? _instance;
  static String? _dbFilePathCache;

  static MyDatabase get instance {
    _instance ??= constructDb();
    return _instance!;
  }

  static void setInstanceForTesting(MyDatabase testingInstance) {
    if (_instance != null) {
      _instance!.close();
    }
    _instance = testingInstance;
  }

  /// 获取本地 SQLite 文件路径（非 Web），并做缓存。
  ///
  /// 说明：getApplicationDocumentsDirectory() 在某些设备/首次调用时可能较慢，
  /// 下载完成后如果再调用会导致 UI 在 20% 附近短暂卡顿（Timer 无法及时刷新）。
  static Future<String> getDbFilePath() async {
    if (_dbFilePathCache != null) return _dbFilePathCache!;
    final dbFolder = await getApplicationDocumentsDirectory();
    _dbFilePathCache = p.join(dbFolder.path, 'db.sqlite');
    return _dbFilePathCache!;
  }

  static void closeDatabase() {
    if (_instance != null) {
      _instance!.close();
      _instance = null;
    }
  }

  /// 确保数据库完整性，如果检测到表缺失会自动重建
  ///
  /// 此方法会检查关键表是否存在，如果不存在则自动重建数据库
  /// 应该在应用启动时调用，确保数据库在使用前是完整的
  static Future<void> ensureDatabaseIntegrity() async {
    try {
      final db = instance;

      // 先触发数据库打开（如果还没打开的话），确保迁移已完成
      try {
        await db.customSelect('SELECT 1', readsFrom: {}).get();
      } catch (e) {
        // 如果数据库打开失败，可能表不存在，继续检查
      }

      // 检查关键表是否存在（通过查询 sqlite_master 来判断）
      try {
        final tables = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
          readsFrom: {},
        ).get();

        // 如果查询返回结果，说明表存在，数据库完整
        if (tables.isNotEmpty) {
          Global.logger.d('✅ 数据库完整性检查通过');
          return;
        }
      } catch (e) {
        // 如果查询失败，可能是表不存在或其他问题
        Global.logger.d('数据库完整性检查查询失败: $e');
      }

      // 如果表不存在，自动重建数据库
      // 直接使用 wipeAllTables 进行完整重建，确保表结构正确
      Global.logger.w('⚠️ 检测到数据库表缺失，自动重建数据库...');
      await db.wipeAllTables();
      Global.logger.i('✅ 数据库自动重建完成');
    } catch (e, stackTrace) {
      Global.logger.e('❌ 数据库完整性检查失败: $e', error: e, stackTrace: stackTrace);
      // 不抛出异常，让应用继续启动
    }
  }

  /// 🚀 初始化预置数据库
  ///
  /// 在 App 首次启动时，将 Assets 中的黄金母版数据库拷贝到应用数据目录。
  /// 这可以免去用户下载通用词典的漫长等待。
  static Future<void> initPrepopulatedDb() async {
    try {
      final dbPath = await getDbFilePath();
      final File dbFile = File(dbPath);

      // 只有当本地数据库不存在时（即全新安装），才进行拷贝
      // 注意：此方法必须在 MyDatabase.instance 被初次调用前执行，否则 drift 会自动创建空文件导致此判断失效
      if (!await dbFile.exists()) {
        Global.logger.i('📦 检测到全新安装，正在寻找预置数据库...');
        try {
          // 尝试从 Assets 加载
          // 注意：需要在 pubspec.yaml 中声明 assets/db/initial.sqlite
          const assetKey = 'assets/db/initial.sqlite';

          try {
            // 检查资源是否存在 (load 会抛出异常如果不存在)
            // 我们不需要真正 catch，因为 rootBundle.load 失败就是不存在
            final ByteData data = await rootBundle.load(assetKey);

            Global.logger.i('📦 发现预置数据库，正在部署...');

            // 确保父目录存在
            if (!await dbFile.parent.exists()) {
              await dbFile.parent.create(recursive: true);
            }

            // 写入文件
            // 直接 writeAsBytes，Flutter/Dart 会处理内存，buffer 不算太大通常没问题
            // 如果文件真的极其巨大(>500MB)，可以考虑 openWrite().add(buffer)
            await dbFile.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);

            Global.logger.i('✅ 预置数据库部署成功！');
          } catch (e) {
            // 资源没找到，是预期的（如果你忘了放进去，或者这是 Release 包没打进去）
            Global.logger.d('未找到预置数据库资源($assetKey)，将使用空库初始化: $e');
          }
        } catch (e) {
          Global.logger.e('❌ 部署预置数据库过程出错: $e');
          // 失败了也不要紧，Drift 会自动创建一个空的新库
        }
      } else {
        Global.logger.d('本地数据库已存在，跳过预置部署。');
      }
    } catch (e) {
      Global.logger.e('预置数据库检查流程异常: $e');
    }
  }

  // we tell the database where to store the data with this constructor
  //MyDatabase() : super(_openConnection());

  // you should bump this number whenever you change or add a table definition. Migrations
  // are covered later in this readme.
  @override
  int get schemaVersion => 37;

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
          // 从版本 3 升级到版本 4：创建本地异常记录表
          if (from < 4) {
            await _migrateFromV3ToV4(m);
          }
          // 从版本 4 升级到版本 5：添加订阅相关字段（按平台区分）
          if (from < 5) {
            await _migrateFromV4ToV5(m);
          }
          // 从版本 5 升级到版本 6：修复订阅字段列名（历史版本曾误用驼峰列名）
          if (from < 6) {
            await _migrateFromV5ToV6FixIosSubscriptionColumns();
          }
          // 从版本 6 升级到版本 7：添加“强制视为会员”字段
          if (from < 7) {
            await _migrateFromV6ToV7AddPremiumOverrideFields(m);
          }
          // 从版本 7 升级到版本 8：删除levels表
          if (from < 8) {
            await _migrateFromV7ToV8RemoveLevelsTable(m);
          }
          if (from < 9) {
            await _migrateFromV8ToV9RemoveLevelId();
          }
          if (from < 10) {
            await _migrateFromV9ToV10RemoveTodayLearningFields();
          }
          if (from < 11) {
            await _migrateFromV10ToV11RemoveTotalScoreField();
          }
          if (from < 12) {
            await _migrateFromV11ToV12RemoveVotedChinesesTable(m);
          }
          if (from < 13) {
            await _migrateFromV12ToV13RemoveLearningPositionFields();
          }
          if (from < 14) {
            await _migrateFromV13ToV14(m);
          }
          if (from < 15) {
            await _migrateFromV14ToV15(m);
          }
          if (from < 16) {
            await _migrateFromV15ToV16();
          }
          if (from < 17) {
            await _migrateFromV16ToV17FixDateTimeFormat();
          }
          if (from < 18) {
            await _migrateFromV17ToV18AddTodayStudyStarted(m);
          }
          if (from < 19) {
            await _migrateFromV18ToV19AddEditable(m);
          }
          if (from < 20) {
            await _migrateFromV19ToV20DropMasteredWordsTable(m);
          }
          if (from < 21) {
            await _migrateFromV20ToV21AddDeletable(m);
          }
          if (from < 22) {
            await _migrateFromV21ToV22AddLearningSeconds(m);
          }
          if (from < 23) {
            await _migrateFromV22ToV23(m);
          }
          if (from < 24) {
            await _migrateFromV23ToV24(m);
          }
          if (from < 25) {
            await _migrateFromV24ToV25(m);
          }
          if (from < 26) {
            await _migrateFromV25ToV26AddWalkmanConfig(m);
          }
          if (from < 27) {
            await _migrateFromV26ToV27SwapWalkmanConfigToStudyConfig(m);
          }
          if (from < 28) {
            await _migrateFromV27ToV28(m);
          }
          if (from < 29) {
            await _migrateFromV28ToV29(m);
          }
          if (from < 30) {
            await _migrateFromV29ToV30AddDomain(m);
          }
          if (from < 31) {
            await _migrateFromV30ToV31(m);
          }
          if (from < 32) {
            await _migrateFromV31ToV32(m);
          }
          if (from < 33) {
            await _migrateFromV32ToV33(m);
          }
          if (from < 34) {
            await _migrateFromV33ToV34(m);
          }
          if (from < 35) {
            await _migrateFromV34ToV35DropWordShortDescChineses(m);
          }
          if (from < 36) {
            await _migrateFromV35ToV36AddCoverUrl(m);
          }
          if (from < 37) {
            await _migrateFromV36ToV37AddUnitToDictWords(m);
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
      beforeOpen: (details) async {
        // 允许读写并发，并在锁冲突时等待而不是直接抛错
        // - WAL：写入不阻塞读取（读看到旧快照）
        // - busy_timeout：遇到锁时等待一段时间
        try {
          await customStatement('PRAGMA journal_mode=WAL;');
          await customStatement('PRAGMA busy_timeout=5000;');
        } catch (e) {
          // 某些平台/场景下 pragma 可能失败，不影响继续运行
          Global.logger.w('设置 SQLite PRAGMA 失败: $e');
        }
      },
    );
  }

  /// 从版本 6 升级到版本 7：添加“强制视为会员”字段
  Future<void> _migrateFromV6ToV7AddPremiumOverrideFields(Migrator m) async {
    await transaction(() async {
      await m.addColumn(users, users.premiumOverrideEnabled);
      await m.addColumn(users, users.premiumOverrideUpdateTime);
      await m.addColumn(users, users.premiumOverrideReason);
      await m.addColumn(users, users.premiumOverrideDuration);
    });
  }

  /// 从版本 7 升级到版本 8：删除levels表
  Future<void> _migrateFromV7ToV8RemoveLevelsTable(Migrator m) async {
    await transaction(() async {
      // 删除levels表
      await m.deleteTable('levels');

      // 从user_db_logs中删除与levels相关的记录
      await customStatement("DELETE FROM user_db_logs WHERE tbl_name = 'levels' OR tbl_name = 'level';");
    });
  }

  /// 从版本 8 升级到版本 9：删除users表中的level_id字段
  Future<void> _migrateFromV8ToV9RemoveLevelId() async {
    await transaction(() async {
      // 注意：SQLite 3.35.0+ 支持 DROP COLUMN
      // 如果设备上的 SQLite 版本较旧，此语句可能会失败。
      // 但Flutter通常捆绑较新的SQLite，或者Drift有处理机制。
      // 这里直接尝试使用 SQL 删除列。
      try {
        await customStatement('ALTER TABLE users DROP COLUMN level_id');
      } catch (e) {
        // 如果直接删除失败，通常意味着SQLite版本过低或约束限制。
        // 在这种情况下，Drift通常建议重建表，但这里尝试忽略或记录，
        // 因为level_id字段在代码中已移除，不影响后续运行（除了占用空间）。
        Global.logger.e('删除 level_id 列失败 (可能是SQLite版本过低): $e');
        // 可选：执行复杂的 recreate table 逻辑，但风险较大，暂且保留列。
      }
    });
  }

  /// 从版本 9 升级到版本 10：删除users表中的isTodayLearningStarted和isTodayLearningFinished字段
  Future<void> _migrateFromV9ToV10RemoveTodayLearningFields() async {
    await transaction(() async {
      // 注意：SQLite 3.35.0+ 支持 DROP COLUMN
      try {
        await customStatement('ALTER TABLE users DROP COLUMN is_today_learning_started');
        await customStatement('ALTER TABLE users DROP COLUMN is_today_learning_finished');
      } catch (e) {
        // 如果直接删除失败，记录错误但不停止迁移
        Global.logger.e('删除 is_today_learning_started 或 is_today_learning_finished 列失败 (可能是SQLite版本过低): $e');
      }
    });
  }

  /// 从版本 10 升级到版本 11：删除users表中的totalScore字段
  Future<void> _migrateFromV10ToV11RemoveTotalScoreField() async {
    await transaction(() async {
      // 注意：SQLite 3.35.0+ 支持 DROP COLUMN
      try {
        await customStatement('ALTER TABLE users DROP COLUMN total_score');
      } catch (e) {
        // 如果直接删除失败，记录错误但不停止迁移
        // 这种情况通常发生在SQLite版本过低或有其他约束
        Global.logger.e('删除 total_score 列失败 (可能是SQLite版本过低): $e');
      }
    });
  }

  /// 从版本 11 升级到版本 12：删除voted_chineses表
  Future<void> _migrateFromV11ToV12RemoveVotedChinesesTable(Migrator m) async {
    await transaction(() async {
      // 删除voted_chineses表
      await m.deleteTable('voted_chineses');

      // 从user_db_logs中删除相关的记录（如果存在）
      await customStatement("DELETE FROM user_db_logs WHERE tbl_name = 'voted_chineses' OR tbl_name = 'votedChineses';");
    });
  }

  /// 从版本 12 升级到版本 13：删除 learning_dicts 表中的 current_word_id 和 current_word_seq 字段
  /// 这两个字段已废弃，进度改为基于 learning_words 和 mastered_words 表动态计算
  Future<void> _migrateFromV12ToV13RemoveLearningPositionFields() async {
    await transaction(() async {
      try {
        await customStatement('ALTER TABLE learning_dicts DROP COLUMN current_word_id');
      } catch (e) {
        Global.logger.w('删除 current_word_id 列失败: $e');
      }
      try {
        await customStatement('ALTER TABLE learning_dicts DROP COLUMN current_word_seq');
      } catch (e) {
        Global.logger.w('删除 current_word_seq 列失败: $e');
      }
    });
  }

  /// 从版本 13 升级到版本 14：
  /// 1. 向 learning_words 表添加 today_learned_times 字段
  /// 2. 从 users 表删除已废弃的 last_learning_mode 字段
  Future<void> _migrateFromV13ToV14(Migrator m) async {
    await transaction(() async {
      // 1. 添加 today_learned_times 字段
      try {
        await m.addColumn(learningWords, learningWords.todayLearnedTimes);
      } catch (e) {
        Global.logger.w('添加 today_learned_times 列失败: $e');
      }

      // 2. 删除 last_learning_mode 和 last_learning_position 字段
      try {
        await customStatement('ALTER TABLE users DROP COLUMN last_learning_mode');
      } catch (e) {
        Global.logger.w('删除 last_learning_mode 列失败: $e');
      }
      try {
        await customStatement('ALTER TABLE users DROP COLUMN last_learning_position');
      } catch (e) {
        Global.logger.w('删除 last_learning_position 列失败: $e');
      }
    });
  }

  /// 从版本 14 升级到版本 15
  /// 向 learning_words 表添加 batch_id 字段
  Future<void> _migrateFromV14ToV15(Migrator m) async {
    try {
      await m.addColumn(learningWords, learningWords.batchId);
    } catch (e) {
      Global.logger.w('添加 batch_id 列失败: $e');
    }
  }

  /// 从版本 16 升级到版本 17
  /// 修复 user_study_steps 表中错误的 DateTime 格式(ISO8601字符串 -> Unix时间戳)
  Future<void> _migrateFromV16ToV17FixDateTimeFormat() async {
    try {
      // 查询所有 create_time 为字符串格式的记录
      final rows = await customSelect('SELECT user_id, study_step FROM user_study_steps').get();
      
      if (rows.isEmpty) {
        Global.logger.d('user_study_steps 表为空,跳过修复');
        return;
      }
      
      // 删除所有记录
      await customStatement('DELETE FROM user_study_steps');
      
      // 为每个用户重新插入正确格式的记录
      final userIds = rows.map((r) => r.data['user_id'] as String).toSet();
      
      for (final userId in userIds) {
        final now = AppClock.now();
        final nowTimestamp = now.millisecondsSinceEpoch ~/ 1000;
        
        // 重建学习步骤:List(预习)-> En2Ch -> Ch2En
        await customStatement(
          'INSERT INTO user_study_steps (user_id, study_step, seq, state, create_time) VALUES (?, ?, ?, ?, ?)',
          [userId, 'List', 0, 'Active', nowTimestamp],
        );
        await customStatement(
          'INSERT INTO user_study_steps (user_id, study_step, seq, state, create_time) VALUES (?, ?, ?, ?, ?)',
          [userId, 'En2Ch', 1, 'Active', nowTimestamp],
        );
        await customStatement(
          'INSERT INTO user_study_steps (user_id, study_step, seq, state, create_time) VALUES (?, ?, ?, ?, ?)',
          [userId, 'Ch2En', 2, 'Active', nowTimestamp],
        );
      }
      
      Global.logger.i('✅ 修复 user_study_steps 表 DateTime 格式完成,影响 ${userIds.length} 个用户');
    } catch (e) {
      Global.logger.w('修复 user_study_steps DateTime 格式失败: $e');
    }
  }

  /// 从版本 17 升级到版本 18：添加“今日学习是否已开始”字段
  Future<void> _migrateFromV17ToV18AddTodayStudyStarted(Migrator m) async {
    await transaction(() async {
      await customStatement('ALTER TABLE users ADD COLUMN today_study_started INTEGER NOT NULL DEFAULT 0');
    });
  }

  /// 从版本 18 升级到版本 19：添加“是否可编辑”字段
  Future<void> _migrateFromV18ToV19AddEditable(Migrator m) async {
    await transaction(() async {
      await customStatement('ALTER TABLE dicts ADD COLUMN editable INTEGER NOT NULL DEFAULT 0');
      // 生词本和自定义词书（ownerId 不是系统用户）默认 editable 为 true
      // 系统用户 ID 为 Global.sysUserId (15118)
      await customStatement("UPDATE dicts SET editable = 1 WHERE name = '生词本' OR owner_id != '${Global.sysUserId}'");
    });
  }

  /// 从版本 19 升级到版本 20：删除 mastered_words 表
  /// 已掌握单词现在存储在 dict_word 表中，通过"已掌握"词书管理
  Future<void> _migrateFromV19ToV20DropMasteredWordsTable(Migrator m) async {
    await transaction(() async {
      // 删除 mastered_words 表
      try {
        await m.deleteTable('mastered_words');
        Global.logger.i('✅ 已删除 mastered_words 表');
      } catch (e) {
        Global.logger.w('删除 mastered_words 表失败（可能已不存在）: $e');
      }

      // 从 user_db_logs 中删除 masteredWords 相关的日志记录
      await customStatement("DELETE FROM user_db_logs WHERE tbl_name = 'masteredWords' OR tbl_name = 'mastered_word';");
    });
  }

  /// 从版本 20 升级到版本 21：添加“是否可删除”字段
  Future<void> _migrateFromV20ToV21AddDeletable(Migrator m) async {
    await transaction(() async {
      await customStatement('ALTER TABLE dicts ADD COLUMN deletable INTEGER NOT NULL DEFAULT 1');
      // 系统词书（ownerId 是系统用户）、生词本和已掌握 不可删除
      // 系统用户 ID 为 Global.sysUserId (15118)
      await customStatement("UPDATE dicts SET deletable = 0 WHERE name IN ('生词本', '已掌握') OR owner_id = '${Global.sysUserId}'");
    });
  }

  /// 从版本 21 升级到版本 22：添加“学习时长”字段
  Future<void> _migrateFromV21ToV22AddLearningSeconds(Migrator m) async {
    await transaction(() async {
      try {
        await m.addColumn(users, users.totalLearningSeconds);
        await m.addColumn(users, users.todayLearningSeconds);
      } catch (e) {
        Global.logger.w('添加学习时长字段失败: $e');
      }
    });
  }

  /// 从版本 22 升级到版本 23：重构 life_value 为 mastery_level
  Future<void> _migrateFromV22ToV23(Migrator m) async {
    await transaction(() async {
      try {
        // 1. 重命名列 life_value -> mastery_level
        // 注意：SQLite 3.25.0+ (2018-09-15) 才支持 RENAME COLUMN
        // Flutter 捆绑的 SQLite 通常足够新。
        await customStatement('ALTER TABLE learning_words RENAME COLUMN life_value TO mastery_level');
        Global.logger.i('✅ 已重命名 learning_words.life_value 为 mastery_level');

        // 2. 转换数据逻辑：mastery_level = 5 - life_value
        // 此时 mastery_level 列里的数据还是原来的 life_value 值 (5,4,3,2,1,0)
        await customStatement('UPDATE learning_words SET mastery_level = 5 - mastery_level');
        Global.logger.i('✅ 已转换 learning_words 掌握度数据');

        // 3. 删除相关的同步日志 (user_db_logs)，因为 life_value 字段已不存在，后端也已重构
        // 这样可以避免同步旧数据到已更名的列
        await customStatement("DELETE FROM user_db_logs WHERE tbl_name = 'learningWords' OR tbl_name = 'learning_words';");
        Global.logger.i('✅ 已清空学习中单词相关的同步日志');
        
        // 4. 更新相关索引
        await customStatement('DROP INDEX IF EXISTS idx_learning_words_user_life');
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_learning_words_user_mastery 
          ON learning_words (user_id, mastery_level)
        ''');
        Global.logger.i('✅ 已更新 learning_words 索引');

      } catch (e, stackTrace) {
        Global.logger.e('升级从 V22 到 V23 失败: $e', error: e, stackTrace: stackTrace);
        rethrow;
      }
    });
  }

  /// 从版本 23 升级到版本 24：添加 FSRS 算法相关字段
  Future<void> _migrateFromV23ToV24(Migrator m) async {
    await transaction(() async {
      try {
        // 1. 添加 FSRS 列
        // 使用 try-catch 保护，防止列已存在时报错
        try { await m.addColumn(learningWords, learningWords.stability); } catch(_) {}
        try { await m.addColumn(learningWords, learningWords.difficulty); } catch(_) {}
        try { await m.addColumn(learningWords, learningWords.elapsedDays); } catch(_) {}
        try { await m.addColumn(learningWords, learningWords.scheduledDays); } catch(_) {}
        try { await m.addColumn(learningWords, learningWords.reps); } catch(_) {}
        try { await m.addColumn(learningWords, learningWords.lapses); } catch(_) {}
        try { await m.addColumn(learningWords, learningWords.state); } catch(_) {}
        Global.logger.i('✅ 已向 learning_words 添加 FSRS 算法字段');

        // 2. 迁移数据：根据 mastery_level 智能设置初始 Stability
        // 检查 mastery_level 列是否存在
        final columns = await customSelect("PRAGMA table_info(learning_words)").get();
        final hasMasteryLevel = columns.any((element) => element.read<String>('name') == 'mastery_level');

        if (hasMasteryLevel) {
          await customStatement('''
            UPDATE learning_words SET 
              stability = CASE 
                WHEN mastery_level >= 5 THEN 180.0 
                WHEN mastery_level = 4 THEN 14.0 
                WHEN mastery_level = 3 THEN 6.0 
                WHEN mastery_level = 2 THEN 3.0 
                WHEN mastery_level = 1 THEN 1.0 
                ELSE 0.1 
              END,
              difficulty = 5.0,
              reps = COALESCE(mastery_level, 0),
              state = 2, -- Review
              elapsed_days = 0,
              scheduled_days = 0,
              lapses = 0
            WHERE stability IS NULL OR stability = 0.0
          ''');
          Global.logger.i('✅ 已将 learning_words 掌握度数据迁移至 FSRS 稳定性参数');

          // 3. 删除旧字段 (mastery_level)
          // 注意：必须在 alterTable 之前先删除引用该列的旧索引，
          // 因为 alterTable 会尝试在重建表后重新创建索引，如果索引引用了已删除的列会报错。
          await customStatement('DROP INDEX IF EXISTS idx_learning_words_user_mastery');
          await customStatement('DROP INDEX IF EXISTS idx_learning_words_user_life');
          await customStatement('DROP INDEX IF EXISTS idx_learning_words_add_time_life');

          // ignore: experimental_member_use
          await m.alterTable(TableMigration(learningWords));
          Global.logger.i('✅ 已成功删除 mastery_level 冗余字段');
        }

        // 4. 清理旧格式数据
        await customStatement("UPDATE learning_words SET batch_id = NULL;");
        await customStatement("DELETE FROM user_db_logs WHERE tbl_name = 'learningWords' OR tbl_name = 'learning_words';");
        Global.logger.i('✅ 已清空旧批次数据和同步日志');

        // 5. 更新索引 (新索引)
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_learning_words_user_stability 
          ON learning_words (user_id, stability)
        ''');
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_learning_words_add_time_stability 
          ON learning_words (add_time, stability, word_id)
        ''');
        Global.logger.i('✅ 已更新 FSRS 相关索引');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V23 到 V24 失败: $e', error: e, stackTrace: stackTrace);
        rethrow;
      }
    });
  }

  /// 从版本 24 升级到版本 25：添加 LearningLogs 表
  Future<void> _migrateFromV24ToV25(Migrator m) async {
    await m.createTable(learningLogs);
    Global.logger.i('✅ 创建 learning_logs 表完成');
  }

  /// 从版本 25 升级到版本 26：添加“随身听配置”字段
  Future<void> _migrateFromV25ToV26AddWalkmanConfig(Migrator m) async {
    await transaction(() async {
      try {
        await customStatement('ALTER TABLE users ADD COLUMN walkman_config TEXT');
        Global.logger.i('✅ 向 users 表添加 walkman_config 字段完成');
      } catch (e) {
        Global.logger.w('添加 walkman_config 字段失败: $e');
      }
    });
  }

  /// 从版本 26 升级到版本 27：添加“综合学习配置”字段，将 walkman_config 以及分散的配置字段迁移并抛弃
  Future<void> _migrateFromV26ToV27SwapWalkmanConfigToStudyConfig(Migrator m) async {
    await transaction(() async {
      try {
        await customStatement('ALTER TABLE users ADD COLUMN study_config TEXT');

        // 迁移旧数据: 构造 JSON 字符串保存到 study_config
        // SQLite 的 Boolean 存储为 1/0
        await customStatement("""
          UPDATE users SET study_config = '{' || 
            '"autoPlayWord":' || CASE WHEN auto_play_word = 1 THEN 'true' ELSE 'false' END || ',' ||
            '"autoPlaySentence":' || CASE WHEN auto_play_sentence = 1 THEN 'true' ELSE 'false' END || ',' ||
            '"showAnswersDirectly":' || CASE WHEN show_answers_directly = 1 THEN 'true' ELSE 'false' END || ',' ||
            '"enableAllWrong":' || CASE WHEN enable_all_wrong = 1 THEN 'true' ELSE 'false' END || 
            CASE WHEN walkman_config IS NOT NULL AND walkman_config != '' THEN ',"walkman":' || walkman_config ELSE '' END ||
          '}'
        """);

        // 删除旧字段 (SQLite 3.35.0+ 支持 DROP COLUMN)
        final columns = ['walkman_config', 'auto_play_word', 'auto_play_sentence', 'show_answers_directly', 'enable_all_wrong'];
        for (var col in columns) {
          try {
            await customStatement('ALTER TABLE users DROP COLUMN $col');
          } catch (e) {
            Global.logger.w('DROP COLUMN $col 失败: $e');
          }
        }

        Global.logger.i('✅ 升级用户配置到 study_config 完成');
      } catch (e) {
        Global.logger.w('升级 study_config 发生异常: $e');
      }
    });
  }

  /// 从版本 27 升级到版本 28：向 Sentences 表添加 part_of_speech 字段
  Future<void> _migrateFromV27ToV28(Migrator m) async {
    await transaction(() async {
      try {
        await m.addColumn(sentences, sentences.partOfSpeech);
        Global.logger.i('✅ 升级从 V27 到 V28 完成，添加例句词性字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V27 到 V28 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 28 升级到版本 29：向 Dicts 表添加 base_dict_id 和 sort_alg 字段
  Future<void> _migrateFromV28ToV29(Migrator m) async {
    await transaction(() async {
      try {
        await m.addColumn(dicts, dicts.baseDictId);
        await m.addColumn(dicts, dicts.sortAlg);
        Global.logger.i('✅ 升级从 V28 到 V29 完成，添加字典从属与算法配置');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V28 到 V29 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 29 升级到版本 30：向 Dicts 表添加 domain 字段
  Future<void> _migrateFromV29ToV30AddDomain(Migrator m) async {
    await transaction(() async {
      try {
        // We use try-catch specifically per column because users might have wiped DB 
        // and got it created directly by onCreate without migrations.
        try {
          await m.addColumn(dicts, dicts.domain);
        } catch (e) {
          Global.logger.i('Column domain already exists or error: $e');
        }
        Global.logger.i('✅ 升级从 V29 到 V30 完成，添加 domain 字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V29 到 V30 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 35 升级到版本 36：向 Dicts 表添加 cover_url 字段
  Future<void> _migrateFromV35ToV36AddCoverUrl(Migrator m) async {
    await transaction(() async {
      try {
        await customStatement('ALTER TABLE dicts ADD COLUMN cover_url TEXT');
        Global.logger.i('✅ 升级从 V35 到 V36 完成，添加词书封面字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V35 到 V36 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 36 升级到版本 37：向 DictWords 表添加 unit 字段
  Future<void> _migrateFromV36ToV37AddUnitToDictWords(Migrator m) async {
    await transaction(() async {
      try {
        await customStatement('ALTER TABLE dict_words ADD COLUMN unit INTEGER NOT NULL DEFAULT 0');
        Global.logger.i('✅ 升级从 V36 到 V37 完成，添加 DictWords 的 unit 字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V36 到 V37 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  Future<void> _migrateFromV30ToV31(Migrator m) async {
    await transaction(() async {
      try {
        await customStatement('ALTER TABLE word_images ADD COLUMN status TEXT');
        await customStatement('ALTER TABLE word_images ADD COLUMN audit_reason TEXT');
        Global.logger.i('✅ 升级从 V30 到 V31 完成，添加单词配图审核相关字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V30 到 V31 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 31 升级到版本 32：向 Users 表添加 apple_user_id 字段
  Future<void> _migrateFromV31ToV32(Migrator m) async {
    await transaction(() async {
      try {
        await m.addColumn(users, users.appleUserId);
        Global.logger.i('✅ 升级从 V31 到 V32 完成，添加 apple_user_id 字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V31 到 V32 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 32 升级到版本 33：向 Cigens 表添加 spell, category, meaning_cn, meaning_en 字段
  Future<void> _migrateFromV32ToV33(Migrator m) async {
    await transaction(() async {
      try {
        await m.addColumn(cigens, cigens.spell);
        await m.addColumn(cigens, cigens.category);
        await m.addColumn(cigens, cigens.meaningCn);
        await m.addColumn(cigens, cigens.meaningEn);
        Global.logger.i('✅ 升级从 V32 到 V33 完成，添加 Cigens 的字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V32 到 V33 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 33 升级到版本 34：为各 UGC 表添加 ownerId 字段
  Future<void> _migrateFromV33ToV34(Migrator m) async {
    await transaction(() async {
      try {
        await m.addColumn(sentences, sentences.ownerId);
        await m.addColumn(wordImages, wordImages.ownerId);
        await m.addColumn(meaningItems, meaningItems.ownerId);
        // word_short_desc_chinese 表已在 V35 删除，这里跳过对它的操作
        try {
          await customStatement('ALTER TABLE word_short_desc_chineses ADD COLUMN owner_id TEXT NOT NULL DEFAULT \'15118\'');
        } catch (e) {
          // 表可能不存在（新安装）或列已存在，忽略
        }
        Global.logger.i('✅ 升级从 V33 到 V34 完成，添加各表 ownerId 字段');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V33 到 V34 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 34 升级到版本 35：删除 word_short_desc_chineses 表（无UI展示，纯冗余数据）
  Future<void> _migrateFromV34ToV35DropWordShortDescChineses(Migrator m) async {
    await transaction(() async {
      try {
        await m.deleteTable('word_short_desc_chineses');
        Global.logger.i('✅ 升级从 V34 到 V35 完成，删除 word_short_desc_chineses 表');
      } catch (e, stackTrace) {
        Global.logger.e('升级从 V34 到 V35 失败: $e', error: e, stackTrace: stackTrace);
      }
    });
  }

  /// 从版本 15 升级到版本 16
  /// 重建学习步骤,添加 List 学习步骤
  Future<void> _migrateFromV15ToV16() async {
    try {
      // 清空所有用户的学习步骤
      await customStatement('DELETE FROM user_study_steps');
        
      // 重新获取所有用户(users 表的主键是 id)
      final users = await customSelect('SELECT id FROM users').get();
        
      for (final user in users) {
        final userId = user.data['id'] as String;
        // 使用 Drift 的 DateTimeType 将 DateTime 转换为 Unix 时间戳(秒)
        final now = AppClock.now();
        final nowTimestamp = now.millisecondsSinceEpoch ~/ 1000;
          
        // 重建学习步骤:List(预习)-> En2Ch -> Ch2En
        await customStatement(
          'INSERT INTO user_study_steps (user_id, study_step, seq, state, create_time) VALUES (?, ?, ?, ?, ?)',
          [userId, 'List', 0, 'Active', nowTimestamp],
        );
        await customStatement(
          'INSERT INTO user_study_steps (user_id, study_step, seq, state, create_time) VALUES (?, ?, ?, ?, ?)',
          [userId, 'En2Ch', 1, 'Active', nowTimestamp],
        );
        await customStatement(
          'INSERT INTO user_study_steps (user_id, study_step, seq, state, create_time) VALUES (?, ?, ?, ?, ?)',
          [userId, 'Ch2En', 2, 'Active', nowTimestamp],
        );
  
        Global.logger.d('重建用户 $userId 的学习步骤: List, En2Ch, Ch2En');
      }
    } catch (e) {
      Global.logger.w('重建学习步骤失败: $e');
    }
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

  /// 从版本 3 升级到版本 4 的迁移逻辑
  /// 创建本地异常记录表
  Future<void> _migrateFromV3ToV4(Migrator m) async {
    await m.createTable(localExceptions);
    Global.logger.i('✅ 创建 local_exceptions 表完成');
  }

  /// 从版本 4 升级到版本 5 的迁移逻辑
  /// 添加订阅相关字段（仅支持iOS平台）
  Future<void> _migrateFromV4ToV5(Migrator m) async {
    await transaction(() async {
      // 添加iOS订阅字段
      // 注意：Drift 在 SQLite 中使用下划线列名（snake_case）
      // is_premium_ios 设置为 NOT NULL，默认值为 0 (false)
      await customStatement('''
        ALTER TABLE users 
        ADD COLUMN is_premium_ios INTEGER NOT NULL DEFAULT 0
      ''');

      await customStatement('''
        ALTER TABLE users 
        ADD COLUMN subscription_expire_date_ios INTEGER
      ''');

      await customStatement('''
        ALTER TABLE users 
        ADD COLUMN subscription_type_ios TEXT
      ''');

      await customStatement('''
        ALTER TABLE users 
        ADD COLUMN subscription_status_ios TEXT
      ''');

      await customStatement('''
        ALTER TABLE users 
        ADD COLUMN last_receipt_data_ios TEXT
      ''');

      Global.logger.i('✅ 添加iOS订阅相关字段完成（版本4→5）');
    });
  }

  /// 从版本 5 升级到版本 6：修复订阅字段列名
  ///
  /// 历史版本曾通过 SQL 手工添加了驼峰列名（如 isPremiumIos），而 Drift 读取的是 snake_case（如 is_premium_ios），
  /// 会导致查询映射时出现空值并触发 `!` 崩溃。
  Future<void> _migrateFromV5ToV6FixIosSubscriptionColumns() async {
    await transaction(() async {
      final cols = await customSelect("PRAGMA table_info(users)", readsFrom: {}).get();
      final colNames = cols.map((r) => (r.data['name'] as String?) ?? '').toSet();

      bool has(String name) => colNames.contains(name);

      // 1) 确保 snake_case 列存在（Drift 读取依赖这些列名）
      if (!has('is_premium_ios')) {
        await customStatement("ALTER TABLE users ADD COLUMN is_premium_ios INTEGER NOT NULL DEFAULT 0");
      }
      if (!has('subscription_expire_date_ios')) {
        await customStatement("ALTER TABLE users ADD COLUMN subscription_expire_date_ios INTEGER");
      }
      if (!has('subscription_type_ios')) {
        await customStatement("ALTER TABLE users ADD COLUMN subscription_type_ios TEXT");
      }
      if (!has('subscription_status_ios')) {
        await customStatement("ALTER TABLE users ADD COLUMN subscription_status_ios TEXT");
      }
      if (!has('last_receipt_data_ios')) {
        await customStatement("ALTER TABLE users ADD COLUMN last_receipt_data_ios TEXT");
      }

      // 2) 若存在历史驼峰列名，则把数据迁移到 snake_case 列
      // 注：SQLite 不支持 DROP COLUMN（老版本），所以保留旧列不影响。
      if (has('isPremiumIos')) {
        await customStatement("UPDATE users SET is_premium_ios = COALESCE(isPremiumIos, 0)");
      }
      if (has('subscriptionExpireDateIos')) {
        await customStatement("UPDATE users SET subscription_expire_date_ios = subscriptionExpireDateIos");
      }
      if (has('subscriptionTypeIos')) {
        await customStatement("UPDATE users SET subscription_type_ios = subscriptionTypeIos");
      }
      if (has('subscriptionStatusIos')) {
        await customStatement("UPDATE users SET subscription_status_ios = subscriptionStatusIos");
      }
      if (has('lastReceiptDataIos')) {
        await customStatement("UPDATE users SET last_receipt_data_ios = lastReceiptDataIos");
      }

      Global.logger.i('✅ 修复 users 表 iOS 订阅字段列名完成（版本5→6）');
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
      CREATE INDEX IF NOT EXISTS idx_learning_words_user_stability 
      ON learning_words (user_id, stability)
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
      CREATE INDEX IF NOT EXISTS idx_learning_words_add_time_stability 
      ON learning_words (add_time, stability, word_id)
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

    // mastered_words 表已在 v20 中删除，不再创建索引

    // 为sentences表添加索引
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_sentences_meaning_item 
      ON sentences (meaning_item_id)
    ''');


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
    // 直接复用全清逻辑，保持与"重新安装"效果一致
    await wipeAllTables();
  }

  /// 删除所有表并重建数据库（使用最新的数据库表结构）
  ///
  /// 此方法会：
  /// 1. 删除所有现有的表（包括表结构）
  /// 2. 删除 drift_schema 表以触发 onCreate
  /// 3. 重新创建所有表
  /// 4. 创建性能优化索引
  /// 5. 初始化基础数据
  ///
  /// 使用后应用将回到近似初始安装状态，但表结构是最新的
  Future<void> wipeAllTables() async {
    Global.logger.i('🔄 开始删除所有表并重建数据库...');

    try {
      // 1. 关闭数据库连接
      final wasCurrentInstance = (_instance == this);
      if (wasCurrentInstance) {
        close();
        _instance = null;
      }

      // 2. 删除数据库文件，确保重新创建时触发 onCreate
      // 这是最可靠的方法，因为删除文件后重新创建会确保 onCreate 被触发
      try {
        final dbFolder = await getApplicationDocumentsDirectory();
        final dbFile = File(p.join(dbFolder.path, 'db.sqlite'));
        if (await dbFile.exists()) {
          await dbFile.delete();
          Global.logger.i('🗑️ 删除数据库文件: ${dbFile.path}');
        }
      } catch (e) {
        Global.logger.w('删除数据库文件失败: $e，尝试删除表...');
        // 如果删除文件失败（可能文件被锁定），尝试删除表
        // 需要先创建一个临时实例来删除表
        final tempDb = constructDb();
        try {
          await tempDb._dropAllTables();
          tempDb.close();
        } catch (e2) {
          Global.logger.w('删除表也失败: $e2');
          tempDb.close();
        }
      }

      // 3. 重新创建数据库实例，这会触发 onCreate
      final newDb = constructDb();
      if (wasCurrentInstance) {
        _instance = newDb;
      }

      // 4. 通过执行一个查询来触发数据库打开和迁移
      // 由于数据库文件不存在，Drift 会调用 onCreate 回调，并同步等待其完成
      await newDb.customSelect('SELECT 1', readsFrom: {}).get();

      Global.logger.i('🎉 数据库重建完成');
    } catch (e, stackTrace) {
      Global.logger.e('❌ 重建数据库失败: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 删除所有表的通用方法
  Future<void> _dropAllTables() async {
    // 获取所有表名并删除
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

      // 删除 Drift 的内部版本表，这样重新打开数据库时会触发 onCreate
      await customStatement('DROP TABLE IF EXISTS "drift_schema"');
      Global.logger.d('🗑️ 删除 drift_schema 表');

      // 重新启用外键约束
      await customStatement('PRAGMA foreign_keys = ON');
    });
  }

  /// 重建所有表的通用方法（需要 Migrator）
  Future<void> _recreateAllTablesWithMigrator(Migrator m) async {
    // 重新创建表、索引和初始化数据
    await _initializeDatabaseSchema(m);
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
      // 1. 删除所有表
      await _dropAllTables();

      // 2. 重新创建表、索引和初始化数据
      await _recreateAllTablesWithMigrator(m);

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
