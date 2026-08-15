# 失败测试修复方案(Plan)

> 状态:已通过架构审查 → 已获用户审批 → 执行完成(阶段 3-5:代码审查进行中)→ 待用户决策(阶段 6)
> 目标:修复当前失败的测试用例 —— Flutter `english_correction_test.dart` 4 例 + Java `EmailUtilTest` 3 例。

## 1. 失败清单与根因诊断

### 1.1 Flutter:english_correction_test.dart(4 例失败)

测试文件是历史提交(8 月 2 日)所加,断言 ChSentence2En 例句环节 ASR 发音纠错行为:

| 用例 | 输入 → 期望 | 实际 |
|---|---|---|
| 用例1 | `good this plan` → `good discipline` | `good is plan` |
| 用例2 | `gurty seaplane` → `good discipline` | `gurty seaplane`(未纠错) |
| 用例3 | `could this plan is essential` → `good discipline is essential` | `good discipline essential`(`is` 被吞) |
| 用例4 | `gulty seaplane` → 含 `discipline` 且 ≠ `discipline` | `gulty seaplane`(未纠错) |

**根因一(算法回归,历史提交引入)**:`2daab543`(8 月 8 日)重构 `_phoneticAutoCorrectSentence` 时删除了"功能词保护"(`this`→`is` 错纠、`this plan is` 把 `is` 吞进 `discipline`);`90767ee6`(8 月 8 日)新增"无精确锚点直接跳过纠错"(用例2/4 完全不纠错)。两个提交均早于当前 HEAD,测试在 HEAD 上已失败。

**根因二(测试基础设施)**:`bdcNotifierProvider` 是 Riverpod 2.0 AutoDispose provider。测试用 `container.read(...notifier)` 不建立订阅,`loadData` 后 provider 被 Riverpod 自动 dispose,`sentenceAnswerController` 随之 dispose;`onAsrResult` 在 await 音素纠错间隙恢复后写入已 dispose 的 controller,抛 `A TextEditingController was used after being disposed`,被 catch 分支**吞掉**并把整个 JSON 文本当识别文本二次纠错,污染 `_accumulatedAsrText`。

**根因三(吞异常)**:`onAsrResult` 的 catch 分支不记录异常、dispose 后仍继续写状态;await 间隙无 `_isDisposed` 校验(入口与轮次校验均缺),生产环境用户快速退出页面时同样会命中。

### 1.2 Java:EmailUtilTest(3 例 Error)

`@SpringBootTest @ActiveProfiles("test")` 加载 ApplicationContext 时,logback 按生产配置 `logging.file.name=/var/nnbdc/log/nnbdc-service.log` 打开 FILE appender,目标目录不可写 → `Failed to load ApplicationContext`,3 个测试全部 Error(其余 14 个非 Spring 测试通过)。

**根因**:测试无 `logback-test.xml` / `application-test.yml`,复用生产日志文件路径,测试依赖 `/var/nnbdc/log` 可写。

## 2. 修复方案(Task 分解)

### Task 1:测试基础设施 —— AutoDispose provider 保活

**文件**:`app/test/english_correction_test.dart`
**变更**:`setupSentence2En` 中创建 notifier 前,用 `container.listen(bdcNotifierProvider, (_, __) {})` 建立订阅(模拟生产环境页面监听),并 `addTearDown(sub.close)`。
**目的**:防止测试期间 provider 被自动 dispose,使测试真实反映生产调用路径。
**验证**:4 个用例不再出现 "TextEditingController was used after being disposed"。

### Task 2:纠错算法修复 —— `_phoneticAutoCorrectSentence`

**文件**:`app/lib/page/bdc/providers/bdc_notifier.dart`
**变更**(恢复测试时代的算法语义,保留锚点定位能力):

1. **移除"无锚点直接跳过"**:无锚点时仍逐词纠错;无锚点时左右位置窗口退化为全局窗口(不再用词数比例估算 —— 比例估算对短输入会错位,如 `seaplane` 的估算窗口 `[5..11]` 不含 `discipline`)。
2. **恢复功能词集合与保护**(与历史版本一致:`a an the is are was were to for of at in on this that these those his her it its and or but with as by from up out do does`):
   - 功能词输入词:不做单词级音素纠正,只允许发起合并(如 `this plan` → `discipline`);
   - 功能词目标词:不作为音素纠正目标(防 `x` → `is`);
   - 合并窗口扩展遇到功能词(除首词外)即停止(防 `this plan is` 吞 `is`;实测 `sim('this plan','discipline')=71`、`sim('this plan is','discipline')=76`)。
3. **合并阈值**:当前词为功能词时合并阈值 70(历史语义,`this plan`→`discipline`=71 恰好过线);非功能词保留现有 `+15` 显著门槛与"窗口长度 ≤ 目标词长度+2"保护(防 `gurty seaplane`/`gulty seaplane` 整体合并吞词)。
4. 保留现有:≤2 字符碎片不纠错、精确锚点对齐、位置窗口(有锚点时)。

**依据的实测数据**(PhonemeUtil 同环境测量):`this plan↔discipline=71`、`this plan is↔discipline=76`、`this↔is=60`、`gurty↔good=69`、`seaplane↔discipline=71`(全局最高,无误配)、`gulty↔good=48`、`could↔good=93`、`talk↔dock=91`、`to↔towed=64`。

**预期结果**:用例1 `good discipline`;用例2 `good discipline`;用例3 `good discipline is essential`;用例4 `gulty discipline`(含 `discipline` 且非纯 `discipline`,断言成立)。

**权衡说明(需用户确认)**:移除"无锚点跳过"后,完全跑偏的输入(如 `to try talk`)可能被局部误纠(≤2 字符保护与 55 阈值仍挡住大部分,但 `talk`→`dock`=91 类残余幻觉回归到 8 月 2 日测试时代的水平)。90767ee6 的"跳过"一刀切使所有无锚点输入(包括用例2/4 这类整句近音误识)完全失去纠错,与既有测试冲突;本方案以测试为准,保留其余全部防幻觉机制。

### Task 3:onAsrResult 异步间隙防护与异常可见性

**文件**:`app/lib/page/bdc/providers/bdc_notifier.dart`
**变更**:
1. `onAsrResult` 入口加 `if (_isDisposed) return;`(与 `stopPttAsr` 一致);
2. await 纠错恢复后的轮次校验加入 `_isDisposed`(`if (_isDisposed || !_isPttPressed || ...) return;`,两处);
3. catch 分支:`if (_isDisposed) return;` + 用 `catch (e, stackTrace)` 记录异常日志(不吞异常,遵循 arch.md 快速失败原则;当前已临时加入的日志行转为正式修复)。

**目的**:防用户快速退出页面后异步 ASR 回调继续写入已 dispose 状态;异常不再静默吞掉。
**验证**:`flutter analyze` 无警告;相关测试全量通过。

### Task 4:Java 测试日志隔离

**文件**:新增 `server/nnbdc-service/src/test/resources/logback-test.xml`
**变更**:仅保留 CONSOLE appender(复用生产 conversionRule 与 pattern,不含 FILE appender)。logback 测试期自动优先加载 `logback-test.xml`,生产配置不动。
**目的**:`@SpringBootTest` 测试不再依赖 `/var/nnbdc/log` 可写,测试日志与生产文件日志隔离。
**验证**:`mvn test -pl nnbdc-service -Dtest=EmailUtilTest` 3 例通过;全量 `mvn test` 通过。

## 3. 集成验证(阶段 5)

- `cd app && flutter analyze`(零警告)
- `cd app && flutter test`(全量,重点 `english_correction_test.dart` 4 例 + `bdc_notifier_test.dart` 不受影响)
- `cd server && mvn test`(全量,17 例全部通过)
- 检查无其它测试被破坏

## 4. 不改动的部分

- `_phoneticAutoCorrectSentence` 之外的 PTT/stitch/判定流程
- 工作区中已有的 FSRS 双轨道未提交改动(与本修复正交,回归测试中一并验证)
- 生产 logback-spring.xml、application.yml
