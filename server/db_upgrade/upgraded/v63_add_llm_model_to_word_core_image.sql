-- 为 word_core_image 新增 llm_model 字段
-- 
-- 数据库方言: PostgreSQL
-- 背景: 记录评估单词、构建一词多义认知拓扑网络及生成文生图提示词所使用的文本语言大模型标识（如 deepseek-chat）。
-- 与现有的 image_model（文生图大模型，如 doubao-seedream-4-0-250828）成对记录，完整追溯生成链路。

ALTER TABLE "word_core_image" ADD COLUMN IF NOT EXISTS "llm_model" VARCHAR(100);

COMMENT ON COLUMN "word_core_image"."llm_model" IS '生成拓扑网络与文生图提示词的文本大模型标识（如 deepseek-chat）';
