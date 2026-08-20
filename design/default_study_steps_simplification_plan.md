# 新词默认学习环节简化 Plan

## 需求背景

当前新词（`scope='new'`）未配置时返回的默认三组规则为：
- 测评：`En2Ch`（单词 ・ 英→中）
- 答对后（correct）：`['Ch2En', 'EnSentence2Ch', 'ChSentence2En']`
- 答错后（wrong）：`['Ch2En', 'EnSentence2Ch', 'ChSentence2En']`

用户反馈：默认环节不要例句的两个环节（`EnSentence2Ch` 与 `ChSentence2En`），因为例句模式学习难度较高，会影响新用户的上手体验。

修改后新词默认三组规则应为：
- 测评：`En2Ch`（单词 ・ 英→中）
- 答对后（correct）：`['Ch2En']`（单词 ・ 中→英）
- 答错后（wrong）：`['Ch2En']`（单词 ・ 中→英）

（注：用户如需例句训练，仍可在「今日学习计划」中手动添加例句环节。）

---

## 影响范围

1. **前端运行时默认值**：`app/lib/util/study_steps_service.dart` 中的 `StudyStepsService.getThreeGroupConfig('new')` 默认三组。
2. **后端补缺默认值**：`server/nnbdc-service/src/main/java/beidanci/service/bo/UserStudyStepBo.java` 中的 `initUserStudySteps`（新词初始化步骤）。
3. **单元测试与集成测试适配**：
   - `app/test/study_steps_service_test.dart`（默认值断言）。
   - `app/test/learning_workflow_integration_test.dart`（长周期自然毕业仿真用例中的默认当天巩固次数与日志条数计算）。

---

## Task 分解

### Task 1: 前端 `StudyStepsService` 默认环节调整与单元测试
- **文件**: 
  - `app/lib/util/study_steps_service.dart`
  - `app/test/study_steps_service_test.dart`
- **变更**:
  - 将 `study_steps_service.dart` 中 `scope == 'new'` 的 `defaultSteps` 从 `['Ch2En', 'EnSentence2Ch', 'ChSentence2En']` 修改为 `['Ch2En']`。
  - 将 `study_steps_service_test.dart` 中 `新词未配置时返回默认三组且不落库` 的预期断言修改为 `['Ch2En']`。
- **目的**: 使未自定义配置的新用户进入新词学习时，仅包含「英→中」测评与「中→英」环节，去除例句两个环节。
- **验证**: 运行 `flutter test test/study_steps_service_test.dart`。

---

### Task 2: 后端 `UserStudyStepBo` 新词默认步骤初始化调整
- **文件**:
  - `server/nnbdc-service/src/main/java/beidanci/service/bo/UserStudyStepBo.java`
- **变更**:
  - 将 `initUserStudySteps` 中的 `scope='new'` 初始 steps 从 `[Ch2En, EnSentence2Ch, ChSentence2En]` 修改为 `[Ch2En]`。
- **目的**: 保持服务端与客户端新词默认三组规则一致。
- **验证**: 运行 `mvn test -Dtest=UserStudyStep*`。

---

### Task 3: 前端集成测试仿真适配与全量验证
- **文件**:
  - `app/test/learning_workflow_integration_test.dart`
- **变更**:
  - 调整 `整本词书多天学习到自然毕业` 仿真用例：新词当天评分次数从 4 次（init + 3次巩固）更新为 2 次（init + 1次巩固），自然毕业日志条数预期从 7 条调整为 5 条。
- **目的**: 保证端到端自然学习全链路测试与新默认规则一致。
- **验证**: 运行 `flutter test test/learning_workflow_integration_test.dart`。

---

## 阶段 1：架构审查结果 (ppdc-architect)

| 审查维度 | 审查结果 | 理由 |
| :--- | :---: | :--- |
| **1. 分层与职责** | ✅ PASS | 变更精确作用于前端配置服务与后端默认数据初始化，职责清晰一致。 |
| **2. 数据流与同步** | ✅ PASS | 不破坏既有同步逻辑与三组数据结构，且前后端默认值保持对称。 |
| **3. Dto/Vo 规范** | ✅ PASS | 不涉及 Dto/Vo 结构变动。 |
| **4. 设计原则** | ✅ PASS | 简化默认流程，降低新用户门槛；未增加任何冗余实体与 workaround。 |
| **5. Surgical Changes** | ✅ PASS | 仅修改默认环节列表及相关测试预期，不夹带任何无关改动。 |
| **6. 验证充分性** | ✅ PASS | 包含单元测试与端到端自然学习全链路集成测试验证。 |
| **7. 可执行性** | ✅ PASS | 依赖关系清晰，分步可独立验证。 |

**架构师审查结论**: **PASS**
