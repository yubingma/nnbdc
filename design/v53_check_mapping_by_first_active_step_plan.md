# v53 升级脚本修正：新词测评环节按"用户实际配置的第一个环节"映射（Plan）

> 状态：待架构审查 → 待用户审批
> 目标：修正 v53 升级脚本对新词测评组 check 的映射逻辑——由"硬编码 En2Ch"改为"按用户实际配置的第一个 Active 环节"。

## 1. 背景与问题

`server/db_upgrade/latest-to-upgrade/v53_single_table_three_group_study_steps.sql` 第 3 步将老激活序列映射到 `scope='new'` 三组：

```sql
UPDATE user_study_step SET scope = 'new', group_name = 'check'
WHERE scope IS NULL AND study_step = 'En2Ch' AND state = 'Active';
```

即：**硬编码 `study_step = 'En2Ch'` 作为测评组 check**，依赖注释假设"历史上第 1 环节恒为 En2Ch"。

该假设仅在默认初始化数据下成立；若用户自定义过学习步骤顺序（旧客户端支持 `saveStudySteps(clearFirst=true)` 及 seq 重排），`En2Ch` 可能不在第一位，映射将偏离用户实际配置。

**前端 v49 迁移已采用正确语义**（`app/lib/db/db.dart` `_migrateFromV48ToV49UserStudyStepsThreeGroup`）：

```dart
// 老激活序列 → scope='new' 三组（seq 最小的激活环节为 check，其余为 correct + wrong 各一份）
final rows = SELECT ... WHERE state = 'Active' AND study_step != 'List'  → 按 user 分组
final ordered = ...sort((a, b) => a.seq.compareTo(b.seq));
final check = ordered.first;  // 其余 → correct + wrong 各一份
```

后端 v53 与前端 v49 语义不一致，且设计文档（`fsrs_learning_review_separation_plan.md` 第 11 节）明确意图为"第1环节=check"。本次修正后端脚本，两端对齐。

## 2. 设计决策（与用户确认的方向一致）

### 2.1 check（测评组）映射规则（与前端 v49 完全对齐）

每用户取 **state='Active' 且 study_step != 'List'** 的行，按 **seq 升序**（seq 相同时按 study_step 定序，保证唯一）取第 1 行 → `scope='new', group_name='check'`。

- 排除 List：旧客户端/服务端恒将 List 排在最后，且三组模型无 List 环节（第 5 步丢弃），显式排除与前端一致。
- 排除 Inactive：Inactive 环节不参与学习（客户端 `getThreeGroupConfig` 也过滤 `state != 'Active'`）。

### 2.2 correct（答对组）映射规则

check 之外的**其余 Active 非 List 环节** → `scope='new', group_name='correct'`。

利用执行顺序天然达到：先执行 check UPDATE（该行 scope 变为 'new'），再执行 correct UPDATE 时用 `scope IS NULL` 条件即自动排除 check 行，无需显式排除。

### 2.3 幂等与丢失行为（保持现状）

- 仅处理 `scope IS NULL` 的行（升级窗口内新客户端数据不受影响）。
- 所有环节均 Inactive 或无环节的用户：无匹配行 → 该用户无 `scope='new'` 数据 → 新服务端 `initUserStudySteps`（或前端运行时默认补全）兜底默认三组。与前端 v49 行为一致。
- wrong 组（第 4 步）与 List/Inactive 丢弃（第 5 步）逻辑不变。

### 2.4 seq 保留

不重编号：check 保留原 seq（默认 En2Ch 场景下为 0），correct 保留原 seq（1..n），wrong 复制 correct 的 seq。组内相对顺序不变，语义与前端"重编号"等价。

## 3. 改动清单

### A. `server/db_upgrade/latest-to-upgrade/v53_single_table_three_group_study_steps.sql`

第 3 步两个 UPDATE 改写（含注释更新）：

```sql
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
```

- PostgreSQL 12+ 语法：`UPDATE ... WHERE (col1, col2) IN (SELECT ...)` 行值子查询。
- `ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY seq, study_step)` 保证每用户恰一行 rn=1（seq 重复时按 study_step 定序）。
- 第 4/5/6/7/8 步不动。

### B. 验证脚本（不入库，阶段 3 临时使用）

本地临时 PostgreSQL 库构造样例数据执行 v53 脚本，断言：

| 场景 | 老数据（用户 A） | 期望映射结果 |
|---|---|---|
| 默认顺序 | En2Ch(0,A), Ch2En(1,A), EnSentence2Ch(2,I), ChSentence2En(3,A), List(4,A) | check=En2Ch；correct=[Ch2En, ChSentence2En]；wrong 同 correct；List/Inactive 被删 |
| 自定义顺序（En2Ch 非首位） | Ch2En(0,A), En2Ch(1,A), List(2,A) | check=Ch2En；correct=[En2Ch]；wrong=[En2Ch] |
| 无 Active 环节 | En2Ch(0,I), List(1,A) | 无 scope='new' 行；List/Inactive 被删 |
| 幂等 | 已存在 scope='new' 行 + 老 scope NULL 行 | 老行映射，新行不受影响 |

**每场景执行完整 8 步后，额外断言**：
- 第 6 步执行成功后 `user_review_study_step` 表已不存在（DROP）；
- **第 8 步 `ADD PRIMARY KEY (user_id, scope, group_name, study_step)` 成功**（迁移硬性完整性条件：4/5 步后无重复行、无 NULL scope 残留）。

## 4. 架构审查要点（ppdc-architect）

1. 分层与职责 ✅：纯后端 DB 升级脚本，与前端 v49 迁移对齐。
2. 数据流与同步 ✅：映射结果进入 scope/group 结构，与客户端三组读取协议一致；幂等条件不触碰新客户端数据。
3. Dto/Vo ✅：不涉及。
4. 设计原则 ✅：按用户实际配置（seq 最小 Active）而非硬编码枚举，与设计文档"第1环节=check"意图一致；利用执行顺序天然排除 check 行，无冗余条件。
5. Surgical ✅：仅第 3 步 2 条 UPDATE + 注释，其余步骤不动。
6. 验证充分性 ✅：临时 PG 库样例数据回归（4 场景）+ mvn compile 确认后端编译不受影响。
7. 可执行性 ✅：psql（postgresql@16）与 docker 本机可用。

## 5. Task 分解

1. Task A：改写 v53 脚本第 3 步（2 条 UPDATE + 注释）。
2. Task B：临时 PG 库执行验证（4 场景断言，如 2.4 表）。
3. 集成验证：`mvn compile`（后端无 Java 改动，确认不受影响）。

## 6. 风险与注意事项

- **seq 非唯一的老数据**：`ROW_NUMBER` 按 `(seq, study_step)` 定序保证唯一选择；若 seq 为 NULL（理论上不应存在，seq 校正逻辑恒赋值），`ORDER BY seq` NULL 排最后——不影响"选第一个"语义。
- 本机 PG 服务可能未运行：验证时优先用本机 postgresql@16 服务，不可用时以 docker 起临时 PG 16 容器，不污染本机实例。