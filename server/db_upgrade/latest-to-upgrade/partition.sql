-- =================================================================================
-- user_db_log 性能优化迁移脚本 (PostgreSQL)
-- 说明：将原表转换为 64 路哈希分区表，极大提升在高并发/大数据量下的同步性能。
-- =================================================================================

-- 1. 只有当主表存在且备份表不存在时，才执行重命名（防止重复运行时报错）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_db_log') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_db_log_old') THEN
        ALTER TABLE user_db_log RENAME TO user_db_log_old;
    END IF;
END $$;

-- 2. 重命名旧索引，释放名称空间
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_user_db_log_user_version') THEN
        ALTER INDEX idx_user_db_log_user_version RENAME TO idx_user_db_log_user_version_old;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_user_db_log_create_time') THEN
        ALTER INDEX idx_user_db_log_create_time RENAME TO idx_user_db_log_create_time_old;
    END IF;
END $$;

-- 3. 创建新的哈希分区主表
-- 注意：在 PG 分区表中，主键必须包含分区键（user_id）
CREATE TABLE IF NOT EXISTS user_db_log (
    id          VARCHAR(32) NOT NULL,
    user_id     VARCHAR(32) NOT NULL,
    version     INT NOT NULL,
    operate     VARCHAR(20) NOT NULL,
    tbl_name    VARCHAR(50) NOT NULL,
    record_id   VARCHAR(131) NOT NULL,
    record      TEXT NOT NULL,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP,
    CONSTRAINT user_db_log_pk PRIMARY KEY (id, user_id)
) PARTITION BY HASH (user_id);

-- 4. 使用匿名代码块一次性创建 64 个子分区 (p0 到 p63)
DO $$
BEGIN
    FOR i IN 0..63 LOOP
        -- 确定分区表是否已经存在（限定在 public schema 下）
        IF NOT EXISTS (
            SELECT 1 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
              AND table_name = 'user_db_log_p' || i
        ) THEN
            EXECUTE format(
                'CREATE TABLE public.user_db_log_p%s PARTITION OF public.user_db_log FOR VALUES WITH (MODULUS 64, REMAINDER %s)', 
                i, i
            );
        END IF;
    END LOOP;
END $$;

-- 5. 为主表创建关键索引
CREATE INDEX IF NOT EXISTS idx_user_db_log_user_version ON user_db_log (user_id, version);
CREATE INDEX IF NOT EXISTS idx_user_db_log_create_time ON user_db_log (create_time);

-- 6. 迁移数据
-- 只有在新表为空的情况下才迁移数据，防止重复迁移
DO $$
BEGIN
    IF (SELECT count(*) FROM user_db_log) = 0 THEN
        INSERT INTO user_db_log (id, user_id, version, operate, tbl_name, record_id, record, create_time, update_time)
        SELECT id, user_id, version, operate, tbl_name, record_id, record, create_time, update_time 
        FROM user_db_log_old 
        WHERE create_time > NOW() - INTERVAL '10 days';
    END IF;
END $$;
