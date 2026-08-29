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

## 实体主键 ID 生成规范
- 所有同步业务表实体的主键 ID 必须使用标准的 32 位 UUID（客户端统一使用 `Util.uuid()`，服务端使用 `Util.uuid()`）。
- 严禁通过字符串拼接（例如 `${userId}_${code}` 或 `${userId}_${timestamp}`）作为实体 ID，以防止超出数据库 `VARCHAR(32)` 限制并在端云同步时导致入库异常或主键分裂。

## 端云同步表名与日志规范
- 服务端数据库表名与同步日志中的 `tbl_name` 必须严格统一使用**单数下划线命名**（例如 `user`、`daka`、`user_study_step`、`learning_dict`、`dict` 等，与服务端 JPA `@Table(name = "...")` 保持完全一致）。
- 严禁在服务端代码中向 `user_db_log` / `sys_db_log` 写入复数或不一致的表名（例如严禁将 `user` 错写为 `users`）。
- 客户端与服务端维护的双向表名映射（如客户端 `Util.localTableNameToRemote` 和 `Util.remoteTableNameToLocal`）必须保持严格对齐；新增或修改同步表时需同步检查两端映射，避免产生客户端无法解析的非法表名导致同步中断。


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


