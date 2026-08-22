# 词书 seq 连续性修复：删除即重排 + 同步前自检 + 服务端 issue 落库（Plan）

> 状态：架构审查 PASS（1 处修正已落实）→ 待用户审批
> 目标：根治 `DICT_WORD_ORDER_INVALID: ... 序号不连续: 期望=1, 实际=202` 类同步失败——
> 客户端保证用户词书 `dict_word.seq` 恒为 1..N 连续（删除路径恢复重排 + 同步前自检兜底），
> 服务端让 `user_db_issue` 记录在事务回滚后仍能落库（可观测）。

## 1. 背景与问题

生产日志（用户[十月]，2026-08-21 20:36）：

```
WARN SyncController - 同步用户数据时发生词书数据异常... error=[DICT_WORD_ORDER_INVALID:
     cdb06f8fcabd424889e0151bf0fecef3|序号不连续: 期望=1, 实际=202]
```

**现象**：服务端每次同步收尾执行 `validateAndFinalizeSync`（`UserDbSyncBo.java:1044`）→
`DictWordBo.validateDictWordOrder`（`DictWordBo.java:425`）要求该用户**每本词书**的
`dict_word.seq` 从 1 开始逐 1 连续；不满足则抛 `RawWordDataErrorException`，**整个同步事务回滚**
（`UserDbSyncBo.java:250-313`），返回 `DICT_WORD_ORDER_INVALID` 错误码；客户端收到后走
"修复本地词书 → 下次同步全量重写"流程（`sync.dart:561-596`），最终自愈。

**根因（代码层，两层不对称）**：

1. **客户端删除不重排**。commit `12910a73`（2026-04-21 "removing sequence update overhead"）
   删掉了 `DictWordsDao.deleteEntity` 里"删除后后续词 seq-1 前移"逻辑；
   `deleteDictWordWithCleanup`（`dao.dart:654`）也是只删不重排。
   → 用户删掉词书**前面的 N 个词**后，剩余词 seq 从 N+1 开始（如 202..N'），本地即断裂。
2. **同步镜像不重排 + 校验要求严格连续**。服务端 `processDictWordSync`（`UserDbSyncBo.java:903`）
   对客户端 DELETE/INSERT/UPDATE 照单全收、不维护连续性；校验器却要求 1..N 连续。两端不对称，
   坏状态一同步即被拦。

**佐证**：本地库（bdc）全库扫描发现同类异常实例——用户 `d18b5ce2...` 词书"哈哈哈"
seq 为 `[1, 1, 2]`（重复序号），说明该不变量已被多次破坏，是系统性问题而非个例。

**附带缺陷**：`validateAndFinalizeSync` 先 `userDbIssueBo.recordIssue(...)` 再抛异常，
而 `UserDbIssueBo` 类级 `@Transactional(rollbackFor = Throwable.class)`（REQUIRED 传播），
recordIssue 加入外层同步事务 → 回滚时 issue 记录一并回滚 → `user_db_issue` 表永远为空，
**问题埋点形同虚设**，运维不可见。

## 2. 设计决策

### 2.1 客户端：删除路径恢复 seq 连续性（治本）

`DictWordsDao` 两个删除入口，在 `genLog == true`（用户主动删除）时删除后立即重排：

- `deleteEntity(entry, genLog)`（`dao.dart:637`）：`genLog == true` 时删除后调用
  `_reorderDictWords(dictId, true)`。
- `deleteDictWordWithCleanup(...)`（`dao.dart:654`）：wordCount 更新后，`genLog == true` 时
  同样调用 `_reorderDictWords(dictId, true)`。

理由与约束：

- `_reorderDictWords`（`dao.dart:830`）已内置优化：逐词比较，仅对 `seq != i+1` 的词写库并生成
  UPDATE 日志（`dao.dart:844-856`），连续时零写入零日志。删除一个词至多产生 O(N) 条 UPDATE
  （删第 1 个词时 N-1 条），远优于现状"上传失败 → 全量 BATCH_DELETE + 全部 UPDATE 重写"的
  两次流量，且不再有失败往返。
- 删除后重排生成的 UPDATE 日志时间戳晚于同批 DELETE 日志，客户端上传按时间戳排序
  （`sync.dart:293-305`），服务端先 DELETE 后 UPDATE，最终连续。即使 `DbLogUtil.logOperation`
  的 UPDATE 智能合并（`db_log_util.dart:90-101`）或同毫秒排序抖动导致顺序颠倒，批尾状态仍收敛：
  重排 UPDATE 携带最终 seq（1..N）、DELETE 只移除目标词，服务端对两种顺序均收敛。
- `genLog == false`（服务端日志回放，`sync.dart:436`、`sys_db_sync.dart:162`）**不重排**：
  服务端只下发通过校验的镜像（失败即回滚），回放保持本地与服务端一致，且回放不生成日志，
  避免日志循环。

覆盖到的主动删除入口：`removeWordFromDict`（`word_bo.dart:2334`）、词书 UI 删除
（`dict_words.dart:181`）、`deleteMasteredWord` 移出已掌握（`dao.dart:1859`）、
`addRawWord` 联动移出已掌握（`word_bo.dart:1098`）。已掌握词书同样受服务端校验约束，
删除后重排对它是**必要**的；已掌握列表按 seq 升序展示（`dao.dart:1760-1763`），
重排仅压缩断裂、保持相对顺序，无 UI 语义回归。

### 2.2 客户端：同步前自检（兜底，修复历史遗留断裂）

在 `syncUserDb`（`sync.dart:816`）**查询待上传日志之前**（第 848 行 `getUserDbLogs` 之前），
调用新增公开顶层函数 `repairDictWordSequences(String userId)`（sync.dart 顶层函数均为公开风格，
保证测试可调用）：

- 枚举当前用户全部词书（复用 `data_integrity_checker.dart:1001-1013` 的模式：
  select dicts + 过滤 `ownerId == userId`）；
- 对每本用户词书调用 `dictWordsDao.fixDictOrder(dictId, true)`（公开入口，内部 `_reorderDictWords`）。

效果：

- 历史遗留断裂（旧版本同步进来的、回放产生的、未知路径产生的）在**上传前**本地自愈，
  生成的 UPDATE 日志进入本次上传批次，服务端校验不再失败——把"被动失败再修复"变为"主动预防"；
- seq 连续时零写入零日志，仅读开销（用户词书个位数，可接受）；
- 修复日志与本次其他日志按时间戳排序，先 DELETE 后 UPDATE，语义正确；
- 附带修正既有缺陷：`data_integrity_checker._fixDictWordSequences`（`data_integrity_checker.dart:1028`）
  对非生词本词书 `genLog=false` 静默修复、不生成日志 → 服务端镜像永远学不到修复、该词书持续校验
  失败；本自检对所有用户词书 `genLog=true`，恰好修正此缺陷。

### 2.3 服务端：issue 落库移出同步事务（兜底可观测）

**不做 REQUIRES_NEW**（已核实 `user_db_issue` 存在外键 `user_db_issue_user_id_fkey` 指向 user：
外层同步事务处理本批 users UPDATE 时持有 user 行 X 锁，REQUIRES_NEW 内层 INSERT 触发外键
FOR KEY SHARE 锁请求与之互斥 → 死锁/挂起）。

改为**回滚后记录**（同步事务已回滚，无行锁冲突，普通 REQUIRED 事务即可提交）：

- `UserDbSyncBo.validateAndFinalizeSync` 中**删除** `recordIssue` 调用（事务内必然随回滚丢失，
  保留无意义），仅保留校验与 throw；
- `UserDbSyncBo` 新增公开方法：
  `recordDictWordOrderIssue(String userId, String message)` → 内部调用
  `userDbIssueBo.recordIssue(userId, "DICT_WORD_ORDER_INVALID", message)`；
- `SyncController.syncUserDb2Back` 的 `catch (RawWordDataErrorException e)` 分支（此时外层事务
  已由 `UserDbSyncBo` 回滚并 rethrow）调用 `syncBo.recordDictWordOrderIssue(userId, e.getMessage())`
  （包 try-catch 记日志，不影响错误码返回）。

`UserDbIssueBo.recordIssue` 保持类级普通事务不变（无外层事务时独立提交）。
调用点仅 `UserDbSyncBo.java:1050` 一处，改动面小。

### 2.4 明确不做（保持 Surgical）

- **不动服务端 `processDictWordSync`**（不重排）：服务端是备份、客户端是数据源，客户端保证连续后
  服务端镜像即连续；
- **不改 `validateDictWordOrder` 校验语义**（保持严格 1..N 连续）：这是"快速失败"意图，客户端修复后
  不再误伤；
- **不改 SyncController 错误码协议**（客户端修复流程保留，作为最后防线）；
- **不改 `_reorderDictWords`/`fixDictOrder` 既有签名与优化逻辑**；
- 不引入"seq 允许不连续"等行为变更（改动大、破坏顺序语义，超出本次范围，仅作备选记录）。
- 已知既有行为（与本 Plan 无关，不改）：`batchDeleteUserRecords` 回放 BATCH_DELETE 时无条件
  `updateWordCount(dictId, true)` 会生成 dicts UPDATE 日志，幂等无害。

## 3. 改动清单

### A. `app/lib/db/dao.dart`（Flutter）

- `deleteEntity`：`genLog == true` 时，删除后调用 `_reorderDictWords(dictId, true)`。
- `deleteDictWordWithCleanup`：`genLog == true` 时，wordCount 更新后调用 `_reorderDictWords(dictId, true)`。

### B. `app/lib/util/sync.dart`（Flutter）

- 新增公开顶层函数 `repairDictWordSequences(String userId)`（枚举用户词书 + `fixDictOrder(dictId, true)`）。
- `syncUserDb` 第 848 行 `getUserDbLogs` 之前调用 `await repairDictWordSequences(userId)`。

### C. 服务端（Java）

- `UserDbSyncBo.java`：
  - `validateAndFinalizeSync`（1044-1058 行）删除 `userDbIssueBo.recordIssue(...)` 调用（约 1050 行），
    并**同步删除 `catch (IllegalAccessException e)` 块（1055-1057 行）**——该 catch 原只服务于
    recordIssue 的 throws，删除后成为不可达 catch 会导致 `mvn compile` 失败；将 1047-1058 的
    try/catch 简化为直接 `String issue = validate...; if (issue != null) throw new
    RawWordDataErrorException("DICT_WORD_ORDER_INVALID: " + issue);`（`catch (RawWordDataErrorException)`
    一并消失，行为等价）；方法签名 1045 行多余的 `throws IllegalAccessException` 一并删除；
  - 新增公开方法 `recordDictWordOrderIssue(String userId, String message)`，内部
    `userDbIssueBo.recordIssue(userId, "DICT_WORD_ORDER_INVALID", message)`，并**内部 try-catch
    吞掉 `IllegalAccessException` 记日志**（不向调用方传播）。
- `SyncController.java`：`syncUserDb2Back` 的 `catch (RawWordDataErrorException e)` 分支（约 204-207 行）
  调用 `syncBo.recordDictWordOrderIssue(userId, e.getMessage())`（新方法内部已吞异常，**必须**
  不向客户端传播——否则客户端收不到 `DICT_WORD_ORDER_INVALID` 错误码）。

## 4. 架构审查要点（ppdc-architect）

1. 分层与职责 ✅：修复落点在数据产生端（客户端 DAO/同步入口）与服务端可观测层（issue 落库），
   不引入新的职责。
2. 数据流与同步 ✅：重排 UPDATE 日志复用既有 `dictWords` 同步链路与排序规则；回放路径（genLog=false）
   不重排、不生成日志，无循环；批尾状态收敛（重排 UPDATE 携带最终 seq）；服务端镜像语义不变。
3. Dto/Vo ✅：不涉及。
4. 设计原则 ✅：治本（删除即重排）而非兜住每次失败；快速失败保留（服务端校验不动）；
   `_reorderDictWords` 复用而非新写重排逻辑（减少冗余）；issue 落库移出事务后埋点真正生效；
   附加修正 data_integrity_checker"静默修复不上传"缺陷。
5. Surgical ✅：改动集中在 2 个 Flutter 文件 + 2 个 Java 文件，不夹带无关改动。
6. 验证充分性 ✅：Task 1/2 有针对性 flutter 用例（删除重排行为、同步前自检行为）+ flutter analyze；
   Task 3 以 `mvn compile` + 现有 `mvn test` 回归为主（Spring 事务行为无法纯 POJO 验证），
   并在本机库核实外键存在后采用无锁风险的替代方案。
7. 可执行性 ✅：Task 依赖清晰（1 → 2 同端顺序实现、3 独立），无前置缺失。

## 5. Task 分解

1. **Task 1（Flutter，TDD）**：`dao.dart` 删除路径重排。
   - 测试（`app/test/words_dao_test.dart` 新增 group；需 `MyDatabase.setInstanceForTesting`
     （`db.dart:94`）使 `DbLogUtil` 单例写入测试库；插入 Dict/DictWord 夹具，Dict 需 ownerId 非空）：
     - 删除中间词后剩余 seq 连续（1..N-1）；
     - `genLog=true` 时生成 UPDATE 日志（数量 = 被前移的词数），`genLog=false` 时不生成；
     - 删除最后一个词：seq 不变、无 UPDATE 日志；
     - 删除后新加词（maxSeq+1）续接正确。
   - 验证：针对性 `flutter test` + `flutter analyze`。
2. **Task 2（Flutter，TDD）**：`sync.dart` 同步前自检。
   - 测试（新文件 `app/test/sync_repair_test.dart`，内存库 + `setInstanceForTesting`）：
     本地词书 seq 断裂（如 3..5）→ `repairDictWordSequences` 后 seq 连续且本地日志表出现 UPDATE
     日志；seq 连续时零新日志；非用户词书（ownerId 为系统用户）不被处理。
   - 验证：针对性 `flutter test` + `flutter analyze`。
3. **Task 3（Java）**：issue 落库移出同步事务（改动清单 C）。
   - 验证：`mvn compile` + `mvn test`（现有 6 个测试类不破坏）——重点确认删除不可达 catch 后
     编译通过；已在本机 bdc 库核实 `user_db_issue` 外键存在 → 替代方案（回滚后记录）成立，
     无死锁风险；代码审查确认 catch 分支记录路径与错误码返回互不影响。
   - 注意：details 落库内容为 `e.getMessage()`（带 `DICT_WORD_ORDER_INVALID: ` 前缀），
     冗余但无害，长度远小于 `details` 列（varchar 2000），保持原样。
4. **阶段 5 集成验证**：`flutter analyze` 全量 0 issue + 全量 `flutter test`；
   `mvn compile` + `mvn test` 全量。修复所有编译错误、警告、测试失败。

## 6. 风险与注意事项

- **重排日志量**：删第 1 个词产生 N-1 条 UPDATE——对超大词书（数千词）单次删除流量较大，
  但一次性成功，优于现状失败重写（BATCH_DELETE + 全部 UPDATE × 2 次往返）；若后续需要可再加
  "批量删除合并重排"优化，本次不做。
- **自检读开销**：每次 `syncUserDb` 枚举用户词书并逐词比较，用户词书个位数、零写入时仅读，
  可接受；若将来用户词书规模剧增再考虑"仅对有待上传词书日志的词书自检"。
- **`_reorderDictWords` 的 owner 获取**：`DbLogUtil.logOperation(owner!, ...)` 依赖 dict 记录存在
  （现有代码同假设，调用点均在词书存在场景），不新增防御。
- **并发**：`ThrottledDbSyncService` 已保证同一客户端不同时跑两个同步（`_isSyncUserDbRunning` /
  `_isSyncDbRunning`），自检不会与事务 A 写入交错。
- **issue 落库时序**：catch 分支记录时同步事务已回滚（`UserDbSyncBo` catch 块 rollback 后 rethrow），
  `user_db_issue` 落库为独立事务，无行锁冲突；`recordIssue` 内 `userBo.findById` 在回滚后读取，
  语义正确。
- **未来优化项（本次不做，记录）**：服务端校验失败回滚整个事务（含用户资料等无关数据）——回滚后
  客户端本地数据由事务 A 保存、日志未清，下次同步整体重传，无数据丢失；2.2 上线后该失败路径应近
  消失。拆事务/提前校验涉及跨表一致性与幂等重放，超出本次范围。
