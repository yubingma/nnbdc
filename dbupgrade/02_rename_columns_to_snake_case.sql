-- 数据库升级脚本：将所有字段名从驼峰改为 snake_case（小写+下划线）
-- 日期：2025-12-17
-- 说明：本脚本可重复执行：仅当旧列存在且新列不存在时才执行 RENAME COLUMN
-- 依赖：MySQL 8+（支持 RENAME COLUMN）

-- 注意：某些库可能已经部分升级过，本脚本会自动跳过已完成的改名


-- article
-- article: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `article` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- article: keyWords -> key_words
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'keyWords')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'key_words'),
    'ALTER TABLE `article` RENAME COLUMN `keyWords` TO `key_words`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- article: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `article` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- article: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `article` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- article: viewedCount -> viewed_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'viewedCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND COLUMN_NAME = 'viewed_count'),
    'ALTER TABLE `article` RENAME COLUMN `viewedCount` TO `viewed_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- book_mark
-- book_mark: bookMarkName -> book_mark_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'bookMarkName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'book_mark_name'),
    'ALTER TABLE `book_mark` RENAME COLUMN `bookMarkName` TO `book_mark_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- book_mark: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `book_mark` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- book_mark: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `book_mark` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- book_mark: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `book_mark` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- cigen
-- cigen: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `cigen` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- cigen: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `cigen` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- cigen_word_link
-- cigen_word_link: cigenId -> cigen_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'cigenId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'cigen_id'),
    'ALTER TABLE `cigen_word_link` RENAME COLUMN `cigenId` TO `cigen_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- cigen_word_link: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `cigen_word_link` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- cigen_word_link: theExplain -> the_explain
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'theExplain')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'the_explain'),
    'ALTER TABLE `cigen_word_link` RENAME COLUMN `theExplain` TO `the_explain`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- cigen_word_link: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `cigen_word_link` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- cigen_word_link: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `cigen_word_link` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- daka
-- daka: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `daka` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- daka: forLearningDate -> for_learning_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'forLearningDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'for_learning_date'),
    'ALTER TABLE `daka` RENAME COLUMN `forLearningDate` TO `for_learning_date`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- daka: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `daka` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- daka: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `daka` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict
-- dict: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `dict` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict: isReady -> is_ready
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'isReady')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'is_ready'),
    'ALTER TABLE `dict` RENAME COLUMN `isReady` TO `is_ready`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict: isShared -> is_shared
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'isShared')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'is_shared'),
    'ALTER TABLE `dict` RENAME COLUMN `isShared` TO `is_shared`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict: ownerId -> owner_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'ownerId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'owner_id'),
    'ALTER TABLE `dict` RENAME COLUMN `ownerId` TO `owner_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict: popularityLimit -> popularity_limit
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'popularityLimit')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'popularity_limit'),
    'ALTER TABLE `dict` RENAME COLUMN `popularityLimit` TO `popularity_limit`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `dict` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict: wordCount -> word_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'wordCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND COLUMN_NAME = 'word_count'),
    'ALTER TABLE `dict` RENAME COLUMN `wordCount` TO `word_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_group
-- dict_group: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `dict_group` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict_group: displayIndex -> display_index
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'displayIndex')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'display_index'),
    'ALTER TABLE `dict_group` RENAME COLUMN `displayIndex` TO `display_index`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict_group: parentId -> parent_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'parentId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'parent_id'),
    'ALTER TABLE `dict_group` RENAME COLUMN `parentId` TO `parent_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict_group: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `dict_group` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_word
-- dict_word: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `dict_word` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict_word: dictId -> dict_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'dictId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'dict_id'),
    'ALTER TABLE `dict_word` RENAME COLUMN `dictId` TO `dict_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict_word: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `dict_word` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- dict_word: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `dict_word` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- email_verification_code
-- email_verification_code: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'email_verification_code' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'email_verification_code' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `email_verification_code` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- email_verification_code: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'email_verification_code' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'email_verification_code' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `email_verification_code` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- error_report
-- error_report: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `error_report` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- error_report: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `error_report` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- error_report: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `error_report` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event
-- event: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `event` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- event: eventType -> event_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'eventType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'event_type'),
    'ALTER TABLE `event` RENAME COLUMN `eventType` TO `event_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- event: sentenceId -> sentence_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'sentenceId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'sentence_id'),
    'ALTER TABLE `event` RENAME COLUMN `sentenceId` TO `sentence_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- event: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `event` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- event: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `event` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- event: wordImageId -> word_image_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'wordImageId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'word_image_id'),
    'ALTER TABLE `event` RENAME COLUMN `wordImageId` TO `word_image_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- event: wordShortDescChineseId -> word_short_desc_chinese_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'wordShortDescChineseId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'word_short_desc_chinese_id'),
    'ALTER TABLE `event` RENAME COLUMN `wordShortDescChineseId` TO `word_short_desc_chinese_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- feature_request
-- feature_request: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `feature_request` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request: creatorId -> creator_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'creatorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'creator_id'),
    'ALTER TABLE `feature_request` RENAME COLUMN `creatorId` TO `creator_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `feature_request` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request: voteCount -> vote_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'voteCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND COLUMN_NAME = 'vote_count'),
    'ALTER TABLE `feature_request` RENAME COLUMN `voteCount` TO `vote_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- feature_request_report
-- feature_request_report: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `feature_request_report` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_report: featureRequestId -> feature_request_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'featureRequestId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'feature_request_id'),
    'ALTER TABLE `feature_request_report` RENAME COLUMN `featureRequestId` TO `feature_request_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_report: reporterId -> reporter_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'reporterId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'reporter_id'),
    'ALTER TABLE `feature_request_report` RENAME COLUMN `reporterId` TO `reporter_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_report: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `feature_request_report` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- feature_request_vote
-- feature_request_vote: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `feature_request_vote` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_vote: requestId -> request_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'requestId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'request_id'),
    'ALTER TABLE `feature_request_vote` RENAME COLUMN `requestId` TO `request_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_vote: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `feature_request_vote` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_vote: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `feature_request_vote` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum
-- forum: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `forum` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `forum` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post
-- forum_post: browseCount -> browse_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'browseCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'browse_count'),
    'ALTER TABLE `forum_post` RENAME COLUMN `browseCount` TO `browse_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `forum_post` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: forumId -> forum_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'forumId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'forum_id'),
    'ALTER TABLE `forum_post` RENAME COLUMN `forumId` TO `forum_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: lastReplyTime -> last_reply_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'lastReplyTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'last_reply_time'),
    'ALTER TABLE `forum_post` RENAME COLUMN `lastReplyTime` TO `last_reply_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: postContent -> post_content
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'postContent')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'post_content'),
    'ALTER TABLE `forum_post` RENAME COLUMN `postContent` TO `post_content`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: postTitle -> post_title
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'postTitle')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'post_title'),
    'ALTER TABLE `forum_post` RENAME COLUMN `postTitle` TO `post_title`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: replyCount -> reply_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'replyCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'reply_count'),
    'ALTER TABLE `forum_post` RENAME COLUMN `replyCount` TO `reply_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `forum_post` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `forum_post` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post_reply
-- forum_post_reply: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `forum_post_reply` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post_reply: forumPostId -> forum_post_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'forumPostId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'forum_post_id'),
    'ALTER TABLE `forum_post_reply` RENAME COLUMN `forumPostId` TO `forum_post_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post_reply: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `forum_post_reply` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post_reply: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `forum_post_reply` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- game_hall
-- game_hall: basePoint -> base_point
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'basePoint')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'base_point'),
    'ALTER TABLE `game_hall` RENAME COLUMN `basePoint` TO `base_point`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- game_hall: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `game_hall` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- game_hall: dictGroupId -> dict_group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'dictGroupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'dict_group_id'),
    'ALTER TABLE `game_hall` RENAME COLUMN `dictGroupId` TO `dict_group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- game_hall: displayOrder -> display_order
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'displayOrder')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'display_order'),
    'ALTER TABLE `game_hall` RENAME COLUMN `displayOrder` TO `display_order`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- game_hall: gameType -> game_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'gameType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'game_type'),
    'ALTER TABLE `game_hall` RENAME COLUMN `gameType` TO `game_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- game_hall: hallGroupId -> hall_group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'hallGroupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'hall_group_id'),
    'ALTER TABLE `game_hall` RENAME COLUMN `hallGroupId` TO `hall_group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- game_hall: hallName -> hall_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'hallName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'hall_name'),
    'ALTER TABLE `game_hall` RENAME COLUMN `hallName` TO `hall_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- game_hall: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `game_hall` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- get_pwd_log
-- get_pwd_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `get_pwd_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- get_pwd_log: sendTime -> send_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'sendTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'send_time'),
    'ALTER TABLE `get_pwd_log` RENAME COLUMN `sendTime` TO `send_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- get_pwd_log: toEmail -> to_email
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'toEmail')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'to_email'),
    'ALTER TABLE `get_pwd_log` RENAME COLUMN `toEmail` TO `to_email`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- get_pwd_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'get_pwd_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `get_pwd_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- hall_group
-- hall_group: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `hall_group` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- hall_group: displayOrder -> display_order
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'displayOrder')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'display_order'),
    'ALTER TABLE `hall_group` RENAME COLUMN `displayOrder` TO `display_order`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- hall_group: gameType -> game_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'gameType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'game_type'),
    'ALTER TABLE `hall_group` RENAME COLUMN `gameType` TO `game_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- hall_group: groupName -> group_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'groupName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'group_name'),
    'ALTER TABLE `hall_group` RENAME COLUMN `groupName` TO `group_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- hall_group: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'hall_group' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `hall_group` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- info_vote_log
-- info_vote_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `info_vote_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- info_vote_log: infoId -> info_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'infoId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'info_id'),
    'ALTER TABLE `info_vote_log` RENAME COLUMN `infoId` TO `info_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- info_vote_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `info_vote_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- info_vote_log: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `info_vote_log` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- info_vote_log: voteTime -> vote_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'voteTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'vote_time'),
    'ALTER TABLE `info_vote_log` RENAME COLUMN `voteTime` TO `vote_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- info_vote_log: voteType -> vote_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'voteType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'vote_type'),
    'ALTER TABLE `info_vote_log` RENAME COLUMN `voteType` TO `vote_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- info_vote_log: wordAdditionalInfoId -> word_additional_info_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'wordAdditionalInfoId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND COLUMN_NAME = 'word_additional_info_id'),
    'ALTER TABLE `info_vote_log` RENAME COLUMN `wordAdditionalInfoId` TO `word_additional_info_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_dict
-- learning_dict: IsPrivileged -> is_privileged
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'IsPrivileged')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'is_privileged'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `IsPrivileged` TO `is_privileged`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_dict: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_dict: currentWordId -> current_word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'currentWordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'current_word_id'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `currentWordId` TO `current_word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_dict: currentWordSeq -> current_word_seq
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'currentWordSeq')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'current_word_seq'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `currentWordSeq` TO `current_word_seq`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_dict: dictId -> dict_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'dictId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'dict_id'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `dictId` TO `dict_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_dict: fetchMastered -> fetch_mastered
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'fetchMastered')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'fetch_mastered'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `fetchMastered` TO `fetch_mastered`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_dict: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_dict: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `learning_dict` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- learning_word
-- learning_word: addDay -> add_day
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'addDay')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'add_day'),
    'ALTER TABLE `learning_word` RENAME COLUMN `addDay` TO `add_day`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: addTime -> add_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'addTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'add_time'),
    'ALTER TABLE `learning_word` RENAME COLUMN `addTime` TO `add_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `learning_word` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: isTodayNewWord -> is_today_new_word
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'isTodayNewWord')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'is_today_new_word'),
    'ALTER TABLE `learning_word` RENAME COLUMN `isTodayNewWord` TO `is_today_new_word`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: lastLearningDate -> last_learning_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'lastLearningDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'last_learning_date'),
    'ALTER TABLE `learning_word` RENAME COLUMN `lastLearningDate` TO `last_learning_date`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: learnedTimes -> learned_times
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'learnedTimes')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'learned_times'),
    'ALTER TABLE `learning_word` RENAME COLUMN `learnedTimes` TO `learned_times`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: learningOrder -> learning_order
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'learningOrder')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'learning_order'),
    'ALTER TABLE `learning_word` RENAME COLUMN `learningOrder` TO `learning_order`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: lifeValue -> life_value
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'lifeValue')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'life_value'),
    'ALTER TABLE `learning_word` RENAME COLUMN `lifeValue` TO `life_value`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `learning_word` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `learning_word` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- learning_word: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_word' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `learning_word` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- level
-- level: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `level` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- level: maxScore -> max_score
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'maxScore')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'max_score'),
    'ALTER TABLE `level` RENAME COLUMN `maxScore` TO `max_score`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- level: minScore -> min_score
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'minScore')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'min_score'),
    'ALTER TABLE `level` RENAME COLUMN `minScore` TO `min_score`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- level: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'level' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `level` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- login_log
-- login_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `login_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- login_log: loginTime -> login_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'loginTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'login_time'),
    'ALTER TABLE `login_log` RENAME COLUMN `loginTime` TO `login_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- login_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `login_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- login_log: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `login_log` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- mastered_word
-- mastered_word: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `mastered_word` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- mastered_word: masterAtTime -> master_at_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'masterAtTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'master_at_time'),
    'ALTER TABLE `mastered_word` RENAME COLUMN `masterAtTime` TO `master_at_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- mastered_word: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `mastered_word` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- mastered_word: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `mastered_word` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- mastered_word: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `mastered_word` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- meaning_item
-- meaning_item: ciXing -> ci_xing
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'ciXing')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'ci_xing'),
    'ALTER TABLE `meaning_item` RENAME COLUMN `ciXing` TO `ci_xing`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- meaning_item: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `meaning_item` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- meaning_item: dictId -> dict_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'dictId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'dict_id'),
    'ALTER TABLE `meaning_item` RENAME COLUMN `dictId` TO `dict_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- meaning_item: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `meaning_item` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- meaning_item: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `meaning_item` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- msg
-- msg: clientType -> client_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'clientType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'client_type'),
    'ALTER TABLE `msg` RENAME COLUMN `clientType` TO `client_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- msg: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `msg` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- msg: fromUserId -> from_user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'fromUserId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'from_user_id'),
    'ALTER TABLE `msg` RENAME COLUMN `fromUserId` TO `from_user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- msg: msgType -> msg_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'msgType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'msg_type'),
    'ALTER TABLE `msg` RENAME COLUMN `msgType` TO `msg_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- msg: toUserId -> to_user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'toUserId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'to_user_id'),
    'ALTER TABLE `msg` RENAME COLUMN `toUserId` TO `to_user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- msg: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `msg` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence
-- sentence: authorId -> author_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'authorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'author_id'),
    'ALTER TABLE `sentence` RENAME COLUMN `authorId` TO `author_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sentence` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: englishDigest -> english_digest
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'englishDigest')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'english_digest'),
    'ALTER TABLE `sentence` RENAME COLUMN `englishDigest` TO `english_digest`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: footCount -> foot_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'footCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'foot_count'),
    'ALTER TABLE `sentence` RENAME COLUMN `footCount` TO `foot_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: handCount -> hand_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'handCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'hand_count'),
    'ALTER TABLE `sentence` RENAME COLUMN `handCount` TO `hand_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: lastDiyUpdateTime -> last_diy_update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'lastDiyUpdateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'last_diy_update_time'),
    'ALTER TABLE `sentence` RENAME COLUMN `lastDiyUpdateTime` TO `last_diy_update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: meaningItemId -> meaning_item_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'meaningItemId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'meaning_item_id'),
    'ALTER TABLE `sentence` RENAME COLUMN `meaningItemId` TO `meaning_item_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: needTts -> need_tts
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'needTts')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'need_tts'),
    'ALTER TABLE `sentence` RENAME COLUMN `needTts` TO `need_tts`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: partOfSpeech -> part_of_speech
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'partOfSpeech')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'part_of_speech'),
    'ALTER TABLE `sentence` RENAME COLUMN `partOfSpeech` TO `part_of_speech`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: theType -> the_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'theType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'the_type'),
    'ALTER TABLE `sentence` RENAME COLUMN `theType` TO `the_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sentence` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: wordMeaning -> word_meaning
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'wordMeaning')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'word_meaning'),
    'ALTER TABLE `sentence` RENAME COLUMN `wordMeaning` TO `word_meaning`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_update_notify
-- sentence_update_notify: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sentence_update_notify` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_update_notify: sentenceId -> sentence_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND COLUMN_NAME = 'sentenceId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND COLUMN_NAME = 'sentence_id'),
    'ALTER TABLE `sentence_update_notify` RENAME COLUMN `sentenceId` TO `sentence_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_update_notify: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sentence_update_notify` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sms_verification_code
-- sms_verification_code: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sms_verification_code' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sms_verification_code' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sms_verification_code` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sms_verification_code: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sms_verification_code' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sms_verification_code' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sms_verification_code` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group
-- study_group: cowDung -> cow_dung
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'cowDung')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'cow_dung'),
    'ALTER TABLE `study_group` RENAME COLUMN `cowDung` TO `cow_dung`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `study_group` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group: creatorId -> creator_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'creatorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'creator_id'),
    'ALTER TABLE `study_group` RENAME COLUMN `creatorId` TO `creator_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group: groupName -> group_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'groupName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'group_name'),
    'ALTER TABLE `study_group` RENAME COLUMN `groupName` TO `group_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group: groupRemark -> group_remark
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'groupRemark')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'group_remark'),
    'ALTER TABLE `study_group` RENAME COLUMN `groupRemark` TO `group_remark`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group: groupTitle -> group_title
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'groupTitle')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'group_title'),
    'ALTER TABLE `study_group` RENAME COLUMN `groupTitle` TO `group_title`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group: studyGroupGradeId -> study_group_grade_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'studyGroupGradeId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'study_group_grade_id'),
    'ALTER TABLE `study_group` RENAME COLUMN `studyGroupGradeId` TO `study_group_grade_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `study_group` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_grade
-- study_group_grade: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `study_group_grade` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_grade: maxUserCount -> max_user_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND COLUMN_NAME = 'maxUserCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND COLUMN_NAME = 'max_user_count'),
    'ALTER TABLE `study_group_grade` RENAME COLUMN `maxUserCount` TO `max_user_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_grade: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `study_group_grade` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post
-- study_group_post: browseCount -> browse_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'browseCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'browse_count'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `browseCount` TO `browse_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: lastReplyTime -> last_reply_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'lastReplyTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'last_reply_time'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `lastReplyTime` TO `last_reply_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: postContent -> post_content
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'postContent')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'post_content'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `postContent` TO `post_content`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: postTitle -> post_title
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'postTitle')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'post_title'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `postTitle` TO `post_title`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: replyCount -> reply_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'replyCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'reply_count'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `replyCount` TO `reply_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: studyGroupId -> study_group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'studyGroupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'study_group_id'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `studyGroupId` TO `study_group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post_reply
-- study_group_post_reply: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `study_group_post_reply` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post_reply: studyGroupPostId -> study_group_post_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'studyGroupPostId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'study_group_post_id'),
    'ALTER TABLE `study_group_post_reply` RENAME COLUMN `studyGroupPostId` TO `study_group_post_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post_reply: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `study_group_post_reply` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post_reply: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `study_group_post_reply` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_snapshot_daily
-- study_group_snapshot_daily: cowDung -> cow_dung
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'cowDung')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'cow_dung'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `cowDung` TO `cow_dung`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: dakaRatio -> daka_ratio
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'dakaRatio')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'daka_ratio'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `dakaRatio` TO `daka_ratio`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: dakaScore -> daka_score
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'dakaScore')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'daka_score'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `dakaScore` TO `daka_score`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: gameScore -> game_score
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'gameScore')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'game_score'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `gameScore` TO `game_score`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: groupId -> group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'groupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'group_id'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `groupId` TO `group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: memberCount -> member_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'memberCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'member_count'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `memberCount` TO `member_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: orderNo -> order_no
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'orderNo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'order_no'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `orderNo` TO `order_no`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: theDate -> the_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'theDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'the_date'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `theDate` TO `the_date`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_snapshot_daily: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- synonym
-- synonym: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `synonym` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- synonym: meaningItemId -> meaning_item_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'meaningItemId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'meaning_item_id'),
    'ALTER TABLE `synonym` RENAME COLUMN `meaningItemId` TO `meaning_item_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- synonym: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `synonym` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- synonym: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'synonym' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `synonym` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sys_db_log
-- sys_db_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sys_db_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sys_db_log: recordId -> record_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'recordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'record_id'),
    'ALTER TABLE `sys_db_log` RENAME COLUMN `recordId` TO `record_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sys_db_log: tblName -> tbl_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'tblName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'tbl_name'),
    'ALTER TABLE `sys_db_log` RENAME COLUMN `tblName` TO `tbl_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sys_db_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sys_db_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sys_db_version
-- sys_db_version: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_version' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_version' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sys_db_version` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sys_db_version: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_version' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_db_version' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sys_db_version` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sys_param
-- sys_param: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sys_param` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sys_param: paramName -> param_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'paramName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'param_name'),
    'ALTER TABLE `sys_param` RENAME COLUMN `paramName` TO `param_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sys_param: paramValue -> param_value
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'paramValue')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'param_value'),
    'ALTER TABLE `sys_param` RENAME COLUMN `paramValue` TO `param_value`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sys_param: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sys_param' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sys_param` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- update_log
-- update_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'update_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'update_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `update_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- update_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'update_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'update_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `update_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user
-- user: asrPassRule -> asr_pass_rule
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'asrPassRule')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'asr_pass_rule'),
    'ALTER TABLE `user` RENAME COLUMN `asrPassRule` TO `asr_pass_rule`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: autoPlaySentence -> auto_play_sentence
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'autoPlaySentence')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'auto_play_sentence'),
    'ALTER TABLE `user` RENAME COLUMN `autoPlaySentence` TO `auto_play_sentence`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: autoPlayWord -> auto_play_word
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'autoPlayWord')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'auto_play_word'),
    'ALTER TABLE `user` RENAME COLUMN `autoPlayWord` TO `auto_play_word`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: continuousDakaDayCount -> continuous_daka_day_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'continuousDakaDayCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'continuous_daka_day_count'),
    'ALTER TABLE `user` RENAME COLUMN `continuousDakaDayCount` TO `continuous_daka_day_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: cowDung -> cow_dung
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'cowDung')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'cow_dung'),
    'ALTER TABLE `user` RENAME COLUMN `cowDung` TO `cow_dung`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: dakaDayCount -> daka_day_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'dakaDayCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'daka_day_count'),
    'ALTER TABLE `user` RENAME COLUMN `dakaDayCount` TO `daka_day_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: dakaScore -> daka_score
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'dakaScore')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'daka_score'),
    'ALTER TABLE `user` RENAME COLUMN `dakaScore` TO `daka_score`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: enableAllWrong -> enable_all_wrong
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'enableAllWrong')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'enable_all_wrong'),
    'ALTER TABLE `user` RENAME COLUMN `enableAllWrong` TO `enable_all_wrong`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: gameScore -> game_score
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'gameScore')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'game_score'),
    'ALTER TABLE `user` RENAME COLUMN `gameScore` TO `game_score`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: inviteAwardTaken -> invite_award_taken
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'inviteAwardTaken')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'invite_award_taken'),
    'ALTER TABLE `user` RENAME COLUMN `inviteAwardTaken` TO `invite_award_taken`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: invitedById -> invited_by_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'invitedById')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'invited_by_id'),
    'ALTER TABLE `user` RENAME COLUMN `invitedById` TO `invited_by_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: isAdmin -> is_admin
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'isAdmin')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'is_admin'),
    'ALTER TABLE `user` RENAME COLUMN `isAdmin` TO `is_admin`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: isInputor -> is_inputor
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'isInputor')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'is_inputor'),
    'ALTER TABLE `user` RENAME COLUMN `isInputor` TO `is_inputor`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: isPremiumIos -> is_premium_ios
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'isPremiumIos')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'is_premium_ios'),
    'ALTER TABLE `user` RENAME COLUMN `isPremiumIos` TO `is_premium_ios`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: isSuperAdmin -> is_super_admin
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'isSuperAdmin')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'is_super_admin'),
    'ALTER TABLE `user` RENAME COLUMN `isSuperAdmin` TO `is_super_admin`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: isSysUser -> is_sys_user
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'isSysUser')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'is_sys_user'),
    'ALTER TABLE `user` RENAME COLUMN `isSysUser` TO `is_sys_user`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: lastDakaDate -> last_daka_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'lastDakaDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'last_daka_date'),
    'ALTER TABLE `user` RENAME COLUMN `lastDakaDate` TO `last_daka_date`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: lastLearningDate -> last_learning_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'lastLearningDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'last_learning_date'),
    'ALTER TABLE `user` RENAME COLUMN `lastLearningDate` TO `last_learning_date`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: lastLearningMode -> last_learning_mode
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'lastLearningMode')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'last_learning_mode'),
    'ALTER TABLE `user` RENAME COLUMN `lastLearningMode` TO `last_learning_mode`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: lastLearningPosition -> last_learning_position
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'lastLearningPosition')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'last_learning_position'),
    'ALTER TABLE `user` RENAME COLUMN `lastLearningPosition` TO `last_learning_position`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: lastLoginTime -> last_login_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'lastLoginTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'last_login_time'),
    'ALTER TABLE `user` RENAME COLUMN `lastLoginTime` TO `last_login_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: lastReceiptDataIos -> last_receipt_data_ios
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'lastReceiptDataIos')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'last_receipt_data_ios'),
    'ALTER TABLE `user` RENAME COLUMN `lastReceiptDataIos` TO `last_receipt_data_ios`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: lastShareTime -> last_share_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'lastShareTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'last_share_time'),
    'ALTER TABLE `user` RENAME COLUMN `lastShareTime` TO `last_share_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: learnedDays -> learned_days
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'learnedDays')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'learned_days'),
    'ALTER TABLE `user` RENAME COLUMN `learnedDays` TO `learned_days`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: learningFinished -> learning_finished
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'learningFinished')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'learning_finished'),
    'ALTER TABLE `user` RENAME COLUMN `learningFinished` TO `learning_finished`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: levelId -> level_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'levelId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'level_id'),
    'ALTER TABLE `user` RENAME COLUMN `levelId` TO `level_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: masteredWords -> mastered_words
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'masteredWords')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'mastered_words'),
    'ALTER TABLE `user` RENAME COLUMN `masteredWords` TO `mastered_words`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: maxContinuousDakaDayCount -> max_continuous_daka_day_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'maxContinuousDakaDayCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'max_continuous_daka_day_count'),
    'ALTER TABLE `user` RENAME COLUMN `maxContinuousDakaDayCount` TO `max_continuous_daka_day_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: nickName -> nick_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'nickName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'nick_name'),
    'ALTER TABLE `user` RENAME COLUMN `nickName` TO `nick_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: showAnswersDirectly -> show_answers_directly
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'showAnswersDirectly')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'show_answers_directly'),
    'ALTER TABLE `user` RENAME COLUMN `showAnswersDirectly` TO `show_answers_directly`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: subscriptionExpireDateIos -> subscription_expire_date_ios
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'subscriptionExpireDateIos')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'subscription_expire_date_ios'),
    'ALTER TABLE `user` RENAME COLUMN `subscriptionExpireDateIos` TO `subscription_expire_date_ios`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: subscriptionStatusIos -> subscription_status_ios
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'subscriptionStatusIos')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'subscription_status_ios'),
    'ALTER TABLE `user` RENAME COLUMN `subscriptionStatusIos` TO `subscription_status_ios`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: subscriptionTypeIos -> subscription_type_ios
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'subscriptionTypeIos')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'subscription_type_ios'),
    'ALTER TABLE `user` RENAME COLUMN `subscriptionTypeIos` TO `subscription_type_ios`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: throwDiceChance -> throw_dice_chance
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'throwDiceChance')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'throw_dice_chance'),
    'ALTER TABLE `user` RENAME COLUMN `throwDiceChance` TO `throw_dice_chance`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: userName -> user_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'userName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'user_name'),
    'ALTER TABLE `user` RENAME COLUMN `userName` TO `user_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: wechatAvatar -> wechat_avatar
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechatAvatar')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechat_avatar'),
    'ALTER TABLE `user` RENAME COLUMN `wechatAvatar` TO `wechat_avatar`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: wechatNickname -> wechat_nickname
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechatNickname')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechat_nickname'),
    'ALTER TABLE `user` RENAME COLUMN `wechatNickname` TO `wechat_nickname`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: wechatOpenId -> wechat_open_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechatOpenId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechat_open_id'),
    'ALTER TABLE `user` RENAME COLUMN `wechatOpenId` TO `wechat_open_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: wechatUnionId -> wechat_union_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechatUnionId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wechat_union_id'),
    'ALTER TABLE `user` RENAME COLUMN `wechatUnionId` TO `wechat_union_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: wordsPerDay -> words_per_day
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'wordsPerDay')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND COLUMN_NAME = 'words_per_day'),
    'ALTER TABLE `user` RENAME COLUMN `wordsPerDay` TO `words_per_day`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_cow_dung_log
-- user_cow_dung_log: cowDung -> cow_dung
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'cowDung')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'cow_dung'),
    'ALTER TABLE `user_cow_dung_log` RENAME COLUMN `cowDung` TO `cow_dung`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_cow_dung_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_cow_dung_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_cow_dung_log: theTime -> the_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'theTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'the_time'),
    'ALTER TABLE `user_cow_dung_log` RENAME COLUMN `theTime` TO `the_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_cow_dung_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_cow_dung_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_cow_dung_log: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_cow_dung_log` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_db_issue
-- user_db_issue: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_db_issue` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_issue: issueType -> issue_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'issueType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'issue_type'),
    'ALTER TABLE `user_db_issue` RENAME COLUMN `issueType` TO `issue_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_issue: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_db_issue` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_issue: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_issue' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_db_issue` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_db_log
-- user_db_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_db_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_log: recordId -> record_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'recordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'record_id'),
    'ALTER TABLE `user_db_log` RENAME COLUMN `recordId` TO `record_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_log: tblName -> tbl_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'tblName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'tbl_name'),
    'ALTER TABLE `user_db_log` RENAME COLUMN `tblName` TO `tbl_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_db_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_log: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_log' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_db_log` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_db_version
-- user_db_version: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_db_version` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_version: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_db_version` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_db_version: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_db_version` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_game
-- user_game: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_game` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_game: loseCount -> lose_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'loseCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'lose_count'),
    'ALTER TABLE `user_game` RENAME COLUMN `loseCount` TO `lose_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_game: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_game` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_game: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_game` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_game: winCount -> win_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'winCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND COLUMN_NAME = 'win_count'),
    'ALTER TABLE `user_game` RENAME COLUMN `winCount` TO `win_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_oper
-- user_oper: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_oper` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_oper: operTime -> oper_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'operTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'oper_time'),
    'ALTER TABLE `user_oper` RENAME COLUMN `operTime` TO `oper_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_oper: operType -> oper_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'operType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'oper_type'),
    'ALTER TABLE `user_oper` RENAME COLUMN `operType` TO `oper_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_oper: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_oper` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_oper: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_oper` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_score_log
-- user_score_log: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_score_log` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_score_log: theTime -> the_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'theTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'the_time'),
    'ALTER TABLE `user_score_log` RENAME COLUMN `theTime` TO `the_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_score_log: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_score_log` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_score_log: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_score_log` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_snapshot_daily
-- user_snapshot_daily: cowDung -> cow_dung
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'cowDung')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'cow_dung'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `cowDung` TO `cow_dung`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: dakaDays -> daka_days
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'dakaDays')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'daka_days'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `dakaDays` TO `daka_days`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: learnedWords -> learned_words
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'learnedWords')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'learned_words'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `learnedWords` TO `learned_words`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: masteredWords -> mastered_words
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'masteredWords')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'mastered_words'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `masteredWords` TO `mastered_words`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: russiaScore -> russia_score
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'russiaScore')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'russia_score'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `russiaScore` TO `russia_score`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: theDate -> the_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'theDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'the_date'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `theDate` TO `the_date`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_snapshot_daily: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_snapshot_daily` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_study_record
-- user_study_record: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_study_record` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_record: endTime -> end_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'endTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'end_time'),
    'ALTER TABLE `user_study_record` RENAME COLUMN `endTime` TO `end_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_record: startTime -> start_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'startTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'start_time'),
    'ALTER TABLE `user_study_record` RENAME COLUMN `startTime` TO `start_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_record: theDate -> the_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'theDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'the_date'),
    'ALTER TABLE `user_study_record` RENAME COLUMN `theDate` TO `the_date`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_record: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_study_record` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_record: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_study_record` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_study_step
-- user_study_step: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_study_step` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_step: studyStep -> study_step
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'studyStep')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'study_step'),
    'ALTER TABLE `user_study_step` RENAME COLUMN `studyStep` TO `study_step`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_step: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_study_step` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_study_step: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_study_step` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- verb_tense
-- verb_tense: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `verb_tense` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- verb_tense: tenseType -> tense_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'tenseType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'tense_type'),
    'ALTER TABLE `verb_tense` RENAME COLUMN `tenseType` TO `tense_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- verb_tense: tensedSpell -> tensed_spell
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'tensedSpell')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'tensed_spell'),
    'ALTER TABLE `verb_tense` RENAME COLUMN `tensedSpell` TO `tensed_spell`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- verb_tense: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `verb_tense` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- verb_tense: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `verb_tense` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word
-- word: americaPronounce -> america_pronounce
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'americaPronounce')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'america_pronounce'),
    'ALTER TABLE `word` RENAME COLUMN `americaPronounce` TO `america_pronounce`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word: britishPronounce -> british_pronounce
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'britishPronounce')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'british_pronounce'),
    'ALTER TABLE `word` RENAME COLUMN `britishPronounce` TO `british_pronounce`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `word` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word: groupInfo -> group_info
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'groupInfo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'group_info'),
    'ALTER TABLE `word` RENAME COLUMN `groupInfo` TO `group_info`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word: longDesc -> long_desc
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'longDesc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'long_desc'),
    'ALTER TABLE `word` RENAME COLUMN `longDesc` TO `long_desc`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word: shortDesc -> short_desc
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'shortDesc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'short_desc'),
    'ALTER TABLE `word` RENAME COLUMN `shortDesc` TO `short_desc`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `word` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_additional_info
-- word_additional_info: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `word_additional_info` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_additional_info: footCount -> foot_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'footCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'foot_count'),
    'ALTER TABLE `word_additional_info` RENAME COLUMN `footCount` TO `foot_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_additional_info: handCount -> hand_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'handCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'hand_count'),
    'ALTER TABLE `word_additional_info` RENAME COLUMN `handCount` TO `hand_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_additional_info: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `word_additional_info` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_additional_info: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `word_additional_info` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_additional_info: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `word_additional_info` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_image
-- word_image: authorId -> author_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'authorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'author_id'),
    'ALTER TABLE `word_image` RENAME COLUMN `authorId` TO `author_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_image: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `word_image` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_image: imageFile -> image_file
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'imageFile')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'image_file'),
    'ALTER TABLE `word_image` RENAME COLUMN `imageFile` TO `image_file`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_image: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `word_image` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_image: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `word_image` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_sentence
-- word_sentence: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `word_sentence` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_sentence: sentenceId -> sentence_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'sentenceId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'sentence_id'),
    'ALTER TABLE `word_sentence` RENAME COLUMN `sentenceId` TO `sentence_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_sentence: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `word_sentence` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_sentence: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `word_sentence` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_shortdesc_chinese
-- word_shortdesc_chinese: authorId -> author_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'authorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'author_id'),
    'ALTER TABLE `word_shortdesc_chinese` RENAME COLUMN `authorId` TO `author_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_shortdesc_chinese: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `word_shortdesc_chinese` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_shortdesc_chinese: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `word_shortdesc_chinese` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- word_shortdesc_chinese: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `word_shortdesc_chinese` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_wrong_word
-- user_wrong_word: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `user_wrong_word` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_wrong_word: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `user_wrong_word` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_wrong_word: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `user_wrong_word` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_wrong_word: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `user_wrong_word` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- ===== 额外补充（非实体建模/历史字段） =====
-- group_and_dict_link（该表未建模为实体，需手工补充）
-- group_and_dict_link: groupId -> group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND COLUMN_NAME = 'groupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND COLUMN_NAME = 'group_id'),
    'ALTER TABLE `group_and_dict_link` RENAME COLUMN `groupId` TO `group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- group_and_dict_link: dictId -> dict_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND COLUMN_NAME = 'dictId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND COLUMN_NAME = 'dict_id'),
    'ALTER TABLE `group_and_dict_link` RENAME COLUMN `dictId` TO `dict_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese（该表未建模为实体，需手工补充）
-- sentence_chinese: sentenceId -> sentence_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'sentenceId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'sentence_id'),
    'ALTER TABLE `sentence_chinese` RENAME COLUMN `sentenceId` TO `sentence_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- similar_word（该表未建模为实体，需手工补充）
-- similar_word: similarWordId -> similar_word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND COLUMN_NAME = 'similarWordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND COLUMN_NAME = 'similar_word_id'),
    'ALTER TABLE `similar_word` RENAME COLUMN `similarWordId` TO `similar_word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- similar_word: wordId -> word_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND COLUMN_NAME = 'wordId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND COLUMN_NAME = 'word_id'),
    'ALTER TABLE `similar_word` RENAME COLUMN `wordId` TO `word_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event（补充：代码中使用了 sentenceChineseId）
-- event: sentenceChineseId -> sentence_chinese_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'sentenceChineseId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND COLUMN_NAME = 'sentence_chinese_id'),
    'ALTER TABLE `event` RENAME COLUMN `sentenceChineseId` TO `sentence_chinese_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_word（补充：部分代码仍在使用 dictName）
-- dict_word: dictName -> dict_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'dictName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND COLUMN_NAME = 'dict_name'),
    'ALTER TABLE `dict_word` RENAME COLUMN `dictName` TO `dict_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
