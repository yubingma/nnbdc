-- 1. 确保 FSRS 模型字段存在
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS stability DOUBLE PRECISION;
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS difficulty DOUBLE PRECISION;
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS elapsed_days INTEGER;
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS scheduled_days INTEGER;
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS reps INTEGER;
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS lapses INTEGER;
ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS state INTEGER;

-- 2. 迁移数据并删除旧字段 (mastery_level 或 life_value)
DO $$
DECLARE
    col_name TEXT;
BEGIN
    -- 优先检查 mastery_level
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='learning_word' AND column_name='mastery_level') THEN
        col_name := 'mastery_level';
    -- 如果没有 mastery_level, 检查原始的 life_value
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='learning_word' AND column_name='life_value') THEN
        col_name := 'life_value';
    END IF;

    IF col_name IS NOT NULL THEN
        -- 迁移数据到 FSRS 核心参数 (针对还未有 FSRS 数据的老记录)
        IF col_name = 'mastery_level' THEN
            EXECUTE 'UPDATE learning_word SET ' ||
                    'stability = CASE ' ||
                    '    WHEN mastery_level >= 5 THEN 180.0 ' ||
                    '    WHEN mastery_level = 4 THEN 14.0 ' ||
                    '    WHEN mastery_level = 3 THEN 6.0 ' ||
                    '    WHEN mastery_level = 2 THEN 3.0 ' ||
                    '    WHEN mastery_level = 1 THEN 1.0 ' ||
                    '    ELSE 0.1 ' ||
                    'END, ' ||
                    'difficulty = COALESCE(difficulty, 5.0), ' ||
                    'reps = COALESCE(reps, mastery_level), ' ||
                    'state = COALESCE(state, 2), ' ||
                    'elapsed_days = COALESCE(elapsed_days, 0), ' ||
                    'scheduled_days = COALESCE(scheduled_days, 0), ' ||
                    'lapses = COALESCE(lapses, 0) ' ||
                    'WHERE stability IS NULL';
        ELSE
            -- life_value 逻辑: 0 是掌握, 越大越生疏
            EXECUTE 'UPDATE learning_word SET ' ||
                    'stability = CASE ' ||
                    '    WHEN life_value <= 0 THEN 180.0 ' ||
                    '    WHEN life_value = 1 THEN 14.0 ' ||
                    '    WHEN life_value = 2 THEN 6.0 ' ||
                    '    WHEN life_value = 3 THEN 3.0 ' ||
                    '    WHEN life_value = 4 THEN 1.0 ' ||
                    '    ELSE 0.1 ' ||
                    'END, ' ||
                    'difficulty = COALESCE(difficulty, 5.0), ' ||
                    'reps = COALESCE(reps, 5 - life_value), ' ||
                    'state = COALESCE(state, 2), ' ||
                    'elapsed_days = COALESCE(elapsed_days, 0), ' ||
                    'scheduled_days = COALESCE(scheduled_days, 0), ' ||
                    'lapses = COALESCE(lapses, 0) ' ||
                    'WHERE stability IS NULL';
        END IF;

        -- 删除旧字段
        EXECUTE 'ALTER TABLE learning_word DROP COLUMN ' || col_name;
        
        -- 重置批次标记，确保前后端逻辑一致
        ALTER TABLE learning_word ALTER COLUMN batch_id DROP NOT NULL;
        ALTER TABLE learning_word ALTER COLUMN batch_id DROP DEFAULT;
        UPDATE learning_word SET batch_id = NULL;
        
        -- 删除相关的同步日志，避免同步旧数据格式引起前端崩溃
        DELETE FROM user_db_log WHERE tbl_name = 'learningWords' OR tbl_name = 'learning_word';
    END IF;
END $$;
