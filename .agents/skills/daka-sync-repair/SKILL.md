---
name: daka-sync-repair
description: 诊断并修复"多设备打卡数据不同步"（打卡率不达标、最近30天色块缺块）。当用户用多台设备（手机/iPad）轮流打卡，但各端"打卡天数/打卡率"不一致、或页面色块不完整、或服务端 daka 记录缺失时使用。
whenToUse: 用户反馈"打卡率应该是100%但显示不对"、"两台设备数据不一样"、"色块缺"、"打卡记录没同步上来"等情况。
---

# 打卡数据多端同步 诊断与修复

## 核心数据模型（谁驱动谁）

| 界面/统计 | 来源表 | 说明 |
|---|---|---|
| 打卡天数 + 打卡率 | `user` 表的 `daka_day_count`（**派生缓存值**）+ `daka_ratio` | 打卡率 = `daka_day_count / 注册至今总天数` |
| 「最近30天学习情况」色块 | `user_study_daily_stat`（`day_status` 列） | 由 `user_oper` 的 `DAKA/START_LEARN/LOGIN` 在 `saveUserOper` 里反向涂色（DAKAED>STUDIED>LOGGEDIN）|
| 真实打卡记录 | `daka` 表（复合主键 `user_id+for_learning_date`）| 真正"打过卡"的底层数据 |
| 用户行为流水 | `user_oper`（oper_type=DAKA/START_LEARN/LOGIN）| 打卡动作是否发生、是否同步成功的权威依据 |

**关键概念**：
- `daka`（记录）与 `user_oper`（动作）容易分叉：`user_oper` 同步成功但 `daka` 记录缺失 → "色块全绿、打卡天数却不足"。
- `user.daka_day_count` 是派生缓存，可能被不同设备以 last-write-wins 互相覆盖 → 数值震荡。
- 色块由 `user_oper` 驱动，不直接读 `daka`；所以"色块绿" ≠ "daka 记录存在"。

## 诊断步骤（生产库只读）

> 生产库连接方式见 `~/.zprofile`（SSH 隧道 + `bdc` 库）。默认**只读**。任何 `daka`/`user`/`user_study_daily_stat`/`user_db_version`/`user_db_log` 的**写操作必须先获得用户明确授权**。

1. 定位用户（无 userId 时，可按"注册近7天 + 每天都打卡"匹配）：注册日 = 今天 - (totalDays-1)。
2. 核对三张表的不一致：
```sql
-- 真实打卡记录 vs 缓存天数 vs 每日状态
SELECT u.id, u.daka_day_count AS cached, d.cnt AS real_daka
FROM "user" u LEFT JOIN (SELECT user_id,count(*) cnt FROM daka GROUP BY user_id) d ON d.user_id=u.id
WHERE u.id='<userId>';
SELECT for_learning_date FROM daka WHERE user_id='<userId>' ORDER BY 1;
SELECT date, day_status FROM user_study_daily_stat WHERE user_id='<userId>' ORDER BY date;
SELECT version FROM user_db_version WHERE user_id='<userId>';
-- user_oper 是否有 DAKA（覆盖 7 天）——判断"动作发生但记录缺失"
SELECT DISTINCT oper_time::date FROM user_oper WHERE user_id='<userId>' AND oper_type='DAKA' ORDER BY 1;
-- daka 的同步日志（哪些天被 INSERT 到服务端）
SELECT version, operate, record_id FROM user_db_log WHERE user_id='<userId>' AND tbl_name='daka' ORDER BY version;
```
3. 判断：
   - `user_oper` 有 DAKA、但 `daka` 无记录 → **客户端没把 daka 上传**（服务端 `user_db_log` 里也无该天的 `daka` INSERT）。
   - `user_study_daily_stat` `DAKAED` < daka 天数 → 色块缺。
   - `user.daka_day_count` 在两端打架 → 缓存字段震荡（派生值 last-write-wins）。

## 已知根因与对应修复（代码）

| 根因 | 位置 | 修复 |
|---|---|---|
| 打卡动作被写两次 `user_oper`（saveDakaRecord + recordDaka）| `finish.dart` / `dao.recordDaka` | 移除重复的 `recordDaka` 调用（`saveDakaRecord` 已写），并删掉孤儿方法 `recordDaka` |
| 派生打卡统计非幂等 `+1`、分母不一致、多端互相覆盖 | `study_bo.saveDakaRecord` / `user_bo.updateAndSyncUserDakaStats` | 改为从本地 `dakas` 幂等推导；累计/最大天数**单调只增不减**；打卡率分母统一为"注册至今天数"并 clamp |
| 服务端 `processDakasSync` **静默吞异常**（`catch{logger.error}`），导致 daka 反序列化/入库失败时悄悄丢记录、`user_oper` 却成功 | `UserDbSyncBo.processDakasSync` | 去掉静默吞，让异常上抛（`throws IllegalAccessException`），整个同步批次回滚——避免"半成功"、暴露数据丢失 |
| 客户端 `Daka` 字段 `textContent` vs 服务端 `DakaDto.text` | `DakaBo` / `DakaDto` | DakaDto 加 `textContent` 别名 + `effectiveText()`；toDto 同时输出 `text`/`textContent`，fromDto 用 `effectiveText()` |
| 服务端 `user` 缓存打卡统计不可信 | `UserBo.recomputeDakaStats`（新增） | 以服务端 `daka` 表为权威重算（单调 max），并广播 |
| iPad 等某端不把 `daka` 推上来（运行期、需现场日志）| 客户端 `dakas` 推送链路 | 仍待定位；可加诊断日志，或用下述重建修复 |

## 数据修复：以 user_oper 重建缺失 daka

若确认 `user_oper` 有 DAKA 但 `daka` 缺失，可重建：

**方式 A（推荐，代码已实现、需部署）**：
- 接口 `POST /repairDakaFromUserOper.do?userId=<id>`（`SyncController`，调 `UserDbSyncBo.repairDakaFromUserOper`）。
- 逻辑：取 `user_oper` 的 DAKA 日期 → 对缺失日期建 `daka` 记录 + `DAKAED` 每日状态 → `userBo.recomputeDakaStats` → `logUserOperations` 生成 `user_db_log` 并递增版本 → 客户端增量同步即拉取补全本地。

**方式 B（临时，直接 SQL，需授权）**：
- 在事务内：往 `daka` 补缺失日期记录；`user_study_daily_stat` 置 `DAKAED`（`ON CONFLICT (user_id,date) DO UPDATE`）；`UPDATE "user"` 修正 `daka_day_count/continuous/max/last_daka_date`；向 `user_db_log` 写 `daka` INSERT 与 `user_study_daily_stat` UPDATE（`version = 当前+1`，`tbl_name` 用 `daka`，record_id 用 `userId-yyyyMMdd` 与 `userId|yyyy-MM-dd`，`record` 用 `json_build_object(...)` 组装）；`UPDATE user_db_version SET version=当前+1`。
- 注意：`user_db_log.id` 是 `varchar(32)`，生成 id 用 `replace(gen_random_uuid()::text,'-','')`；补的记录 `text` 用默认"好好学习，天天向上"（user_oper 不保存文案）。

## 安全红线

- 生产库**默认只读**；一切 `daka/user/user_study_daily_stat/user_db_log/user_db_version` 写入需**用户明确授权**。
- 不改动**其它**用户；重建/修复按单个 `userId` 精确限定。
- 不搞"客户端静默清理日志/实体掩盖问题"；让非法数据暴露到同步链路被拒或报错。
- 修复后引导用户在相关设备各点一次"立即同步"，让其增量拉取补全本地。
