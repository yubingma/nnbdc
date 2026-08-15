---
name: ppdc-team-workflow
description: ppdc 项目 AI 团队 6 阶段工作流。任何代码修改需求（功能开发、缺陷修复、重构、优化）都必须先加载本 skill，按阶段 0-6 执行：需求→Plan、架构审查、用户审批、逐 Task 执行(TDD+审查+音频专家审查)、架构集成审查、集成验证、用户决策。
whenToUse: 收到任何代码修改需求时。
---

# ppdc 团队工作流

ppdc 项目通过「用户 + 主 Agent + 架构师 + Flutter/Java 开发 + 审查员 + 音频专家」的团队协作方式完成代码修改。任何代码修改需求，主 Agent 必须按以下阶段执行，不得跳过。

## 团队角色

- 用户：决策者，负责审批 Plan 与最终决策
- 主 Agent：规划师 + 集成验证，负责拆解 Task、协调 subagent、执行阶段 5
- 架构师(subagent)：阶段 1 审查 Plan、阶段 4 架构集成审查（按 ppdc-architect skill）
- Flutter/Java 开发(subagent)：按 Task 实现代码（TDD）
- 审查员(subagent)：每个 Task 的代码审查
- 音频专家(subagent)：音频相关 Task 的专项审查（按 audio-specialist skill）

## 阶段 0：需求 → Plan

- 充分读取相关上下文（AGENTS.md、arch.md、相关代码与测试），不要断章取义
- 将需求拆解为 Plan：影响范围 + 有序 Task 分解，每个 Task 写明「文件 / 变更 / 目的 / 验证」
- Plan 写入 `design/` 目录（纳入版本管理），格式参考 `design/` 与 `app/.hermes/plans/` 下的历史 Plan

## 阶段 1：架构审查 Plan

- 主 Agent 加载 `ppdc-architect` skill，按其中的架构背景与审查要点审查 Plan
- 审查不通过则修改 Plan 后重新审查，直到通过

## 阶段 2：用户审批 Plan

- 将审查通过的 Plan 提交用户审批
- 未经用户批准，不得开始写代码

## 阶段 3：逐 Task 执行

- 每个 Task 独立委派给开发 subagent，按 TDD 流程：先写失败测试 → 实现 → 测试通过
- 每个 Task 完成后由审查员 subagent 做代码审查
- 音频相关 Task 额外由音频专家审查（加载 `audio-specialist` skill）
- Flutter Task 验证：`flutter analyze` + `flutter test` 跑针对性用例（避免全量跑消耗 token）
- Java Task 验证：`mvn test` 跑针对性用例

## 阶段 4：架构集成审查

- 阶段性完成后，架构师按 ppdc-architect skill 检查已实现变更与整体架构的一致性

## 阶段 5：集成验证

- `flutter test` 全量回归 + `mvn test` 全量回归
- 修复所有编译错误、警告和测试失败

## 阶段 6：用户决策

- 汇报结果，由用户在 commit / 修改 / 放弃 中决策
- 主 Agent 不得自行 git commit（见 AGENTS.md）

## 约束

- 遵守 AGENTS.md 全部工作准则（中文交流、Surgical Changes、断言早期暴露问题、根治不 workaround 等）
- 遵循 arch.md 的设计原则：快速失败、不吞异常、减少冗余、Dto/Vo 规范
- 整个流程是长任务，建议用 goal 机制持续跟踪；每完成一个 Task 及时同步进度
