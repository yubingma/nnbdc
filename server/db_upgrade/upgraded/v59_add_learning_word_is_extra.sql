-- 新增"加餐"单词标记 (learning_word.is_extra)
--
-- 背景: 用户当日打卡后仍可追加学习（"再背一组"）。加餐词复用 learning_word 与既有取词/学习流程，
-- 但必须能与"今日计划"词区分开——否则加餐会污染进度环分母、今日词数、"今日目标已达成"判定，
-- 并会被取词准备流程的溢出削减当作可删对象清除。
--
-- 不变量: is_extra = TRUE 当且仅当该词属于当日加餐批次 (batch_id > 0 且由加餐取词产生)。
-- 客户端在跨天重置、削减、已掌握清理等所有将 batch_id 置 0 的地方，必须同步将本列置回 FALSE。
--
-- 说明: 本列上线前不存在加餐概念，历史数据一律为 FALSE。

ALTER TABLE learning_word ADD COLUMN IF NOT EXISTS is_extra BOOLEAN NOT NULL DEFAULT FALSE;
