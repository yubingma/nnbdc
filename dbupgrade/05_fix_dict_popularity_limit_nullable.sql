-- 数据库升级脚本：修正 dict.popularity_limit 允许为 NULL
-- 日期：2025-12-17
-- 背景：业务含义上 popularity_limit 为 NULL 表示“不限制”，但当前库中该列为 NOT NULL，会导致同步更新失败
-- 说明：可重复执行；仅当当前列为 NOT NULL 时才执行 ALTER

SET @__sql := (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'dict'
        AND COLUMN_NAME = 'popularity_limit'
        AND IS_NULLABLE = 'NO'
    ),
    'ALTER TABLE `dict` MODIFY COLUMN `popularity_limit` int NULL DEFAULT NULL COMMENT ''过滤展示给用户的通用词典单词释义的popularity阈值''',
    'SELECT 1'
  )
);
PREPARE __stmt FROM @__sql;
EXECUTE __stmt;
DEALLOCATE PREPARE __stmt;

