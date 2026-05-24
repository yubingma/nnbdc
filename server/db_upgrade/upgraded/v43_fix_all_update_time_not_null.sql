-- ==========================================
-- 第一阶段：自动补齐缺失的审计字段 (针对链接表等)
-- ==========================================
DO $$ 
DECLARE 
    t text;
BEGIN
    -- 查找所有在 public 模式下但缺少 create_time 或 update_time 的表
    FOR t IN (SELECT table_name FROM information_schema.tables 
              WHERE table_schema = 'public' 
              AND table_type = 'BASE TABLE') 
    LOOP
        -- 如果缺少 create_time，则添加
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                       WHERE table_name = t AND column_name = 'create_time') THEN
            EXECUTE format('ALTER TABLE %I ADD COLUMN create_time TIMESTAMP', t);
        END IF;

        -- 如果缺少 update_time，则添加
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                       WHERE table_name = t AND column_name = 'update_time') THEN
            EXECUTE format('ALTER TABLE %I ADD COLUMN update_time TIMESTAMP', t);
        END IF;
    END LOOP;
END $$;

-- ==========================================
-- 第二阶段：动态数据修复 (确保 create_time 和 update_time 都有值)
-- ==========================================
DO $$ 
DECLARE 
    t text;
BEGIN
    -- 1. 处理 create_time
    FOR t IN (SELECT table_name FROM information_schema.columns 
              WHERE column_name = 'create_time' 
              AND table_schema = 'public') 
    LOOP
        -- 将 create_time 为空的记录补齐为 2000-01-01
        EXECUTE format('UPDATE %I SET create_time = ''2000-01-01 00:00:00'' WHERE create_time IS NULL', t);
    END LOOP;

    -- 2. 处理 update_time
    FOR t IN (SELECT table_name FROM information_schema.columns 
              WHERE column_name = 'update_time' 
              AND table_schema = 'public') 
    LOOP
        -- 此时 create_time 已确保有值，优先用它补齐 update_time
        EXECUTE format('UPDATE %I SET update_time = COALESCE(create_time, NOW()) WHERE update_time IS NULL', t);
    END LOOP;
END $$;

-- ==========================================
-- 第三阶段：动态约束锁定 (设为 NOT NULL)
-- ==========================================
DO $$ 
DECLARE 
    t text;
    col text;
BEGIN
    FOR t, col IN (SELECT table_name, column_name FROM information_schema.columns 
                   WHERE column_name IN ('create_time', 'update_time') 
                   AND table_schema = 'public' 
                   AND is_nullable = 'YES') 
    LOOP
        EXECUTE format('ALTER TABLE %I ALTER COLUMN %I SET NOT NULL', t, col);
    END LOOP;
END $$;
