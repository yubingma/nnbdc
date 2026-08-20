# ASR发音评分闪烁变低缺陷修复方案

## 背景与问题分析

### 1. 现象
在背单词（如中译英 `Ch2En` 等支持语音发音判定的环节）中：
用户说出正确发音并通过了测试，发音评分区域短暂显示了较高得分（如绿色 80~100 分），但随后瞬间被一个较低的评分（如橙色 45 分）覆盖，给用户带来“明明读对了却显示低分”的困惑与不良体验。

### 2. 根因剖析
1. **ASR 流式识别分包与异步时序**：
   - 用户发音时，ASR 引擎持续传回多帧识别结果（流式候选词）。
   - 中间某一帧命中高分（如 `score = 85`）且匹配目标词，`checkAsrResult` 触发 `_onAnswerCorrect`，将 `state.hasFinishedAnswering` 置为 `true` 并开始异步关麦。
2. **残余尾帧未做状态拦截**：
   - 关麦指令在底层硬件完成需要几十毫秒；在此期间，麦克风尾音（如呼吸声、环境音）被 ASR 引擎解析出低置信度尾帧候选。
   - 尾帧到达 `bdc_notifier.dart` 的 `onAsrResult` 时，虽然 `checkAsrResult` 内部有 `if (state.hasFinishedAnswering || _isAnswerCorrectHandling) return;` 保护（不会回退通关状态），但 `onAsrResult` 在调用 `checkAsrResult` **之前** 就直接执行了 `_updateState(state.copyWith(currentScore: result.score, ...))`。
   - 这导致界面上的 `currentScore` 被尾帧的低分（如 45 分）无条件覆盖。

---

## 修复目标与设计原则

1. **精确拦截残余尾帧**：
   - 当题目已完成作答（`state.hasFinishedAnswering == true`）且非处于主动练习模式（`!_isPracticeMode`），或者当前正在处理答对过渡中（`_isAnswerCorrectHandling == true`）时，`onAsrResult` 应直接丢弃后续到达的残余识别帧，不得更新 `currentScore` 和候选词。
2. **支持后续主动练习**：
   - 当用户在查看释义后主动点击发音/录音进入练习模式（`_isPracticeMode == true`）时，重新允许 ASR 结果正常更新评分，保证练习体验完整。
3. **保持最高分或达标分展示（双重防御）**：
   - 当单词已答对时，保持通关时的高分展示，避免在视觉上造成混淆。

---

## 影响范围与修改点

### 1. `app/lib/page/bdc/providers/bdc_notifier.dart`
- 在 `onAsrResult` 入口及单词评分更新处，增加针对 `(state.hasFinishedAnswering || _isAnswerCorrectHandling) && !_isPracticeMode` 的防御性拦截。
- 确保在关麦过渡期间到达的尾帧不会篡改 UI 上的发音评分。

### 2. 测试用例验证
- 在 `app/test/bdc_notifier_test.dart` 中增加单元测试：
  - 模拟单词发音识别通过后收到残余低分 ASR 帧的场景，验证 `state.currentScore` 保持原高分而不被低分篡改。
  - 验证练习模式下重新发音依然可以正常更新 `currentScore`。

---

## Task 拆解与执行计划

### Task 1: 编写失败测试用例 (TDD)
- **文件**: `app/test/bdc_notifier_test.dart`
- **目的**: 复现单词识别通过后残余尾帧覆盖 `currentScore` 的 bug，并建立防回归测试。
- **验证**: `flutter test test/bdc_notifier_test.dart` 失败。

### Task 2: 修复 `bdc_notifier.dart` 中的 ASR 尾帧评分覆盖问题
- **文件**: `app/lib/page/bdc/providers/bdc_notifier.dart`
- **目的**: 拦截答对完成/处理中的残余 ASR 帧对 `currentScore` 的污染，同时保留练习模式下的更新能力。
- **验证**: `flutter test test/bdc_notifier_test.dart` 通过。

### Task 3: 架构审查与音频专项审查
- **目的**: 确认改动不影响音频状态机、PTT 流程及练习模式。
- **验证**: `flutter analyze` + `flutter test test/audio_state_machine_test.dart` + `flutter test test/bdc_notifier_test.dart`。

---

## 阶段 1：架构审查结果

- **1. 分层与职责**: ✅ PASS。修改仅在前端状态管理层（`BdcNotifier`），属于纯 UI/ASR 交互流控制，职责清晰。
- **2. 数据流与同步**: ✅ PASS。不改变底层数据持久化与数据库表结构，不影响服务端同步。
- **3. Dto/Vo 规范**: ✅ PASS。不涉及 DTO/VO 改动。
- **4. 设计原则（Surgical Changes & 根治）**: ✅ PASS。从 ASR 事件流状态机入口根治尾帧污染，不使用延时或 hack 机制，逻辑对称自然。
- **5. 验证充分性**: ✅ PASS。包含 TDD 单元测试、音频状态机测试及整体 analyze。
- **架构审查结论**: **PASS（审查通过，提交用户审批）**
