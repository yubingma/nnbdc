-- =====================================================
-- 废除"当前学习位置"字段的数据库升级脚本
-- 执行时间: 在应用升级前执行
-- =====================================================



-- 2. 删除 learning_dict 表中不再使用的字段
ALTER TABLE learning_dict DROP COLUMN IF EXISTS current_word_seq;
ALTER TABLE learning_dict DROP COLUMN IF EXISTS current_word_id;

-- 1. 删除 user 表中不再使用的字段
ALTER TABLE "user" DROP COLUMN IF EXISTS last_learning_position;
ALTER TABLE "user" DROP COLUMN IF EXISTS last_learning_mode;

-- 3. 在 learning_word 表中增加 batch_id 字段
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS batch_id INTEGER DEFAULT 1;
COMMENT ON COLUMN learning_word.batch_id IS '今日学习中单词的取词批次';

ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS today_learned_times INTEGER DEFAULT 0;
COMMENT ON COLUMN learning_word.today_learned_times IS '今日已学习次数';

-- =====================================================
-- 说明:
-- 1. 废除 last_learning_position, current_word_seq 和 current_word_id 字段
-- 2. 增加 batch_id 字段用于识别每日取词批次，精细化管理学习进度
-- =====================================================
