-- 创建学习历史记录表
CREATE TABLE learning_log (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    word_id VARCHAR(36) NOT NULL,
    rating INTEGER NOT NULL,            -- 1: Again, 2: Hard, 3: Good, 4: Easy
    stability DOUBLE PRECISION NOT NULL,
    difficulty DOUBLE PRECISION NOT NULL,
    elapsed_days INTEGER NOT NULL,      -- 距离上次学习天数
    scheduled_days INTEGER NOT NULL,    -- 本次安排的复习间隔
    create_time TIMESTAMPTZ NOT NULL,   -- 创建时间
    update_time TIMESTAMPTZ             -- 更新时间
);

-- 创建索引以优化查询性能
CREATE INDEX idx_learning_log_user_word ON learning_log(user_id, word_id);
CREATE INDEX idx_learning_log_create_time ON learning_log(create_time DESC);

-- 为同步逻辑添加备注
COMMENT ON TABLE learning_log IS '单词学习历史记录表';
COMMENT ON COLUMN learning_log.rating IS '评分 (1: Again, 2: Hard, 3: Good, 4: Easy)';
