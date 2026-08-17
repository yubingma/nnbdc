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

**重测环节 = 与测评方向互补的单词环节（反向永远成立，规则后续简化）**：
- 测评是英→中方向（En2Ch / EnSentence2Ch）→ 重测 Ch2En（中→英）；
- 测评是中→英方向（Ch2En / ChSentence2En）→ 重测 En2Ch（英→中）。
（例句与单词同理：例句英→中答错，反向为单词中→英。）

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

## 9. 补充需求 Plan：学习环节设置分"新词/旧词"Tab + "重测"用词统一（方案 A）

### 需求

1. 今日计划页"学习环节"设置区拆为**新词 / 旧词两个 tab**（方案 A：旧词 tab 只读说明型，不新增配置存储与同步）。
2. "恢复"环节用词统一改为 **"重测"**（面板行标签、底部环节标签、旧词 tab 文案、相关中文注释）。

### 改动清单

**A. 用词统一（UI + 中文注释）**
- `bdc_dialogs.dart`：面板行标签 `恢复(...)` → `重测(...)`；相关注释"恢复环节"→"重测环节"。
- `bdc_ui_components.dart`：`'[恢复] '` → `'[重测] '`。
- `bdc_state.dart` / `bdc_notifier.dart` / `study_track.dart` / `study_bo.dart`：中文注释"恢复环节"→"重测环节"（内部标识符 `isRestoreStep` 等保留英文，不动）。

**B. `today_plan.dart` 的 `renderStudySteps()`（约 :1119）改造为双 tab**
- 标题"学习环节"下加两个 tab：**新词 / 旧词**（页面内嵌 TabBar + TabBarView，旧词说明卡固定高度避免布局问题）。
- **新词 tab**：现有 ReorderableListView 环节设置（激活开关 + 拖动排序 + List 恒末尾），原样迁移。
- **旧词 tab**：只读说明卡：
  - ① 测评：新词序列的第 1 环节（动态显示环节名，跟随新词设置，不可单独改）
  - ② 重测：仅当测评答错时，当天加测一次反向环节（如英→中答错则中→英）
  - ③ 单词列表：浏览本组单词
  - 附一句说明："旧词不需要再学例句等巩固环节，复习更轻快。"

### 架构审查（ppdc-architect 要点）

1. 分层与职责 ✅ PASS：纯前端 UI 与文案，落 app/。
2. 数据流与同步 ✅ PASS：方案 A 不新增配置存储，无同步影响。
3. Dto/Vo ✅ PASS：不涉及。
4. 设计原则 ✅ PASS：只读说明型避免新增实体；用词统一消除歧义。
5. Surgical ✅ PASS：改动限定 today_plan.dart 与文案文件。
6. 验证充分性 ✅ PASS：flutter analyze + bdc_notifier_test + 全量回归。
7. 可执行性 ✅ PASS：无前置依赖。

结论：PASS。

### 验证

`flutter analyze` 无问题；`flutter test test/bdc_notifier_test.dart` 通过；全量回归通过后交用户决策。

### 执行结果（第 9 节）

- 用词统一完成："恢复"→"重测"（面板行标签 `重测(Ch2En)`、底部 `[重测]`、6 个文件的中文注释；内部标识符 `isRestoreStep` 保留英文）。
- `today_plan.dart` 学习环节设置区改造为 **新词/旧词双 tab**（TabBar + 条件渲染）：
  - 新词 tab：现有环节配置（激活开关 + 拖排序 + "拖动 ⠿ 排序"徽章仅此 tab 显示）；
  - 旧词 tab：只读说明卡（① 测评=新词第 1 环节（动态显示名称）② 重测=答错当天反向加测 ③ 单词列表 + "旧词不需要再学例句等巩固环节，复习更轻快"）。
- 验证：`flutter analyze` 7 文件无问题；全量 `flutter test` 294 通过、2 skip、0 失败。

## 10. 补充需求 Plan：旧词学习规则三组显式设置（修订版，取代旧方案 B）

### 需求（已与用户确认，取消所有隐含规则）

旧词 tab 设置三个显式区块：

| 区块 | 内容 | 语义 |
|---|---|---|
| 测评环节 | 单选 1 个（必选） | 进入旧词后先做 |
| 答对后 | 多选 + 排序，**可为空** | 测评答对 → 走这些环节（空 = 直接完成） |
| 答错后 | 多选 + 排序，**可为空** | 测评答错 → 走这些环节（空 = 答错即结束，明日重现） |

- 全部显式、所见即所得；取消"自动补反向重测""N=1 补/N≥2 全走"等隐含规则。
- 四类环节（含例句）都可选；List 恒末尾（内部环节）。
- FSRS 语义不变：测评 = next 复习公式；后续环节 = relearn 重设（现有 updateCurrWord 的 isSameDayToday 分支已支持）。
- 存量用户：表为空 → 回退旧行为并在 UI 预填显示（测评=新词第 1 环节、答对后=空、答错后=[反向互补环节]），用户改动保存后才落库。

### 存储

`UserReviewStudySteps` 表：userId / group（'check'/'correct'/'wrong'）/ studyStep / seq / state / 时间戳，主键 (userId, group, studyStep)。（已开工的 Task 1 半成品按此调整：加 group 列并纳入主键。）

### 轨道构造（study_track）

- `reviewTrack({checkStep, correctSteps, wrongSteps, firstLogRating, fallbackCheckStep})`：
  - check 为空（未设置）→ 回退：check = fallbackCheckStep（新词第 1）、correct = []、wrong = [反向(check)]；
  - 轨道 = `[check] + (当天首条评分日志 rating == again ? wrong : correct) + [List]`；
  - 测评尚未提交（无首条日志）→ `[check, List]`（仅测评可见，评分后轨道扩展）。
- 调用方需提供"当天首条日志的 rating"：getWord 的日志预查 Map 由 (wordId → elapsedDays) 扩展为 (wordId → (elapsedDays, rating))；bdc_notifier/面板/today_plan 同步适配。

### 调度（study_bo）

- 测评评分后的推进增量：
  - 测评答对且 correct 组为空 → todayLearnedTimes +2（跳过组直接进 List 位置，当日完成）；
  - 测评答错且 wrong 组为空 → +2（直接完成，scheduledDays=1 明日重现）；
  - 组非空 → +1（进入组第 1 环节，逐环节推进）。
- 原 skipRestoreStep 参数改造为该增量逻辑（skipRemainingSteps）。

### UI（today_plan）

- 旧词 tab 三区块：测评（四选一）、答对后（多选+排序，可空）、答错后（多选+排序，可空）；保存落库（三组）。
- 表为空 → 预填默认值（测评=新词第 1、答对后=空、答错后=[反向]）并标注"当前为默认规则（未自定义）"。
- 至少测评 1 个校验；拖动排序徽章两 tab 显示。

### Task 分解

1. 存储：表加 group 列入主键（调整半成品）+ db 迁移（49 版）+ dao 按 group 增删改查与 DbLog 同步。
2. sync.dart 分发 'userReviewStudySteps'。
3. study_steps_service：读三组（check/correct/wrong）、保存三组。
4. study_track：三组轨道规则 + trackOf/isReviewTrack 参数扩展 + 全部调用方适配（含日志 Map 带 rating）。
5. 调度：测评后推进增量（组空 +2 / 组非空 +1）。
6. UI 三区块 + 默认预填 + 校验。
7. 测试：study_track（三组轨道/空组/回退）、service、study_bo（答对空组直跳/答错空组明日重现/组内逐环节）、integration 适配；全量 flutter test。

### 架构审查要点

1. 分层 ✅ PASS：前端为主，后端透传零改动。
2. 数据流与同步 ✅ PASS：新表 db_log 同步；老客户端安全跳过已验证。
3. Dto/Vo ✅ PASS：VO 复用 UserStudyStepVo。
4. 设计原则 ✅ PASS：显式三组消除隐含规则；空表回退 + UI 预填免迁移。
5. Surgical ✅ PASS：新表 + 参数扩展，不动新词逻辑。
6. 验证 ✅ PASS：单元 + 集成 + 全量（后端无改动）。
7. 可执行性 ✅ PASS。

结论：PASS。

### 验证

flutter analyze 无问题；flutter test 全量通过后交用户决策。

### 执行结果（第 10 节修订版）

- 存储：`UserReviewStudySteps` 表（userId/group/studyStep 复合主键，group ∈ check/correct/wrong）+ db schemaVersion 49 迁移 + DAO（INSERT/UPDATE/DELETE 全量 DbLog 同步，与 userStudySteps 的"禁 INSERT"历史包袱不同）。
- sync.dart：新表分发分支 + 未知表白名单；老客户端安全跳过（已验证）。
- study_track：`effectiveReviewConfig`（未设置回退默认）、`oppositeWordStep`（反向互补）、`reviewTrack` 三组轨道（测评 + 按首条日志 rating 选答对/答错组 + List；测评未提交仅 [测评, List]）。
- 调度：`skipGroupSteps` 判据（测评评分后对应组为空 → +2 直接完成；组非空 → +1 逐环节）；日志预查扩展为 (elapsedDays, rating)。
- UI：旧词 tab 三区块（测评 ChoiceChip 单选 / 答对后 FilterChip 多选 / 答错后 FilterChip 多选，选择顺序即序列）+ 默认规则预填与说明 + 保存按钮。
- 面板：轨道 2 行标签改为 `答错(环节名)`（答错组第一项），拼写/环节颜色语义保持。
- 测试：study_track_test 14、study_bo_test 新增"答错组推进 List"与"答对组空 +2 完成"用例；全量 flutter test 298 通过、2 skip、0 失败。

### 纠正：后端同步并非透明透传（用户质疑后实证发现）

- 拉取接口（getUserDbLogsFromVersion）仅按表名过滤 JSON，但**上传链路** `UserDbSyncBo.processSyncLog` 有表名白名单 switch，未知表名会抛 `IllegalArgumentException` 导致整个同步批次失败。
- 已补齐后端：`UserReviewStudyStepDto`（api/model）、`UserReviewStudyStep`/`UserReviewStudyStepId`（PO，表 `user_review_study_step`，group 保留字用列名 `group_name`）、`UserReviewStudyStepBo`、`UserDbSyncBo` switch 新增 `user_review_study_step` 分支与处理函数（INSERT/UPDATE/DELETE 正常处理，无 userStudySteps 的"禁 INSERT"历史包袱）。
- 前端 `utils.dart` 表名双向映射新增 `userReviewStudySteps ↔ user_review_study_step`。
- 运维脚本：`db_upgrade/latest-to-upgrade/v52_add_user_review_study_step.sql`（需在生产库执行）。
- 验证：后端 `mvn compile` 通过；前端全量 298 通过、2 skip、0 失败。

## 11. 补充需求 Plan：UserStudySteps 单表增强，承载新词+旧词三组规则（未发版窗口重构）

### 需求（已与用户确认）

- 新词环节设置也改为"测评单选 + 答对后/答错后分支"三组结构（与旧词同款 UI），答对后为空 = 测评答对当天即完成。
- **删除 UserReviewStudySteps 表**，增强 UserStudySteps 单表承载两套三组规则（scope 区分）。
- 老数据升级：老激活序列 → scope='new' 等价映射（第1环节=check，剩余=correct+wrong 各存一份，List/Inactive 丢弃）；user_review_study_step 已有数据并入 scope='review'。
- 已接受：老版本 App 在升级窗口内"学习环节设置不同步"（老式日志被后端忽略；强制升级机制兜底）。

### 存储设计

前端 `UserStudySteps` 增强：userId / **scope**('new'/'review') / **group**('check'/'correct'/'wrong') / studyStep / seq / state / 时间戳；主键 (userId, scope, group, studyStep)。同步 tblName 保持 'userStudySteps'（复用现有链路，删除之前加的 userReviewStudySteps 映射与分支）。

### 迁移

- **前端 v49（改写）**：SQLite 重建 user_study_steps 表（新主键）→ 老序列映射为 scope='new' 三组 → user_review_study_steps 数据并入 scope='review' → DROP user_review_study_steps。
- **后端 v53（改写 v52）**：PostgreSQL 同构迁移（老序列映射 + review 表并入 + DROP user_review_study_step）。
- 默认三组（表空时运行时补全，不落库）：scope='new' → check=En2Ch、correct=[Ch2En, EnSentence2Ch, ChSentence2En]、wrong=同；scope='review' → check=新词 check、correct=[]、wrong=[反向(check)]。

### 轨道与调度

- study_track：新旧词轨道同构（check + 按首条评分选 correct/wrong 组 + List）；删除"未配置回退激活序列"逻辑（三组为唯一表达，默认三组运行时补全）。
- skipGroupSteps 通用化：测评评分后对应组为空 → +2 直接完成（新词、旧词同规则）。
- FSRS 语义不变：新词测评=init、后续=relearn；旧词测评=next、后续=relearn。

### 服务与 UI

- StudyStepsService 改造：getThreeGroupConfig(scope)/saveThreeGroupConfig(scope, ...)（diff 保存）；删除 ReviewStudyStepsService。
- 后端 UserStudyStepBo.initUserStudySteps 改为初始化默认三组（scope='new' + scope='review'）。
- 后端 UserDbSyncBo：user_study_step handler 改为三组语义（INSERT/UPDATE/DELETE 正常处理，含 DELETE 从 recordId 解析）；**老客户端无 scope/group 字段的日志 → warn + 跳过（不抛异常）**。
- 前端新词 tab 换三组分支 UI（复用旧词组件，参数化 scope）；删除旧"激活+拖排序"列表 UI。

### Task 分解

1. 前端存储：UserStudySteps 表增强 + v49 迁移（含 review 表并入与 DROP）+ DAO 三组 diff 读写；删除 UserReviewStudySteps 表与 DAO。
2. 前端服务：StudyStepsService 三组读写与默认补全；删 ReviewStudyStepsService；调用方适配（study_bo/bdc_notifier/today_plan/面板）。
3. 前端轨道：study_track 三组同构 + skipGroupSteps 通用化。
4. 前端同步：utils.dart 删多余映射；sync.dart userStudySteps 分支适配三组实体。
5. 前端 UI：新词 tab 三组分支（复用组件）+ 删旧列表。
6. 后端：PO/ID/DTO 增强 + v53 迁移 + initUserStudySteps 三组化 + handler 三组化与老日志跳过。
7. 测试：迁移、三组读写、轨道、调度、同步用例 + 全量 flutter test + mvn compile。

### 架构审查要点

1. 分层 ✅：前端为主 + 后端同步/初始化配套。
2. 数据流与同步 ✅：单表沿用既有同步链路；老客户端日志安全跳过（接受窗口内设置不同步）。
3. Dto/Vo ✅：UserStudyStepDto 扩展 scope/group。
4. 设计原则 ✅：单表收敛、未发版窗口改写迁移、等价映射保行为。
5. Surgical ✅：改动集中存储/轨道/UI 三处，学习词表等不动。
6. 验证 ✅：迁移单测 + 全量 + mvn compile。
7. 可执行性 ✅。

结论：PASS。

### 验证

flutter analyze / flutter test 全量 / mvn compile 通过后交用户决策。

### 执行记录（Task 1-7）

- Task 1 存储 ✅：UserStudySteps 表增强（scope/group，主键 userId+scope+group+studyStep）+ schemaVersion 49 迁移（老序列→scope='new' 三组、user_review_study_steps 并入 scope='review'、DROP）+ DAO 三组读写（saveUserStudyStep 普通 INSERT/UPDATE/DELETE 日志，recordId=userId-scope-group-studyStep）；UserReviewStudySteps 表与 DAO 删除。
- Task 2 服务 ✅：StudyStepsService 三组读写（getThreeGroupConfig 空表默认补全不落库 / saveThreeGroupConfig diff 保存）；ReviewStudyStepsService 删除；调用方（study_bo / bdc_notifier / today_plan / bdc_dialogs）全部适配；global.dart 访客步骤初始化删除。
- Task 3 轨道 ✅：study_track 三组同构（[check, 按首条评分选组, List]，isReviewTrack 由当天首条日志 elapsedDays 固化）；skipGroupSteps 通用化（测评评分后对应组空 → +2 直接完成）。**额外修复**：getWord 的 allStepsCompletedForWord 原按"评分前轨道"判定，测评环节轨道尚未按首条评分扩展，会导致新词答对后过早转 review；改为按所选组长度判定（与 skipGroupSteps 共用 groupAfterRating）。
- Task 4 同步 ✅：utils.dart 删多余映射；sync.dart userStudySteps 分支适配三组实体（含 DELETE 走 recordId 解析）。
- Task 5 UI ✅：新词 tab 三组分支 UI（复用旧词组件参数化 scope），progress modeCount 固定 5；today_plan 三组配置卡（check 下拉 + correct/wrong ReorderableListView，自动保存）。
- Task 6 后端 ✅：UserStudyStepId/PO/Dto 加 scope/group（列名 group_name）；UserStudyStepBo.initUserStudySteps 初始化默认三组（new + review）；UserDbSyncBo user_study_step handler 三组化（INSERT/UPDATE/DELETE 正常处理、DELETE 从 recordId 解析、老客户端无 scope/group 日志 warn+跳过）；UserBo/SystemHealthCheckBo 适配；删除 UserReviewStudyStep PO/Id/Bo/Dto；v53 迁移（user_study_step 加列、老序列→new 三组、review 表并入 scope='review'、DROP user_review_study_step、重建主键）。mvn compile ✅。
- Task 7 测试 ✅：study_bo_test（三组 fixture + 首条日志预置 + 15 用例）、study_track_test 重写、study_steps_service_test 重写、learning_workflow_integration_test 重写（多天端到端 + 自然毕业：每词 8 次评分、日志 7 条、约 135 天毕业）、bdc_notifier_test / english_correction_test fixture 三组化；flutter analyze 全量 0 issue；相关测试全绿。
