-- =========================================================================
-- 更新日期: 2026-03-22
-- 描述: 添加 tts_voice 和 tts_engine 字段用于保存 AI 生成例句语音的具体引擎和角色信息
-- 目标表: sentence
-- 数据库: PostgreSQL
-- =========================================================================

ALTER TABLE sentence ADD COLUMN IF NOT EXISTS tts_voice VARCHAR(50);
ALTER TABLE sentence ADD COLUMN IF NOT EXISTS tts_engine VARCHAR(50);

-- 可选：给之前的记录加上默认标记，否则为空
-- UPDATE sentence SET tts_engine = 'cosyvoice-v1', tts_voice = 'longxiaochun' WHERE the_type = 'tts' AND tts_engine IS NULL;
