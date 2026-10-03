# 工作准则

## 请使用中文交流

## 与用户沟通、编写任何方案/分析/文档时，必须遵守 `doc/glossary.md`（项目术语表）
- 术语表已有的概念，必须使用表中的「标准叫法」，不得随手换同义词。
- 禁止裸用字母代号（A/B/C/E/F/G/H）：只能在同一轮已给出清单时使用，跨轮引用必须重述人话摘要。
- 禁止用术语表第三章的工程黑话描述业务动作，必须说人话。
- 指代文件必须给全路径与行号，指代数值必须写全。
- 发现新概念或术语冲突，先补进术语表再继续。

## 适当地读取相关上下文，做到尽量不要断章取义, 按下葫芦起了瓢

## 不要用 workaround 和所谓的托底来掩盖问题，宁愿出现异常暴露问题，要追本溯源，根治问题

## 坚决拒绝防御性过度编码（Defensive Over-engineering）与虚假托底
- **源头单一根治原则（Single-Point Root-Cause）**：
  - 一个 Bug 往往只有一个真正的物理根因（例如网络并发乱序覆盖）。
  - 在源头彻底修复后，**严禁在下游链路（如服务端 Bo、DAO、数据库、前端展示层）做臆想式的多处布防与防御性篡改**。下游处处设卡不仅违反奥卡姆剃刀原理，还会将代码复杂度成倍放大。
  - 扪心自问：“如果源头修好了，下游这段防护在正常逻辑下是否永远不会触发？”如果是，坚决删除，严禁增加无用实体。
- **断言暴露 vs 静默掩盖的界限（Fail Fast vs Silent Masking）**：
  - **合法的契约校验**：当下游收到不符合业务事实的数据时（例如内部计数倒退、主键非法），应**直接抛出异常、记录错误日志或 Fail Fast 暴露**，绝不允许隐忍；
  - **非法的掩盖托底**：收到不符合事实的数据时，**写一个 `if (newVal < oldVal) continue/ignore` 静默吞掉、或强行覆写回旧值**。凡是“假装错误没发生、让程序强行继续”的代码，一律视为违规托底，坚决禁止。
- **禁止把客观反常归咎于“用户错觉”（No Premature Rationalization）**：
  - 当用户反馈“进度倒退”、“数字变小”等反直觉现象时，**严禁在没有全链路代码和日志确凿证据前，轻率归因为‘视觉错觉’或‘用户看错’**；
  - 必须假设用户的观察是 100% 客观真实的，穷尽全链路排查并发竞争、时序乱序、事务隔离与缓存覆盖，直到找到能物理复现该现象的代码根因为止。

## 代码追求 简洁(奥卡姆剃刀原理: 如非必要, 勿增实体)、优雅(对称, 一致, 自然, 低熵)、合理(符合直觉, 自洽)、高效、可维护

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
## HTML 原型与真机图规范
- 生成 UI 设计与预览 HTML 时，严禁使用 Google Fonts 等外部网络字体链接（避免网络环境限制导致加载阻塞或显示异常），统一使用系统原生跨平台现代字体栈（`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif` 与等宽字体 `ui-monospace, monospace`）。
- **原型真机高清 PNG 导出规范**：生成与更新 UI 原型真机图（`design/ui/png/`）时，必须统一执行 `node design/ui/render_mockup_png.js`（或 `npm run render-ui`），严格使用该脚本固化的统一旗舰真机模具（深空钛金属双层中框、实体侧按键、灵动岛、安全区状态栏、Home Bar 及透明画布），严禁临时手写异构样式导致真机壳风格分裂。

## 文档编写规范
- 今后凡是要求编写设计方案、创意记录、业务分析等文档，**如无特别说明，统一使用 HTML 格式，不要使用 Markdown (.md)**。
- **产品灵感与创意档案固定文件名**：统一为 `design/ideas.html`（Sparks & Ideas Hub），所有产品闪念、玩法构想、交互实验均集中在此维护更新，严禁新建碎片化文档，今后无需再次查找。
- 遵循现代极简排版美学与系统原生字体栈，兼顾可读性与结构化视觉层次。

## 中间生成文件与落盘规范
- 除非用户明确要求生成并保留的文档和图片，否则中间过程生成的任何文案、草稿、临时图片和测试数据，若需保存，**必须统一保存到本项目的 `tmp/` 目录下（`tmp/`）**，严禁私自写入或污染正式目录（如 `design/`、`assets/` 等）。

## 连机真机调试的进程规范（设备独占，必须现开现关）
- **真机是独占资源**：同一台设备同时只允许一个 `flutter run` 会话。谁占着设备，别人的 IDE 就会一直卡在 `Installing and launching`（连 `xcodebuild -prepareDeviceSupport` 都进不去），这不是"慢"，是互相抢占。
- **现开现关，禁止长期挂后台**：`flutter run`、`idevicesyslog`、`devicectl`（install / process launch）、`xcode_debug.js` 等一切占用设备的进程，只在需要真机验证的那一刻开，**验证一结束立刻关闭**。严禁把它们留在后台"等下次用"。
- **开之前先自检**：每次连机前先跑一遍 `pgrep -fl "flutter_tools.snapshot run|idevicesyslog|devicectl|xcode_debug.js"`，确认没有自己上一轮的残留；有就先清掉再开。
- **收尾必须自检**：任务收尾（含被打断、失败、用户改主意）时，再跑一遍同一条命令，确认自己起的进程数为 0；只报告"已验证"而没释放设备，视为未完成。
- **pid 记录要逐个校验**：不要在同一个 pid 文件上反复覆盖写入（后一次会盖掉前一次，导致 `kill` 落空、进程一直挂着）。记录时追加，关闭时逐个核对是否真的退出了，必要时补 `kill -9`。
- **辅助进程同样算数**：`idevicesyslog` 这类只读抓包进程也会占用设备连接，必须和应用进程一起关，不许"抓完忘了关"。
- 违反本条的后果不是"多占点资源"，而是直接堵死用户自己的开发流程，属于严重浪费他人时间的行为。

## 数据库连接信息
- 生产库、开发库连接方式见 ~/.zprofile
- 严禁私自修改生产数据库。若需修改, 必须经过我的明确授权。

## 数据库类型与 SQL 规范
- 本项目后端统一使用 **PostgreSQL** 数据库。
- 编写 SQL 升级脚本（`server/db_upgrade/`）或 JPA 注解时，必须严格遵守 **PostgreSQL** 语法：
  - 严禁使用 MySQL 方言特性（如 `ENGINE=InnoDB`、`MEDIUMTEXT`、表内 `INDEX name (col)` 语法等）。
  - 大文本字段统一使用 `TEXT`。
  - 索引使用标准的 `CREATE INDEX IF NOT EXISTS ... ON table_name (column_name);`。
  - 布尔类型统一使用 `BOOLEAN`。
- **表与字段注释铁律**：新建表或新增/修改数据库表字段时，必须使用 `COMMENT ON TABLE "table_name" IS '...';` 和 `COMMENT ON COLUMN "table_name"."column_name" IS '...';` 为所有表和字段添加清晰准确的中文业务注释，严禁字段注释裸奔，便于长期维护与理解。
- **保留关键字转义铁律**：PostgreSQL 中包含大量系统保留关键字（最典型的如 `"user"`、`"group"`、`"order"`、`"position"`、`"date"` 等）。编写 DDL、SQL 升级脚本或原生查询时，**涉及保留关键字的表名与列名必须强制使用双引号包裹**（如 `COMMENT ON TABLE "user" IS '...';`），严禁裸写导致语法解析异常。

## Flutter 资源目录声明铁律
- `pubspec.yaml` 的 `assets:` 声明**只递归一层**：声明 `assets/images/` 只覆盖它直接包含的文件，以及「一层子目录里直接包含的文件」。
- **`assets/images/pet/moods/` 这类第二层及更深的子目录必须单独声明**，否则整个目录会被静默跳过：代码报 `Unable to load asset`，而编译、静态检查、单元测试全部通过，毫无提示。
- **验证必须看打包产物，不能看界面、也不能只看文件是否存在**：执行 `flutter build bundle` 后检查 `build/flutter_assets/` 下是否真有该文件，或查 `.dart_tool/flutter_build/*/flutter_assets.d` 资源清单里有没有该目录条目。
- **读文件系统的测试验证不了资源能否随包发布**（`File(...).existsSync()` 不经过 Flutter 的资源解析）。新增资源目录时，必须同时在测试中断言 pubspec 里已声明该目录。
- 资源路径与目录名必须完全一致（含大小写与中文），路径写错同样只在真机运行时才报错，因此新增资源时应补一条「代码引用的资源是否存在」的断言。
- 新增或替换资源后必须**完全重新构建**才会进包，热重载与热重启都不重扫资源清单。



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


