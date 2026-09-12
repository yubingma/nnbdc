import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
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
  void seedV51Fixture() {
    final raw = sqlite3.open(dbFile.path);
    raw.execute(_v51UsersDdl);
    raw.execute(_v51LearningWordsDdl);
    raw.execute(
      'INSERT INTO users (id, user_name, game_score, daka_score, learned_days, words_per_day, '
      'daka_day_count, mastered_words_count, cow_dung, throw_dice_chance, '
      'continuous_daka_day_count, max_continuous_daka_day_count, create_time, update_time) '
      "VALUES ('u1', 'tester', 0, 0, 10, 20, 5, 1000, 0, 0, 3, 21, 1, 1)",
    );
    raw.execute('PRAGMA user_version = 51');
    raw.dispose();
  }

  test('v51 → 最新版: 逐级补齐列且不丢用户数据', () async {
    seedV51Fixture();

    final db = MyDatabase(NativeDatabase(dbFile));
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

      // v52 → v53: learning_words 补上加餐标记列, 且历史数据一律为非加餐
      final learningWordColumns = await db.customSelect("PRAGMA table_info('learning_words')").get();
      expect(
        learningWordColumns.map((row) => row.read<String>('name')),
        contains('is_extra'),
      );

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, 53);
    } finally {
      await db.close();
    }
  });
}
