-- ==========================================
-- 生产环境 sentence 表结构升级脚本 
-- ==========================================

-- 1. 为例句新增对应单词的词性 (part_of_speech) 字段
ALTER TABLE sentence ADD COLUMN IF NOT EXISTS part_of_speech VARCHAR(10);
