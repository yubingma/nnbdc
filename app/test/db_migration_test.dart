import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/date_utils.dart';
import 'package:sqlite3/sqlite3.dart';

/// v51 的 users 建表语句, 直接取自随包发布的 v51 母版库 (assets/db/initial.sqlite.gz),
/// 保证夹具与线上真实 schema 同构, 而不是靠手写臆测。
///
/// 迁移失败会走 `_recreateDatabaseOnUpgradeFailure` 删光所有表重建 —— 代价是用户数据丢失,
/// 所以这条路径必须有回归测试兜住"列补齐了 + 老数据还在"。
const String _v51UsersDdl = r'''
CREATE TABLE "users" ("id" TEXT NOT NULL, "user_name" TEXT NOT NULL, "nick_name" TEXT NULL, "game_score" INTEGER NOT NULL, "password" TEXT NULL, "daka_score" INTEGER NOT NULL, "last_login_time" INTEGER NULL, "last_share_time" INTEGER NULL, "email" TEXT NULL, "wechat_open_id" TEXT NULL, "wechat_union_id" TEXT NULL, "wechat_nickname" TEXT NULL, "wechat_avatar" TEXT NULL, "last_learning_date" INTEGER NULL, "learned_days" INTEGER NOT NULL, "learning_finished" INTEGER NULL DEFAULT 0 CHECK ("learning_finished" IN (0, 1)), "invite_award_taken" INTEGER NULL DEFAULT 0 CHECK ("invite_award_taken" IN (0, 1)), "is_super_admin" INTEGER NULL DEFAULT 0 CHECK ("is_super_admin" IN (0, 1)), "is_admin" INTEGER NULL DEFAULT 0 CHECK ("is_admin" IN (0, 1)), "is_inputor" INTEGER NULL DEFAULT 0 CHECK ("is_inputor" IN (0, 1)), "words_per_day" INTEGER NOT NULL, "daka_day_count" INTEGER NOT NULL, "mastered_words_count" INTEGER NOT NULL, "cow_dung" INTEGER NOT NULL, "throw_dice_chance" INTEGER NOT NULL, "invited_by_id" TEXT NULL, "continuous_daka_day_count" INTEGER NOT NULL, "max_continuous_daka_day_count" INTEGER NOT NULL, "last_daka_date" INTEGER NULL, "daka_ratio" REAL NULL, "today_study_started" INTEGER NOT NULL DEFAULT 0 CHECK ("today_study_started" IN (0, 1)), "total_learning_seconds" INTEGER NULL DEFAULT 0, "today_learning_seconds" INTEGER NULL DEFAULT 0, "apple_user_id" TEXT NULL, "is_premium_ios" INTEGER NULL DEFAULT 0 CHECK ("is_premium_ios" IN (0, 1)), "subscription_expire_date_ios" INTEGER NULL, "vip_expire_date" INTEGER NULL, "vip_type" TEXT NULL, "last_pay_channel" TEXT NULL, "subscription_type_ios" TEXT NULL, "subscription_status_ios" TEXT NULL, "last_receipt_data_ios" TEXT NULL, "premium_override_enabled" INTEGER NULL DEFAULT 0 CHECK ("premium_override_enabled" IN (0, 1)), "premium_override_update_time" INTEGER NULL, "premium_override_reason" TEXT NULL, "premium_override_duration" TEXT NULL, "study_config" TEXT NULL, "create_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))
''';

/// v51 的 learning_words 建表语句, 同样取自随包发布的 v51 母版库。
/// v52 → v53 迁移要给这张表补 is_extra 列, 因此夹具必须包含它,
/// 否则迁移会因缺表失败并触发删库重建(用户数据丢失)。
const String _v51LearningWordsDdl = r'''
CREATE TABLE IF NOT EXISTS "learning_words" ("user_id" TEXT NOT NULL, "word_id" TEXT NOT NULL, "add_day" INTEGER NOT NULL, "add_time" INTEGER NOT NULL, "last_learning_date" INTEGER NULL, "learning_order" INTEGER NOT NULL, "batch_id" INTEGER NULL, "stability" REAL NULL, "difficulty" REAL NULL, "elapsed_days" INTEGER NULL, "scheduled_days" INTEGER NULL, "reps" INTEGER NULL, "lapses" INTEGER NULL, "state" INTEGER NULL DEFAULT 0, "is_today_new_word" INTEGER NOT NULL CHECK ("is_today_new_word" IN (0, 1)), "learned_times" INTEGER NOT NULL, "today_learned_times" INTEGER NOT NULL DEFAULT 0, "create_time" INTEGER NOT NULL, "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("user_id", "word_id"));
''';

/// v51 的 cigens 建表语句, 同样取自随包发布的母版库。
/// v54 → v55 迁移要给这张表补 spell_variants 列, 因此夹具必须包含它,
/// 否则迁移会因缺表失败并触发删库重建(用户数据丢失)。
const String _v51CigensDdl = r'''
CREATE TABLE "cigens" ("id" TEXT NOT NULL, "description" TEXT NOT NULL, "spell" TEXT NULL, "category" TEXT NULL, "meaning_cn" TEXT NULL, "meaning_en" TEXT NULL, "create_time" INTEGER NOT NULL, "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))
''';

/// v51 的 words 建表语句（此时 embedding_1bit 已存在，3D 向量列已在 v46 删除）。
/// v55 → v56 迁移要给它补 short_desc_cn 列，夹具必须包含这张表，
/// 否则迁移会因缺表失败并触发删库重建(用户数据丢失)。
const String _v51WordsDdl = r'''
CREATE TABLE "words" ("id" TEXT NOT NULL, "america_pronounce" TEXT NULL, "british_pronounce" TEXT NULL, "group_info" TEXT NULL, "long_desc" TEXT NULL, "popularity" INTEGER NOT NULL, "pronounce" TEXT NULL, "short_desc" TEXT NULL, "spell" TEXT NOT NULL, "embedding_1bit" BLOB NULL, "create_time" INTEGER NOT NULL, "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))
''';

/// v51 的 learning_logs / user_db_logs / dicts 建表语句，同样取自随包发布的母版库
/// （这三张表自 v51 起未被任何迁移改动）。
/// v56 → v57 迁移要跨用户扫 learning_logs 去重、回填 learning_words，
/// 并为删除/回填写同步日志（user_db_logs）、查「已掌握」词书（dicts），缺任一张都会触发删库重建。
const String _v51LearningLogsDdl = r'''
CREATE TABLE IF NOT EXISTS "learning_logs" ("id" TEXT NOT NULL, "user_id" TEXT NOT NULL, "word_id" TEXT NOT NULL, "rating" INTEGER NOT NULL, "stability" REAL NOT NULL, "difficulty" REAL NOT NULL, "elapsed_days" INTEGER NOT NULL, "scheduled_days" INTEGER NOT NULL, "create_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))
''';

const String _v51UserDbLogsDdl = r'''
CREATE TABLE IF NOT EXISTS "user_db_logs" ("id" TEXT NOT NULL, "operate" TEXT NOT NULL, "record_id" TEXT NOT NULL, "record" TEXT NOT NULL, "tbl_name" TEXT NOT NULL, "user_id" TEXT NOT NULL, "version" INTEGER NOT NULL, "create_time" INTEGER NOT NULL, "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))
''';

const String _v51DictsDdl = r'''
CREATE TABLE IF NOT EXISTS "dicts" ("id" TEXT NOT NULL, "is_ready" INTEGER NOT NULL CHECK ("is_ready" IN (0, 1)), "is_shared" INTEGER NOT NULL CHECK ("is_shared" IN (0, 1)), "name" TEXT NOT NULL, "word_count" INTEGER NOT NULL, "owner_id" TEXT NOT NULL DEFAULT '15118', "visible" INTEGER NOT NULL CHECK ("visible" IN (0, 1)), "editable" INTEGER NOT NULL DEFAULT 0 CHECK ("editable" IN (0, 1)), "deletable" INTEGER NOT NULL DEFAULT 1 CHECK ("deletable" IN (0, 1)), "popularity_limit" INTEGER NULL, "domain" TEXT NULL, "base_dict_id" TEXT NULL, "cover_url" TEXT NULL, "sort_alg" TEXT NULL, "description" TEXT NULL, "create_time" INTEGER NOT NULL, "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"))
''';

/// v51 的 user_study_daily_stats 建表语句（v39 → v40 创建，此后未被改动）。
/// v56 → v57 的修复删除重复日志时要回滚当日的 review_count，夹具必须包含它。
const String _v51UserStudyDailyStatsDdl = r'''
CREATE TABLE IF NOT EXISTS "user_study_daily_stats" ("user_id" TEXT NOT NULL, "date" INTEGER NOT NULL, "study_seconds" INTEGER NOT NULL DEFAULT 0, "review_count" INTEGER NOT NULL DEFAULT 0, "day_status" TEXT NULL, "create_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "update_time" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("user_id", "date"))
''';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nnbdc_db_migration');
    dbFile = File('${tempDir.path}/v51.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 造一个停在 v51、且已有一条用户数据的库
  ///
  /// [duplicateMasteredDicts] 为 true 时额外插两本同名「已掌握」词书：
  /// DictsDao.findUserMasteredDict 撞到这种核心数据异常会直接抛错，
  /// 用于验证 56→57 的修复抛异常时不会把整个迁移推进"删库重建"。
  void seedV51Fixture({bool duplicateMasteredDicts = false}) {
    final raw = sqlite3.open(dbFile.path);
    raw.execute(_v51UsersDdl);
    raw.execute(_v51LearningWordsDdl);
    raw.execute(_v51CigensDdl);
    raw.execute(_v51WordsDdl);
    raw.execute(_v51LearningLogsDdl);
    raw.execute(_v51UserDbLogsDdl);
    raw.execute(_v51DictsDdl);
    raw.execute(_v51UserStudyDailyStatsDdl);
    raw.execute(
      "INSERT INTO words (id, spell, popularity, short_desc, create_time, update_time) "
      "VALUES ('w1', 'defect', 5, 'A flaw in something is a defect.', 1, 1)",
    );
    raw.execute(
      'INSERT INTO users (id, user_name, game_score, daka_score, learned_days, words_per_day, '
      'daka_day_count, mastered_words_count, cow_dung, throw_dice_chance, '
      'continuous_daka_day_count, max_continuous_daka_day_count, create_time, update_time) '
      "VALUES ('u1', 'tester', 0, 0, 10, 20, 5, 1000, 0, 0, 3, 21, 1, 1)",
    );
    // v56 → v57 修复夹具：真实首次作答（stability 57.0）+ 30ms 后的重复日志（同一秒），
    // learning_words 已被重复那条污染成 5.8/2.4/0/0
    raw.execute(
      'INSERT INTO learning_logs (id, user_id, word_id, rating, stability, difficulty, '
      'elapsed_days, scheduled_days, create_time, update_time) '
      "VALUES ('log-real', 'u1', 'dupw', 3, 57.0, 7.0, 3, 15, 1767225600, 1767225600)",
    );
    raw.execute(
      'INSERT INTO learning_logs (id, user_id, word_id, rating, stability, difficulty, '
      'elapsed_days, scheduled_days, create_time, update_time) '
      "VALUES ('log-dup', 'u1', 'dupw', 3, 5.8, 2.4, 0, 0, 1767225600, 1767225600)",
    );
    raw.execute(
      'INSERT INTO learning_words (user_id, word_id, add_day, add_time, learning_order, '
      'is_today_new_word, learned_times, stability, difficulty, elapsed_days, scheduled_days, '
      'create_time, update_time) '
      "VALUES ('u1', 'dupw', 1, 1767225600, 1, 1, 1, 5.8, 2.4, 0, 0, 1767225600, 1767225600)",
    );
    if (duplicateMasteredDicts) {
      for (final id in ['dict-mastered-1', 'dict-mastered-2']) {
        raw.execute(
          'INSERT INTO dicts (id, is_ready, is_shared, name, word_count, owner_id, visible, '
          'editable, deletable, create_time, update_time) '
          "VALUES ('$id', 1, 0, '已掌握', 0, 'u1', 1, 0, 1, 1, 1)",
        );
      }
    }
    // 与两条日志同一业务日的统计行：重复作答把 review_count 多加了 1（2 → 修复后应为 1）
    final logBusinessDay =
        DateUtils.businessDate(DateTime.fromMillisecondsSinceEpoch(1767225600 * 1000));
    raw.execute(
      'INSERT INTO user_study_daily_stats (user_id, date, study_seconds, review_count, create_time, update_time) '
      "VALUES ('u1', ${logBusinessDay.millisecondsSinceEpoch ~/ 1000}, 0, 2, 1, 1)",
    );
    raw.execute('PRAGMA user_version = 51');
    raw.dispose();
  }

  test('v51 → 最新版: 逐级补齐列且不丢用户数据', () async {
    seedV51Fixture();

    final db = MyDatabase(NativeDatabase(dbFile));
    // v56 → v57 的修复要用 DbLogUtil 写同步日志，而它依赖 MyDatabase.instance 单例
    MyDatabase.setInstanceForTesting(db);
    try {
      // 用 drift 生成的 DAO 读取: 若迁移未执行, 这里会因缺列直接抛错
      final user = await db.usersDao.getUserById('u1');

      expect(user, isNotNull, reason: '迁移失败会删库重建, 届时用户数据丢失');
      expect(user!.masteredWordsCount, 1000, reason: '原有字段必须原样保留');
      expect(user.maxMasteredWords, 1000, reason: '迁移应把峰值用当前掌握词数播种');
      expect(user.continuousDakaDayCount, 3);
      expect(user.maxContinuousDakaDayCount, 21);

      final columns = await db.customSelect("PRAGMA table_info('users')").get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('max_mastered_words'),
      );

      // v52 → v53: learning_words 补上加量标记列, 且历史数据一律为非加量
      final learningWordColumns = await db.customSelect("PRAGMA table_info('learning_words')").get();
      expect(
        learningWordColumns.map((row) => row.read<String>('name')),
        contains('is_extra'),
      );

      // v53 → v54: 增加 word_core_images 核心意象表
      final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
      expect(
        tables.map((row) => row.read<String>('name')),
        contains('word_core_images'),
      );

      // v54 → v55: cigens 补上词根拼写变形列（词根卡片表头提示）
      final cigenColumns = await db.customSelect("PRAGMA table_info('cigens')").get();
      expect(
        cigenColumns.map((row) => row.read<String>('name')),
        contains('spell_variants'),
      );

      // v57 → v58: 新建记忆守护兽养成状态表（每个用户一行）
      expect(
        tables.map((row) => row.read<String>('name')),
        contains('user_pet_states'),
      );

      // v55 → v56: words 补上「深度讲解」中文译文列，且老单词数据仍在
      final wordColumns = await db.customSelect("PRAGMA table_info('words')").get();
      expect(
        wordColumns.map((row) => row.read<String>('name')),
        contains('short_desc_cn'),
      );
      final word = await (db.select(db.words)..where((w) => w.id.equals('w1'))).getSingleOrNull();
      expect(word, isNotNull, reason: '迁移不得丢失已有单词行');
      expect(word!.shortDesc, 'A flaw in something is a defect.');
      expect(word.shortDescCn, isNull, reason: '新列对老数据应为空，等待服务端下发译文');

      // v56 → v57: 同秒的重复日志被删除（只留最早那条），被污染的记忆字段按日志真值回填
      final repairedLogs = await (db.select(db.learningLogs)
            ..where((l) => l.userId.equals('u1'))
            ..where((l) => l.wordId.equals('dupw')))
          .get();
      expect(repairedLogs.map((l) => l.id), ['log-real']);
      expect(repairedLogs.single.stability, 57.0);
      final repairedWord = await db.learningWordsDao.getById('u1', 'dupw');
      expect(repairedWord, isNotNull);
      expect(repairedWord!.stability, 57.0);
      expect(repairedWord.difficulty, 7.0);
      expect(repairedWord.elapsedDays, 3);
      expect(repairedWord.scheduledDays, 15);

      // 删除/回填都要留下待同步日志，服务端据此自动收敛
      final syncLogs = await db.select(db.userDbLogs).get();
      expect(
        syncLogs.map((l) => '${l.operate}|${l.tblName}|${l.recordId}'),
        containsAll(['DELETE|learningLogs|log-dup', 'UPDATE|learningWords|u1-dupw']),
      );

      // 重复作答派生的当日评分次数也要回滚（2 → 1），并留下待同步日志
      final stat = await (db.select(db.userStudyDailyStats)
            ..where((t) => t.userId.equals('u1')))
          .getSingle();
      expect(stat.reviewCount, 1, reason: '删掉 1 条重复日志，当日 review_count 必须回滚 1');
      expect(
        syncLogs.map((l) => '${l.operate}|${l.tblName}'),
        contains('UPDATE|userStudyDailyStats'),
      );

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, 58);
    } finally {
      await db.close();
      MyDatabase.setInstanceForTesting(null);
    }
  });

  test('v56 → v57: 修复自身抛异常时不得删库重建, 且版本照常推进到最新版', () async {
    // 同一用户两本同名「已掌握」词书 → DictsDao.findUserMasteredDict 抛「核心数据异常」，
    // 而该查询正好发生在修复删掉重复日志之后。若异常冒泡到外层 catch，
    // 整库会被删光重建 —— 一次纯清理把用户本地数据全部抹掉，这个代价不可接受。
    seedV51Fixture(duplicateMasteredDicts: true);

    final db = MyDatabase(NativeDatabase(dbFile));
    MyDatabase.setInstanceForTesting(db);
    try {
      final user = await db.usersDao.getUserById('u1');
      expect(user, isNotNull, reason: '修复失败绝不能触发删库重建');
      expect(user!.masteredWordsCount, 1000);

      // 两本「已掌握」词书还在（删库重建会连它们一起清掉）
      expect((await db.select(db.dicts).get()).length, 2);

      // 修复在删完重复日志之后才失败 → 整个修复事务回滚：日志、记忆字段、同步日志都原样保留
      final logs = await (db.select(db.learningLogs)..where((l) => l.wordId.equals('dupw'))).get();
      expect(logs.map((l) => l.id), containsAll(['log-real', 'log-dup']));
      final word = await db.learningWordsDao.getById('u1', 'dupw');
      expect(word!.stability, 5.8, reason: '回填必须随事务一起回滚');
      expect(await db.select(db.userDbLogs).get(), isEmpty, reason: '同步日志必须随事务一起回滚');

      // 修复失败也要推进版本，否则每次启动都会重跑同一个必失败的迁移
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, 58);
    } finally {
      await db.close();
      MyDatabase.setInstanceForTesting(null);
    }
  });
}
