-- 修正 dict.owner_id 字段的错误说明
--
-- 数据库方言: PostgreSQL
--
-- 背景: v62_add_table_and_column_comments.sql 第 89 行给该字段写的是
--   「官方词书此字段为null」，与生产库实际数据不符。
--
-- 生产库实测（2026-09-30，只读统计）:
--   dict 共 49076 本；
--   其中 owner_id = '15118' 的 761 本，即系统官方词书；
--   owner_id 为 NULL 的词书数量为 0；
--   其余为各用户自建词书（32 位 UUID 或历史数字 ID）。
--
-- 取值依据: Constants.SYS_USER_SYS_ID = "15118"
--   （server/nnbdc-util/src/main/java/beidanci/util/Constants.java）
--
-- 说明: 本脚本仅修正注释文字，不改动任何表结构与数据。

COMMENT ON COLUMN "dict"."owner_id" IS '词书创建者用户ID（系统官方词书为系统用户 15118，即 Constants.SYS_USER_SYS_ID；用户自建词书为该用户ID）';
