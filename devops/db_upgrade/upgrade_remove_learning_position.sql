-- =====================================================
-- 废除"当前学习位置"字段的数据库升级脚本
-- 执行时间: 在应用升级前执行
-- =====================================================

-- 1. 删除 learning_dict 表中不再使用的字段
ALTER TABLE learning_dict DROP COLUMN IF EXISTS current_word_seq;
ALTER TABLE learning_dict DROP COLUMN IF EXISTS current_word_id;

-- 2. (可选) 删除 currPosOfLearningDict 函数 (如果不再需要)
-- 注意: 先检查该函数是否有其他依赖
-- DROP FUNCTION IF EXISTS currPosOfLearningDict;

-- =====================================================
-- 说明:
-- 废除 current_word_seq 和 current_word_id 字段后:
-- - 取词逻辑改为: 词书中既不在 learning_word 也不在 mastered_word 的词
-- - 学习进度改为: (word_count - 未学习词数) / word_count
-- =====================================================
