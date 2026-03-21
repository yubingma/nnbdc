-- ==========================================
-- 生产环境 sentence 表结构升级脚本 
-- ==========================================

-- 1. 为例句新增对应单词的词性 (part_of_speech) 字段
ALTER TABLE sentence ADD COLUMN IF NOT EXISTS part_of_speech VARCHAR(10);

-- 2. 为 word 表新增 is_updating 字段
ALTER TABLE word ADD COLUMN IF NOT EXISTS is_updating BOOLEAN DEFAULT FALSE NOT NULL;

ALTER TABLE "user" ADD COLUMN apple_user_id VARCHAR(100) UNIQUE;