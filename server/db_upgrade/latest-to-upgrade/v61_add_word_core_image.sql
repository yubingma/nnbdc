-- 一词多义核心意象与 AI 生图表 (word_core_image)
--
-- 数据库方言: PostgreSQL
-- 背景: 存储经认知语言学与词源学提示词由大模型（DeepSeek）分析得出的一词多义核心意象拓扑数据，
-- 以及由文生图大模型（火山引擎/豆包等）生成的核心意象矢量简笔画图。
--
-- 索引:
-- 1. word_id 建立唯一约束/索引 (uk_wci_word_id)，保证每个单词单条记录，天然支持任务断点续跑与排重。
-- 2. word 建立普通索引 (idx_wci_word)，支持按拼写快速检索。

CREATE TABLE IF NOT EXISTS word_core_image (
    id VARCHAR(32) PRIMARY KEY,
    word_id VARCHAR(32) NOT NULL,
    word VARCHAR(100) NOT NULL,
    is_applicable BOOLEAN NOT NULL DEFAULT FALSE,
    not_applicable_reason VARCHAR(255),
    core_image VARCHAR(255),
    schema_desc VARCHAR(1000),
    topology_json TEXT,
    image_prompt TEXT,
    image_url VARCHAR(500),
    image_status VARCHAR(32),
    image_model VARCHAR(100),
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL,
    CONSTRAINT uk_wci_word_id UNIQUE (word_id)
);

CREATE INDEX IF NOT EXISTS idx_wci_word ON word_core_image (word);
