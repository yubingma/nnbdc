-- ==============================================================================
-- v73: 修复 learning_word 历史遗留的非法难度数据 (difficulty = 0)
-- 
-- 背景:
--   在 FSRS 算法体系中，单词认知难度 difficulty 的合法区间为 [1.0, 10.0]。
--   历史遗留数据中存在 15,197 条 difficulty = 0 的记录：
--   1. 14,233 条从未学习的新词 (stability = 0, difficulty = 0, reps = 0, state = 0)，
--      按照新词规范，未评估前 stability 与 difficulty 应当为 NULL。
--   2. 964 条历史已掌握词 (stability IN (180, 120), difficulty = 0)，
--      系旧版艾宾浩斯掌握度迁移为 FSRS 时漏赋初始难度，按 FSRS 规范赋予中等基准难度 5.0。
-- ==============================================================================

-- 1. 修复历史已掌握/毕业词 (赋中等难度 5.0)
UPDATE "learning_word"
SET "difficulty" = 5.0,
    "update_time" = CURRENT_TIMESTAMP
WHERE "difficulty" = 0
  AND "stability" IN (180.0, 120.0);

-- 2. 修复存量未学习新词 (重置为 NULL，符合新词初始状态标准)
UPDATE "learning_word"
SET "stability" = NULL,
    "difficulty" = NULL,
    "update_time" = CURRENT_TIMESTAMP
WHERE "difficulty" = 0
  AND "stability" = 0
  AND "reps" = 0;
