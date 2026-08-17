-- Upgrade database to single-table three-group study steps (v53)
-- 单表三组重构：user_study_step 增加 scope/group_name，老激活序列映射为 scope='new' 三组，
-- user_review_study_step 已有数据并入 scope='review' 后删除该表。
-- 说明：group 是 SQL 保留字，DB 列名统一用 group_name（前端 JSON 字段仍叫 group）。

-- 1. 增加列
ALTER TABLE user_study_step ADD COLUMN IF NOT EXISTS scope VARCHAR(10);
ALTER TABLE user_study_step ADD COLUMN IF NOT EXISTS group_name VARCHAR(20);

-- 2. 去掉旧主键 (user_id, study_step)，以便同一 studyStep 可同时进入 correct 与 wrong
ALTER TABLE user_study_step DROP CONSTRAINT IF EXISTS pk_user_study_step_study_step_user_id;
ALTER TABLE user_study_step DROP CONSTRAINT IF EXISTS user_study_step_pkey;
DROP INDEX IF EXISTS pk_user_study_step_study_step_user_id;
DROP INDEX IF EXISTS user_study_step_pkey;

-- 3. 老激活序列 → scope='new'：
--    - 测评组 check：每用户 seq 最小的 Active 非 List 环节（即用户实际配置的第一个环节）
--    - 答对组 correct：其余 Active 非 List 环节（check 已先行置 scope，天然排除）
--    仅处理 scope IS NULL 的行（幂等；升级窗口内新客户端尚未同步进来）

UPDATE user_study_step SET scope = 'new', group_name = 'check'
WHERE scope IS NULL AND state = 'Active' AND study_step <> 'List'
  AND (user_id, study_step) IN (
    SELECT user_id, study_step FROM (
      SELECT user_id, study_step,
             ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY seq, study_step) AS rn
      FROM user_study_step
      WHERE scope IS NULL AND state = 'Active' AND study_step <> 'List'
    ) ranked
    WHERE rn = 1
  );

UPDATE user_study_step SET scope = 'new', group_name = 'correct'
WHERE scope IS NULL AND state = 'Active' AND study_step <> 'List';

-- 4. 答错组 wrong：老序列不分对错，答对/答错走同样环节 → 与 correct 组一致，各存一份
INSERT INTO user_study_step (user_id, scope, group_name, study_step, seq, state, create_time, update_time)
SELECT s.user_id, 'new', 'wrong', s.study_step, s.seq, s.state, s.create_time, s.update_time
FROM user_study_step s
WHERE s.scope = 'new' AND s.group_name = 'correct'
  AND NOT EXISTS (
    SELECT 1 FROM user_study_step w
    WHERE w.user_id = s.user_id AND w.scope = 'new' AND w.group_name = 'wrong' AND w.study_step = s.study_step
  );

-- 5. 丢弃 List 与 Inactive 行（三组模型无 List 环节；Inactive 在新模型中无意义）
DELETE FROM user_study_step WHERE study_step = 'List' OR state != 'Active' OR scope IS NULL;

-- 6. user_review_study_step 已有数据并入 scope='review'（幂等防重）
INSERT INTO user_study_step (user_id, scope, group_name, study_step, seq, state, create_time, update_time)
SELECT r.user_id, 'review', r.group_name, r.study_step, r.seq, r.state, r.create_time, r.update_time
FROM user_review_study_step r
WHERE r.state = 'Active'
  AND NOT EXISTS (
    SELECT 1 FROM user_study_step e
    WHERE e.user_id = r.user_id AND e.scope = 'review' AND e.group_name = r.group_name AND e.study_step = r.study_step
  );

-- 7. 删除已并入的旧词独立表
DROP TABLE IF EXISTS user_review_study_step;

-- 8. 重建主键 (user_id, scope, group_name, study_step)
ALTER TABLE user_study_step ADD PRIMARY KEY (user_id, scope, group_name, study_step);
