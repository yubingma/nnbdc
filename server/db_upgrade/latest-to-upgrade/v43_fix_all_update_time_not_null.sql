-- ==========================================
-- 第一阶段：数据修复 (补齐 update_time 为 NULL 的记录)
-- ==========================================

-- 1. 用户与日志类
UPDATE "user" SET update_time = create_time WHERE update_time IS NULL;
UPDATE user_db_log SET update_time = create_time WHERE update_time IS NULL;
UPDATE sys_db_log SET update_time = create_time WHERE update_time IS NULL;
UPDATE user_oper SET update_time = create_time WHERE update_time IS NULL;

-- 2. 词书与关系类
UPDATE dict SET update_time = create_time WHERE update_time IS NULL;
UPDATE dict_word SET update_time = create_time WHERE update_time IS NULL;
UPDATE learning_dict SET update_time = create_time WHERE update_time IS NULL;

-- 3. 学习数据与统计类
UPDATE learning_word SET update_time = create_time WHERE update_time IS NULL;
UPDATE learning_log SET update_time = create_time WHERE update_time IS NULL;
UPDATE user_wrong_word SET update_time = create_time WHERE update_time IS NULL;
UPDATE user_study_step SET update_time = create_time WHERE update_time IS NULL;
UPDATE user_study_daily_stat SET update_time = create_time WHERE update_time IS NULL;
UPDATE daka SET update_time = create_time WHERE update_time IS NULL;
UPDATE book_mark SET update_time = create_time WHERE update_time IS NULL;
UPDATE mastered_word SET update_time = create_time WHERE update_time IS NULL;
UPDATE user_cow_dung_log SET update_time = create_time WHERE update_time IS NULL;

-- 4. 核心词库与内容类
UPDATE word SET update_time = create_time WHERE update_time IS NULL;
UPDATE meaning_item SET update_time = create_time WHERE update_time IS NULL;
UPDATE sentence SET update_time = create_time WHERE update_time IS NULL;
UPDATE word_image SET update_time = create_time WHERE update_time IS NULL;
UPDATE word_short_desc_chinese SET update_time = create_time WHERE update_time IS NULL;
UPDATE cigen SET update_time = create_time WHERE update_time IS NULL;
UPDATE cigen_word_link SET update_time = create_time WHERE update_time IS NULL;


-- ==========================================
-- 第二阶段：约束锁定 (设为 NOT NULL)
-- ==========================================

-- 脚本会自动查找所有包含 update_time 字段且目前允许为空的表，并批量将其设为 NOT NULL
DO $$ 
DECLARE 
    t text;
BEGIN
    FOR t IN (SELECT table_name FROM information_schema.columns 
              WHERE column_name = 'update_time' 
              AND table_schema = 'public' 
              AND is_nullable = 'YES') 
    LOOP
        EXECUTE format('ALTER TABLE %I ALTER COLUMN update_time SET NOT NULL', t);
    END LOOP;
END $$;
