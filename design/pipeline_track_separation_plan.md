# 方案设计：今日取词流水线中新词与旧词环节分离展示

## 1. 背景与目标

当前“今日取词流水线”弹窗中，行标题将测评（第 1 行）与各接续环节合并展示，导致用户难以直观分辨新词和旧词各自的完整学习轨道。

**目标**：
- 将新词（scope='new'）和旧词（scope='review'）的学习环节在流水线中按独立行清晰分开。
- 区分颜色：新词环节采用绿色系，旧词环节采用橙色系。
- 仅保留末位的 `List` 环节为新旧词公用行（采用次要中性色）。
- 各单词在所属轨道行上展示进度（完成/未完成/当前/下一个），非所属轨道的行显示轻量占位，使学习调度流一目了然。

---

## 2. 核心改动点

### 2.1 流水线行定义与结构化 (`PipelineRow`)
- **文件**：`app/lib/page/bdc/dialogs/bdc_dialogs.dart`
- **设计**：
  1. 定义流水线行模型，包含行类型、显示标签、环节标识、专属轨道颜色：
     - **新词专属行**：
       - 新词测评：`新: ${newCfg.check}`（绿色）
       - 新词中间环节：新词 `correct` 与 `wrong` 的去重集合（排重测评与 List），如 `新: ${step}`（绿色）
     - **旧词专属行**：
       - 旧词测评：`旧: ${reviewCfg.check}`（橙色）
       - 旧词中间环节：旧词 `correct` 与 `wrong` 的去重集合（排重测评与 List），如 `旧: ${step}`（橙色）
     - **公用行**：
       - 列表结算环节：`List`（次要文本中性色）

### 2.2 单元格与轨道状态映射逻辑
- 对于批次中的单词 `w`：
  - 判定其是否属于复习轨道：`isReviewWord = StudyTrack.isReviewTrack(...)`。
  - 获取该词当天的轨道步骤：`track = trackOf(w)`。
  - **新词行**：
    - 若 `isReviewWord == true`（旧词），`trackIndex = null`，显示极浅占位点。
    - 若 `isReviewWord == false`（新词），测评对应 `trackIndex = 0`；中间环节在 `track` 中则对应其在 `track` 中的实际下标，不在当前走向中则为 `null`。
  - **旧词行**：
    - 若 `isReviewWord == false`（新词），`trackIndex = null`，显示极浅占位点。
    - 若 `isReviewWord == true`（旧词），测评对应 `trackIndex = 0`；中间环节在 `track` 中则对应其在 `track` 中的实际下标，不在当前走向中则为 `null`。
  - **List 公用行**：
    - 新词与旧词均适用，`trackIndex = track.length - 1`。
- 根据 `trackIndex` 精确计算 `isCurrentStep`（蓝框）、`isNextStep`（橙框）、`isStepCompleted`（绿圆/方）。

### 2.3 图例与界面微调
- 优化弹窗顶部的图例（Legend），包含：
  - 状态：学过（绿圆）、未学（灰圆）、已掌握（绿方）、当前（蓝边框）、下一个（橙边框）。
  - 轨道颜色：新词环节（绿色）、旧词环节（橙色）、公用环节（次要文本色）。

---

## 3. Task 分解

### Task 1: 改造 `bdc_dialogs.dart` 中的流水线行结构与轨道映射
- **文件**：`app/lib/page/bdc/dialogs/bdc_dialogs.dart`
- **变更**：
  - 构造包含新词行、旧词行、公用 List 行的有序行列表；
  - 改造单元格渲染与 `trackIndex` 映射逻辑；
  - 更新顶部图例展示。
- **目的**：清晰分离新旧词环节，直观可视化调度状态。
- **验证**：`flutter analyze` 无警告与错误。

### Task 2: 验证流水线弹窗逻辑与回归测试
- **文件**：`app/test/` 相关测试
- **变更**：
  - 运行 `flutter test test/study_track_test.dart` 与相关测试，确保轨道推导逻辑无误；
  - 确保全量相关测试通过。
- **目的**：保证无语法错误与运行时逻辑缺陷。
- **验证**：`flutter test` 针对性测试全部通过。

---

## 4. 架构审查（阶段 1）

| 审查维度 | 结论 | 理由 |
| :--- | :--- | :--- |
| **1. 分层与职责** | ✅ PASS | 纯前端 UI 表现层（`bdc_dialogs.dart`）改动，不侵入底层 FSRS/调度核心及服务端，职责清晰。 |
| **2. 数据流与同步** | ✅ PASS | 读取前端本地 DB 和既有的 `StudyTrack`/`StudyStepsService`，不产生新的数据流或同步负担。 |
| **3. Dto/Vo 规范** | ✅ PASS | 不修改现有的 Dto/Vo 数据传输结构。 |
| **4. 设计原则** | ✅ PASS | 直观反映了当前调度系统的轨道逻辑（新词与旧词独立三组配置，最终收敛至 List），消除歧义，提升可读性。 |
| **5. Surgical Changes** | ✅ PASS | 聚焦在 `showPipelineDialog` 的行构建和单元格渲染，改动集中且最小化。 |
| **6. 验证充分性** | ✅ PASS | 包含语法检查与单元测试验证。 |
| **7. 可执行性** | ✅ PASS | 改动点清晰，步骤独立可验证。 |

**架构审查结论**：**PASS 通过**。
