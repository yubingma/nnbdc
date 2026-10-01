---
name: wordbook-batch-import
description: 泡泡单词 (NNBDC) 词书批量导入与全流程品控。包含从 TXT/PDF 提取后的质量审查（重名冲突一票否决、口语短语末尾脱标、称谓缩写归一、大小写异义词保护、大词典粘连词审计）、二级版本分组与 UUID 规划、端云增量同步日志闭环（dict_group + sys_db_log + sys_db_version）、游戏大厅自动绑定（targetGameHallIds）、数据库时区治理以及生产环境批量导入执行与验证。
whenToUse: 当需要向系统批量导入一批词书（例如「小学」「初中」「高中」「考研」等大类下的多版本词书）、生成/维护 meta.json、对原始词汇表执行高标准清洗品控、规划词书子分组与游戏大厅关联、或处理词书端云同步时使用。
---

# 泡泡单词 词书批量导入与全流程品控标准化指南

## 0. 一句话定位与核心思想

> **“粗提取不等于可入库，机器提取底板，严格质量审查清洗，端云同步闭环治理。”**
> 
> 任何批量的词书入库，必须经历：
> 1. **数据品控**：执行重名排查、末尾脱标、缩写归一、粘连审计，达到出厂级“无菌”；
> 2. **元数据自洽**：分配标准 32 位 UUID 分组，锁定推升 `sys_db_version`，确保客户端离线/首屏静默同步生效；
> 3. **关联打通**：通过 `targetGameHallIds` 将主词书及派生乱序版自动绑定至对应游戏大厅。

---

## 1. 核心数据格式规范

### 1.1 物理词汇文件 (`tools/book/<分类>/<书名>_<时间戳>.txt`)
每个 txt 文件必须严格使用 UTF-8 编码，每行表示一个词条，标准格式如下：
```text
unit|spell
或
unit|spell|manualMeaning
```
- `unit`：教材单元编号（整型数字，如 `0`, `1`, `2`...，若无分单元则统一写 `0`）；
- `spell`：纯净单词拼写或固定短语（**严禁混入句末标点符号、音标或中文**）；
- `manualMeaning`：可选的指定中文释义（若不指定则由系统词典或 AI 自动补全）。
- **注释行**：允许 `#` 开头的审计注释（如提取报告），服务端批量导入会自动忽略。

### 1.2 元数据配置文件 (`tools/book/<分类>/meta.json`)
```json
{
  "isSystemImport": true,
  "generateWordImage": false,
  "generateShuffledVersion": false,
  "targetDictGroupId": "21",
  "targetGameHallIds": ["19"],
  "books": [
    {
      "fileName": "人教版三年级起点三年级上_20260930_165039.txt",
      "dictName": "人教版三年级起点三年级上",
      "domain": "",
      "description": "",
      "targetDictGroupId": "98a1b021d7434a978f89e13a401c1001",
      "targetGameHallIds": ["19"]
    }
  ]
}
```
- `targetDictGroupId`：词书挂载的二级分组 UUID（必须在生产库 `dict_group` 预先存在）；
- `targetGameHallIds`：所属游戏大厅 ID 列表（如小学游戏大厅 `["19"]`），导入时由 `DictImportBo` 自动绑定。

---

## 2. 严格质量审查与标准化清洗（核心品控）

入库前必须运行品控脚本（见 `scripts/audit_books.py` 与 `scripts/clean_books.py`），严格遵循以下 5 大铁律：

### ① 重名冲突一票否决（安全第一）
- **服务端机制**：批量导入时，**只要批次中任意 1 本词书与生产库已有词书同名，整个批次所有任务全部拒绝创建**！
- **审查动作**：必须首先直连生产库执行 `SELECT name FROM dict;`，取交集排查重名冲突。

### ② 口语交际短语末尾脱标
- **问题根源**：中小学教材词汇表常附带日常交际句（如 `Help!`、`Happy birthday!`、`Sit down.`、`What time is it?`）。
- **危害**：若保留末尾标点入库，客户端拼写测试会强制要求用户键盘输入标点才算对，且 TTS 发音与词典释义无法精准命中。
- **清洗动作**：剥离末尾的 `!`, `?`, `.`，转换为纯净短语（如 `Sit down.` → `Sit down`，`Help!` → `Help`）。

### ③ 称谓缩写归一化与去重
- **规则**：教材附录常混杂带点与不带点的缩写（如同一本书同时出现 `Mrs` 与 `Mrs.`）。
- **清洗动作**：统一收敛为标准无点形式（`Mr.` → `Mr`，`Mrs.` → `Mrs`，`Ms.` → `Ms`，`Dr.` → `Dr`），并在同书内彻底去重。

### ④ 大小写异义词严格保护
- **规则**：切忌无脑转小写（`lower()`）导致异义词丢失。
- **保护示例**：
  - `Miss`（小姐/老师，名词）与 `miss`（想念/错过，动词）
  - `US`（美国，专有名词）与 `us`（我们，代词）
  - 必须保留原本大小写差异，允许在同一本词书中作为独立考点存在。

### ⑤ 系统大词典粘连词（Glued Words）审计
- **问题根源**：部分排版破损的 PDF 在文本提取时会丢失空格，导致短语粘成死字（如 `bringhometo`、`lookat`）。
- **审查动作**：载入系统纯净大词典（如 macOS `/usr/share/dict/words` 23.4 万词库），扫描所有无空格长单字。若不在词典中且可被介词切分，必须人工复核原 PDF。

---

## 3. 分组规划与端云增量同步规范

### 3.1 二级分组规划原则
- **避免大杂烩**：大分类（如小学 `id=21`）下，必须按教材出版社版本细分二级子分组（如人教版、外研版、北京版等）。
- **标准 32 位 UUID**：严禁随意拼凑字符串，统一使用标准 32 位小写 UUID（如 `98a1b021d7434a978f89e13a401c1001`）。

### 3.2 炭炭背单词 vs 泡泡单词 分组架构与 UUID 映射速查表（核心记忆库）

> **★ 特别规则：炭炭界面的「其他」大分类 ⇋ 泡泡单词生产库的「进阶与经典」**
> - **原因**：客户端选书页（`SelectBookPage`）代码中包含 `g.name != '其他'` 的硬过滤，因此炭炭中的「其他」大类在生产数据库中统一定名为 **「进阶与经典」**，确保用户选书时在顶部 Tab 正常展示。

未来批量导入时，`meta.json` 中的 `targetDictGroupId` 直接查阅下表填入即可，严禁另起炉灶：

#### ① 【进阶与经典】（对应炭炭背单词的「其他」Tab，大类 UUID: `d4100600d7434a978f89e13a401c2000`）
| 炭炭二级分组 Chip | 泡泡单词二级分组名 | 生产库 `targetDictGroupId` (UUID) | 典型书目 |
| :--- | :--- | :--- | :--- |
| **新概念** | 新概念 | `d4100601d7434a978f89e13a401c2051` | 新概念英语第一册至第四册（新版） |
| **PETS** | PETS | `d4100601d7434a978f89e13a401c2052` | 全国等级考试词汇第一级至第五级 |
| **BEC** | BEC | `d4100601d7434a978f89e13a401c2053` | BEC 初/中/高级词汇精选与乱序版 |
| **MBA** | MBA | `d4100601d7434a978f89e13a401c2054` | MBA 词汇正序版/大纲 |
| **朗文** | 朗文 | `d4100601d7434a978f89e13a401c2055` | 朗文3000常用交流词汇 |
| **COCA** | COCA | `d4100601d7434a978f89e13a401c2056` | 美国当代语料库 5000/10000/15000/20200 |
| **剑桥英语考试** | 剑桥英语考试 | `d4100601d7434a978f89e13a401c2057` | KET / PET / FCE 核心词巧记速练 |
| **牛津词汇** | 牛津词汇 | `d4100601d7434a978f89e13a401c2058` | The Oxford 3000 / 5000 (American & English) |
| **词汇进阶** | 词汇进阶 | `d4100601d7434a978f89e13a401c2059` | 词汇进阶 6000 / 12000 / 23000 / BASIC |
| **剑桥国际** | 剑桥国际 | `d4100601d7434a978f89e13a401c2060` | 剑桥国际英语教程入门级、第1/2/3册 |
| **突破词汇** | 突破词汇 | `d4100601d7434a978f89e13a401c2061` | 突破英文词汇 5000 / 10000 / 22000（新版） |

#### ② 【留学】（对应炭炭「留学」Tab，大类 UUID: `d4100200d7434a978f89e13a401c2000`）
| 炭炭二级分组 Chip | 泡泡单词二级分组名 | 生产库 `targetDictGroupId` (UUID) | 典型书目 |
| :--- | :--- | :--- | :--- |
| **雅思** | 雅思 | `d4100201d7434a978f89e13a401c2011` | 剑桥雅思听力考点词真经、雅思真词汇等 |
| **托福** | 托福 | `d4100201d7434a978f89e13a401c2012` | 新托福官方指定核心词汇等 |
| **GRE** | GRE | `d4100201d7434a978f89e13a401c2013` | GRE 红宝书、核心词汇等 |
| **SAT** | SAT | `d4100201d7434a978f89e13a401c2014` | SAT 考试词汇 |
| **托业** | 托业 | `d4100201d7434a978f89e13a401c2015` | 托业词汇正序版/职场核心词 |
| **ACT** | ACT | `d4100201d7434a978f89e13a401c2016` | ACT 考试词汇 |
| **GMAT** | GMAT | `d4100201d7434a978f89e13a401c2017` | GMAT 商学院入学考试词汇 |

#### ③ 【高中】（对应炭炭「高中」Tab，大类 `id = '44'`）
- **高中英语(大纲教辅)**: `d4100301d7434a978f89e13a401c2021`（高考3500、维克多、闪过等）
- **人教版**: `d4100301d7434a978f89e13a401c2022`
- **外研版**: `d4100301d7434a978f89e13a401c2023`
- **译林版**: `d4100301d7434a978f89e13a401c2024`
- **牛津版**: `d4100301d7434a978f89e13a401c2025`
- **牛津上海版**: `d4100301d7434a978f89e13a401c2026`
- **北师大版**: `d4100301d7434a978f89e13a401c2027`
- **上外版**: `d4100301d7434a978f89e13a401c2028`
- **中职**: `d4100301d7434a978f89e13a401c2029`

#### ④ 【初中】（对应炭炭「初中」Tab，大类 `id = '11'`）
- **初中英语(大纲教辅)**: `d4100401d7434a978f89e13a401c2031`
- **人教版**: `d4100401d7434a978f89e13a401c2032`
- **仁爱版**: `d4100401d7434a978f89e13a401c2033`
- **外研版**: `d4100401d7434a978f89e13a401c2034`
- **译林版**: `d4100401d7434a978f89e13a401c2035`
- **沪教版**: `d4100401d7434a978f89e13a401c2036`
- **牛津上海版**: `d4100401d7434a978f89e13a401c2037`
- **北师大版**: `d4100401d7434a978f89e13a401c2038`
- **鲁教版**: `d4100401d7434a978f89e13a401c2039`
- **冀教版**: `d4100401d7434a978f89e13a401c2040`

#### ⑤ 【大学】（对应炭炭「大学」Tab，大类 `id = '18'`）
- **考研**: `d4100101d7434a978f89e13a401c2001`
- **四级**: `d4100101d7434a978f89e13a401c2002`
- **六级**: `d4100101d7434a978f89e13a401c2003`
- **专四**: `d4100101d7434a978f89e13a401c2004`
- **专八**: `d4100101d7434a978f89e13a401c2005`
- **教科书(高校综合教程)**: `d4100101d7434a978f89e13a401c2006`
- **考博**: `d4100101d7434a978f89e13a401c2007`
- **自学考试**: `d4100101d7434a978f89e13a401c2008`
- **专升本**: `d4100101d7434a978f89e13a401c2009`
- **成人本科**: `d4100101d7434a978f89e13a401c2010`

#### ⑥ 【小学】（对应炭炭「小学」Tab，大类 `id = '21'`）
- 人教版 (`98a1b021d7434a978f89e13a401c1001`), 外研版 (`...1002`), 北京版 (`...1003`), 译林版 (`...1004`), 北师大版 (`...1005`), 冀教版 (`...1006`), 沪教版 (`...1007`), 鲁科版 (`...1008`), 牛津上海版 (`...1009`), 广东版 (`...1010`), 广州版 (`...1011`), 闽教版 (`...1012`), 重庆版 (`...1013`), 重大版 (`...1014`), JOIN版 (`...1015`), 小学英语大纲词汇 (`...1016`)。

---

### 3.3 端云同步铁律（双端闭环）
客户端选书页从本地 SQLite 加载。服务端新增分组时，必须同步产生增量日志，否则客户端永远感知不到新分组：
1. **表名单数下划线**：同步日志 `tbl_name` 必须严格写 `'dict_group'`（严禁复数）；
2. **时间戳自洽**：`record` JSON 必须携带完整的 UTC 时间戳（`createTime`, `updateTime`）；
3. **版本锁推升**：必须在同一事务中以 `FOR UPDATE` 锁定单例版本表 `sys_db_version`，严格顺序递增 `version`：

```sql
DO $$
DECLARE
    curr_v INT;
    now_ts TIMESTAMP := NOW();
    now_iso TEXT := to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
BEGIN
    SELECT version INTO curr_v FROM sys_db_version WHERE id = 'singleton' FOR UPDATE;
    
    -- 1. 创建分组
    INSERT INTO dict_group (id, name, display_index, parent_id, create_time, update_time)
    VALUES ('<UUID>', '人教版', 10, '21', now_ts, now_ts)
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, update_time = now_ts;
    
    -- 2. 插入增量同步日志
    curr_v := curr_v + 1;
    INSERT INTO sys_db_log (id, version, operate, tbl_name, record_id, record, create_time, update_time)
    VALUES ('<LOG_UUID>', curr_v, 'INSERT', 'dict_group', '<UUID>',
            json_build_object('id', '<UUID>', 'name', '人教版', 'parentId', '21', 'displayIndex', 10, 'createTime', now_iso, 'updateTime', now_iso)::text,
            now_ts, now_ts);
            
    -- 3. 推升全局版本号
    UPDATE sys_db_version SET version = curr_v, update_time = now_ts WHERE id = 'singleton';
END $$;
```

---

## 4. 游戏大厅自动绑定机制 (`targetGameHallIds`)

### 4.1 服务端处理机制 (`DictImportBo.java`)
在 `processSystemImport` 完成词典保存后，调用 `linkDictToGameHall(dictId, hallIdOrName)`：
- 自动查询大厅实体，并向关联表 `game_hall_and_dict_link`（或通过大厅对应的 `dict_group`）挂载该词书；
- **乱序版联动**：若开启了 `generateShuffledVersion: true`，主词书与派生乱序版词书将**同时**自动绑定至该游戏大厅。

---

## 5. 生产数据库时区与时间规范

### 5.1 根治时区撕裂
- **问题**：官方 Docker `postgres` 镜像默认时区为 `Etc/UTC`。在表结构为 `timestamp without time zone` 的情况下，若使用 SQL 原生 `NOW()` 写入，会比 Java 宿主机（北京时间 UTC+8）慢 8 小时，并导致每天凌晨 00:00~08:00 之间的 `CURRENT_DATE` 统计发生跨天偏差。
- **根治方案**：生产数据库必须全局设置并持久化为北京时间：
  ```sql
  ALTER SYSTEM SET timezone = 'Asia/Shanghai';
  ALTER SYSTEM SET log_timezone = 'Asia/Shanghai';
  SELECT pg_reload_conf();
  ```

---

## 6. 标准执行工作流与验证清单

1. **第一步：准备物理词书与生成 meta.json**
   - 将 TXT 文件放入 `tools/book/<分类>/`；
   - 生成初步的 `meta.json`。
2. **第二步：执行全量品控审计与清洗**
   ```bash
   python3 .agents/skills/wordbook-batch-import/scripts/audit_books.py tools/book/<分类>
   python3 .agents/skills/wordbook-batch-import/scripts/clean_books.py tools/book/<分类>
   python3 .agents/skills/wordbook-batch-import/scripts/audit_books.py tools/book/<分类>
   ```
   - 验证：断言 0 同名冲突、0 句末标点残留、0 变体重复、0 连字粘连。
3. **第三步：核验并初始化生产分组**
   - 检查生产库 `dict_group` 是否存在对应的二级版本分组；
   - 若缺失，生成包含 `sys_db_log` 和 `sys_db_version` 推升的 SQL，经用户授权后入库。
4. **第四步：打包并部署后端最新服务**
   - 确保 `DictImportBo` 包含最新的 `targetGameHallIds` 与分组处理逻辑；
   - 部署到生产服务器并重启。
5. **第五步：触发批量导入**
   - 打包目录并调用 `/import/batch` 接口；
   - 轮询监控 `import_task` 状态，直至全量批次成功入库。
