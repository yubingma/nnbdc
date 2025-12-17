-- 数据库升级脚本：将索引/外键/唯一约束名字改为严格 snake_case
-- 日期：2025-12-17
-- 来源：自动扫描 /tmp/bdc.sql 生成
-- 说明：可重复执行；仅当旧名存在且新名不存在时才执行
-- 注意：外键约束名的“重命名”通过 DROP + ADD 实现（会短暂移除外键后再加回）

-- ===== 索引/唯一索引改名（RENAME INDEX） =====
-- study_group_grade: INDEX UK_grr4fesaas4otr2jq0t2xh7ye -> uk_grr4fesaas4otr2jq0t2xh7ye
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND BINARY INDEX_NAME = 'UK_grr4fesaas4otr2jq0t2xh7ye')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND BINARY INDEX_NAME = 'uk_grr4fesaas4otr2jq0t2xh7ye'),
    'ALTER TABLE `study_group_grade` RENAME INDEX `UK_grr4fesaas4otr2jq0t2xh7ye` TO `uk_grr4fesaas4otr2jq0t2xh7ye`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- cigen_word_link: INDEX FKfg6o4pg8ran0btsx0fl4v53wt -> fkfg6o4pg8ran0btsx0fl4v53wt
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY INDEX_NAME = 'FKfg6o4pg8ran0btsx0fl4v53wt')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY INDEX_NAME = 'fkfg6o4pg8ran0btsx0fl4v53wt'),
    'ALTER TABLE `cigen_word_link` RENAME INDEX `FKfg6o4pg8ran0btsx0fl4v53wt` TO `fkfg6o4pg8ran0btsx0fl4v53wt`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_group: INDEX FKam1kwdtewl5mj4w24i0vjsgvr -> fkam1kwdtewl5mj4w24i0vjsgvr
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND BINARY INDEX_NAME = 'FKam1kwdtewl5mj4w24i0vjsgvr')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND BINARY INDEX_NAME = 'fkam1kwdtewl5mj4w24i0vjsgvr'),
    'ALTER TABLE `dict_group` RENAME INDEX `FKam1kwdtewl5mj4w24i0vjsgvr` TO `fkam1kwdtewl5mj4w24i0vjsgvr`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- game_hall: INDEX FKbb8bsyk402u3fxe0vnv2ecp12 -> fkbb8bsyk402u3fxe0vnv2ecp12
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY INDEX_NAME = 'FKbb8bsyk402u3fxe0vnv2ecp12')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY INDEX_NAME = 'fkbb8bsyk402u3fxe0vnv2ecp12'),
    'ALTER TABLE `game_hall` RENAME INDEX `FKbb8bsyk402u3fxe0vnv2ecp12` TO `fkbb8bsyk402u3fxe0vnv2ecp12`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- game_hall: INDEX FKs184ekmq8ct8x9etyonngejo4 -> fks184ekmq8ct8x9etyonngejo4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY INDEX_NAME = 'FKs184ekmq8ct8x9etyonngejo4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY INDEX_NAME = 'fks184ekmq8ct8x9etyonngejo4'),
    'ALTER TABLE `game_hall` RENAME INDEX `FKs184ekmq8ct8x9etyonngejo4` TO `fks184ekmq8ct8x9etyonngejo4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- similar_word: INDEX FK1mqflio4f1yp8ety4wsa8naku -> fk1mqflio4f1yp8ety4wsa8naku
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY INDEX_NAME = 'FK1mqflio4f1yp8ety4wsa8naku')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY INDEX_NAME = 'fk1mqflio4f1yp8ety4wsa8naku'),
    'ALTER TABLE `similar_word` RENAME INDEX `FK1mqflio4f1yp8ety4wsa8naku` TO `fk1mqflio4f1yp8ety4wsa8naku`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- similar_word: INDEX FKcwlj8g7yxqfqag6sbcypi705a -> fkcwlj8g7yxqfqag6sbcypi705a
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY INDEX_NAME = 'FKcwlj8g7yxqfqag6sbcypi705a')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY INDEX_NAME = 'fkcwlj8g7yxqfqag6sbcypi705a'),
    'ALTER TABLE `similar_word` RENAME INDEX `FKcwlj8g7yxqfqag6sbcypi705a` TO `fkcwlj8g7yxqfqag6sbcypi705a`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user: INDEX user_email_IDX -> user_email_idx
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY INDEX_NAME = 'user_email_IDX')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY INDEX_NAME = 'user_email_idx'),
    'ALTER TABLE `user` RENAME INDEX `user_email_IDX` TO `user_email_idx`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user: INDEX FKefu5f2ioj2qy2bycuh6g3wbkd -> fkefu5f2ioj2qy2bycuh6g3wbkd
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY INDEX_NAME = 'FKefu5f2ioj2qy2bycuh6g3wbkd')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY INDEX_NAME = 'fkefu5f2ioj2qy2bycuh6g3wbkd'),
    'ALTER TABLE `user` RENAME INDEX `FKefu5f2ioj2qy2bycuh6g3wbkd` TO `fkefu5f2ioj2qy2bycuh6g3wbkd`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user: INDEX FK6lqwkmrxl04j2k3d2oqysgwvm -> fk6lqwkmrxl04j2k3d2oqysgwvm
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY INDEX_NAME = 'FK6lqwkmrxl04j2k3d2oqysgwvm')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY INDEX_NAME = 'fk6lqwkmrxl04j2k3d2oqysgwvm'),
    'ALTER TABLE `user` RENAME INDEX `FK6lqwkmrxl04j2k3d2oqysgwvm` TO `fk6lqwkmrxl04j2k3d2oqysgwvm`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_cow_dung_log: INDEX FKp01eygbwkg91uujcjasrhbu2y -> fkp01eygbwkg91uujcjasrhbu2y
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND BINARY INDEX_NAME = 'FKp01eygbwkg91uujcjasrhbu2y')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND BINARY INDEX_NAME = 'fkp01eygbwkg91uujcjasrhbu2y'),
    'ALTER TABLE `user_cow_dung_log` RENAME INDEX `FKp01eygbwkg91uujcjasrhbu2y` TO `fkp01eygbwkg91uujcjasrhbu2y`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_game: INDEX FKe1j2if58j0qgke4numextbw8a -> fke1j2if58j0qgke4numextbw8a
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND BINARY INDEX_NAME = 'FKe1j2if58j0qgke4numextbw8a')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND BINARY INDEX_NAME = 'fke1j2if58j0qgke4numextbw8a'),
    'ALTER TABLE `user_game` RENAME INDEX `FKe1j2if58j0qgke4numextbw8a` TO `fke1j2if58j0qgke4numextbw8a`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_score_log: INDEX FKn1b5wicvnceas08ju14uk3qqw -> fkn1b5wicvnceas08ju14uk3qqw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND BINARY INDEX_NAME = 'FKn1b5wicvnceas08ju14uk3qqw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND BINARY INDEX_NAME = 'fkn1b5wicvnceas08ju14uk3qqw'),
    'ALTER TABLE `user_score_log` RENAME INDEX `FKn1b5wicvnceas08ju14uk3qqw` TO `fkn1b5wicvnceas08ju14uk3qqw`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_snapshot_daily: INDEX FKm48fwdudlv10kcn0wafvdves3 -> fkm48fwdudlv10kcn0wafvdves3
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND BINARY INDEX_NAME = 'FKm48fwdudlv10kcn0wafvdves3')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND BINARY INDEX_NAME = 'fkm48fwdudlv10kcn0wafvdves3'),
    'ALTER TABLE `user_snapshot_daily` RENAME INDEX `FKm48fwdudlv10kcn0wafvdves3` TO `fkm48fwdudlv10kcn0wafvdves3`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_study_step: INDEX FKkb5mbew7a6hawfub12aotlpbh -> fkkb5mbew7a6hawfub12aotlpbh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND BINARY INDEX_NAME = 'FKkb5mbew7a6hawfub12aotlpbh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND BINARY INDEX_NAME = 'fkkb5mbew7a6hawfub12aotlpbh'),
    'ALTER TABLE `user_study_step` RENAME INDEX `FKkb5mbew7a6hawfub12aotlpbh` TO `fkkb5mbew7a6hawfub12aotlpbh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_wrong_word: INDEX FKwkw9ln2wtbqtq0e7s5ayti2t -> fkwkw9ln2wtbqtq0e7s5ayti2t
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY INDEX_NAME = 'FKwkw9ln2wtbqtq0e7s5ayti2t')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY INDEX_NAME = 'fkwkw9ln2wtbqtq0e7s5ayti2t'),
    'ALTER TABLE `user_wrong_word` RENAME INDEX `FKwkw9ln2wtbqtq0e7s5ayti2t` TO `fkwkw9ln2wtbqtq0e7s5ayti2t`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_wrong_word: INDEX FKqneibfe99w3ktslncl4vt009k -> fkqneibfe99w3ktslncl4vt009k
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY INDEX_NAME = 'FKqneibfe99w3ktslncl4vt009k')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY INDEX_NAME = 'fkqneibfe99w3ktslncl4vt009k'),
    'ALTER TABLE `user_wrong_word` RENAME INDEX `FKqneibfe99w3ktslncl4vt009k` TO `fkqneibfe99w3ktslncl4vt009k`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- verb_tense: INDEX FKrymhs6cvyoh40cpcslopn98yo -> fkrymhs6cvyoh40cpcslopn98yo
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND BINARY INDEX_NAME = 'FKrymhs6cvyoh40cpcslopn98yo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND BINARY INDEX_NAME = 'fkrymhs6cvyoh40cpcslopn98yo'),
    'ALTER TABLE `verb_tense` RENAME INDEX `FKrymhs6cvyoh40cpcslopn98yo` TO `fkrymhs6cvyoh40cpcslopn98yo`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_additional_info: INDEX FKf3xqffcm8vnaqbucfr5i24yqh -> fkf3xqffcm8vnaqbucfr5i24yqh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY INDEX_NAME = 'FKf3xqffcm8vnaqbucfr5i24yqh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY INDEX_NAME = 'fkf3xqffcm8vnaqbucfr5i24yqh'),
    'ALTER TABLE `word_additional_info` RENAME INDEX `FKf3xqffcm8vnaqbucfr5i24yqh` TO `fkf3xqffcm8vnaqbucfr5i24yqh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_additional_info: INDEX FK5jynq4erw7uwlffv3covsa9oc -> fk5jynq4erw7uwlffv3covsa9oc
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY INDEX_NAME = 'FK5jynq4erw7uwlffv3covsa9oc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY INDEX_NAME = 'fk5jynq4erw7uwlffv3covsa9oc'),
    'ALTER TABLE `word_additional_info` RENAME INDEX `FK5jynq4erw7uwlffv3covsa9oc` TO `fk5jynq4erw7uwlffv3covsa9oc`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_image: INDEX FKcsrc6dqtt1q9907n2w3qcy71v -> fkcsrc6dqtt1q9907n2w3qcy71v
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY INDEX_NAME = 'FKcsrc6dqtt1q9907n2w3qcy71v')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY INDEX_NAME = 'fkcsrc6dqtt1q9907n2w3qcy71v'),
    'ALTER TABLE `word_image` RENAME INDEX `FKcsrc6dqtt1q9907n2w3qcy71v` TO `fkcsrc6dqtt1q9907n2w3qcy71v`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_image: INDEX FK22nlb05j0hk398isouqw9ehbc -> fk22nlb05j0hk398isouqw9ehbc
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY INDEX_NAME = 'FK22nlb05j0hk398isouqw9ehbc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY INDEX_NAME = 'fk22nlb05j0hk398isouqw9ehbc'),
    'ALTER TABLE `word_image` RENAME INDEX `FK22nlb05j0hk398isouqw9ehbc` TO `fk22nlb05j0hk398isouqw9ehbc`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_shortdesc_chinese: INDEX FKtfaryode4etiv5gh8vr47bnbh -> fktfaryode4etiv5gh8vr47bnbh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY INDEX_NAME = 'FKtfaryode4etiv5gh8vr47bnbh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY INDEX_NAME = 'fktfaryode4etiv5gh8vr47bnbh'),
    'ALTER TABLE `word_shortdesc_chinese` RENAME INDEX `FKtfaryode4etiv5gh8vr47bnbh` TO `fktfaryode4etiv5gh8vr47bnbh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_shortdesc_chinese: INDEX FK662626om3lfe5ov2fohxuqpgp -> fk662626om3lfe5ov2fohxuqpgp
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY INDEX_NAME = 'FK662626om3lfe5ov2fohxuqpgp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY INDEX_NAME = 'fk662626om3lfe5ov2fohxuqpgp'),
    'ALTER TABLE `word_shortdesc_chinese` RENAME INDEX `FK662626om3lfe5ov2fohxuqpgp` TO `fk662626om3lfe5ov2fohxuqpgp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- article: INDEX FKdw5d9vdw43e3nvtpqk8l4iitp -> fkdw5d9vdw43e3nvtpqk8l4iitp
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND BINARY INDEX_NAME = 'FKdw5d9vdw43e3nvtpqk8l4iitp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND BINARY INDEX_NAME = 'fkdw5d9vdw43e3nvtpqk8l4iitp'),
    'ALTER TABLE `article` RENAME INDEX `FKdw5d9vdw43e3nvtpqk8l4iitp` TO `fkdw5d9vdw43e3nvtpqk8l4iitp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- daka: INDEX FK9lw3569kklr2aem8j3lgooofo -> fk9lw3569kklr2aem8j3lgooofo
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND BINARY INDEX_NAME = 'FK9lw3569kklr2aem8j3lgooofo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND BINARY INDEX_NAME = 'fk9lw3569kklr2aem8j3lgooofo'),
    'ALTER TABLE `daka` RENAME INDEX `FK9lw3569kklr2aem8j3lgooofo` TO `fk9lw3569kklr2aem8j3lgooofo`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict: INDEX dict_owner_IDX -> dict_owner_idx
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND BINARY INDEX_NAME = 'dict_owner_IDX')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND BINARY INDEX_NAME = 'dict_owner_idx'),
    'ALTER TABLE `dict` RENAME INDEX `dict_owner_IDX` TO `dict_owner_idx`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict: INDEX FKba1lo3o2pqjwuhuo55a173tpn -> fkba1lo3o2pqjwuhuo55a173tpn
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND BINARY INDEX_NAME = 'FKba1lo3o2pqjwuhuo55a173tpn')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND BINARY INDEX_NAME = 'fkba1lo3o2pqjwuhuo55a173tpn'),
    'ALTER TABLE `dict` RENAME INDEX `FKba1lo3o2pqjwuhuo55a173tpn` TO `fkba1lo3o2pqjwuhuo55a173tpn`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_word: INDEX FKoocgndgdxfsmi9l22c779ve5f -> fkoocgndgdxfsmi9l22c779ve5f
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY INDEX_NAME = 'FKoocgndgdxfsmi9l22c779ve5f')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY INDEX_NAME = 'fkoocgndgdxfsmi9l22c779ve5f'),
    'ALTER TABLE `dict_word` RENAME INDEX `FKoocgndgdxfsmi9l22c779ve5f` TO `fkoocgndgdxfsmi9l22c779ve5f`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- error_report: INDEX FKt63m0vobg7664cjmoyuwngl2r -> fkt63m0vobg7664cjmoyuwngl2r
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND BINARY INDEX_NAME = 'FKt63m0vobg7664cjmoyuwngl2r')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND BINARY INDEX_NAME = 'fkt63m0vobg7664cjmoyuwngl2r'),
    'ALTER TABLE `error_report` RENAME INDEX `FKt63m0vobg7664cjmoyuwngl2r` TO `fkt63m0vobg7664cjmoyuwngl2r`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_and_manager_link: INDEX FK4rgldqqyj2v6ko5fb3j4h00hw -> fk4rgldqqyj2v6ko5fb3j4h00hw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY INDEX_NAME = 'FK4rgldqqyj2v6ko5fb3j4h00hw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY INDEX_NAME = 'fk4rgldqqyj2v6ko5fb3j4h00hw'),
    'ALTER TABLE `forum_and_manager_link` RENAME INDEX `FK4rgldqqyj2v6ko5fb3j4h00hw` TO `fk4rgldqqyj2v6ko5fb3j4h00hw`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_and_manager_link: INDEX FKm2ne0gyp8to1iltn9y5xatn5g -> fkm2ne0gyp8to1iltn9y5xatn5g
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY INDEX_NAME = 'FKm2ne0gyp8to1iltn9y5xatn5g')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY INDEX_NAME = 'fkm2ne0gyp8to1iltn9y5xatn5g'),
    'ALTER TABLE `forum_and_manager_link` RENAME INDEX `FKm2ne0gyp8to1iltn9y5xatn5g` TO `fkm2ne0gyp8to1iltn9y5xatn5g`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post: INDEX FKh0s5a90088gbywb9u9j5fase4 -> fkh0s5a90088gbywb9u9j5fase4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY INDEX_NAME = 'FKh0s5a90088gbywb9u9j5fase4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY INDEX_NAME = 'fkh0s5a90088gbywb9u9j5fase4'),
    'ALTER TABLE `forum_post` RENAME INDEX `FKh0s5a90088gbywb9u9j5fase4` TO `fkh0s5a90088gbywb9u9j5fase4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post: INDEX FK89ba00sxrqhbgl7cgwt6y0tux -> fk89ba00sxrqhbgl7cgwt6y0tux
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY INDEX_NAME = 'FK89ba00sxrqhbgl7cgwt6y0tux')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY INDEX_NAME = 'fk89ba00sxrqhbgl7cgwt6y0tux'),
    'ALTER TABLE `forum_post` RENAME INDEX `FK89ba00sxrqhbgl7cgwt6y0tux` TO `fk89ba00sxrqhbgl7cgwt6y0tux`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post_reply: INDEX FKsmolky8m77uf3aygscwtlh7 -> fksmolky8m77uf3aygscwtlh7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY INDEX_NAME = 'FKsmolky8m77uf3aygscwtlh7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY INDEX_NAME = 'fksmolky8m77uf3aygscwtlh7'),
    'ALTER TABLE `forum_post_reply` RENAME INDEX `FKsmolky8m77uf3aygscwtlh7` TO `fksmolky8m77uf3aygscwtlh7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post_reply: INDEX FKctt5g9ionoo960lak0p7ss6ou -> fkctt5g9ionoo960lak0p7ss6ou
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY INDEX_NAME = 'FKctt5g9ionoo960lak0p7ss6ou')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY INDEX_NAME = 'fkctt5g9ionoo960lak0p7ss6ou'),
    'ALTER TABLE `forum_post_reply` RENAME INDEX `FKctt5g9ionoo960lak0p7ss6ou` TO `fkctt5g9ionoo960lak0p7ss6ou`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- group_and_dict_link: INDEX FKhuoc8hxjs2c8w1fgickojg6ff -> fkhuoc8hxjs2c8w1fgickojg6ff
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY INDEX_NAME = 'FKhuoc8hxjs2c8w1fgickojg6ff')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY INDEX_NAME = 'fkhuoc8hxjs2c8w1fgickojg6ff'),
    'ALTER TABLE `group_and_dict_link` RENAME INDEX `FKhuoc8hxjs2c8w1fgickojg6ff` TO `fkhuoc8hxjs2c8w1fgickojg6ff`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- group_and_dict_link: INDEX FKanvwboyqdce5mb41j8q4qly3c -> fkanvwboyqdce5mb41j8q4qly3c
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY INDEX_NAME = 'FKanvwboyqdce5mb41j8q4qly3c')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY INDEX_NAME = 'fkanvwboyqdce5mb41j8q4qly3c'),
    'ALTER TABLE `group_and_dict_link` RENAME INDEX `FKanvwboyqdce5mb41j8q4qly3c` TO `fkanvwboyqdce5mb41j8q4qly3c`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- info_vote_log: INDEX FKnyxodwmjasis1v8c04xsen7dh -> fknyxodwmjasis1v8c04xsen7dh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY INDEX_NAME = 'FKnyxodwmjasis1v8c04xsen7dh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY INDEX_NAME = 'fknyxodwmjasis1v8c04xsen7dh'),
    'ALTER TABLE `info_vote_log` RENAME INDEX `FKnyxodwmjasis1v8c04xsen7dh` TO `fknyxodwmjasis1v8c04xsen7dh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_dict: INDEX FKs6prwtgob6wmhxysa8bu1096r -> fks6prwtgob6wmhxysa8bu1096r
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY INDEX_NAME = 'FKs6prwtgob6wmhxysa8bu1096r')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY INDEX_NAME = 'fks6prwtgob6wmhxysa8bu1096r'),
    'ALTER TABLE `learning_dict` RENAME INDEX `FKs6prwtgob6wmhxysa8bu1096r` TO `fks6prwtgob6wmhxysa8bu1096r`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_dict: INDEX FKpiu1chqdc7gn2bchpkxcbdqu6 -> fkpiu1chqdc7gn2bchpkxcbdqu6
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY INDEX_NAME = 'FKpiu1chqdc7gn2bchpkxcbdqu6')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY INDEX_NAME = 'fkpiu1chqdc7gn2bchpkxcbdqu6'),
    'ALTER TABLE `learning_dict` RENAME INDEX `FKpiu1chqdc7gn2bchpkxcbdqu6` TO `fkpiu1chqdc7gn2bchpkxcbdqu6`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- login_log: INDEX FK9auh6uhsrknd75ipjypyyha90 -> fk9auh6uhsrknd75ipjypyyha90
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND BINARY INDEX_NAME = 'FK9auh6uhsrknd75ipjypyyha90')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND BINARY INDEX_NAME = 'fk9auh6uhsrknd75ipjypyyha90'),
    'ALTER TABLE `login_log` RENAME INDEX `FK9auh6uhsrknd75ipjypyyha90` TO `fk9auh6uhsrknd75ipjypyyha90`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- mastered_word: INDEX mastered_word_userId_IDX -> mastered_word_user_id_idx
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND BINARY INDEX_NAME = 'mastered_word_userId_IDX')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND BINARY INDEX_NAME = 'mastered_word_user_id_idx'),
    'ALTER TABLE `mastered_word` RENAME INDEX `mastered_word_userId_IDX` TO `mastered_word_user_id_idx`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- meaning_item: INDEX FKbq1kwqm7l14nowpnkgyct7qmb -> fkbq1kwqm7l14nowpnkgyct7qmb
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY INDEX_NAME = 'FKbq1kwqm7l14nowpnkgyct7qmb')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY INDEX_NAME = 'fkbq1kwqm7l14nowpnkgyct7qmb'),
    'ALTER TABLE `meaning_item` RENAME INDEX `FKbq1kwqm7l14nowpnkgyct7qmb` TO `fkbq1kwqm7l14nowpnkgyct7qmb`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- meaning_item: INDEX FKhajsfsxiyna9xuo9i974u8v07 -> fkhajsfsxiyna9xuo9i974u8v07
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY INDEX_NAME = 'FKhajsfsxiyna9xuo9i974u8v07')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY INDEX_NAME = 'fkhajsfsxiyna9xuo9i974u8v07'),
    'ALTER TABLE `meaning_item` RENAME INDEX `FKhajsfsxiyna9xuo9i974u8v07` TO `fkhajsfsxiyna9xuo9i974u8v07`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- msg: INDEX FKpwao1csk2fiqn8x0taf5n4lxp -> fkpwao1csk2fiqn8x0taf5n4lxp
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY INDEX_NAME = 'FKpwao1csk2fiqn8x0taf5n4lxp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY INDEX_NAME = 'fkpwao1csk2fiqn8x0taf5n4lxp'),
    'ALTER TABLE `msg` RENAME INDEX `FKpwao1csk2fiqn8x0taf5n4lxp` TO `fkpwao1csk2fiqn8x0taf5n4lxp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- msg: INDEX FKduaesr28u3xkjgacqyp6f9k69 -> fkduaesr28u3xkjgacqyp6f9k69
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY INDEX_NAME = 'FKduaesr28u3xkjgacqyp6f9k69')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY INDEX_NAME = 'fkduaesr28u3xkjgacqyp6f9k69'),
    'ALTER TABLE `msg` RENAME INDEX `FKduaesr28u3xkjgacqyp6f9k69` TO `fkduaesr28u3xkjgacqyp6f9k69`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence: INDEX sentence_FK -> sentence_fk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY INDEX_NAME = 'sentence_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY INDEX_NAME = 'sentence_fk'),
    'ALTER TABLE `sentence` RENAME INDEX `sentence_FK` TO `sentence_fk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence: INDEX sentence_meaning_item_FK -> sentence_meaning_item_fk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY INDEX_NAME = 'sentence_meaning_item_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY INDEX_NAME = 'sentence_meaning_item_fk'),
    'ALTER TABLE `sentence` RENAME INDEX `sentence_meaning_item_FK` TO `sentence_meaning_item_fk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese: INDEX FK1ea8mppmrgwbn1gcmn0n4s95n -> fk1ea8mppmrgwbn1gcmn0n4s95n
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY INDEX_NAME = 'FK1ea8mppmrgwbn1gcmn0n4s95n')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY INDEX_NAME = 'fk1ea8mppmrgwbn1gcmn0n4s95n'),
    'ALTER TABLE `sentence_chinese` RENAME INDEX `FK1ea8mppmrgwbn1gcmn0n4s95n` TO `fk1ea8mppmrgwbn1gcmn0n4s95n`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese: INDEX FK4qkl23fg27sp450b9h3n7xnwx -> fk4qkl23fg27sp450b9h3n7xnwx
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY INDEX_NAME = 'FK4qkl23fg27sp450b9h3n7xnwx')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY INDEX_NAME = 'fk4qkl23fg27sp450b9h3n7xnwx'),
    'ALTER TABLE `sentence_chinese` RENAME INDEX `FK4qkl23fg27sp450b9h3n7xnwx` TO `fk4qkl23fg27sp450b9h3n7xnwx`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese_remark: INDEX FK9eseuj1b3lp9r0cp52hl524i7 -> fk9eseuj1b3lp9r0cp52hl524i7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY INDEX_NAME = 'FK9eseuj1b3lp9r0cp52hl524i7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY INDEX_NAME = 'fk9eseuj1b3lp9r0cp52hl524i7'),
    'ALTER TABLE `sentence_chinese_remark` RENAME INDEX `FK9eseuj1b3lp9r0cp52hl524i7` TO `fk9eseuj1b3lp9r0cp52hl524i7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese_remark: INDEX FKqb6gj27jt2kffko46xcctg0u6 -> fkqb6gj27jt2kffko46xcctg0u6
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY INDEX_NAME = 'FKqb6gj27jt2kffko46xcctg0u6')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY INDEX_NAME = 'fkqb6gj27jt2kffko46xcctg0u6'),
    'ALTER TABLE `sentence_chinese_remark` RENAME INDEX `FKqb6gj27jt2kffko46xcctg0u6` TO `fkqb6gj27jt2kffko46xcctg0u6`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_update_notify: INDEX sentence_update_notify_FK -> sentence_update_notify_fk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY INDEX_NAME = 'sentence_update_notify_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY INDEX_NAME = 'sentence_update_notify_fk'),
    'ALTER TABLE `sentence_update_notify` RENAME INDEX `sentence_update_notify_FK` TO `sentence_update_notify_fk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group: INDEX UK_jpg0rl0cauvsfe6doei229ae1 -> uk_jpg0rl0cauvsfe6doei229ae1
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY INDEX_NAME = 'UK_jpg0rl0cauvsfe6doei229ae1')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY INDEX_NAME = 'uk_jpg0rl0cauvsfe6doei229ae1'),
    'ALTER TABLE `study_group` RENAME INDEX `UK_jpg0rl0cauvsfe6doei229ae1` TO `uk_jpg0rl0cauvsfe6doei229ae1`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group: INDEX FKfml3yg6yg9a2xi45w4vx7dqfb -> fkfml3yg6yg9a2xi45w4vx7dqfb
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY INDEX_NAME = 'FKfml3yg6yg9a2xi45w4vx7dqfb')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY INDEX_NAME = 'fkfml3yg6yg9a2xi45w4vx7dqfb'),
    'ALTER TABLE `study_group` RENAME INDEX `FKfml3yg6yg9a2xi45w4vx7dqfb` TO `fkfml3yg6yg9a2xi45w4vx7dqfb`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group: INDEX FK36s0562yu4gydy3xr28u95eqd -> fk36s0562yu4gydy3xr28u95eqd
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY INDEX_NAME = 'FK36s0562yu4gydy3xr28u95eqd')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY INDEX_NAME = 'fk36s0562yu4gydy3xr28u95eqd'),
    'ALTER TABLE `study_group` RENAME INDEX `FK36s0562yu4gydy3xr28u95eqd` TO `fk36s0562yu4gydy3xr28u95eqd`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_manager_link: INDEX FKgfviie87tlf3c34ipmx31ynj7 -> fkgfviie87tlf3c34ipmx31ynj7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY INDEX_NAME = 'FKgfviie87tlf3c34ipmx31ynj7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY INDEX_NAME = 'fkgfviie87tlf3c34ipmx31ynj7'),
    'ALTER TABLE `study_group_and_manager_link` RENAME INDEX `FKgfviie87tlf3c34ipmx31ynj7` TO `fkgfviie87tlf3c34ipmx31ynj7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_manager_link: INDEX FKrdflptnxblu6aa5r7s9747ko4 -> fkrdflptnxblu6aa5r7s9747ko4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY INDEX_NAME = 'FKrdflptnxblu6aa5r7s9747ko4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY INDEX_NAME = 'fkrdflptnxblu6aa5r7s9747ko4'),
    'ALTER TABLE `study_group_and_manager_link` RENAME INDEX `FKrdflptnxblu6aa5r7s9747ko4` TO `fkrdflptnxblu6aa5r7s9747ko4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_user_link: INDEX FK66ybol3y7m0xgvon3hovu9ifv -> fk66ybol3y7m0xgvon3hovu9ifv
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY INDEX_NAME = 'FK66ybol3y7m0xgvon3hovu9ifv')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY INDEX_NAME = 'fk66ybol3y7m0xgvon3hovu9ifv'),
    'ALTER TABLE `study_group_and_user_link` RENAME INDEX `FK66ybol3y7m0xgvon3hovu9ifv` TO `fk66ybol3y7m0xgvon3hovu9ifv`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_user_link: INDEX FKs1c5cfbgl89yn2p955v7sugj7 -> fks1c5cfbgl89yn2p955v7sugj7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY INDEX_NAME = 'FKs1c5cfbgl89yn2p955v7sugj7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY INDEX_NAME = 'fks1c5cfbgl89yn2p955v7sugj7'),
    'ALTER TABLE `study_group_and_user_link` RENAME INDEX `FKs1c5cfbgl89yn2p955v7sugj7` TO `fks1c5cfbgl89yn2p955v7sugj7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post: INDEX FKc3t23fo2d1n4cqsq5ct92vtjn -> fkc3t23fo2d1n4cqsq5ct92vtjn
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY INDEX_NAME = 'FKc3t23fo2d1n4cqsq5ct92vtjn')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY INDEX_NAME = 'fkc3t23fo2d1n4cqsq5ct92vtjn'),
    'ALTER TABLE `study_group_post` RENAME INDEX `FKc3t23fo2d1n4cqsq5ct92vtjn` TO `fkc3t23fo2d1n4cqsq5ct92vtjn`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post: INDEX FKmy0w3ae9nui45ii8gg5ftx03y -> fkmy0w3ae9nui45ii8gg5ftx03y
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY INDEX_NAME = 'FKmy0w3ae9nui45ii8gg5ftx03y')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY INDEX_NAME = 'fkmy0w3ae9nui45ii8gg5ftx03y'),
    'ALTER TABLE `study_group_post` RENAME INDEX `FKmy0w3ae9nui45ii8gg5ftx03y` TO `fkmy0w3ae9nui45ii8gg5ftx03y`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post_reply: INDEX FK302iba0o0rgoegvo0en7a05jl -> fk302iba0o0rgoegvo0en7a05jl
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY INDEX_NAME = 'FK302iba0o0rgoegvo0en7a05jl')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY INDEX_NAME = 'fk302iba0o0rgoegvo0en7a05jl'),
    'ALTER TABLE `study_group_post_reply` RENAME INDEX `FK302iba0o0rgoegvo0en7a05jl` TO `fk302iba0o0rgoegvo0en7a05jl`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post_reply: INDEX FKlbwltcdwo4x4hlkbl51fpph -> fklbwltcdwo4x4hlkbl51fpph
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY INDEX_NAME = 'FKlbwltcdwo4x4hlkbl51fpph')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY INDEX_NAME = 'fklbwltcdwo4x4hlkbl51fpph'),
    'ALTER TABLE `study_group_post_reply` RENAME INDEX `FKlbwltcdwo4x4hlkbl51fpph` TO `fklbwltcdwo4x4hlkbl51fpph`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_snapshot_daily: INDEX FKs0e3efs4xyt73agwc6e96wjc4 -> fks0e3efs4xyt73agwc6e96wjc4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND BINARY INDEX_NAME = 'FKs0e3efs4xyt73agwc6e96wjc4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND BINARY INDEX_NAME = 'fks0e3efs4xyt73agwc6e96wjc4'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME INDEX `FKs0e3efs4xyt73agwc6e96wjc4` TO `fks0e3efs4xyt73agwc6e96wjc4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_sentence: INDEX FKaqa9an1x12g7s6u92i30raln7 -> fkaqa9an1x12g7s6u92i30raln7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY INDEX_NAME = 'FKaqa9an1x12g7s6u92i30raln7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY INDEX_NAME = 'fkaqa9an1x12g7s6u92i30raln7'),
    'ALTER TABLE `word_sentence` RENAME INDEX `FKaqa9an1x12g7s6u92i30raln7` TO `fkaqa9an1x12g7s6u92i30raln7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: INDEX FKn0s3foajghecveph3do4wqngk -> fkn0s3foajghecveph3do4wqngk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'FKn0s3foajghecveph3do4wqngk')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'fkn0s3foajghecveph3do4wqngk'),
    'ALTER TABLE `event` RENAME INDEX `FKn0s3foajghecveph3do4wqngk` TO `fkn0s3foajghecveph3do4wqngk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: INDEX FKe4y90yg6c4gxbdwn2w9lgcb98 -> fke4y90yg6c4gxbdwn2w9lgcb98
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'FKe4y90yg6c4gxbdwn2w9lgcb98')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'fke4y90yg6c4gxbdwn2w9lgcb98'),
    'ALTER TABLE `event` RENAME INDEX `FKe4y90yg6c4gxbdwn2w9lgcb98` TO `fke4y90yg6c4gxbdwn2w9lgcb98`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: INDEX FK8up0cm0j7flyds8mljh3wslcs -> fk8up0cm0j7flyds8mljh3wslcs
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'FK8up0cm0j7flyds8mljh3wslcs')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'fk8up0cm0j7flyds8mljh3wslcs'),
    'ALTER TABLE `event` RENAME INDEX `FK8up0cm0j7flyds8mljh3wslcs` TO `fk8up0cm0j7flyds8mljh3wslcs`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: INDEX FKcaqnogrpoabtlfqf9h4wuxybk -> fkcaqnogrpoabtlfqf9h4wuxybk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'FKcaqnogrpoabtlfqf9h4wuxybk')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'fkcaqnogrpoabtlfqf9h4wuxybk'),
    'ALTER TABLE `event` RENAME INDEX `FKcaqnogrpoabtlfqf9h4wuxybk` TO `fkcaqnogrpoabtlfqf9h4wuxybk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: INDEX FK8y4063ul9igji7dsmq61t7pg3 -> fk8y4063ul9igji7dsmq61t7pg3
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'FK8y4063ul9igji7dsmq61t7pg3')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY INDEX_NAME = 'fk8y4063ul9igji7dsmq61t7pg3'),
    'ALTER TABLE `event` RENAME INDEX `FK8y4063ul9igji7dsmq61t7pg3` TO `fk8y4063ul9igji7dsmq61t7pg3`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- ===== 外键约束名改名（DROP + ADD CONSTRAINT） =====
-- cigen_word_link: FOREIGN KEY FKfg6o4pg8ran0btsx0fl4v53wt -> fkfg6o4pg8ran0btsx0fl4v53wt
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY CONSTRAINT_NAME = 'FKfg6o4pg8ran0btsx0fl4v53wt')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY CONSTRAINT_NAME = 'fkfg6o4pg8ran0btsx0fl4v53wt'),
    'ALTER TABLE `cigen_word_link` DROP FOREIGN KEY `FKfg6o4pg8ran0btsx0fl4v53wt`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY CONSTRAINT_NAME = 'fkfg6o4pg8ran0btsx0fl4v53wt')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link'),
    'ALTER TABLE `cigen_word_link` ADD CONSTRAINT `fkfg6o4pg8ran0btsx0fl4v53wt` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- cigen_word_link: FOREIGN KEY FKsbo1vxf9xm27mmqfeuytgjm8r -> fksbo1vxf9xm27mmqfeuytgjm8r
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY CONSTRAINT_NAME = 'FKsbo1vxf9xm27mmqfeuytgjm8r')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY CONSTRAINT_NAME = 'fksbo1vxf9xm27mmqfeuytgjm8r'),
    'ALTER TABLE `cigen_word_link` DROP FOREIGN KEY `FKsbo1vxf9xm27mmqfeuytgjm8r`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND BINARY CONSTRAINT_NAME = 'fksbo1vxf9xm27mmqfeuytgjm8r')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link'),
    'ALTER TABLE `cigen_word_link` ADD CONSTRAINT `fksbo1vxf9xm27mmqfeuytgjm8r` FOREIGN KEY (`cigen_id`) REFERENCES `cigen` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_group: FOREIGN KEY FKam1kwdtewl5mj4w24i0vjsgvr -> fkam1kwdtewl5mj4w24i0vjsgvr
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND BINARY CONSTRAINT_NAME = 'FKam1kwdtewl5mj4w24i0vjsgvr')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND BINARY CONSTRAINT_NAME = 'fkam1kwdtewl5mj4w24i0vjsgvr'),
    'ALTER TABLE `dict_group` DROP FOREIGN KEY `FKam1kwdtewl5mj4w24i0vjsgvr`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND BINARY CONSTRAINT_NAME = 'fkam1kwdtewl5mj4w24i0vjsgvr')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group'),
    'ALTER TABLE `dict_group` ADD CONSTRAINT `fkam1kwdtewl5mj4w24i0vjsgvr` FOREIGN KEY (`parent_id`) REFERENCES `dict_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- game_hall: FOREIGN KEY FKbb8bsyk402u3fxe0vnv2ecp12 -> fkbb8bsyk402u3fxe0vnv2ecp12
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY CONSTRAINT_NAME = 'FKbb8bsyk402u3fxe0vnv2ecp12')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY CONSTRAINT_NAME = 'fkbb8bsyk402u3fxe0vnv2ecp12'),
    'ALTER TABLE `game_hall` DROP FOREIGN KEY `FKbb8bsyk402u3fxe0vnv2ecp12`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY CONSTRAINT_NAME = 'fkbb8bsyk402u3fxe0vnv2ecp12')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall'),
    'ALTER TABLE `game_hall` ADD CONSTRAINT `fkbb8bsyk402u3fxe0vnv2ecp12` FOREIGN KEY (`dict_group_id`) REFERENCES `dict_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- game_hall: FOREIGN KEY FKs184ekmq8ct8x9etyonngejo4 -> fks184ekmq8ct8x9etyonngejo4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY CONSTRAINT_NAME = 'FKs184ekmq8ct8x9etyonngejo4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY CONSTRAINT_NAME = 'fks184ekmq8ct8x9etyonngejo4'),
    'ALTER TABLE `game_hall` DROP FOREIGN KEY `FKs184ekmq8ct8x9etyonngejo4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND BINARY CONSTRAINT_NAME = 'fks184ekmq8ct8x9etyonngejo4')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall'),
    'ALTER TABLE `game_hall` ADD CONSTRAINT `fks184ekmq8ct8x9etyonngejo4` FOREIGN KEY (`hall_group_id`) REFERENCES `hall_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- similar_word: FOREIGN KEY FK1mqflio4f1yp8ety4wsa8naku -> fk1mqflio4f1yp8ety4wsa8naku
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY CONSTRAINT_NAME = 'FK1mqflio4f1yp8ety4wsa8naku')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY CONSTRAINT_NAME = 'fk1mqflio4f1yp8ety4wsa8naku'),
    'ALTER TABLE `similar_word` DROP FOREIGN KEY `FK1mqflio4f1yp8ety4wsa8naku`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY CONSTRAINT_NAME = 'fk1mqflio4f1yp8ety4wsa8naku')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word'),
    'ALTER TABLE `similar_word` ADD CONSTRAINT `fk1mqflio4f1yp8ety4wsa8naku` FOREIGN KEY (`similar_word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- similar_word: FOREIGN KEY FKcwlj8g7yxqfqag6sbcypi705a -> fkcwlj8g7yxqfqag6sbcypi705a
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY CONSTRAINT_NAME = 'FKcwlj8g7yxqfqag6sbcypi705a')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY CONSTRAINT_NAME = 'fkcwlj8g7yxqfqag6sbcypi705a'),
    'ALTER TABLE `similar_word` DROP FOREIGN KEY `FKcwlj8g7yxqfqag6sbcypi705a`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND BINARY CONSTRAINT_NAME = 'fkcwlj8g7yxqfqag6sbcypi705a')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word'),
    'ALTER TABLE `similar_word` ADD CONSTRAINT `fkcwlj8g7yxqfqag6sbcypi705a` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user: FOREIGN KEY FK6lqwkmrxl04j2k3d2oqysgwvm -> fk6lqwkmrxl04j2k3d2oqysgwvm
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY CONSTRAINT_NAME = 'FK6lqwkmrxl04j2k3d2oqysgwvm')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY CONSTRAINT_NAME = 'fk6lqwkmrxl04j2k3d2oqysgwvm'),
    'ALTER TABLE `user` DROP FOREIGN KEY `FK6lqwkmrxl04j2k3d2oqysgwvm`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY CONSTRAINT_NAME = 'fk6lqwkmrxl04j2k3d2oqysgwvm')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user'),
    'ALTER TABLE `user` ADD CONSTRAINT `fk6lqwkmrxl04j2k3d2oqysgwvm` FOREIGN KEY (`level_id`) REFERENCES `level` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user: FOREIGN KEY FKefu5f2ioj2qy2bycuh6g3wbkd -> fkefu5f2ioj2qy2bycuh6g3wbkd
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY CONSTRAINT_NAME = 'FKefu5f2ioj2qy2bycuh6g3wbkd')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY CONSTRAINT_NAME = 'fkefu5f2ioj2qy2bycuh6g3wbkd'),
    'ALTER TABLE `user` DROP FOREIGN KEY `FKefu5f2ioj2qy2bycuh6g3wbkd`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND BINARY CONSTRAINT_NAME = 'fkefu5f2ioj2qy2bycuh6g3wbkd')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user'),
    'ALTER TABLE `user` ADD CONSTRAINT `fkefu5f2ioj2qy2bycuh6g3wbkd` FOREIGN KEY (`invited_by_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_cow_dung_log: FOREIGN KEY FKp01eygbwkg91uujcjasrhbu2y -> fkp01eygbwkg91uujcjasrhbu2y
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND BINARY CONSTRAINT_NAME = 'FKp01eygbwkg91uujcjasrhbu2y')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND BINARY CONSTRAINT_NAME = 'fkp01eygbwkg91uujcjasrhbu2y'),
    'ALTER TABLE `user_cow_dung_log` DROP FOREIGN KEY `FKp01eygbwkg91uujcjasrhbu2y`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND BINARY CONSTRAINT_NAME = 'fkp01eygbwkg91uujcjasrhbu2y')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log'),
    'ALTER TABLE `user_cow_dung_log` ADD CONSTRAINT `fkp01eygbwkg91uujcjasrhbu2y` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_game: FOREIGN KEY FKe1j2if58j0qgke4numextbw8a -> fke1j2if58j0qgke4numextbw8a
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND BINARY CONSTRAINT_NAME = 'FKe1j2if58j0qgke4numextbw8a')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND BINARY CONSTRAINT_NAME = 'fke1j2if58j0qgke4numextbw8a'),
    'ALTER TABLE `user_game` DROP FOREIGN KEY `FKe1j2if58j0qgke4numextbw8a`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND BINARY CONSTRAINT_NAME = 'fke1j2if58j0qgke4numextbw8a')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game'),
    'ALTER TABLE `user_game` ADD CONSTRAINT `fke1j2if58j0qgke4numextbw8a` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_score_log: FOREIGN KEY FKn1b5wicvnceas08ju14uk3qqw -> fkn1b5wicvnceas08ju14uk3qqw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND BINARY CONSTRAINT_NAME = 'FKn1b5wicvnceas08ju14uk3qqw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND BINARY CONSTRAINT_NAME = 'fkn1b5wicvnceas08ju14uk3qqw'),
    'ALTER TABLE `user_score_log` DROP FOREIGN KEY `FKn1b5wicvnceas08ju14uk3qqw`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND BINARY CONSTRAINT_NAME = 'fkn1b5wicvnceas08ju14uk3qqw')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log'),
    'ALTER TABLE `user_score_log` ADD CONSTRAINT `fkn1b5wicvnceas08ju14uk3qqw` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_snapshot_daily: FOREIGN KEY FKm48fwdudlv10kcn0wafvdves3 -> fkm48fwdudlv10kcn0wafvdves3
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND BINARY CONSTRAINT_NAME = 'FKm48fwdudlv10kcn0wafvdves3')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND BINARY CONSTRAINT_NAME = 'fkm48fwdudlv10kcn0wafvdves3'),
    'ALTER TABLE `user_snapshot_daily` DROP FOREIGN KEY `FKm48fwdudlv10kcn0wafvdves3`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND BINARY CONSTRAINT_NAME = 'fkm48fwdudlv10kcn0wafvdves3')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily'),
    'ALTER TABLE `user_snapshot_daily` ADD CONSTRAINT `fkm48fwdudlv10kcn0wafvdves3` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_study_step: FOREIGN KEY FKkb5mbew7a6hawfub12aotlpbh -> fkkb5mbew7a6hawfub12aotlpbh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND BINARY CONSTRAINT_NAME = 'FKkb5mbew7a6hawfub12aotlpbh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND BINARY CONSTRAINT_NAME = 'fkkb5mbew7a6hawfub12aotlpbh'),
    'ALTER TABLE `user_study_step` DROP FOREIGN KEY `FKkb5mbew7a6hawfub12aotlpbh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND BINARY CONSTRAINT_NAME = 'fkkb5mbew7a6hawfub12aotlpbh')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step'),
    'ALTER TABLE `user_study_step` ADD CONSTRAINT `fkkb5mbew7a6hawfub12aotlpbh` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_wrong_word: FOREIGN KEY FKqneibfe99w3ktslncl4vt009k -> fkqneibfe99w3ktslncl4vt009k
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY CONSTRAINT_NAME = 'FKqneibfe99w3ktslncl4vt009k')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY CONSTRAINT_NAME = 'fkqneibfe99w3ktslncl4vt009k'),
    'ALTER TABLE `user_wrong_word` DROP FOREIGN KEY `FKqneibfe99w3ktslncl4vt009k`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY CONSTRAINT_NAME = 'fkqneibfe99w3ktslncl4vt009k')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word'),
    'ALTER TABLE `user_wrong_word` ADD CONSTRAINT `fkqneibfe99w3ktslncl4vt009k` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_wrong_word: FOREIGN KEY FKwkw9ln2wtbqtq0e7s5ayti2t -> fkwkw9ln2wtbqtq0e7s5ayti2t
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY CONSTRAINT_NAME = 'FKwkw9ln2wtbqtq0e7s5ayti2t')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY CONSTRAINT_NAME = 'fkwkw9ln2wtbqtq0e7s5ayti2t'),
    'ALTER TABLE `user_wrong_word` DROP FOREIGN KEY `FKwkw9ln2wtbqtq0e7s5ayti2t`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND BINARY CONSTRAINT_NAME = 'fkwkw9ln2wtbqtq0e7s5ayti2t')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word'),
    'ALTER TABLE `user_wrong_word` ADD CONSTRAINT `fkwkw9ln2wtbqtq0e7s5ayti2t` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- verb_tense: FOREIGN KEY FKrymhs6cvyoh40cpcslopn98yo -> fkrymhs6cvyoh40cpcslopn98yo
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND BINARY CONSTRAINT_NAME = 'FKrymhs6cvyoh40cpcslopn98yo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND BINARY CONSTRAINT_NAME = 'fkrymhs6cvyoh40cpcslopn98yo'),
    'ALTER TABLE `verb_tense` DROP FOREIGN KEY `FKrymhs6cvyoh40cpcslopn98yo`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND BINARY CONSTRAINT_NAME = 'fkrymhs6cvyoh40cpcslopn98yo')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense'),
    'ALTER TABLE `verb_tense` ADD CONSTRAINT `fkrymhs6cvyoh40cpcslopn98yo` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_additional_info: FOREIGN KEY FK5jynq4erw7uwlffv3covsa9oc -> fk5jynq4erw7uwlffv3covsa9oc
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY CONSTRAINT_NAME = 'FK5jynq4erw7uwlffv3covsa9oc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY CONSTRAINT_NAME = 'fk5jynq4erw7uwlffv3covsa9oc'),
    'ALTER TABLE `word_additional_info` DROP FOREIGN KEY `FK5jynq4erw7uwlffv3covsa9oc`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY CONSTRAINT_NAME = 'fk5jynq4erw7uwlffv3covsa9oc')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info'),
    'ALTER TABLE `word_additional_info` ADD CONSTRAINT `fk5jynq4erw7uwlffv3covsa9oc` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_additional_info: FOREIGN KEY FKf3xqffcm8vnaqbucfr5i24yqh -> fkf3xqffcm8vnaqbucfr5i24yqh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY CONSTRAINT_NAME = 'FKf3xqffcm8vnaqbucfr5i24yqh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY CONSTRAINT_NAME = 'fkf3xqffcm8vnaqbucfr5i24yqh'),
    'ALTER TABLE `word_additional_info` DROP FOREIGN KEY `FKf3xqffcm8vnaqbucfr5i24yqh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND BINARY CONSTRAINT_NAME = 'fkf3xqffcm8vnaqbucfr5i24yqh')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info'),
    'ALTER TABLE `word_additional_info` ADD CONSTRAINT `fkf3xqffcm8vnaqbucfr5i24yqh` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_image: FOREIGN KEY FK22nlb05j0hk398isouqw9ehbc -> fk22nlb05j0hk398isouqw9ehbc
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY CONSTRAINT_NAME = 'FK22nlb05j0hk398isouqw9ehbc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY CONSTRAINT_NAME = 'fk22nlb05j0hk398isouqw9ehbc'),
    'ALTER TABLE `word_image` DROP FOREIGN KEY `FK22nlb05j0hk398isouqw9ehbc`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY CONSTRAINT_NAME = 'fk22nlb05j0hk398isouqw9ehbc')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image'),
    'ALTER TABLE `word_image` ADD CONSTRAINT `fk22nlb05j0hk398isouqw9ehbc` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_image: FOREIGN KEY FKcsrc6dqtt1q9907n2w3qcy71v -> fkcsrc6dqtt1q9907n2w3qcy71v
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY CONSTRAINT_NAME = 'FKcsrc6dqtt1q9907n2w3qcy71v')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY CONSTRAINT_NAME = 'fkcsrc6dqtt1q9907n2w3qcy71v'),
    'ALTER TABLE `word_image` DROP FOREIGN KEY `FKcsrc6dqtt1q9907n2w3qcy71v`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND BINARY CONSTRAINT_NAME = 'fkcsrc6dqtt1q9907n2w3qcy71v')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image'),
    'ALTER TABLE `word_image` ADD CONSTRAINT `fkcsrc6dqtt1q9907n2w3qcy71v` FOREIGN KEY (`author_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_shortdesc_chinese: FOREIGN KEY FK662626om3lfe5ov2fohxuqpgp -> fk662626om3lfe5ov2fohxuqpgp
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY CONSTRAINT_NAME = 'FK662626om3lfe5ov2fohxuqpgp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY CONSTRAINT_NAME = 'fk662626om3lfe5ov2fohxuqpgp'),
    'ALTER TABLE `word_shortdesc_chinese` DROP FOREIGN KEY `FK662626om3lfe5ov2fohxuqpgp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY CONSTRAINT_NAME = 'fk662626om3lfe5ov2fohxuqpgp')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese'),
    'ALTER TABLE `word_shortdesc_chinese` ADD CONSTRAINT `fk662626om3lfe5ov2fohxuqpgp` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_shortdesc_chinese: FOREIGN KEY FKtfaryode4etiv5gh8vr47bnbh -> fktfaryode4etiv5gh8vr47bnbh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY CONSTRAINT_NAME = 'FKtfaryode4etiv5gh8vr47bnbh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY CONSTRAINT_NAME = 'fktfaryode4etiv5gh8vr47bnbh'),
    'ALTER TABLE `word_shortdesc_chinese` DROP FOREIGN KEY `FKtfaryode4etiv5gh8vr47bnbh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND BINARY CONSTRAINT_NAME = 'fktfaryode4etiv5gh8vr47bnbh')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese'),
    'ALTER TABLE `word_shortdesc_chinese` ADD CONSTRAINT `fktfaryode4etiv5gh8vr47bnbh` FOREIGN KEY (`author_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- article: FOREIGN KEY FKdw5d9vdw43e3nvtpqk8l4iitp -> fkdw5d9vdw43e3nvtpqk8l4iitp
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND BINARY CONSTRAINT_NAME = 'FKdw5d9vdw43e3nvtpqk8l4iitp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND BINARY CONSTRAINT_NAME = 'fkdw5d9vdw43e3nvtpqk8l4iitp'),
    'ALTER TABLE `article` DROP FOREIGN KEY `FKdw5d9vdw43e3nvtpqk8l4iitp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND BINARY CONSTRAINT_NAME = 'fkdw5d9vdw43e3nvtpqk8l4iitp')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article'),
    'ALTER TABLE `article` ADD CONSTRAINT `fkdw5d9vdw43e3nvtpqk8l4iitp` FOREIGN KEY (`author`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- book_mark: FOREIGN KEY book_mark_user_FK -> book_mark_user_fk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND BINARY CONSTRAINT_NAME = 'book_mark_user_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND BINARY CONSTRAINT_NAME = 'book_mark_user_fk'),
    'ALTER TABLE `book_mark` DROP FOREIGN KEY `book_mark_user_FK`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND BINARY CONSTRAINT_NAME = 'book_mark_user_fk')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark'),
    'ALTER TABLE `book_mark` ADD CONSTRAINT `book_mark_user_fk` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- daka: FOREIGN KEY FK9lw3569kklr2aem8j3lgooofo -> fk9lw3569kklr2aem8j3lgooofo
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND BINARY CONSTRAINT_NAME = 'FK9lw3569kklr2aem8j3lgooofo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND BINARY CONSTRAINT_NAME = 'fk9lw3569kklr2aem8j3lgooofo'),
    'ALTER TABLE `daka` DROP FOREIGN KEY `FK9lw3569kklr2aem8j3lgooofo`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND BINARY CONSTRAINT_NAME = 'fk9lw3569kklr2aem8j3lgooofo')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka'),
    'ALTER TABLE `daka` ADD CONSTRAINT `fk9lw3569kklr2aem8j3lgooofo` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict: FOREIGN KEY FKba1lo3o2pqjwuhuo55a173tpn -> fkba1lo3o2pqjwuhuo55a173tpn
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND BINARY CONSTRAINT_NAME = 'FKba1lo3o2pqjwuhuo55a173tpn')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND BINARY CONSTRAINT_NAME = 'fkba1lo3o2pqjwuhuo55a173tpn'),
    'ALTER TABLE `dict` DROP FOREIGN KEY `FKba1lo3o2pqjwuhuo55a173tpn`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND BINARY CONSTRAINT_NAME = 'fkba1lo3o2pqjwuhuo55a173tpn')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict'),
    'ALTER TABLE `dict` ADD CONSTRAINT `fkba1lo3o2pqjwuhuo55a173tpn` FOREIGN KEY (`owner_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_word: FOREIGN KEY FKhyb2ixqpghb6s7ksefrm42kfa -> fkhyb2ixqpghb6s7ksefrm42kfa
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY CONSTRAINT_NAME = 'FKhyb2ixqpghb6s7ksefrm42kfa')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY CONSTRAINT_NAME = 'fkhyb2ixqpghb6s7ksefrm42kfa'),
    'ALTER TABLE `dict_word` DROP FOREIGN KEY `FKhyb2ixqpghb6s7ksefrm42kfa`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY CONSTRAINT_NAME = 'fkhyb2ixqpghb6s7ksefrm42kfa')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word'),
    'ALTER TABLE `dict_word` ADD CONSTRAINT `fkhyb2ixqpghb6s7ksefrm42kfa` FOREIGN KEY (`dict_id`) REFERENCES `dict` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_word: FOREIGN KEY FKoocgndgdxfsmi9l22c779ve5f -> fkoocgndgdxfsmi9l22c779ve5f
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY CONSTRAINT_NAME = 'FKoocgndgdxfsmi9l22c779ve5f')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY CONSTRAINT_NAME = 'fkoocgndgdxfsmi9l22c779ve5f'),
    'ALTER TABLE `dict_word` DROP FOREIGN KEY `FKoocgndgdxfsmi9l22c779ve5f`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND BINARY CONSTRAINT_NAME = 'fkoocgndgdxfsmi9l22c779ve5f')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word'),
    'ALTER TABLE `dict_word` ADD CONSTRAINT `fkoocgndgdxfsmi9l22c779ve5f` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- error_report: FOREIGN KEY FKt63m0vobg7664cjmoyuwngl2r -> fkt63m0vobg7664cjmoyuwngl2r
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND BINARY CONSTRAINT_NAME = 'FKt63m0vobg7664cjmoyuwngl2r')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND BINARY CONSTRAINT_NAME = 'fkt63m0vobg7664cjmoyuwngl2r'),
    'ALTER TABLE `error_report` DROP FOREIGN KEY `FKt63m0vobg7664cjmoyuwngl2r`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND BINARY CONSTRAINT_NAME = 'fkt63m0vobg7664cjmoyuwngl2r')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report'),
    'ALTER TABLE `error_report` ADD CONSTRAINT `fkt63m0vobg7664cjmoyuwngl2r` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_and_manager_link: FOREIGN KEY FK4rgldqqyj2v6ko5fb3j4h00hw -> fk4rgldqqyj2v6ko5fb3j4h00hw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY CONSTRAINT_NAME = 'FK4rgldqqyj2v6ko5fb3j4h00hw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fk4rgldqqyj2v6ko5fb3j4h00hw'),
    'ALTER TABLE `forum_and_manager_link` DROP FOREIGN KEY `FK4rgldqqyj2v6ko5fb3j4h00hw`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fk4rgldqqyj2v6ko5fb3j4h00hw')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link'),
    'ALTER TABLE `forum_and_manager_link` ADD CONSTRAINT `fk4rgldqqyj2v6ko5fb3j4h00hw` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_and_manager_link: FOREIGN KEY FKm2ne0gyp8to1iltn9y5xatn5g -> fkm2ne0gyp8to1iltn9y5xatn5g
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY CONSTRAINT_NAME = 'FKm2ne0gyp8to1iltn9y5xatn5g')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fkm2ne0gyp8to1iltn9y5xatn5g'),
    'ALTER TABLE `forum_and_manager_link` DROP FOREIGN KEY `FKm2ne0gyp8to1iltn9y5xatn5g`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fkm2ne0gyp8to1iltn9y5xatn5g')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link'),
    'ALTER TABLE `forum_and_manager_link` ADD CONSTRAINT `fkm2ne0gyp8to1iltn9y5xatn5g` FOREIGN KEY (`forum_id`) REFERENCES `forum` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post: FOREIGN KEY FK89ba00sxrqhbgl7cgwt6y0tux -> fk89ba00sxrqhbgl7cgwt6y0tux
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY CONSTRAINT_NAME = 'FK89ba00sxrqhbgl7cgwt6y0tux')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY CONSTRAINT_NAME = 'fk89ba00sxrqhbgl7cgwt6y0tux'),
    'ALTER TABLE `forum_post` DROP FOREIGN KEY `FK89ba00sxrqhbgl7cgwt6y0tux`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY CONSTRAINT_NAME = 'fk89ba00sxrqhbgl7cgwt6y0tux')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post'),
    'ALTER TABLE `forum_post` ADD CONSTRAINT `fk89ba00sxrqhbgl7cgwt6y0tux` FOREIGN KEY (`post_creator_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post: FOREIGN KEY FKh0s5a90088gbywb9u9j5fase4 -> fkh0s5a90088gbywb9u9j5fase4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY CONSTRAINT_NAME = 'FKh0s5a90088gbywb9u9j5fase4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY CONSTRAINT_NAME = 'fkh0s5a90088gbywb9u9j5fase4'),
    'ALTER TABLE `forum_post` DROP FOREIGN KEY `FKh0s5a90088gbywb9u9j5fase4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND BINARY CONSTRAINT_NAME = 'fkh0s5a90088gbywb9u9j5fase4')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post'),
    'ALTER TABLE `forum_post` ADD CONSTRAINT `fkh0s5a90088gbywb9u9j5fase4` FOREIGN KEY (`forum_id`) REFERENCES `forum` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post_reply: FOREIGN KEY FKctt5g9ionoo960lak0p7ss6ou -> fkctt5g9ionoo960lak0p7ss6ou
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY CONSTRAINT_NAME = 'FKctt5g9ionoo960lak0p7ss6ou')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY CONSTRAINT_NAME = 'fkctt5g9ionoo960lak0p7ss6ou'),
    'ALTER TABLE `forum_post_reply` DROP FOREIGN KEY `FKctt5g9ionoo960lak0p7ss6ou`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY CONSTRAINT_NAME = 'fkctt5g9ionoo960lak0p7ss6ou')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply'),
    'ALTER TABLE `forum_post_reply` ADD CONSTRAINT `fkctt5g9ionoo960lak0p7ss6ou` FOREIGN KEY (`post_replyer_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post_reply: FOREIGN KEY FKsmolky8m77uf3aygscwtlh7 -> fksmolky8m77uf3aygscwtlh7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY CONSTRAINT_NAME = 'FKsmolky8m77uf3aygscwtlh7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY CONSTRAINT_NAME = 'fksmolky8m77uf3aygscwtlh7'),
    'ALTER TABLE `forum_post_reply` DROP FOREIGN KEY `FKsmolky8m77uf3aygscwtlh7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND BINARY CONSTRAINT_NAME = 'fksmolky8m77uf3aygscwtlh7')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply'),
    'ALTER TABLE `forum_post_reply` ADD CONSTRAINT `fksmolky8m77uf3aygscwtlh7` FOREIGN KEY (`post_id`) REFERENCES `forum_post` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- group_and_dict_link: FOREIGN KEY FKanvwboyqdce5mb41j8q4qly3c -> fkanvwboyqdce5mb41j8q4qly3c
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY CONSTRAINT_NAME = 'FKanvwboyqdce5mb41j8q4qly3c')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY CONSTRAINT_NAME = 'fkanvwboyqdce5mb41j8q4qly3c'),
    'ALTER TABLE `group_and_dict_link` DROP FOREIGN KEY `FKanvwboyqdce5mb41j8q4qly3c`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY CONSTRAINT_NAME = 'fkanvwboyqdce5mb41j8q4qly3c')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link'),
    'ALTER TABLE `group_and_dict_link` ADD CONSTRAINT `fkanvwboyqdce5mb41j8q4qly3c` FOREIGN KEY (`group_id`) REFERENCES `dict_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- group_and_dict_link: FOREIGN KEY FKhuoc8hxjs2c8w1fgickojg6ff -> fkhuoc8hxjs2c8w1fgickojg6ff
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY CONSTRAINT_NAME = 'FKhuoc8hxjs2c8w1fgickojg6ff')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY CONSTRAINT_NAME = 'fkhuoc8hxjs2c8w1fgickojg6ff'),
    'ALTER TABLE `group_and_dict_link` DROP FOREIGN KEY `FKhuoc8hxjs2c8w1fgickojg6ff`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND BINARY CONSTRAINT_NAME = 'fkhuoc8hxjs2c8w1fgickojg6ff')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link'),
    'ALTER TABLE `group_and_dict_link` ADD CONSTRAINT `fkhuoc8hxjs2c8w1fgickojg6ff` FOREIGN KEY (`dict_id`) REFERENCES `dict` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- info_vote_log: FOREIGN KEY FKnyxodwmjasis1v8c04xsen7dh -> fknyxodwmjasis1v8c04xsen7dh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY CONSTRAINT_NAME = 'FKnyxodwmjasis1v8c04xsen7dh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY CONSTRAINT_NAME = 'fknyxodwmjasis1v8c04xsen7dh'),
    'ALTER TABLE `info_vote_log` DROP FOREIGN KEY `FKnyxodwmjasis1v8c04xsen7dh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY CONSTRAINT_NAME = 'fknyxodwmjasis1v8c04xsen7dh')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log'),
    'ALTER TABLE `info_vote_log` ADD CONSTRAINT `fknyxodwmjasis1v8c04xsen7dh` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- info_vote_log: FOREIGN KEY FKq3tlgwcmlq54suls4sv2vh9xa -> fkq3tlgwcmlq54suls4sv2vh9xa
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY CONSTRAINT_NAME = 'FKq3tlgwcmlq54suls4sv2vh9xa')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY CONSTRAINT_NAME = 'fkq3tlgwcmlq54suls4sv2vh9xa'),
    'ALTER TABLE `info_vote_log` DROP FOREIGN KEY `FKq3tlgwcmlq54suls4sv2vh9xa`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND BINARY CONSTRAINT_NAME = 'fkq3tlgwcmlq54suls4sv2vh9xa')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log'),
    'ALTER TABLE `info_vote_log` ADD CONSTRAINT `fkq3tlgwcmlq54suls4sv2vh9xa` FOREIGN KEY (`info_id`) REFERENCES `word_additional_info` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_dict: FOREIGN KEY FKoaoie5gcg9b8xulawdoaoa4rt -> fkoaoie5gcg9b8xulawdoaoa4rt
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'FKoaoie5gcg9b8xulawdoaoa4rt')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'fkoaoie5gcg9b8xulawdoaoa4rt'),
    'ALTER TABLE `learning_dict` DROP FOREIGN KEY `FKoaoie5gcg9b8xulawdoaoa4rt`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'fkoaoie5gcg9b8xulawdoaoa4rt')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict'),
    'ALTER TABLE `learning_dict` ADD CONSTRAINT `fkoaoie5gcg9b8xulawdoaoa4rt` FOREIGN KEY (`dict_id`) REFERENCES `dict` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_dict: FOREIGN KEY FKpiu1chqdc7gn2bchpkxcbdqu6 -> fkpiu1chqdc7gn2bchpkxcbdqu6
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'FKpiu1chqdc7gn2bchpkxcbdqu6')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'fkpiu1chqdc7gn2bchpkxcbdqu6'),
    'ALTER TABLE `learning_dict` DROP FOREIGN KEY `FKpiu1chqdc7gn2bchpkxcbdqu6`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'fkpiu1chqdc7gn2bchpkxcbdqu6')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict'),
    'ALTER TABLE `learning_dict` ADD CONSTRAINT `fkpiu1chqdc7gn2bchpkxcbdqu6` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_dict: FOREIGN KEY FKs6prwtgob6wmhxysa8bu1096r -> fks6prwtgob6wmhxysa8bu1096r
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'FKs6prwtgob6wmhxysa8bu1096r')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'fks6prwtgob6wmhxysa8bu1096r'),
    'ALTER TABLE `learning_dict` DROP FOREIGN KEY `FKs6prwtgob6wmhxysa8bu1096r`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND BINARY CONSTRAINT_NAME = 'fks6prwtgob6wmhxysa8bu1096r')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict'),
    'ALTER TABLE `learning_dict` ADD CONSTRAINT `fks6prwtgob6wmhxysa8bu1096r` FOREIGN KEY (`current_word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_word: FOREIGN KEY FKpqcu8nmvm7ap2971ok6vs3s0n -> fkpqcu8nmvm7ap2971ok6vs3s0n
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND BINARY CONSTRAINT_NAME = 'FKpqcu8nmvm7ap2971ok6vs3s0n')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND BINARY CONSTRAINT_NAME = 'fkpqcu8nmvm7ap2971ok6vs3s0n'),
    'ALTER TABLE `learning_word` DROP FOREIGN KEY `FKpqcu8nmvm7ap2971ok6vs3s0n`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND BINARY CONSTRAINT_NAME = 'fkpqcu8nmvm7ap2971ok6vs3s0n')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word'),
    'ALTER TABLE `learning_word` ADD CONSTRAINT `fkpqcu8nmvm7ap2971ok6vs3s0n` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- login_log: FOREIGN KEY FK9auh6uhsrknd75ipjypyyha90 -> fk9auh6uhsrknd75ipjypyyha90
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND BINARY CONSTRAINT_NAME = 'FK9auh6uhsrknd75ipjypyyha90')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND BINARY CONSTRAINT_NAME = 'fk9auh6uhsrknd75ipjypyyha90'),
    'ALTER TABLE `login_log` DROP FOREIGN KEY `FK9auh6uhsrknd75ipjypyyha90`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND BINARY CONSTRAINT_NAME = 'fk9auh6uhsrknd75ipjypyyha90')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log'),
    'ALTER TABLE `login_log` ADD CONSTRAINT `fk9auh6uhsrknd75ipjypyyha90` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- mastered_word: FOREIGN KEY FKkx3r0klb1on3xmbmp40dqwrmh -> fkkx3r0klb1on3xmbmp40dqwrmh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND BINARY CONSTRAINT_NAME = 'FKkx3r0klb1on3xmbmp40dqwrmh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND BINARY CONSTRAINT_NAME = 'fkkx3r0klb1on3xmbmp40dqwrmh'),
    'ALTER TABLE `mastered_word` DROP FOREIGN KEY `FKkx3r0klb1on3xmbmp40dqwrmh`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND BINARY CONSTRAINT_NAME = 'fkkx3r0klb1on3xmbmp40dqwrmh')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word'),
    'ALTER TABLE `mastered_word` ADD CONSTRAINT `fkkx3r0klb1on3xmbmp40dqwrmh` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- meaning_item: FOREIGN KEY FKbq1kwqm7l14nowpnkgyct7qmb -> fkbq1kwqm7l14nowpnkgyct7qmb
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY CONSTRAINT_NAME = 'FKbq1kwqm7l14nowpnkgyct7qmb')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY CONSTRAINT_NAME = 'fkbq1kwqm7l14nowpnkgyct7qmb'),
    'ALTER TABLE `meaning_item` DROP FOREIGN KEY `FKbq1kwqm7l14nowpnkgyct7qmb`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY CONSTRAINT_NAME = 'fkbq1kwqm7l14nowpnkgyct7qmb')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item'),
    'ALTER TABLE `meaning_item` ADD CONSTRAINT `fkbq1kwqm7l14nowpnkgyct7qmb` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- meaning_item: FOREIGN KEY FKhajsfsxiyna9xuo9i974u8v07 -> fkhajsfsxiyna9xuo9i974u8v07
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY CONSTRAINT_NAME = 'FKhajsfsxiyna9xuo9i974u8v07')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY CONSTRAINT_NAME = 'fkhajsfsxiyna9xuo9i974u8v07'),
    'ALTER TABLE `meaning_item` DROP FOREIGN KEY `FKhajsfsxiyna9xuo9i974u8v07`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND BINARY CONSTRAINT_NAME = 'fkhajsfsxiyna9xuo9i974u8v07')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item'),
    'ALTER TABLE `meaning_item` ADD CONSTRAINT `fkhajsfsxiyna9xuo9i974u8v07` FOREIGN KEY (`dict_id`) REFERENCES `dict` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- msg: FOREIGN KEY FKduaesr28u3xkjgacqyp6f9k69 -> fkduaesr28u3xkjgacqyp6f9k69
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY CONSTRAINT_NAME = 'FKduaesr28u3xkjgacqyp6f9k69')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY CONSTRAINT_NAME = 'fkduaesr28u3xkjgacqyp6f9k69'),
    'ALTER TABLE `msg` DROP FOREIGN KEY `FKduaesr28u3xkjgacqyp6f9k69`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY CONSTRAINT_NAME = 'fkduaesr28u3xkjgacqyp6f9k69')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg'),
    'ALTER TABLE `msg` ADD CONSTRAINT `fkduaesr28u3xkjgacqyp6f9k69` FOREIGN KEY (`to_user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- msg: FOREIGN KEY FKpwao1csk2fiqn8x0taf5n4lxp -> fkpwao1csk2fiqn8x0taf5n4lxp
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY CONSTRAINT_NAME = 'FKpwao1csk2fiqn8x0taf5n4lxp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY CONSTRAINT_NAME = 'fkpwao1csk2fiqn8x0taf5n4lxp'),
    'ALTER TABLE `msg` DROP FOREIGN KEY `FKpwao1csk2fiqn8x0taf5n4lxp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND BINARY CONSTRAINT_NAME = 'fkpwao1csk2fiqn8x0taf5n4lxp')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg'),
    'ALTER TABLE `msg` ADD CONSTRAINT `fkpwao1csk2fiqn8x0taf5n4lxp` FOREIGN KEY (`from_user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence: FOREIGN KEY FKjsrw5reghdvpvf7rghvlpg8oo -> fkjsrw5reghdvpvf7rghvlpg8oo
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'FKjsrw5reghdvpvf7rghvlpg8oo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'fkjsrw5reghdvpvf7rghvlpg8oo'),
    'ALTER TABLE `sentence` DROP FOREIGN KEY `FKjsrw5reghdvpvf7rghvlpg8oo`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'fkjsrw5reghdvpvf7rghvlpg8oo')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence'),
    'ALTER TABLE `sentence` ADD CONSTRAINT `fkjsrw5reghdvpvf7rghvlpg8oo` FOREIGN KEY (`author_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence: FOREIGN KEY FKnmsdsdecrpllmjlp39xpxnj1d -> fknmsdsdecrpllmjlp39xpxnj1d
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'FKnmsdsdecrpllmjlp39xpxnj1d')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'fknmsdsdecrpllmjlp39xpxnj1d'),
    'ALTER TABLE `sentence` DROP FOREIGN KEY `FKnmsdsdecrpllmjlp39xpxnj1d`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'fknmsdsdecrpllmjlp39xpxnj1d')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence'),
    'ALTER TABLE `sentence` ADD CONSTRAINT `fknmsdsdecrpllmjlp39xpxnj1d` FOREIGN KEY (`meaning_item_id`) REFERENCES `meaning_item` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence: FOREIGN KEY sentence_FK -> sentence_fk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'sentence_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'sentence_fk'),
    'ALTER TABLE `sentence` DROP FOREIGN KEY `sentence_FK`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'sentence_fk')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence'),
    'ALTER TABLE `sentence` ADD CONSTRAINT `sentence_fk` FOREIGN KEY (`author_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence: FOREIGN KEY sentence_meaning_item_FK -> sentence_meaning_item_fk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'sentence_meaning_item_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'sentence_meaning_item_fk'),
    'ALTER TABLE `sentence` DROP FOREIGN KEY `sentence_meaning_item_FK`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND BINARY CONSTRAINT_NAME = 'sentence_meaning_item_fk')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence'),
    'ALTER TABLE `sentence` ADD CONSTRAINT `sentence_meaning_item_fk` FOREIGN KEY (`meaning_item_id`) REFERENCES `meaning_item` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese: FOREIGN KEY FK1ea8mppmrgwbn1gcmn0n4s95n -> fk1ea8mppmrgwbn1gcmn0n4s95n
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY CONSTRAINT_NAME = 'FK1ea8mppmrgwbn1gcmn0n4s95n')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY CONSTRAINT_NAME = 'fk1ea8mppmrgwbn1gcmn0n4s95n'),
    'ALTER TABLE `sentence_chinese` DROP FOREIGN KEY `FK1ea8mppmrgwbn1gcmn0n4s95n`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY CONSTRAINT_NAME = 'fk1ea8mppmrgwbn1gcmn0n4s95n')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese'),
    'ALTER TABLE `sentence_chinese` ADD CONSTRAINT `fk1ea8mppmrgwbn1gcmn0n4s95n` FOREIGN KEY (`author`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese: FOREIGN KEY FK4qkl23fg27sp450b9h3n7xnwx -> fk4qkl23fg27sp450b9h3n7xnwx
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY CONSTRAINT_NAME = 'FK4qkl23fg27sp450b9h3n7xnwx')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY CONSTRAINT_NAME = 'fk4qkl23fg27sp450b9h3n7xnwx'),
    'ALTER TABLE `sentence_chinese` DROP FOREIGN KEY `FK4qkl23fg27sp450b9h3n7xnwx`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND BINARY CONSTRAINT_NAME = 'fk4qkl23fg27sp450b9h3n7xnwx')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese'),
    'ALTER TABLE `sentence_chinese` ADD CONSTRAINT `fk4qkl23fg27sp450b9h3n7xnwx` FOREIGN KEY (`sentence_id`) REFERENCES `sentence` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese_remark: FOREIGN KEY FK9eseuj1b3lp9r0cp52hl524i7 -> fk9eseuj1b3lp9r0cp52hl524i7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY CONSTRAINT_NAME = 'FK9eseuj1b3lp9r0cp52hl524i7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY CONSTRAINT_NAME = 'fk9eseuj1b3lp9r0cp52hl524i7'),
    'ALTER TABLE `sentence_chinese_remark` DROP FOREIGN KEY `FK9eseuj1b3lp9r0cp52hl524i7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY CONSTRAINT_NAME = 'fk9eseuj1b3lp9r0cp52hl524i7')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark'),
    'ALTER TABLE `sentence_chinese_remark` ADD CONSTRAINT `fk9eseuj1b3lp9r0cp52hl524i7` FOREIGN KEY (`chinese_id`) REFERENCES `sentence_chinese` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese_remark: FOREIGN KEY FKqb6gj27jt2kffko46xcctg0u6 -> fkqb6gj27jt2kffko46xcctg0u6
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY CONSTRAINT_NAME = 'FKqb6gj27jt2kffko46xcctg0u6')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY CONSTRAINT_NAME = 'fkqb6gj27jt2kffko46xcctg0u6'),
    'ALTER TABLE `sentence_chinese_remark` DROP FOREIGN KEY `FKqb6gj27jt2kffko46xcctg0u6`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND BINARY CONSTRAINT_NAME = 'fkqb6gj27jt2kffko46xcctg0u6')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark'),
    'ALTER TABLE `sentence_chinese_remark` ADD CONSTRAINT `fkqb6gj27jt2kffko46xcctg0u6` FOREIGN KEY (`author`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_update_notify: FOREIGN KEY FKstugsayfi283agk001cvp8tys -> fkstugsayfi283agk001cvp8tys
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY CONSTRAINT_NAME = 'FKstugsayfi283agk001cvp8tys')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY CONSTRAINT_NAME = 'fkstugsayfi283agk001cvp8tys'),
    'ALTER TABLE `sentence_update_notify` DROP FOREIGN KEY `FKstugsayfi283agk001cvp8tys`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY CONSTRAINT_NAME = 'fkstugsayfi283agk001cvp8tys')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify'),
    'ALTER TABLE `sentence_update_notify` ADD CONSTRAINT `fkstugsayfi283agk001cvp8tys` FOREIGN KEY (`sentence_id`) REFERENCES `sentence` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_update_notify: FOREIGN KEY sentence_update_notify_FK -> sentence_update_notify_fk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY CONSTRAINT_NAME = 'sentence_update_notify_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY CONSTRAINT_NAME = 'sentence_update_notify_fk'),
    'ALTER TABLE `sentence_update_notify` DROP FOREIGN KEY `sentence_update_notify_FK`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND BINARY CONSTRAINT_NAME = 'sentence_update_notify_fk')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify'),
    'ALTER TABLE `sentence_update_notify` ADD CONSTRAINT `sentence_update_notify_fk` FOREIGN KEY (`sentence_id`) REFERENCES `sentence` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group: FOREIGN KEY FK36s0562yu4gydy3xr28u95eqd -> fk36s0562yu4gydy3xr28u95eqd
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY CONSTRAINT_NAME = 'FK36s0562yu4gydy3xr28u95eqd')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY CONSTRAINT_NAME = 'fk36s0562yu4gydy3xr28u95eqd'),
    'ALTER TABLE `study_group` DROP FOREIGN KEY `FK36s0562yu4gydy3xr28u95eqd`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY CONSTRAINT_NAME = 'fk36s0562yu4gydy3xr28u95eqd')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group'),
    'ALTER TABLE `study_group` ADD CONSTRAINT `fk36s0562yu4gydy3xr28u95eqd` FOREIGN KEY (`grade_id`) REFERENCES `study_group_grade` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group: FOREIGN KEY FKfml3yg6yg9a2xi45w4vx7dqfb -> fkfml3yg6yg9a2xi45w4vx7dqfb
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY CONSTRAINT_NAME = 'FKfml3yg6yg9a2xi45w4vx7dqfb')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY CONSTRAINT_NAME = 'fkfml3yg6yg9a2xi45w4vx7dqfb'),
    'ALTER TABLE `study_group` DROP FOREIGN KEY `FKfml3yg6yg9a2xi45w4vx7dqfb`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND BINARY CONSTRAINT_NAME = 'fkfml3yg6yg9a2xi45w4vx7dqfb')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group'),
    'ALTER TABLE `study_group` ADD CONSTRAINT `fkfml3yg6yg9a2xi45w4vx7dqfb` FOREIGN KEY (`creator_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_manager_link: FOREIGN KEY FKgfviie87tlf3c34ipmx31ynj7 -> fkgfviie87tlf3c34ipmx31ynj7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY CONSTRAINT_NAME = 'FKgfviie87tlf3c34ipmx31ynj7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fkgfviie87tlf3c34ipmx31ynj7'),
    'ALTER TABLE `study_group_and_manager_link` DROP FOREIGN KEY `FKgfviie87tlf3c34ipmx31ynj7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fkgfviie87tlf3c34ipmx31ynj7')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link'),
    'ALTER TABLE `study_group_and_manager_link` ADD CONSTRAINT `fkgfviie87tlf3c34ipmx31ynj7` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_manager_link: FOREIGN KEY FKrdflptnxblu6aa5r7s9747ko4 -> fkrdflptnxblu6aa5r7s9747ko4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY CONSTRAINT_NAME = 'FKrdflptnxblu6aa5r7s9747ko4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fkrdflptnxblu6aa5r7s9747ko4'),
    'ALTER TABLE `study_group_and_manager_link` DROP FOREIGN KEY `FKrdflptnxblu6aa5r7s9747ko4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND BINARY CONSTRAINT_NAME = 'fkrdflptnxblu6aa5r7s9747ko4')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link'),
    'ALTER TABLE `study_group_and_manager_link` ADD CONSTRAINT `fkrdflptnxblu6aa5r7s9747ko4` FOREIGN KEY (`group_id`) REFERENCES `study_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_user_link: FOREIGN KEY FK66ybol3y7m0xgvon3hovu9ifv -> fk66ybol3y7m0xgvon3hovu9ifv
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY CONSTRAINT_NAME = 'FK66ybol3y7m0xgvon3hovu9ifv')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY CONSTRAINT_NAME = 'fk66ybol3y7m0xgvon3hovu9ifv'),
    'ALTER TABLE `study_group_and_user_link` DROP FOREIGN KEY `FK66ybol3y7m0xgvon3hovu9ifv`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY CONSTRAINT_NAME = 'fk66ybol3y7m0xgvon3hovu9ifv')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link'),
    'ALTER TABLE `study_group_and_user_link` ADD CONSTRAINT `fk66ybol3y7m0xgvon3hovu9ifv` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_user_link: FOREIGN KEY FKs1c5cfbgl89yn2p955v7sugj7 -> fks1c5cfbgl89yn2p955v7sugj7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY CONSTRAINT_NAME = 'FKs1c5cfbgl89yn2p955v7sugj7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY CONSTRAINT_NAME = 'fks1c5cfbgl89yn2p955v7sugj7'),
    'ALTER TABLE `study_group_and_user_link` DROP FOREIGN KEY `FKs1c5cfbgl89yn2p955v7sugj7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND BINARY CONSTRAINT_NAME = 'fks1c5cfbgl89yn2p955v7sugj7')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link'),
    'ALTER TABLE `study_group_and_user_link` ADD CONSTRAINT `fks1c5cfbgl89yn2p955v7sugj7` FOREIGN KEY (`group_id`) REFERENCES `study_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post: FOREIGN KEY FKc3t23fo2d1n4cqsq5ct92vtjn -> fkc3t23fo2d1n4cqsq5ct92vtjn
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY CONSTRAINT_NAME = 'FKc3t23fo2d1n4cqsq5ct92vtjn')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY CONSTRAINT_NAME = 'fkc3t23fo2d1n4cqsq5ct92vtjn'),
    'ALTER TABLE `study_group_post` DROP FOREIGN KEY `FKc3t23fo2d1n4cqsq5ct92vtjn`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY CONSTRAINT_NAME = 'fkc3t23fo2d1n4cqsq5ct92vtjn')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post'),
    'ALTER TABLE `study_group_post` ADD CONSTRAINT `fkc3t23fo2d1n4cqsq5ct92vtjn` FOREIGN KEY (`group_id`) REFERENCES `study_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post: FOREIGN KEY FKmy0w3ae9nui45ii8gg5ftx03y -> fkmy0w3ae9nui45ii8gg5ftx03y
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY CONSTRAINT_NAME = 'FKmy0w3ae9nui45ii8gg5ftx03y')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY CONSTRAINT_NAME = 'fkmy0w3ae9nui45ii8gg5ftx03y'),
    'ALTER TABLE `study_group_post` DROP FOREIGN KEY `FKmy0w3ae9nui45ii8gg5ftx03y`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND BINARY CONSTRAINT_NAME = 'fkmy0w3ae9nui45ii8gg5ftx03y')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post'),
    'ALTER TABLE `study_group_post` ADD CONSTRAINT `fkmy0w3ae9nui45ii8gg5ftx03y` FOREIGN KEY (`post_creator_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post_reply: FOREIGN KEY FK302iba0o0rgoegvo0en7a05jl -> fk302iba0o0rgoegvo0en7a05jl
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY CONSTRAINT_NAME = 'FK302iba0o0rgoegvo0en7a05jl')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY CONSTRAINT_NAME = 'fk302iba0o0rgoegvo0en7a05jl'),
    'ALTER TABLE `study_group_post_reply` DROP FOREIGN KEY `FK302iba0o0rgoegvo0en7a05jl`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY CONSTRAINT_NAME = 'fk302iba0o0rgoegvo0en7a05jl')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply'),
    'ALTER TABLE `study_group_post_reply` ADD CONSTRAINT `fk302iba0o0rgoegvo0en7a05jl` FOREIGN KEY (`post_id`) REFERENCES `study_group_post` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post_reply: FOREIGN KEY FKlbwltcdwo4x4hlkbl51fpph -> fklbwltcdwo4x4hlkbl51fpph
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY CONSTRAINT_NAME = 'FKlbwltcdwo4x4hlkbl51fpph')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY CONSTRAINT_NAME = 'fklbwltcdwo4x4hlkbl51fpph'),
    'ALTER TABLE `study_group_post_reply` DROP FOREIGN KEY `FKlbwltcdwo4x4hlkbl51fpph`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND BINARY CONSTRAINT_NAME = 'fklbwltcdwo4x4hlkbl51fpph')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply'),
    'ALTER TABLE `study_group_post_reply` ADD CONSTRAINT `fklbwltcdwo4x4hlkbl51fpph` FOREIGN KEY (`post_replyer_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_snapshot_daily: FOREIGN KEY FKs0e3efs4xyt73agwc6e96wjc4 -> fks0e3efs4xyt73agwc6e96wjc4
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND BINARY CONSTRAINT_NAME = 'FKs0e3efs4xyt73agwc6e96wjc4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND BINARY CONSTRAINT_NAME = 'fks0e3efs4xyt73agwc6e96wjc4'),
    'ALTER TABLE `study_group_snapshot_daily` DROP FOREIGN KEY `FKs0e3efs4xyt73agwc6e96wjc4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND BINARY CONSTRAINT_NAME = 'fks0e3efs4xyt73agwc6e96wjc4')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily'),
    'ALTER TABLE `study_group_snapshot_daily` ADD CONSTRAINT `fks0e3efs4xyt73agwc6e96wjc4` FOREIGN KEY (`group_id`) REFERENCES `study_group` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- synonym: FOREIGN KEY FKallgsvuhxdjb80476q64s2moe -> fkallgsvuhxdjb80476q64s2moe
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND BINARY CONSTRAINT_NAME = 'FKallgsvuhxdjb80476q64s2moe')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND BINARY CONSTRAINT_NAME = 'fkallgsvuhxdjb80476q64s2moe'),
    'ALTER TABLE `synonym` DROP FOREIGN KEY `FKallgsvuhxdjb80476q64s2moe`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND BINARY CONSTRAINT_NAME = 'fkallgsvuhxdjb80476q64s2moe')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym'),
    'ALTER TABLE `synonym` ADD CONSTRAINT `fkallgsvuhxdjb80476q64s2moe` FOREIGN KEY (`meaning_item_id`) REFERENCES `meaning_item` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_sentence: FOREIGN KEY FK3ihl69o17ll6saoyahy1iwnml -> fk3ihl69o17ll6saoyahy1iwnml
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY CONSTRAINT_NAME = 'FK3ihl69o17ll6saoyahy1iwnml')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY CONSTRAINT_NAME = 'fk3ihl69o17ll6saoyahy1iwnml'),
    'ALTER TABLE `word_sentence` DROP FOREIGN KEY `FK3ihl69o17ll6saoyahy1iwnml`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY CONSTRAINT_NAME = 'fk3ihl69o17ll6saoyahy1iwnml')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence'),
    'ALTER TABLE `word_sentence` ADD CONSTRAINT `fk3ihl69o17ll6saoyahy1iwnml` FOREIGN KEY (`sentence_id`) REFERENCES `sentence` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_sentence: FOREIGN KEY FKaqa9an1x12g7s6u92i30raln7 -> fkaqa9an1x12g7s6u92i30raln7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY CONSTRAINT_NAME = 'FKaqa9an1x12g7s6u92i30raln7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY CONSTRAINT_NAME = 'fkaqa9an1x12g7s6u92i30raln7'),
    'ALTER TABLE `word_sentence` DROP FOREIGN KEY `FKaqa9an1x12g7s6u92i30raln7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND BINARY CONSTRAINT_NAME = 'fkaqa9an1x12g7s6u92i30raln7')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence'),
    'ALTER TABLE `word_sentence` ADD CONSTRAINT `fkaqa9an1x12g7s6u92i30raln7` FOREIGN KEY (`word_id`) REFERENCES `word` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: FOREIGN KEY FK8up0cm0j7flyds8mljh3wslcs -> fk8up0cm0j7flyds8mljh3wslcs
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'FK8up0cm0j7flyds8mljh3wslcs')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fk8up0cm0j7flyds8mljh3wslcs'),
    'ALTER TABLE `event` DROP FOREIGN KEY `FK8up0cm0j7flyds8mljh3wslcs`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fk8up0cm0j7flyds8mljh3wslcs')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event'),
    'ALTER TABLE `event` ADD CONSTRAINT `fk8up0cm0j7flyds8mljh3wslcs` FOREIGN KEY (`word_short_desc_chinese_id`) REFERENCES `word_shortdesc_chinese` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: FOREIGN KEY FK8y4063ul9igji7dsmq61t7pg3 -> fk8y4063ul9igji7dsmq61t7pg3
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'FK8y4063ul9igji7dsmq61t7pg3')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fk8y4063ul9igji7dsmq61t7pg3'),
    'ALTER TABLE `event` DROP FOREIGN KEY `FK8y4063ul9igji7dsmq61t7pg3`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fk8y4063ul9igji7dsmq61t7pg3')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event'),
    'ALTER TABLE `event` ADD CONSTRAINT `fk8y4063ul9igji7dsmq61t7pg3` FOREIGN KEY (`sentence_chinese_id`) REFERENCES `sentence_chinese` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: FOREIGN KEY FKcaqnogrpoabtlfqf9h4wuxybk -> fkcaqnogrpoabtlfqf9h4wuxybk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'FKcaqnogrpoabtlfqf9h4wuxybk')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fkcaqnogrpoabtlfqf9h4wuxybk'),
    'ALTER TABLE `event` DROP FOREIGN KEY `FKcaqnogrpoabtlfqf9h4wuxybk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fkcaqnogrpoabtlfqf9h4wuxybk')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event'),
    'ALTER TABLE `event` ADD CONSTRAINT `fkcaqnogrpoabtlfqf9h4wuxybk` FOREIGN KEY (`sentence_id`) REFERENCES `sentence` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: FOREIGN KEY FKe4y90yg6c4gxbdwn2w9lgcb98 -> fke4y90yg6c4gxbdwn2w9lgcb98
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'FKe4y90yg6c4gxbdwn2w9lgcb98')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fke4y90yg6c4gxbdwn2w9lgcb98'),
    'ALTER TABLE `event` DROP FOREIGN KEY `FKe4y90yg6c4gxbdwn2w9lgcb98`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fke4y90yg6c4gxbdwn2w9lgcb98')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event'),
    'ALTER TABLE `event` ADD CONSTRAINT `fke4y90yg6c4gxbdwn2w9lgcb98` FOREIGN KEY (`word_image_id`) REFERENCES `word_image` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: FOREIGN KEY FKn0s3foajghecveph3do4wqngk -> fkn0s3foajghecveph3do4wqngk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'FKn0s3foajghecveph3do4wqngk')
    AND NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fkn0s3foajghecveph3do4wqngk'),
    'ALTER TABLE `event` DROP FOREIGN KEY `FKn0s3foajghecveph3do4wqngk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
SET @__sql := (
  SELECT IF(
    NOT EXISTS(SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND BINARY CONSTRAINT_NAME = 'fkn0s3foajghecveph3do4wqngk')
    AND EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event'),
    'ALTER TABLE `event` ADD CONSTRAINT `fkn0s3foajghecveph3do4wqngk` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`)',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
