-- 一词多义核心意象与 AI 生图表 (word_core_image)
--
-- 数据库方言: PostgreSQL
-- 背景: 存储经认知语言学与词源学提示词由大模型（DeepSeek）分析得出的一词多义核心意象拓扑数据，
-- 以及由文生图大模型（火山引擎/豆包等）生成的核心意象矢量简笔画图。
--
-- 索引:
-- 1. word_id 建立唯一约束/索引 (uk_wci_word_id)，保证每个单词单条记录，天然支持任务断点续跑与排重。
-- 2. word 建立普通索引 (idx_wci_word)，支持按拼写快速检索。

CREATE TABLE IF NOT EXISTS "word_core_image" (
    "id" VARCHAR(32) PRIMARY KEY,
    "word_id" VARCHAR(32) NOT NULL,
    "word" VARCHAR(100) NOT NULL,
    "is_applicable" BOOLEAN NOT NULL DEFAULT FALSE,
    "not_applicable_reason" VARCHAR(255),
    "core_image" VARCHAR(255),
    "schema_desc" VARCHAR(1000),
    "topology_json" TEXT,
    "image_prompt" TEXT,
    "image_url" VARCHAR(500),
    "image_status" VARCHAR(32),
    "llm_model" VARCHAR(100),
    "image_model" VARCHAR(100),
    "create_time" TIMESTAMP NOT NULL,
    "update_time" TIMESTAMP NOT NULL,
    CONSTRAINT uk_wci_word_id UNIQUE ("word_id")
);

CREATE INDEX IF NOT EXISTS idx_wci_word ON "word_core_image" ("word");

COMMENT ON TABLE "word_core_image" IS '一词多义核心意象与AI生图拓扑表：存储DeepSeek提炼的核心意象及火山引擎生图数据';
COMMENT ON COLUMN "word_core_image"."id" IS '主键ID (32位UUID)';
COMMENT ON COLUMN "word_core_image"."word_id" IS '关联的单词ID';
COMMENT ON COLUMN "word_core_image"."word" IS '单词拼写';
COMMENT ON COLUMN "word_core_image"."is_applicable" IS '大模型判定是否适合提取核心意象 (true:多义引申 / false:单一实物名词)';
COMMENT ON COLUMN "word_core_image"."not_applicable_reason" IS '不适合提取核心意象时的具体原因';
COMMENT ON COLUMN "word_core_image"."core_image" IS '4-10字底层核心意象短语（空间拓扑/力学动势机制）';
COMMENT ON COLUMN "word_core_image"."schema_desc" IS '认知语言学图式演化深度剖析说明';
COMMENT ON COLUMN "word_core_image"."topology_json" IS '核心意象与多义分支拓扑结构JSON';
COMMENT ON COLUMN "word_core_image"."image_prompt" IS '驱动文生图模型生成简笔画的中文精确提示词';
COMMENT ON COLUMN "word_core_image"."image_url" IS '生成的2D认知图式简笔画图片持久化URL';
COMMENT ON COLUMN "word_core_image"."image_status" IS '生图状态 (SUCCESS/FAILED/PENDING/SKIPPED)';
COMMENT ON COLUMN "word_core_image"."llm_model" IS '生成拓扑网络与文生图提示词的文本大模型标识（如 deepseek-chat）';
COMMENT ON COLUMN "word_core_image"."image_model" IS '使用的文生图大底座模型标识（如 doubao-seedream-4-0-250828）';
COMMENT ON COLUMN "word_core_image"."create_time" IS '记录创建时间';
COMMENT ON COLUMN "word_core_image"."update_time" IS '最后更新时间';
