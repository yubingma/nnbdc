-- 创建单词导入任务表
CREATE TABLE import_task (
    id VARCHAR(32) PRIMARY KEY,
    status VARCHAR(20) NOT NULL,        -- PENDING, RUNNING, COMPLETED, FAILED
    total_words INTEGER DEFAULT 0,
    processed_words INTEGER DEFAULT 0,
    log TEXT,                          -- 详细处理日志
    config TEXT,                       -- 任务配置 (JSON)
    file_name VARCHAR(200),             -- 源文件名
    owner_id VARCHAR(32),               -- 任务所属用户
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP
);

-- 为 MeaningItem 增加所有者字段，并设置存量数据尽可能归属于其所属词典的所有者
ALTER TABLE meaning_item ADD COLUMN IF NOT EXISTS owner_id VARCHAR(32);

-- 让释义项继承所属词典的 owner_id
UPDATE meaning_item mi
SET owner_id = d.owner_id
FROM dict d
WHERE mi.dict_id = d.id 
  AND mi.owner_id IS NULL;

-- 对于确实没有关联词典或关联词典无主的数据，兜底归属为系统管理员 ('15118')
UPDATE meaning_item SET owner_id = '15118' WHERE owner_id IS NULL;

ALTER TABLE meaning_item ALTER COLUMN owner_id SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_meaning_owner ON meaning_item(owner_id);

-- 添加外键关联到 "user" 表
ALTER TABLE import_task ADD CONSTRAINT fk_import_task_owner FOREIGN KEY (owner_id) REFERENCES "user"(id);

COMMENT ON TABLE import_task IS '单词导入任务表';

-- 2026-03-13: Add results column to track detailed statistics for import tasks
ALTER TABLE import_task ADD COLUMN results TEXT;


