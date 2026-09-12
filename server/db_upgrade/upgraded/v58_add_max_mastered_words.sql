-- 新增"历史最高掌握词数"单调量 (user.max_mastered_words)
--
-- 背景: 段位与部分勋章此前只依赖 user.mastered_words(当前值)。用户退火重学导致当前掌握数回落后,
-- 曾达成的成就无法从数据判断, 一旦判定逻辑有 bug 便永久无法修复。
-- 该列把峰值持久化为单调量(只增不减), 使成就判定完全可从数据推出。
--
-- 说明: 本列上线前的历史峰值不可回溯(用户同步日志消费即删, user_db_log 中无 user 表历史),
-- 因此用当前 mastered_words 播种, 作为现有数据能给出的最好下界, 此后由客户端单调抬升。

ALTER TABLE "user" ADD COLUMN IF NOT EXISTS max_mastered_words INTEGER;
UPDATE "user" SET max_mastered_words = mastered_words WHERE max_mastered_words IS NULL;
