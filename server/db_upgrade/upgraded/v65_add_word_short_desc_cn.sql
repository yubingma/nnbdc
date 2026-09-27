-- 为 word 新增 short_desc_cn 字段（「深度讲解」的中文译文）
--
-- 数据库方言: PostgreSQL
-- 背景: word.short_desc 是单词的英文简要描述（App「单词详情 → 深度讲解」展示的正文），
-- 现为其补充中文译文，与 short_desc 一一对应，随 word 行一起进入端云同步通道。
-- 类型使用 TEXT：译文长度由模型生成质量决定，不做人为截断，避免超长入库报错。

ALTER TABLE "word" ADD COLUMN IF NOT EXISTS "short_desc_cn" TEXT;

COMMENT ON COLUMN "word"."short_desc_cn" IS '单词简要描述(深度讲解)的中文译文';
