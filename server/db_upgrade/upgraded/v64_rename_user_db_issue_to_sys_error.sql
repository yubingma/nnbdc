-- =========================================================================
-- v64: 将用户端云同步问题表 user_db_issue 重命名并升级为系统与客户端异常日志表 sys_error
-- 拓宽其适用范围：不仅承载服务端数据同步冲突，还能承载客户端同步异常与全局系统错误
-- =========================================================================

-- 1. 表重命名
ALTER TABLE IF EXISTS "user_db_issue" RENAME TO "sys_error";

-- 2. 字段类型与约束调整
-- 允许 user_id 为空（支持未登录或游客状态下的客户端/系统异常记录）
ALTER TABLE "sys_error" ALTER COLUMN "user_id" DROP NOT NULL;

-- 字段 issue_type 更名为 error_type
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'sys_error' AND column_name = 'issue_type'
    ) THEN
        ALTER TABLE "sys_error" RENAME COLUMN "issue_type" TO "error_type";
    END IF;
END $$;

-- 将 details 扩展为 TEXT，以容纳完整的异常堆栈和上下文信息
ALTER TABLE "sys_error" ALTER COLUMN "details" TYPE TEXT;

-- 3. 添加标准中文业务注释
COMMENT ON TABLE "sys_error" IS '系统与客户端异常日志表';
COMMENT ON COLUMN "sys_error"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "sys_error"."user_id" IS '关联用户ID (可为空)';
COMMENT ON COLUMN "sys_error"."error_type" IS '异常类型分类';
COMMENT ON COLUMN "sys_error"."details" IS '异常堆栈与上下文详情';
COMMENT ON COLUMN "sys_error"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "sys_error"."update_time" IS '最后更新时间';
