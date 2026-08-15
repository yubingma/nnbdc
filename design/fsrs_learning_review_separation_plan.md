# FSRS 学习/复习事件区分修复方案（Plan v2）

> 状态：已通过架构审查 → 已获用户审批 → **执行完成（阶段 3-5）** → 待用户决策（阶段 6）
> 目标：修复 FSRS 调度中"学习事件/复习事件"混用导致的复习次数偏多/偏少问题，并引入双轨道学习流程。

## 1. 背景：现有缺陷（审查结论）

### 1.1 状态机缺失（根因）

`FsrsState`（newItem/learning/review/relearning）只被存储与展示，从未参与调度决策。`updateCurrWord` 仅凭 `stability == null || == 0.0` 决定走 `init` 还是 `next`，导致：

- 新词（learning）当天巩固环节评分走复习公式 `next(rating, elapsedDays=0)`：
  - `elapsedDays=0 → r=1` → 记忆分支增长项为 0 → **答对（good/hard/easy）稳定性不变**；
  - 遗忘分支 → **答错（again）稳定性清零到 0.1**；
  - hard 被吞（复习偏少）、again 清零（复习偏多）、easy/good 组合下间隔失准。
- FSRS 原版语义：学习状态内每次评分**直接重设** `stability = w[rating-1]`（可升可降，最后一次评分决定），完成后才进入 review。

### 1.2 学习/复习流程未区分

新词与复习词走完全相同的环节序列（激活步骤 × 全部），复习词浪费大量时间，且"每天多次复习信号"违反 FSRS 模型假设（每天一次复习信号）。

### 1.3 学一半的词次日消失

新词当天只学部分环节退出后，次日 `isDue` 只看 `lastLearningDate + scheduledDays`，未到期不出现；到期后 `todayLearnedTimes` 已重置为 0 → 从头重学。现象：答对一半的词次日消失、答错的词次日反而出现。

### 1.4 修改评分统计污染

`_recalcFsrsForRating` 用 `lw.reps`（已含本次提交 +1）再 `next()` → reps 重复 +1；again→good 修改时 lapses 不回滚；`latestLog.elapsedDays == 0 → init` 误判（当天巩固日志 elapsedDays 也是 0）。

### 1.5 其他

- `FsrsState.values[lw.state ?? 0]`（3 处）脏数据越界风险，与 `FsrsStateExt.fromInt` 兜底不一致。
- `allStepsCompletedForWord` 传入 `updateCurrWord` 后从未使用（死参数）。
- "巩固评分不得高于测评评分"封顶逻辑（`bdc_notifier.dart` `_onAnswerCorrect` :2021-2039）与新语义冲突，需删除。

## 2. 设计决策（已与用户确认）

### 2.1 FSRS 事件语义（方案 B，含架构修订）

**三条路径**：`init`（新词首次）、`next`（跨天复习信号）、`relearn`（当天重设）。

| 场景 | 路径 | state 转换 |
|---|---|---|
| 新词测评（无任何历史） | `init(rating)` | learning |
| 学习轨道巩固环节（当天非首次评分） | `relearn`：`stability = w[rating-1]`、难度=init 难度公式 | 后续还有评分环节 → learning；无 → again ? relearning : review |
| 学习轨道最后评分环节 | 同上（relearn） | again ? relearning : review |
| 复习词测评（跨天首次评分） | `next(prev, rating, elapsedDays)` | 由 next 返回（review / relearning） |
| 复习轨道恢复环节（当天非首次） | `relearn` | 答对 → review（今日完成）；答错 → relearning（scheduledDays=1 明日重现） |
| 学一半词次日检验（state=learning 跨天首次） | `next(prev, rating, elapsedDays)` | 由 next 返回 |
| List 环节 | 不评分（现状） | — |
| 练习模式（看答案后隐藏再练） | 不评分（现状 `keepRating`） | — |

- **"评分环节"定义：轨道数组中 List 之外的环节**。state 判据是"该评分环节之后是否还有评分环节"，不能用 trackLength（List 不计入评分）。
- 判定"当天首次 vs 非首次"：`lastLearningDate` 与今日是否为同一业务日（businessDate 比较；跨天重置保留 lastLearningDate，判定可靠）。
- 删除"巩固 ≤ 测评"封顶逻辑（学习事件本就可升可降）。
- 毕业判定 `stability >= 180` 只在 `next()` 路径生效（重设路径 stability ≤ 5.8，天然不毕业）。

### 2.2 双轨道流程（单入口，不拆两个入口）

| 轨道 | 环节内容 | 适用 |
|---|---|---|
| 学习轨道 | 用户激活序列 + List（现状） | 新词（learning） |
| 复习轨道（隐藏，不出现在设置页） | `[测评环节, 恢复环节?, List]` | 复习词（review/relearning）、学一半次日检验 |

**测评环节（全局定义）= 用户激活序列的第 1 个环节**（不限类型，单词或例句均可）。

**恢复环节 = En2Ch/Ch2En 二者之一**：
- 测评是单词环节 → 取方向互补的另一个（未激活也出现一次）；
- 测评是例句环节 → 取用户激活的单词环节（两个都激活取序列靠前者；都未激活默认 En2Ch）。

复习词流程：
```
测评答对 → next() → state=review → 跳过恢复 → List → 今日完成
测评答错 → next(again) → state=relearning → 走恢复环节
  恢复答对 → relearn 重设 2.4 → state=review → List → 今日完成
  恢复再错 → relearn 重设 0.4 → state=relearning, scheduledDays=1 → List → 明日重现
```

- 复习环节数固定（不做配置）。
- 复习词也进入 List 环节。

### 2.3 学一半的词次日处理（含不可挤出保护）

- 跨天后，`state == learning && lastLearningDate < 今天`（即昨天学过但未走完学习轨道）的词 → 次日**强制进入今日计划**，按**复习轨道**快速检验（跨天=复习事件）。
- 判定字段可靠：`prepareTodayStudy` 跨天重置只清 `todayLearnedTimes/batchId/learningOrder`（`learning_service.dart:85-89`），保留 `state/lastLearningDate`。
- **不可挤出保护**：`genTodayWords` 的新词配额挤出逻辑（`learning_service.dart:365-376`，`!isTodayNewWord && todayLearnedTimes==0` 可被挤）必须排除"学一半次日检验"词，否则配额高时它们会被挤出计划。

### 2.4 取词流水线调试面板（`_showDebugOverlay`）——双轨道区显示

- 面板分两个行区（不引入"跳过"第三状态色）：
  - **轨道 1（学习轨道）**：激活序列各行（En2Ch、Ch2En、例句…、List）。新词各行按 `todayLearnedTimes` 正常渲染（学过=绿、当前=绿框、未学=灰）；复习词仅在**测评行**（激活序列第 1 环节）与 **List 行**按进度渲染，其余行自然灰色（未学）。
  - **轨道 2（复习轨道）**：仅新增**恢复环节**一行（测评/List 与轨道 1 共用，不重复），行标签动态标注方向（如 `恢复(Ch2En)`）。复习词恢复圆点：走过=绿、跳过/未走=灰；新词此行灰色（不适用）。
- 图例保持现状（学过/未学/已掌握/当前/下一个），取消原 v1 的"跳过"琥珀色方案。

## 3. 改动清单

### A. `app/lib/util/fsrs.dart`

- 新增 `FSRSItem relearn(FSRSItem last, FsrsRating rating, {required FsrsState nextState})`：重设 `stability = w[rating-1]`、`difficulty = clamp(w[4] - (rating-1)*w[5], 1, 10)`、`scheduledDays = _calculateInterval(stability)`、`reps = last.reps + 1`、`lapses = rating==again ? last.lapses+1 : last.lapses`、`elapsedDays = 0`、state 由调用方传入（learning/review/relearning 按 2.1 判据）。
- `init/next/_calculateInterval/_meanReversion` 公式不动。

### B. `app/lib/api/bo/study_bo.dart` — `updateCurrWord`

重写 FSRS 分支：

```
isSameDayToday = lastLearningDate != null && isSameBusinessDay(lastLearningDate, today)
if (isSameDayToday) {
  // 当天非首次：学习/恢复事件 → relearn 重设
  nextFsrs = fsrs.relearn(prev, rating, nextState: 2.1 判据)
} else {
  // 跨天首次：复习事件
  nextFsrs = (stability == null || stability == 0) ? fsrs.init(rating) : fsrs.next(prev, rating, elapsedDays)
}
```

- `prev` 由 currWord 字段构造（现状）；state 判据基于轨道数组（2.1）。
- 毕业判定不变（`stability >= 180` 仅在 next 路径触发）。
- `allStepsCompletedForWord` 参数删除（改由轨道数组判定，见 2.1）。

### C. 轨道构造与环节映射重构（P0-1/P0-3 修订核心）

- 新增轨道推导模块（建议 `app/lib/util/study_track.dart`）：
  - `trackOf(word, 用户激活序列)` → `List<StudyStep>`（学习轨道 / 复习轨道）；
  - 复习轨道构造规则（2.2），含恢复环节选择规则；轨道数组是"内容数组"（如 `[En2Ch, Ch2En, List]`），与激活序列解耦，恢复环节"未激活也出现"天然成立。
- **环节映射统一改造：所有 `steps[todayLearnedTimes]` 硬索引改为 `trackSteps[word][todayLearnedTimes]`**，覆盖：
  - `study_bo.dart:674/783` stepIndex 推导与环节获取；
  - `study_bo.dart:706` `isListStep` 判定 → `trackSteps[currentStepIndex] == List`；
  - `study_bo.dart:478` `completeListStepForCurrentBatch` 的 List 判据 → `trackSteps[word.todayLearnedTimes] == List`（修复复习词 +2 后 List 永不推进的死循环）；
  - `bdc_notifier.dart:509/560` UI 环节渲染 `activeUserStudySteps[stepIndex]` → 轨道数组；
  - `getTwoOtherWords` 的 learningMode 参数 → 传轨道环节类型（混淆项生成按环节类型）。
- `isTodayFinished` / `getCompletedSteps`（`learning_word_extensions.dart`）改为按 `trackLength(word)`。
- 复习词测评答对跳过恢复：提交评分时 `todayLearnedTimes` 直接 +2（跳过恢复段）进 List。
- 进度分母 = Σ trackLength。
- `prepareTodayStudy` 跨天重置逻辑保持（只清进度字段）。

### D. `app/lib/page/bdc/providers/bdc_notifier.dart`

- 删除 `_onAnswerCorrect` 的封顶逻辑（:2021-2039）。
- 删除"例句巩固不评分"：`_isSentencePracticeStep` 的 `fsrsRating: null` 分支共 3 处（已核实：`:802-813` `revealAnswerAndMarkWrong` 看答案路径、`:875-878` `onAnswerClicked` 答错路径、`:2101-2109` `_onAnswerCorrect` 答对路径），例句巩固环节属于学习轨道，参与 relearn 重设评分；**练习模式 keepRating 全链路保留**（`:804/808/811/823/1119/1808` 不动），`_isSentencePracticeStep` 方法（`:764-770`）随之删除。
- 修改评分幂等（P1-4）：
  - LearningLogs 表无 reps/lapses/state 字段，需**回推规则**：`测评前 reps = lw.reps − 当天该词日志条数`；`测评前 lapses = lw.lapses − 当天该词 again 日志条数`。
  - 定位"测评前状态"：**当天首条 LearningLog 的前一条**（不是"倒数第二条"——当天巩固也写日志，最新一条可能非测评）；无则新词 → `init`。
  - 用测评前 stability/difficulty + 回推 reps/lapses + 新评分，按 2.1 相同路径重算，保证幂等；删除 `latestLog.elapsedDays == 0 → init` 误判与 `forceInit` 特殊逻辑。
- `_updateFsrsPreview` / `saveHistoryFSRSUpdate` 对齐新规则。
- 调试面板（`_showDebugOverlay`）双轨道区渲染：轨道 1 学习轨道行 + 轨道 2 恢复环节行，按 2.4 规则渲染（依赖 3.C 落地后实现）。

### E. 防御与清理

- `FsrsState.values[lw.state ?? 0]`（3 处）统一为 `FsrsStateExt.fromInt`。
- 存量 `state==0 && stability>0` 的词走 `next()` 路径，`fsrs.dart:46` assert 可通过，无需迁移。

### F. 测试（TDD）

1. `test/fsrs_test.dart`：新增 `relearn` 重设语义测试（可升可降、reps/lapses 累计、state 传参）。
2. `test/study_bo_test.dart`：当天两次提交组合（good/good、good/hard、good/again、again/good、easy/good、复习词 good/hard/again、恢复环节对/错），断言 stability/state/scheduledDays/reps/lapses 幂等。
3. `test/learning_service_test.dart`：学一半的词次日强制入计划 + 复习轨道 + 不可挤出。
4. 修改评分回归：again→good 后 lapses 回滚、reps 不虚增。
5. 全量 `flutter test`：**轨道改动会影响现有基于 activeSteps 推进的用例，需同步更新受影响用例**（不追求"零改动通过"）。

## 4. 风险与注意事项

- **例句巩固环节参与评分**是行为变化（现状：例句巩固不评分），审批时需明确。
- 复习轨道 List 环节推进：`completeListStepForCurrentBatch` 判据改为轨道数组后，学习轨道（List 恒末位）行为不变，回归测试覆盖。
- 批次轮转兼容性：复习词 todayLearnedTimes 跳 2 后，批次内排序（按 todayLearnedTimes 升序）仍正确。
- 多端同步：FSRS 字段经 learningWords 同步，新 state 取值已在同步协议内，无需协议变更。

## 5. 执行顺序（Task 拆分，含架构修订）

1. Task 1: `fsrs.dart` 新增 `relearn` + 单测
2. Task 2: `updateCurrWord` 状态机分支（当天/跨天 × 学习/复习事件）+ 单测
3. Task 3: 轨道构造模块 + 环节映射重构（stepIndex/isListStep/getTwoOtherWords/UI studyStep/进度分母）
4. Task 4: List 完成机制判据改造（`completeListStepForCurrentBatch`、跳过恢复 +2）
5. Task 5: 学一半次日检验 + 不可挤出保护 + 单测
6. Task 6: UI 层清理（删封顶、删例句巩固不评分分支、修改评分幂等、防越界）
7. Task 7: 调试面板双轨道区渲染
8. Task 8: 全量回归测试（含同步更新受影响用例）

## 6. 架构审查记录（v1 → v2 修订）

- P0-1 环节映射断裂 → 3.C 全部硬索引改轨道数组。
- P0-2 state 判据不自洽 → 2.1 改为"后续是否还有评分环节（List 不计）"。
- P0-3 跳过恢复与 List 完成机制冲突 → 3.C/3.D 判据改 `trackSteps[word][todayLearnedTimes]`。
- P1-4 修改评分幂等缺机制 → 3.D 回推规则 + "当天首条日志的前一条"。
- P1-5 学一半词可被挤出 → 2.3 不可挤出保护。
- P2-6 例句评分分支（:2109）须一并删除 → 3.D。
- P2-7 调试面板依赖映射 → 2.4/3.D。
- P2-8 存量 state==0 无需特殊处理 → 3.E。

## 7. 执行记录（阶段 3-5，全部完成）

| Task | 内容 | 验证 |
|---|---|---|
| 1 | `fsrs.dart` 新增 `relearn`；`init` 增加可选 `nextState` | fsrs_test 16 全绿 |
| 2 | `updateCurrWord` 三路分支（init/relearn/next）+ `allStepsCompletedForWord` 语义修正 | study_bo_test 12 全绿 |
| 3 | 新增 `study_track.dart`（trackOf/isReviewTrack/reviewTrack/hasMoreGradedSteps）+ 环节映射重构（getWord/completeListStepForCurrentBatch/_calculateBatchStartIndex/bdc_notifier/today_plan/distractor_strategy/learning_word_extensions） | study_track_test 10 全绿 |
| 4 | List 完成判据改轨道数组；复习轨道测评答对跳过恢复（todayLearnedTimes +2） | study_bo_test 新增 3 用例 |
| 5 | 学一半词次日强制入计划 + 不可挤出保护 | learning_service_test 23 全绿 |
| 6 | UI 清理：删"巩固≤测评"封顶、删例句不评分三分支、`_recalcFsrsForRating` 幂等重写（回推规则+当天首条日志判据）、`FsrsStateExt.fromInt` 防越界、删 forceInit 死参数 | bdc_notifier_test + study_bo_test 27 全绿 |
| 7 | 调试面板双轨道区：轨道 1 学习轨道行 + 轨道 2 恢复环节行（走过绿/跳过灰，图例不变） | analyze 无问题 |
| 8 | 全量 flutter test | 288 通过、2 skip、4 个既有失败（english_correction_test，ASR 语音纠错，与本次改动无关） |

### 执行中的关键设计修正（偏离 v2 之处）

1. **轨道固化**（架构集成审查发现）：轨道判定若随 state 变化会漂移（新词评分后 state 转 review 导致轨道中途切换、List 索引错位）。最终采用"**今天首条评分日志的 elapsedDays 固化当天轨道**"（init=0 → 学习轨道；跨天 next>0 → 复习轨道），`study_track.dart` 增加 `todayFirstLogElapsedDays` 参数，调用方批量预查日志。
2. **init 的 state 判据**：新词当天仅一个评分环节（最后评分环节即 init）时，state 直接按 `allStepsCompletedForWord` 转 review/relearning（与 relearn 分支对称），否则学完的词次日会被"学一半"判定误抓（集成测试暴露）。
3. `updateCurrWord` 返回 `FSRSItem?` 以便 getWord 把刚写入的首条日志立即固化进轨道 Map。
4. today_plan `_updateProgress` 异步化后补 `if (mounted) setState`（unawaited 调用点的 UI 刷新）。

### 遗留说明

- 全量测试中 `english_correction_test.dart` 4 个失败为既有失败（ASR 语音纠错断言），相关文件不在本次改动范围，未处理。
- 未执行 git commit（按 AGENTS.md 由用户决策）。

## 8. 补充验证 Plan（用户要求：整本词书多天学习到自然毕业的总复习次数验证）

### 需求

现有测试只覆盖 2 天集成与单词级场景，缺少"整本词书、多天循环、经过完整业务调度（prepare→getWord→List→跨天→复习→自然毕业）"的端到端验证。补充一个用例验证每词从新学到自然毕业的总复习次数符合 FSRS 预期。

### 方案（单 Task）

文件：`app/test/learning_workflow_integration_test.dart`（复用 setUp：8 词词书、wordsPerDay=3、En2Ch+List 两步、FakeClock）。

新用例 `'整本词书多天学习到自然毕业：每词总复习次数符合 FSRS 预期'`：

- 每天循环（上限 120 天防死循环）：`prepareTodayStudy(true)` → 逐个 `getWord(true, good)` 答对 → `completeListStepForCurrentBatch()` 完成 List → `fakeClock.advanceDays(1)`。
- 直到 8 词全部进入 mastered_words（自然毕业，无手动掌握）。

断言（全 good 路径 FSRS 理论值：init 2.4→间隔2天→7.0→间隔7天→44→间隔44天→≥180 毕业，即 **4 次评分、约 54 天**）：
- 每词 LearningLog 条数 **== 4**（精确：init + 3 次复习）；
- 每词在 mastered_words 中；
- 总天数在 [40, 70]（宽容：舍入误差）；
- 毕业轮次无人工干预。

### 验证

`flutter test test/learning_workflow_integration_test.dart` 针对性跑通。

### 架构审查（ppdc-architect 要点）

1. 分层与职责 ✅ PASS：纯测试，验证前端调度层。
2. 数据流与同步 ✅ PASS：只读验证，不改数据结构。
3. Dto/Vo ✅ PASS：不涉及。
4. 设计原则 ✅ PASS：精确断言（LearningLog==4）+ 宽容范围（天数）+ 防死循环上限。
5. Surgical Changes ✅ PASS：只加一个用例，复用现有 setUp。
6. 验证充分性 ✅ PASS：针对性 flutter test。
7. 可执行性 ✅ PASS：依赖已有 FakeClock/advanceDays 机制。

结论：PASS，可执行。

### 执行结果（含重大发现）

1. **新用例暴露并修复了一个既有 FSRS 公式 bug**：`fsrs.dart` 记忆（recall）分支误用 `w[11]/w[12]/w[13]`（FSRS-5 的索引位置），而默认权重表是 FSRS-4.5 的，应使用 `w[8]/w[9]/w[10]`（与遗忘分支同一三元组，原版公式如此）。修复前毕业路径 2.4→7.03→22.12→66.42（103 天）；修复后 2.4→8.5→28.7→89.5→≥180（135 天毕业，与理论 134 天一致）。
2. 新用例最终断言（全 good 自然毕业路径）：每词 LearningLog == 4（init + 3 次未毕业复习，毕业复习不写日志）、总天数 [100,160]（实测 135）。
3. `bdc_notifier_test` 的修改评分用例断言 8 天 → 9 天（旧公式硬编码值修正）。
4. 全量回归：290 通过、2 skip、4 个既有 ASR 失败（english_correction_test，已实证与本次改动无关）。
