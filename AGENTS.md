# 工作准则

## 请使用中文交流

## 适当地读取相关上下文，做到尽量不要断章取义, 按下葫芦起了瓢

## 不要用 workaround（变通方案）来掩盖问题，而应该使用 assert 等机制 尽早发现问题

## 代码追求 简洁(卡姆剃刀原理: 如非必要, 勿增实体)、优雅(对称, 一致, 自然, 低熵)、合理(符合直觉, 自洽)、高效、可维护

## 宁愿有暂时性的问题, 也要追求简单合理, 坚守合理, 不搞权宜之计(workaround), 最终淘汰不合理

## 编写 Java 代码时，不要使用类似 com.xxx.AClass 这样的长类名，而应该先 import 再使用类名

## 写完代码后，一定要检查并修复所有编译错误和警告

## 写完代码后要运行单元测试，保证没有破坏现有的功能，同时要注意避免消耗过多的 LLM token

## 不得自行 git commit

## 不要使用一些 取巧/牺牲体验 的方式解决问题, 不是头疼医头脚疼医脚, 而是要根治问题

## Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:

* State your assumptions explicitly. If uncertain, ask.
* If multiple interpretations exist, present them - don't pick silently.
* If a simpler approach exists, say so. Push back when warranted.
* If something is unclear, stop. Name what's confusing. Ask.

## Simplicity First

Minimum code that solves the problem. Nothing speculative.

* No features beyond what was asked.
* No abstractions for single-use code.
* No "flexibility" or "configurability" that wasn't requested.
* No error handling for impossible scenarios.
* If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:

* Don't "improve" adjacent code, comments, or formatting.
* Don't refactor things that aren't broken.
* Match existing style, even if you'd do it differently.
* If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

* Remove imports/variables/functions that YOUR changes made unused.
* Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:

* "Add validation" → "Write tests for invalid inputs, then make them pass"
* "Fix the bug" → "Write a test that reproduces it, then make it pass"
* "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

## AI 团队工作流

对于任何代码修改需求，加载 `ppdc-team-workflow` skill 并按 6 阶段流程执行：

阶段 0: 需求 → Plan (writing-plans)
阶段 1: 架构审查 Plan (ppdc-architect)
阶段 2: 用户审批 Plan
阶段 3: 逐 Task 执行 (TDD + 代码审查 + 音频专家审查)
阶段 4: 架构集成审查
阶段 5: 集成验证 (flutter test + mvn test)
阶段 6: 用户决策 (commit/修改/放弃)

团队角色：用户(决策者) + 主Agent(规划师+集成验证) + 架构师(subagent) + Flutter/Java开发(subagent) + 审查员(subagent) + 音频专家(subagent)

附加 skill(位于 `.agents/skills/` 目录): audio-specialist (音频变更), ppdc-architect (架构审查)
