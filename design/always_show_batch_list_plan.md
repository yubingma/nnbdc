# 方案设计：批次学习完成后统一进入 List 环节（移除 skipGroupSteps）

## 1. 背景与目标
在当前三组学习规则实现中，当单词测评后接续组（`correct` 或 `wrong`）为空时，系统通过 `skipGroupSteps` 将 `todayLearnedTimes` 一次性加 2，直接越过了末位的 `List` 环节并标记完成。
这导致在旧词复习且全部答对时，系统会跳过“本组单词”列表页（List环节）直接进入下一批。

**目标**：
统一学习流程与用户心智模型——无论接续组是否为空、单词是否全对，批次内的所有单词在完成练习题目后，均统一收敛进入末位的 **List 环节**（展示“本组单词”列表页）。用户浏览完本组单词并点击“下一组”后，再批量结算该批次并进入下一批。

---

## 2. 核心改动点

### 2.1 移除 `skipGroupSteps` 特例逻辑
- 文件：`app/lib/api/bo/study_bo.dart`
- 改动：
  1. 移除 `skipGroupSteps` 判定（原 `study_bo.dart:683`）。
  2. 移除 `updateCurrWord` 中的 `skipGroupSteps` 参数（原 `study_bo.dart:886`, `1008`），评分推进时 `todayLearnedTimes` 统一按自然步进 `+ 1`。
  3. 当接续组为空时，单词完成测评后其 `todayLearnedTimes` 从 0 变为 1，正好指向轨道中的末位环节 `track[1] == 'List'`。
  4. `allStepsCompletedForWord` 保持不变（因为 `List` 为不计分环节，接续组为空时无剩余评分环节，FSRS 状态正常转为 `review`/`relearning`）。

### 2.2 批次调度与 List 结算
- 批次内 10 个单词各自分别完成测评和可能存在的接续题后，所有词均推进至末位的 `List` 环节（`todayLearnedTimes == track.length - 1`）。
- 调度器检测到当前批次处于 `List` 环节，返回 `isListStep = true`，前端自动导航到“本组单词”列表页（`/word_list`）。
- 用户点击“下一组”调用 `completeListStepForCurrentBatch()`，批量将当前批次中处于 `List` 环节的单词 `todayLearnedTimes + 1`，全部标记完成并顺利进入下一批。

---

## 3. Task 分解

### Task 1: 修改 StudyBo 移除 skipGroupSteps 步进逻辑
- **文件**：`app/lib/api/bo/study_bo.dart`
- **变更**：
  - 移除 `final bool skipGroupSteps = ...;` 及传参。
  - `updateCurrWord` 中 `todayLearnedTimes: currWord.todayLearnedTimes + 1`。
- **目的**：接续组为空时自然步进至 `List` 环节，不再跳步。
- **验证**：`flutter analyze` 无警告与错误。

### Task 2: 更新并补充单元测试与流转测试
- **文件**：
  - `app/test/study_bo_test.dart`
  - `app/test/study_track_test.dart`
- **变更**：
  - 更新原有用例中关于 `skipGroupSteps +2` 的断言为自然步进 `+1` 至 `List`。
  - 新增测试用例：验证当答对组为空且所有单词答对时，依次测完所有词后进入 `List` 环节，调用 `completeListStepForCurrentBatch` 后批次完成。
- **目的**：保证测试覆盖新流转，防止回归。
- **验证**：`flutter test test/study_bo_test.dart` 和 `flutter test test/study_track_test.dart` 全部通过。

---

## 4. 架构审查（阶段 1）

| 审查维度 | 结论 | 理由 |
| :--- | :--- | :--- |
| **1. 分层与职责** | ✅ PASS | 改动完全位于前端学习业务逻辑层（StudyBo 与单元测试），不侵入后端，不影响数据同步。 |
| **2. 数据流与同步** | ✅ PASS | 学习日志与单词状态同步机制保持原样（仅步骤计数更规范地逐步递增）。 |
| **3. Dto/Vo 规范** | ✅ PASS | 不涉及 Dto/Vo 数据结构变更。 |
| **4. 设计原则** | ✅ PASS | 删除了特殊的跳步 `workaround/特例` 代码，使三组轨道 `[测评, ...接续组, List]` 完全对称、自洽且符合直觉，极大地降低了系统复杂度（奥卡姆剃刀）。 |
| **5. Surgical Changes** | ✅ PASS | 仅修改相关逻辑与对应断言，无无关代码改动。 |
| **6. 验证充分性** | ✅ PASS | 包含专门针对单步推进与整批进入 List 的单测与回归验证。 |
| **7. 可执行性** | ✅ PASS | 拆解清晰，依赖明确，可平滑执行。 |

**架构审查结论**：**PASS 通过**。
