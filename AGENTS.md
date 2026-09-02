# 工作准则

## 请使用中文交流

## 适当地读取相关上下文，做到尽量不要断章取义, 按下葫芦起了瓢

## 不要用 workaround 和所谓的托底来掩盖问题，宁愿出现异常暴露问题，要追本溯源，根治问题

## 代码追求 简洁(卡姆剃刀原理: 如非必要, 勿增实体)、优雅(对称, 一致, 自然, 低熵)、合理(符合直觉, 自洽)、高效、可维护

## 宁愿有暂时性的问题, 也要追求简单合理, 坚守合理, 不搞权宜之计(workaround), 最终让合理战胜不合理

## 编写 Java 代码时，不要使用类似 com.xxx.AClass 这样的长类名，而应该先 import 再使用类名

## 写完代码后，一定要检查并修复所有编译错误和警告

## 写完代码后要运行单元测试，保证没有破坏现有的功能，同时要注意避免消耗过多的 LLM token

## 不得自行 git commit

## 不要使用一些 取巧/牺牲长期 的方式解决问题, 不是头疼医头脚疼医脚, 而是要根治问题

## 实体主键 ID 生成规范
- 所有同步业务表实体的主键 ID 必须使用标准的 32 位 UUID（客户端统一使用 `Util.uuid()`，服务端使用 `Util.uuid()`）。
- 严禁通过字符串拼接（例如 `${userId}_${code}` 或 `${userId}_${timestamp}`）作为实体 ID，以防止超出数据库 `VARCHAR(32)` 限制并在端云同步时导致入库异常或主键分裂。
- 复合主键表（如 `dictWords` 的 `dictId-wordId`、`userStudySteps` 的 `userId-scope-group-studyStep`）的同步日志 `record_id` 天然会超过 32 字符，服务端 `user_db_log.record_id` 为 `VARCHAR(131)`，足以容纳，这是**合法**的，严禁在前端按 `record_id` 长度做清理。
- **严禁在客户端静默清理/修复同步日志或实体数据来掩盖非法数据**（例如删除超长 `record_id` 日志、改写超长主键实体）。非法数据应让其暴露到同步链路被服务端拒绝并报错，而不是在前端"自愈"掩盖问题，否则会长期掩盖根因导致静默数据丢失。

## 端云同步表名与日志规范
- 服务端数据库表名与同步日志中的 `tbl_name` 必须严格统一使用**单数下划线命名**（例如 `user`、`daka`、`user_study_step`、`learning_dict`、`dict` 等，与服务端 JPA `@Table(name = "...")` 保持完全一致）。
- 严禁在服务端代码中向 `user_db_log` / `sys_db_log` 写入复数或不一致的表名（例如严禁将 `user` 错写为 `users`）。
## HTML 原型生成规范
- 生成 UI 设计与预览 HTML 时，严禁使用 Google Fonts 等外部网络字体链接（避免网络环境限制导致加载阻塞或显示异常），统一使用系统原生跨平台现代字体栈（`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif` 与等宽字体 `ui-monospace, monospace`）。

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


