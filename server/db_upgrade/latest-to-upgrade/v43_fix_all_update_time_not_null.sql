-- ==========================================
-- 第一阶段：动态数据修复 (确保所有表的 update_time 都有值)
-- ==========================================
DO $$ 
DECLARE 
    t text;
BEGIN
    FOR t IN (SELECT table_name FROM information_schema.columns 
              WHERE column_name = 'update_time' 
              AND table_schema = 'public') 
    LOOP
        -- 将 update_time 为空的记录补齐为 create_time
        -- 如果连 create_time 也为空（极少见），则补齐为当前时间
        EXECUTE format('UPDATE %I SET update_time = COALESCE(create_time, NOW()) WHERE update_time IS NULL', t);
    END LOOP;
END $$;

-- ==========================================
-- 第二阶段：动态约束锁定 (设为 NOT NULL)
-- ==========================================
DO $$ 
DECLARE 
    t text;
BEGIN
    FOR t IN (SELECT table_name FROM information_schema.columns 
              WHERE column_name = 'update_time' 
              AND table_schema = 'public' 
              AND is_nullable = 'YES') 
    LOOP
        -- 再次检查是否存在漏掉的 NULL（防御性编程）
        -- 如果存在 NULL，ALTER TABLE 会报错并回滚整个块
        EXECUTE format('ALTER TABLE %I ALTER COLUMN update_time SET NOT NULL', t);
    END LOOP;
END $$;
