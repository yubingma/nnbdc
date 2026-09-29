-- ============================================================================
-- NBDC 生产数据修复脚本：清理“同一次作答被重复计分”的历史脏数据
--
-- 【执行前置条件与顺序 · 务必按序】
--   ① 客户端闸门修复必须先发版（app/lib/page/bdc/providers/bdc_notifier.dart 的
--      _pendingGrade / _answerAccepted）。否则边修边脏：修复期间线上每天仍新增
--      约 700~1100 个词日的重复计分。
--   ② 再执行本脚本（去重日志 + 用日志真值恢复 learning_word 的 memory 字段）。
--   ③ 最后执行“掌握线对账”：把 stability >= 120 但不在已掌握记录里的词补录
--      （口径改为“四个月不忘”后，存量 S∈[120,180) 的约 3667 个词否则会一直隐身）。
--   本脚本幂等，可重复执行；重复执行时第 ② 步无匹配行，天然为 no-op。
--
-- 【默认是干跑】文件末尾为 ROLLBACK，确认无误后改为 COMMIT 再执行。
-- 【执行前】把下方两张备份表名里的 20260929 改成执行当天日期（同日重复执行会覆盖上一次备份）。
-- 【备份】自动写入 learning_log_dup_backup_YYYYMMDD / learning_word_state_backup_YYYYMMDD，
--         回滚只需把这两张表按主键写回（已在 2026-09-29 于本地生产副本上实测通过）。
-- ============================================================================
-- 修复“同一次作答被重复计分”产生的历史脏数据
--
-- 根因：客户端把一次作答提交了两次（autoJump 定时器 / 详情页 / 下一词按钮多链路），
--       第二次被 isFirstAttemptOfStep 误判为“下一个环节的首次作答”，于是重复写日志、
--       并把用户没做的学习环节顶掉（today_learned_times 虚高）。
--       客户端闸门修复见 app/lib/page/bdc/providers/bdc_notifier.dart（_pendingGrade/_answerAccepted）。
--
-- 判据：同一 (user_id, word_id) 相邻两条日志间隔 < 50ms 的“后一条”必为重复计分。
--       依据：间隔直方图呈明显双峰 —— 10-50ms 聚集 11.3 万条，而 0.2s~5s 区间几乎为空
--       （人不可能在 50ms 内完成下一环节作答）；>=5s 才是真实用户操作。
--
-- 动作：
--   1) 备份待删日志 + 待修 learning_word 行（可回滚、可审计）
--   2) 删除重复日志
--   3) 用“该词现存最后一条日志”恢复被重复计分污染的 memory 字段
--      （stability/difficulty/elapsed_days/scheduled_days —— 均来自日志真值，不做算法重算）
--   4) 输出校验统计
--
-- 幂等：已清理的数据不再匹配判据，可重复执行。
-- 注意：本脚本不修改 state / reps / lapses / today_learned_times（属状态机与计数语义，
--       改动风险高于收益，留给后续独立评估）；也不回收 user_study_daily_stats 的虚高计数。
--
-- 用法（生产）：docker exec -i pg psql -Umyb -d bdc -v ON_ERROR_STOP=1 < repair_dup_logs.sql
-- ============================================================================
BEGIN;

-- 0) 待删日志与受影响词
CREATE TEMP TABLE tmp_dup_ids ON COMMIT DROP AS
WITH l AS (
  SELECT id, user_id, word_id, create_time,
         lag(create_time) OVER (PARTITION BY user_id, word_id ORDER BY create_time, id) AS prev_t
  FROM learning_log
)
SELECT id FROM l
WHERE prev_t IS NOT NULL
  AND create_time - prev_t < interval '50 milliseconds';

CREATE TEMP TABLE tmp_affected_words ON COMMIT DROP AS
SELECT l.user_id, l.word_id
FROM learning_log l
JOIN tmp_dup_ids d ON d.id = l.id
GROUP BY 1, 2;

-- 1) 备份（建表语句幂等；重复执行时追加会重复，故先清空本次后缀的表）
CREATE TABLE IF NOT EXISTS learning_log_dup_backup_20260929 (LIKE learning_log INCLUDING ALL);
CREATE TABLE IF NOT EXISTS learning_word_state_backup_20260929 (LIKE learning_word INCLUDING ALL);
DELETE FROM learning_log_dup_backup_20260929;
DELETE FROM learning_word_state_backup_20260929;

INSERT INTO learning_log_dup_backup_20260929
SELECT l.* FROM learning_log l JOIN tmp_dup_ids d ON d.id = l.id;

INSERT INTO learning_word_state_backup_20260929
SELECT w.* FROM learning_word w JOIN tmp_affected_words a
  ON a.user_id = w.user_id AND a.word_id = w.word_id;

-- 2) 删除重复日志
DELETE FROM learning_log l USING tmp_dup_ids d WHERE l.id = d.id;

-- 3) 用现存最后一条日志恢复 memory 字段（仅对受影响的词）
--    注意：已毕业词的 stability 是哨兵值 180（Constants.graduationStability，见 StudyBo._saveMasteredWord），
--    毕业那次评分不写日志，因此绝不能按最后一条日志把它改回去 —— 必须排除。
WITH last_log AS (
  SELECT DISTINCT ON (l.user_id, l.word_id)
         l.user_id, l.word_id, l.stability, l.difficulty, l.elapsed_days, l.scheduled_days
  FROM learning_log l
  JOIN tmp_affected_words a ON a.user_id = l.user_id AND a.word_id = l.word_id
  ORDER BY l.user_id, l.word_id, l.create_time DESC, l.id DESC
)
UPDATE learning_word w
SET stability      = ll.stability,
    difficulty     = ll.difficulty,
    elapsed_days   = ll.elapsed_days,
    scheduled_days = ll.scheduled_days,
    update_time    = now()
FROM last_log ll
WHERE w.user_id = ll.user_id
  AND w.word_id = ll.word_id
  AND (w.stability IS NULL OR w.stability < 120);  -- 不触碰已掌握词（掌握线 120 天 ≈ 4 个月不忘）

-- 4) 校验统计
WITH affected AS (
  SELECT DISTINCT user_id, word_id FROM learning_log_dup_backup_20260929
), last_log AS (
  SELECT DISTINCT ON (l.user_id, l.word_id) l.user_id, l.word_id, l.stability
  FROM learning_log l JOIN affected a ON a.user_id = l.user_id AND a.word_id = l.word_id
  ORDER BY l.user_id, l.word_id, l.create_time DESC, l.id DESC
)
SELECT
  (SELECT count(*) FROM learning_log_dup_backup_20260929) AS 备份日志_待删,
  (SELECT count(*) FROM learning_word_state_backup_20260929) AS 备份词状态,
  (SELECT count(*) FROM learning_word w
     JOIN learning_word_state_backup_20260929 b ON b.user_id = w.user_id AND b.word_id = w.word_id
    WHERE w.stability IS DISTINCT FROM b.stability) AS 实际改动词数,
  (SELECT count(*) FROM learning_word w JOIN last_log ll ON ll.user_id = w.user_id AND ll.word_id = w.word_id
    WHERE (w.stability IS NULL OR w.stability < 120)
      AND w.stability IS DISTINCT FROM ll.stability) AS 未掌握受影响词仍不一致_应为0,
  (SELECT count(*) FROM learning_word w
     JOIN learning_word_state_backup_20260929 b ON b.user_id = w.user_id AND b.word_id = w.word_id
    WHERE b.stability >= 120 AND b.stability IS DISTINCT FROM w.stability) AS 原本已掌握却被改动_应为0,
  (SELECT count(*) FROM (
      SELECT create_time,
             lag(create_time) OVER (PARTITION BY user_id, word_id ORDER BY create_time, id) AS prev_t
      FROM learning_log) x
    WHERE prev_t IS NOT NULL AND create_time - prev_t < interval '50 milliseconds') AS 剩余重复日志_应为0;

-- 干跑：确认无误后注释掉 ROLLBACK，改用 COMMIT
ROLLBACK;
-- COMMIT;
