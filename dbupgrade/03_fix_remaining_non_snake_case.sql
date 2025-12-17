-- 数据库升级脚本：修复剩余非 snake_case 的列名/索引名
-- 日期：2025-12-17
-- 来源：自动扫描 /tmp/bdc.sql 生成
-- 说明：可重复执行；仅当旧名存在且新名不存在时才执行
-- 依赖：MySQL 8+（RENAME COLUMN）/ MySQL 5.7+（RENAME INDEX）

-- ===== 表名修复（如存在旧表名则改） =====
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record')
    AND NOT EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_record'),
    'RENAME TABLE `study_record` TO `user_study_record`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- ===== 列名修复（snake_case） =====
-- forum_and_manager_link: forumId -> forum_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND COLUMN_NAME = 'forumId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND COLUMN_NAME = 'forum_id'),
    'ALTER TABLE `forum_and_manager_link` RENAME COLUMN `forumId` TO `forum_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_and_manager_link: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `forum_and_manager_link` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post: postCreatorId -> post_creator_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'postCreatorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND COLUMN_NAME = 'post_creator_id'),
    'ALTER TABLE `forum_post` RENAME COLUMN `postCreatorId` TO `post_creator_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_post_reply: postId -> post_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'postId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'post_id'),
    'ALTER TABLE `forum_post_reply` RENAME COLUMN `postId` TO `post_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- forum_post_reply: postReplyerId -> post_replyer_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'postReplyerId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND COLUMN_NAME = 'post_replyer_id'),
    'ALTER TABLE `forum_post_reply` RENAME COLUMN `postReplyerId` TO `post_replyer_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- id_gen: sequenceName -> sequence_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'id_gen' AND COLUMN_NAME = 'sequenceName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'id_gen' AND COLUMN_NAME = 'sequence_name'),
    'ALTER TABLE `id_gen` RENAME COLUMN `sequenceName` TO `sequence_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- id_gen: nextVal -> next_val
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'id_gen' AND COLUMN_NAME = 'nextVal')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'id_gen' AND COLUMN_NAME = 'next_val'),
    'ALTER TABLE `id_gen` RENAME COLUMN `nextVal` TO `next_val`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- meaning_item: isUpdating -> is_updating
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'isUpdating')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'is_updating'),
    'ALTER TABLE `meaning_item` RENAME COLUMN `isUpdating` TO `is_updating`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- meaning_item: updatingStartAt -> updating_start_at
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'updatingStartAt')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND COLUMN_NAME = 'updating_start_at'),
    'ALTER TABLE `meaning_item` RENAME COLUMN `updatingStartAt` TO `updating_start_at`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence: tempSoundUrl -> temp_sound_url
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'tempSoundUrl')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'temp_sound_url'),
    'ALTER TABLE `sentence` RENAME COLUMN `tempSoundUrl` TO `temp_sound_url`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: isUpdating -> is_updating
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'isUpdating')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'is_updating'),
    'ALTER TABLE `sentence` RENAME COLUMN `isUpdating` TO `is_updating`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: updatingStartAt -> updating_start_at
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'updatingStartAt')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'updating_start_at'),
    'ALTER TABLE `sentence` RENAME COLUMN `updatingStartAt` TO `updating_start_at`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: englishRaw -> english_raw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'englishRaw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'english_raw'),
    'ALTER TABLE `sentence` RENAME COLUMN `englishRaw` TO `english_raw`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence: chineseRaw -> chinese_raw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'chineseRaw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND COLUMN_NAME = 'chinese_raw'),
    'ALTER TABLE `sentence` RENAME COLUMN `chineseRaw` TO `chinese_raw`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sentence_chinese` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_chinese: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sentence_chinese` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_chinese: footCount -> foot_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'footCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'foot_count'),
    'ALTER TABLE `sentence_chinese` RENAME COLUMN `footCount` TO `foot_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_chinese: handCount -> hand_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'handCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'hand_count'),
    'ALTER TABLE `sentence_chinese` RENAME COLUMN `handCount` TO `hand_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_chinese: itemType -> item_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'itemType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND COLUMN_NAME = 'item_type'),
    'ALTER TABLE `sentence_chinese` RENAME COLUMN `itemType` TO `item_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sentence_chinese_remark: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `sentence_chinese_remark` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_chinese_remark: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `sentence_chinese_remark` RENAME COLUMN `updateTime` TO `update_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- sentence_chinese_remark: chineseId -> chinese_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND COLUMN_NAME = 'chineseId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND COLUMN_NAME = 'chinese_id'),
    'ALTER TABLE `sentence_chinese_remark` RENAME COLUMN `chineseId` TO `chinese_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group: gradeId -> grade_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'gradeId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND COLUMN_NAME = 'grade_id'),
    'ALTER TABLE `study_group` RENAME COLUMN `gradeId` TO `grade_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_manager_link: groupId -> group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND COLUMN_NAME = 'groupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND COLUMN_NAME = 'group_id'),
    'ALTER TABLE `study_group_and_manager_link` RENAME COLUMN `groupId` TO `group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_and_manager_link: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `study_group_and_manager_link` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_and_user_link: groupId -> group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND COLUMN_NAME = 'groupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND COLUMN_NAME = 'group_id'),
    'ALTER TABLE `study_group_and_user_link` RENAME COLUMN `groupId` TO `group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_and_user_link: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `study_group_and_user_link` RENAME COLUMN `userId` TO `user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post: groupId -> group_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'groupId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'group_id'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `groupId` TO `group_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post: postCreatorId -> post_creator_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'postCreatorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND COLUMN_NAME = 'post_creator_id'),
    'ALTER TABLE `study_group_post` RENAME COLUMN `postCreatorId` TO `post_creator_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post_reply: postId -> post_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'postId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'post_id'),
    'ALTER TABLE `study_group_post_reply` RENAME COLUMN `postId` TO `post_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- study_group_post_reply: postReplyerId -> post_replyer_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'postReplyerId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND COLUMN_NAME = 'post_replyer_id'),
    'ALTER TABLE `study_group_post_reply` RENAME COLUMN `postReplyerId` TO `post_replyer_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_record: theDate -> the_date
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'theDate')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'the_date'),
    'ALTER TABLE `study_record` RENAME COLUMN `theDate` TO `the_date`',
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
-- study_record: userId -> user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'user_id'),
    'ALTER TABLE `study_record` RENAME COLUMN `userId` TO `user_id`',
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
-- study_record: createTime -> create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'create_time'),
    'ALTER TABLE `study_record` RENAME COLUMN `createTime` TO `create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
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
-- study_record: updateTime -> update_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'updateTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'update_time'),
    'ALTER TABLE `study_record` RENAME COLUMN `updateTime` TO `update_time`',
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
-- study_record: endTime -> end_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'endTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'end_time'),
    'ALTER TABLE `study_record` RENAME COLUMN `endTime` TO `end_time`',
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
-- study_record: startTime -> start_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'startTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_record' AND COLUMN_NAME = 'start_time'),
    'ALTER TABLE `study_record` RENAME COLUMN `startTime` TO `start_time`',
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

-- ===== 索引名修复（snake_case/小写） =====
-- article: INDEX FKdw5d9vdw43e3nvtpqk8l4iitp -> fkdw5d9vdw43e3nvtpqk8l4iitp
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND INDEX_NAME = 'FKdw5d9vdw43e3nvtpqk8l4iitp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'article' AND INDEX_NAME = 'fkdw5d9vdw43e3nvtpqk8l4iitp'),
    'ALTER TABLE `article` RENAME INDEX `FKdw5d9vdw43e3nvtpqk8l4iitp` TO `fkdw5d9vdw43e3nvtpqk8l4iitp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- book_mark: INDEX IDXldmdpxpesl4m2anh96p3upne5 -> id_xldmdpxpesl4m2anh96p3upne5
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND INDEX_NAME = 'IDXldmdpxpesl4m2anh96p3upne5')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'book_mark' AND INDEX_NAME = 'id_xldmdpxpesl4m2anh96p3upne5'),
    'ALTER TABLE `book_mark` RENAME INDEX `IDXldmdpxpesl4m2anh96p3upne5` TO `id_xldmdpxpesl4m2anh96p3upne5`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- cigen_word_link: INDEX FKfg6o4pg8ran0btsx0fl4v53wt -> fkfg6o4pg8ran0btsx0fl4v53wt
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND INDEX_NAME = 'FKfg6o4pg8ran0btsx0fl4v53wt')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cigen_word_link' AND INDEX_NAME = 'fkfg6o4pg8ran0btsx0fl4v53wt'),
    'ALTER TABLE `cigen_word_link` RENAME INDEX `FKfg6o4pg8ran0btsx0fl4v53wt` TO `fkfg6o4pg8ran0btsx0fl4v53wt`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- daka: INDEX FK9lw3569kklr2aem8j3lgooofo -> fk9lw3569kklr2aem8j3lgooofo
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND INDEX_NAME = 'FK9lw3569kklr2aem8j3lgooofo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'daka' AND INDEX_NAME = 'fk9lw3569kklr2aem8j3lgooofo'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND INDEX_NAME = 'dict_owner_IDX')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND INDEX_NAME = 'dict_owner_idx'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND INDEX_NAME = 'FKba1lo3o2pqjwuhuo55a173tpn')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict' AND INDEX_NAME = 'fkba1lo3o2pqjwuhuo55a173tpn'),
    'ALTER TABLE `dict` RENAME INDEX `FKba1lo3o2pqjwuhuo55a173tpn` TO `fkba1lo3o2pqjwuhuo55a173tpn`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_group: INDEX FKam1kwdtewl5mj4w24i0vjsgvr -> fkam1kwdtewl5mj4w24i0vjsgvr
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND INDEX_NAME = 'FKam1kwdtewl5mj4w24i0vjsgvr')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_group' AND INDEX_NAME = 'fkam1kwdtewl5mj4w24i0vjsgvr'),
    'ALTER TABLE `dict_group` RENAME INDEX `FKam1kwdtewl5mj4w24i0vjsgvr` TO `fkam1kwdtewl5mj4w24i0vjsgvr`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- dict_word: INDEX FKoocgndgdxfsmi9l22c779ve5f -> fkoocgndgdxfsmi9l22c779ve5f
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND INDEX_NAME = 'FKoocgndgdxfsmi9l22c779ve5f')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dict_word' AND INDEX_NAME = 'fkoocgndgdxfsmi9l22c779ve5f'),
    'ALTER TABLE `dict_word` RENAME INDEX `FKoocgndgdxfsmi9l22c779ve5f` TO `fkoocgndgdxfsmi9l22c779ve5f`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- email_verification_code: INDEX idx_createTime -> idx_create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'email_verification_code' AND INDEX_NAME = 'idx_createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'email_verification_code' AND INDEX_NAME = 'idx_create_time'),
    'ALTER TABLE `email_verification_code` RENAME INDEX `idx_createTime` TO `idx_create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- error_report: INDEX FKt63m0vobg7664cjmoyuwngl2r -> fkt63m0vobg7664cjmoyuwngl2r
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND INDEX_NAME = 'FKt63m0vobg7664cjmoyuwngl2r')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'error_report' AND INDEX_NAME = 'fkt63m0vobg7664cjmoyuwngl2r'),
    'ALTER TABLE `error_report` RENAME INDEX `FKt63m0vobg7664cjmoyuwngl2r` TO `fkt63m0vobg7664cjmoyuwngl2r`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- event: INDEX FKn0s3foajghecveph3do4wqngk -> fkn0s3foajghecveph3do4wqngk
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'FKn0s3foajghecveph3do4wqngk')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'fkn0s3foajghecveph3do4wqngk'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'FKe4y90yg6c4gxbdwn2w9lgcb98')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'fke4y90yg6c4gxbdwn2w9lgcb98'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'FK8up0cm0j7flyds8mljh3wslcs')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'fk8up0cm0j7flyds8mljh3wslcs'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'FKcaqnogrpoabtlfqf9h4wuxybk')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'fkcaqnogrpoabtlfqf9h4wuxybk'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'FK8y4063ul9igji7dsmq61t7pg3')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'event' AND INDEX_NAME = 'fk8y4063ul9igji7dsmq61t7pg3'),
    'ALTER TABLE `event` RENAME INDEX `FK8y4063ul9igji7dsmq61t7pg3` TO `fk8y4063ul9igji7dsmq61t7pg3`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- feature_request: INDEX idx_status_voteCount -> idx_status_vote_count
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND INDEX_NAME = 'idx_status_voteCount')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND INDEX_NAME = 'idx_status_vote_count'),
    'ALTER TABLE `feature_request` RENAME INDEX `idx_status_voteCount` TO `idx_status_vote_count`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request: INDEX idx_creatorId -> idx_creator_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND INDEX_NAME = 'idx_creatorId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request' AND INDEX_NAME = 'idx_creator_id'),
    'ALTER TABLE `feature_request` RENAME INDEX `idx_creatorId` TO `idx_creator_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- feature_request_report: INDEX idx_reporterId -> idx_reporter_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND INDEX_NAME = 'idx_reporterId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND INDEX_NAME = 'idx_reporter_id'),
    'ALTER TABLE `feature_request_report` RENAME INDEX `idx_reporterId` TO `idx_reporter_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_report: INDEX idx_featureRequestId -> idx_feature_request_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND INDEX_NAME = 'idx_featureRequestId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND INDEX_NAME = 'idx_feature_request_id'),
    'ALTER TABLE `feature_request_report` RENAME INDEX `idx_featureRequestId` TO `idx_feature_request_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_report: INDEX idx_createTime -> idx_create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND INDEX_NAME = 'idx_createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_report' AND INDEX_NAME = 'idx_create_time'),
    'ALTER TABLE `feature_request_report` RENAME INDEX `idx_createTime` TO `idx_create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- feature_request_vote: INDEX idx_requestId -> idx_request_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND INDEX_NAME = 'idx_requestId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND INDEX_NAME = 'idx_request_id'),
    'ALTER TABLE `feature_request_vote` RENAME INDEX `idx_requestId` TO `idx_request_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- feature_request_vote: INDEX idx_userId -> idx_user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND INDEX_NAME = 'idx_userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'feature_request_vote' AND INDEX_NAME = 'idx_user_id'),
    'ALTER TABLE `feature_request_vote` RENAME INDEX `idx_userId` TO `idx_user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- forum_and_manager_link: INDEX FK4rgldqqyj2v6ko5fb3j4h00hw -> fk4rgldqqyj2v6ko5fb3j4h00hw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND INDEX_NAME = 'FK4rgldqqyj2v6ko5fb3j4h00hw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND INDEX_NAME = 'fk4rgldqqyj2v6ko5fb3j4h00hw'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND INDEX_NAME = 'FKm2ne0gyp8to1iltn9y5xatn5g')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_and_manager_link' AND INDEX_NAME = 'fkm2ne0gyp8to1iltn9y5xatn5g'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND INDEX_NAME = 'FKh0s5a90088gbywb9u9j5fase4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND INDEX_NAME = 'fkh0s5a90088gbywb9u9j5fase4'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND INDEX_NAME = 'FK89ba00sxrqhbgl7cgwt6y0tux')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post' AND INDEX_NAME = 'fk89ba00sxrqhbgl7cgwt6y0tux'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND INDEX_NAME = 'FKsmolky8m77uf3aygscwtlh7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND INDEX_NAME = 'fksmolky8m77uf3aygscwtlh7'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND INDEX_NAME = 'FKctt5g9ionoo960lak0p7ss6ou')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'forum_post_reply' AND INDEX_NAME = 'fkctt5g9ionoo960lak0p7ss6ou'),
    'ALTER TABLE `forum_post_reply` RENAME INDEX `FKctt5g9ionoo960lak0p7ss6ou` TO `fkctt5g9ionoo960lak0p7ss6ou`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- game_hall: INDEX FKbb8bsyk402u3fxe0vnv2ecp12 -> fkbb8bsyk402u3fxe0vnv2ecp12
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND INDEX_NAME = 'FKbb8bsyk402u3fxe0vnv2ecp12')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND INDEX_NAME = 'fkbb8bsyk402u3fxe0vnv2ecp12'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND INDEX_NAME = 'FKs184ekmq8ct8x9etyonngejo4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'game_hall' AND INDEX_NAME = 'fks184ekmq8ct8x9etyonngejo4'),
    'ALTER TABLE `game_hall` RENAME INDEX `FKs184ekmq8ct8x9etyonngejo4` TO `fks184ekmq8ct8x9etyonngejo4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- group_and_dict_link: INDEX FKhuoc8hxjs2c8w1fgickojg6ff -> fkhuoc8hxjs2c8w1fgickojg6ff
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND INDEX_NAME = 'FKhuoc8hxjs2c8w1fgickojg6ff')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND INDEX_NAME = 'fkhuoc8hxjs2c8w1fgickojg6ff'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND INDEX_NAME = 'FKanvwboyqdce5mb41j8q4qly3c')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'group_and_dict_link' AND INDEX_NAME = 'fkanvwboyqdce5mb41j8q4qly3c'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND INDEX_NAME = 'FKnyxodwmjasis1v8c04xsen7dh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'info_vote_log' AND INDEX_NAME = 'fknyxodwmjasis1v8c04xsen7dh'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND INDEX_NAME = 'FKs6prwtgob6wmhxysa8bu1096r')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND INDEX_NAME = 'fks6prwtgob6wmhxysa8bu1096r'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND INDEX_NAME = 'FKpiu1chqdc7gn2bchpkxcbdqu6')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'learning_dict' AND INDEX_NAME = 'fkpiu1chqdc7gn2bchpkxcbdqu6'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND INDEX_NAME = 'FK9auh6uhsrknd75ipjypyyha90')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'login_log' AND INDEX_NAME = 'fk9auh6uhsrknd75ipjypyyha90'),
    'ALTER TABLE `login_log` RENAME INDEX `FK9auh6uhsrknd75ipjypyyha90` TO `fk9auh6uhsrknd75ipjypyyha90`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- mastered_word: INDEX mastered_word_userId_IDX -> mastered_word_userid_idx
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND INDEX_NAME = 'mastered_word_userId_IDX')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mastered_word' AND INDEX_NAME = 'mastered_word_userid_idx'),
    'ALTER TABLE `mastered_word` RENAME INDEX `mastered_word_userId_IDX` TO `mastered_word_userid_idx`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- meaning_item: INDEX FKbq1kwqm7l14nowpnkgyct7qmb -> fkbq1kwqm7l14nowpnkgyct7qmb
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND INDEX_NAME = 'FKbq1kwqm7l14nowpnkgyct7qmb')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND INDEX_NAME = 'fkbq1kwqm7l14nowpnkgyct7qmb'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND INDEX_NAME = 'FKhajsfsxiyna9xuo9i974u8v07')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'meaning_item' AND INDEX_NAME = 'fkhajsfsxiyna9xuo9i974u8v07'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND INDEX_NAME = 'FKpwao1csk2fiqn8x0taf5n4lxp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND INDEX_NAME = 'fkpwao1csk2fiqn8x0taf5n4lxp'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND INDEX_NAME = 'FKduaesr28u3xkjgacqyp6f9k69')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'msg' AND INDEX_NAME = 'fkduaesr28u3xkjgacqyp6f9k69'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND INDEX_NAME = 'sentence_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND INDEX_NAME = 'sentence_fk'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND INDEX_NAME = 'sentence_meaning_item_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence' AND INDEX_NAME = 'sentence_meaning_item_fk'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND INDEX_NAME = 'FK1ea8mppmrgwbn1gcmn0n4s95n')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND INDEX_NAME = 'fk1ea8mppmrgwbn1gcmn0n4s95n'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND INDEX_NAME = 'FK4qkl23fg27sp450b9h3n7xnwx')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese' AND INDEX_NAME = 'fk4qkl23fg27sp450b9h3n7xnwx'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND INDEX_NAME = 'FK9eseuj1b3lp9r0cp52hl524i7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND INDEX_NAME = 'fk9eseuj1b3lp9r0cp52hl524i7'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND INDEX_NAME = 'FKqb6gj27jt2kffko46xcctg0u6')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_chinese_remark' AND INDEX_NAME = 'fkqb6gj27jt2kffko46xcctg0u6'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND INDEX_NAME = 'sentence_update_notify_FK')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sentence_update_notify' AND INDEX_NAME = 'sentence_update_notify_fk'),
    'ALTER TABLE `sentence_update_notify` RENAME INDEX `sentence_update_notify_FK` TO `sentence_update_notify_fk`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- similar_word: INDEX FK1mqflio4f1yp8ety4wsa8naku -> fk1mqflio4f1yp8ety4wsa8naku
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND INDEX_NAME = 'FK1mqflio4f1yp8ety4wsa8naku')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND INDEX_NAME = 'fk1mqflio4f1yp8ety4wsa8naku'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND INDEX_NAME = 'FKcwlj8g7yxqfqag6sbcypi705a')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'similar_word' AND INDEX_NAME = 'fkcwlj8g7yxqfqag6sbcypi705a'),
    'ALTER TABLE `similar_word` RENAME INDEX `FKcwlj8g7yxqfqag6sbcypi705a` TO `fkcwlj8g7yxqfqag6sbcypi705a`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- sms_verification_code: INDEX idx_createTime -> idx_create_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sms_verification_code' AND INDEX_NAME = 'idx_createTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sms_verification_code' AND INDEX_NAME = 'idx_create_time'),
    'ALTER TABLE `sms_verification_code` RENAME INDEX `idx_createTime` TO `idx_create_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group: INDEX UK_jpg0rl0cauvsfe6doei229ae1 -> uk_jpg0rl0cauvsfe6doei229ae1
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND INDEX_NAME = 'UK_jpg0rl0cauvsfe6doei229ae1')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND INDEX_NAME = 'uk_jpg0rl0cauvsfe6doei229ae1'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND INDEX_NAME = 'FKfml3yg6yg9a2xi45w4vx7dqfb')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND INDEX_NAME = 'fkfml3yg6yg9a2xi45w4vx7dqfb'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND INDEX_NAME = 'FK36s0562yu4gydy3xr28u95eqd')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group' AND INDEX_NAME = 'fk36s0562yu4gydy3xr28u95eqd'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND INDEX_NAME = 'FKgfviie87tlf3c34ipmx31ynj7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND INDEX_NAME = 'fkgfviie87tlf3c34ipmx31ynj7'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND INDEX_NAME = 'FKrdflptnxblu6aa5r7s9747ko4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_manager_link' AND INDEX_NAME = 'fkrdflptnxblu6aa5r7s9747ko4'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND INDEX_NAME = 'FK66ybol3y7m0xgvon3hovu9ifv')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND INDEX_NAME = 'fk66ybol3y7m0xgvon3hovu9ifv'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND INDEX_NAME = 'FKs1c5cfbgl89yn2p955v7sugj7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_and_user_link' AND INDEX_NAME = 'fks1c5cfbgl89yn2p955v7sugj7'),
    'ALTER TABLE `study_group_and_user_link` RENAME INDEX `FKs1c5cfbgl89yn2p955v7sugj7` TO `fks1c5cfbgl89yn2p955v7sugj7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_grade: INDEX UK_grr4fesaas4otr2jq0t2xh7ye -> uk_grr4fesaas4otr2jq0t2xh7ye
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND INDEX_NAME = 'UK_grr4fesaas4otr2jq0t2xh7ye')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_grade' AND INDEX_NAME = 'uk_grr4fesaas4otr2jq0t2xh7ye'),
    'ALTER TABLE `study_group_grade` RENAME INDEX `UK_grr4fesaas4otr2jq0t2xh7ye` TO `uk_grr4fesaas4otr2jq0t2xh7ye`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- study_group_post: INDEX FKc3t23fo2d1n4cqsq5ct92vtjn -> fkc3t23fo2d1n4cqsq5ct92vtjn
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND INDEX_NAME = 'FKc3t23fo2d1n4cqsq5ct92vtjn')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND INDEX_NAME = 'fkc3t23fo2d1n4cqsq5ct92vtjn'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND INDEX_NAME = 'FKmy0w3ae9nui45ii8gg5ftx03y')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post' AND INDEX_NAME = 'fkmy0w3ae9nui45ii8gg5ftx03y'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND INDEX_NAME = 'FK302iba0o0rgoegvo0en7a05jl')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND INDEX_NAME = 'fk302iba0o0rgoegvo0en7a05jl'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND INDEX_NAME = 'FKlbwltcdwo4x4hlkbl51fpph')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_post_reply' AND INDEX_NAME = 'fklbwltcdwo4x4hlkbl51fpph'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND INDEX_NAME = 'FKs0e3efs4xyt73agwc6e96wjc4')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'study_group_snapshot_daily' AND INDEX_NAME = 'fks0e3efs4xyt73agwc6e96wjc4'),
    'ALTER TABLE `study_group_snapshot_daily` RENAME INDEX `FKs0e3efs4xyt73agwc6e96wjc4` TO `fks0e3efs4xyt73agwc6e96wjc4`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user: INDEX idx_userName -> idx_user_name
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'idx_userName')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'idx_user_name'),
    'ALTER TABLE `user` RENAME INDEX `idx_userName` TO `idx_user_name`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user: INDEX user_email_IDX -> user_email_idx
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'user_email_IDX')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'user_email_idx'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'FKefu5f2ioj2qy2bycuh6g3wbkd')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'fkefu5f2ioj2qy2bycuh6g3wbkd'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'FK6lqwkmrxl04j2k3d2oqysgwvm')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user' AND INDEX_NAME = 'fk6lqwkmrxl04j2k3d2oqysgwvm'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND INDEX_NAME = 'FKp01eygbwkg91uujcjasrhbu2y')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_cow_dung_log' AND INDEX_NAME = 'fkp01eygbwkg91uujcjasrhbu2y'),
    'ALTER TABLE `user_cow_dung_log` RENAME INDEX `FKp01eygbwkg91uujcjasrhbu2y` TO `fkp01eygbwkg91uujcjasrhbu2y`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_db_version: INDEX unique_userId -> unique_user_id
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND INDEX_NAME = 'unique_userId')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_db_version' AND INDEX_NAME = 'unique_user_id'),
    'ALTER TABLE `user_db_version` RENAME INDEX `unique_userId` TO `unique_user_id`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_game: INDEX FKe1j2if58j0qgke4numextbw8a -> fke1j2if58j0qgke4numextbw8a
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND INDEX_NAME = 'FKe1j2if58j0qgke4numextbw8a')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_game' AND INDEX_NAME = 'fke1j2if58j0qgke4numextbw8a'),
    'ALTER TABLE `user_game` RENAME INDEX `FKe1j2if58j0qgke4numextbw8a` TO `fke1j2if58j0qgke4numextbw8a`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_oper: INDEX idx_userId_operTime -> idx_user_id_oper_time
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND INDEX_NAME = 'idx_userId_operTime')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND INDEX_NAME = 'idx_user_id_oper_time'),
    'ALTER TABLE `user_oper` RENAME INDEX `idx_userId_operTime` TO `idx_user_id_oper_time`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
-- user_oper: INDEX idx_operType -> idx_oper_type
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND INDEX_NAME = 'idx_operType')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_oper' AND INDEX_NAME = 'idx_oper_type'),
    'ALTER TABLE `user_oper` RENAME INDEX `idx_operType` TO `idx_oper_type`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- user_score_log: INDEX FKn1b5wicvnceas08ju14uk3qqw -> fkn1b5wicvnceas08ju14uk3qqw
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND INDEX_NAME = 'FKn1b5wicvnceas08ju14uk3qqw')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_score_log' AND INDEX_NAME = 'fkn1b5wicvnceas08ju14uk3qqw'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND INDEX_NAME = 'FKm48fwdudlv10kcn0wafvdves3')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_snapshot_daily' AND INDEX_NAME = 'fkm48fwdudlv10kcn0wafvdves3'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND INDEX_NAME = 'FKkb5mbew7a6hawfub12aotlpbh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_study_step' AND INDEX_NAME = 'fkkb5mbew7a6hawfub12aotlpbh'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND INDEX_NAME = 'FKwkw9ln2wtbqtq0e7s5ayti2t')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND INDEX_NAME = 'fkwkw9ln2wtbqtq0e7s5ayti2t'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND INDEX_NAME = 'FKqneibfe99w3ktslncl4vt009k')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_wrong_word' AND INDEX_NAME = 'fkqneibfe99w3ktslncl4vt009k'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND INDEX_NAME = 'FKrymhs6cvyoh40cpcslopn98yo')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'verb_tense' AND INDEX_NAME = 'fkrymhs6cvyoh40cpcslopn98yo'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND INDEX_NAME = 'FKf3xqffcm8vnaqbucfr5i24yqh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND INDEX_NAME = 'fkf3xqffcm8vnaqbucfr5i24yqh'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND INDEX_NAME = 'FK5jynq4erw7uwlffv3covsa9oc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_additional_info' AND INDEX_NAME = 'fk5jynq4erw7uwlffv3covsa9oc'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND INDEX_NAME = 'FKcsrc6dqtt1q9907n2w3qcy71v')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND INDEX_NAME = 'fkcsrc6dqtt1q9907n2w3qcy71v'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND INDEX_NAME = 'FK22nlb05j0hk398isouqw9ehbc')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_image' AND INDEX_NAME = 'fk22nlb05j0hk398isouqw9ehbc'),
    'ALTER TABLE `word_image` RENAME INDEX `FK22nlb05j0hk398isouqw9ehbc` TO `fk22nlb05j0hk398isouqw9ehbc`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_sentence: INDEX FKaqa9an1x12g7s6u92i30raln7 -> fkaqa9an1x12g7s6u92i30raln7
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND INDEX_NAME = 'FKaqa9an1x12g7s6u92i30raln7')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_sentence' AND INDEX_NAME = 'fkaqa9an1x12g7s6u92i30raln7'),
    'ALTER TABLE `word_sentence` RENAME INDEX `FKaqa9an1x12g7s6u92i30raln7` TO `fkaqa9an1x12g7s6u92i30raln7`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

-- word_shortdesc_chinese: INDEX FKtfaryode4etiv5gh8vr47bnbh -> fktfaryode4etiv5gh8vr47bnbh
SET @__sql := (
  SELECT IF(
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND INDEX_NAME = 'FKtfaryode4etiv5gh8vr47bnbh')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND INDEX_NAME = 'fktfaryode4etiv5gh8vr47bnbh'),
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
    EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND INDEX_NAME = 'FK662626om3lfe5ov2fohxuqpgp')
    AND NOT EXISTS(SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'word_shortdesc_chinese' AND INDEX_NAME = 'fk662626om3lfe5ov2fohxuqpgp'),
    'ALTER TABLE `word_shortdesc_chinese` RENAME INDEX `FK662626om3lfe5ov2fohxuqpgp` TO `fk662626om3lfe5ov2fohxuqpgp`',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;
