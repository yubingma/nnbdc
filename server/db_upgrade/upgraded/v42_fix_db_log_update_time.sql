-- 修复 user_db_log 和 sys_db_log 表的 update_time 字段为 NOT NULL

-- 1. 处理 user_db_log (分区表)
UPDATE user_db_log SET update_time = create_time WHERE update_time IS NULL;
ALTER TABLE user_db_log ALTER COLUMN update_time SET NOT NULL;

-- 2. 处理 sys_db_log
UPDATE sys_db_log SET update_time = create_time WHERE update_time IS NULL;
ALTER TABLE sys_db_log ALTER COLUMN update_time SET NOT NULL;
