# 易混淆单词词表改版：以学习过的词为锚点 + 学习范围内拼写相近词（Plan）

> 状态：待架构审查 → 待用户审批
> 目标：修改已上线的"易混淆单词"功能——词表不再包含学习范围内的全部单词，而是
> **以用户学习过的词为锚点**：词表 = 锚点（学习过的词）∪ 学习范围内与锚点拼写相近（编辑距离 ≤ 2）的词。
> 纯前端本地修改，不动 UI 框架（数据集合由 WordBo 层变化提供），不涉及服务端。

## 1. 背景与需求变更

上一版"易混淆单词"（design/confusable_words_list_plan.md，已实现并验收）：聚合用户**加入学习的词书**
的全部单词（去重）按拼写贪心排序。用户反馈：学习范围单词太多，词表失去意义。

**新需求（已与用户确认）**：

- 以**学习过的词**为锚点：学习过 house，学习范围内有 horse（拼写相近）→ house 和 horse 都出现在词表；
  house 和 horse 都学习过 → 都出现；两者都只在学习范围内而都没学习过 → 不出现。
- **"学习过"的定义**：`learning_words`（进入过学习轨道的词，含学习中和已毕业）**∪ 已掌握词书**
  （掌握后 learning_word 记录可能被删，但词一定在已掌握词书里）——并集，不遗漏。
- **"拼写相近"阈值**：Levenshtein 编辑距离 **≤ 2**（house/horse=1、weather/whether=2、through/though=1）。

## 2. 设计决策

### 2.1 词表集合构造（锚点 + 相近词）

```
B = 学习范围（learning_dicts 词书）去重单词集合          // 既有逻辑
L = learning_words(userId) 的 wordId 集合                 // 学习过（记录）
M = 已掌握词书（mastered dict）的 wordId 集合             // 学习过（掌握）
A = B ∩ (L ∪ M)                                          // 锚点：学习范围内且学习过
C = { b ∈ B \ A | ∃ a ∈ A : EditDistance(a.spell, b.spell) ≤ 2 }   // 相近词
词表 = A ∪ C，再按 confusableSort（既有贪心最近邻）排序展示
```

- 锚点之间拼写相近也天然聚簇（贪心排序处理，如两词都学习过且相近）。
- 空锚点（学习范围内无学习过的词）→ 词表为空（入口计数 0，显示空态）。

### 2.2 相近词过滤：长度分桶剪枝（与排序同为 isolate 计算）

朴素 A×B 两两距离不可取（|A|×|B| 千万级）。利用下界 `编辑距离 ≥ |len 差|`：

```
对 A 按 spell 长度分桶 Map<int, List<A词>>
对每个 b ∈ B\A：只扫 len(b)-2 .. len(b)+2 的 A 桶，找到任一距离 ≤ 2 的 a 即把 b 加入 C
```

- 单次过滤复杂度 ≈ |B| × 每桶 A 词数（桶平均 |A|/长度跨度），远小于全量两两；
- 与排序合并进**同一次 isolate compute**（传 A 与 B，回传"过滤后集合 → 贪心排序"的 id 列表），
  主 isolate 一次等待；复用 `compute`/`TspParams` 模式。

### 2.3 缓存与计数（签名含 B + A 双分量）

- 内存缓存（沿用 `_confusableCache`，key=userId）：签名 = **学习词书 dictId 有序集合 + 学习范围去重
  wordId 集合 B + 锚点 wordId 集合 A** 三部分（sha256）。失效覆盖：学习词书增删（dictIds 变）、
  词书单词增删（B 变，即使锚点不变——如 B 增词 hose 但 A 不变，C 应变）、学习记录/已掌握变化
  （A 变）。三者任一变化 → 签名变化 → 重算。
- **计数与排序共用缓存**：`getConfusableWordCount` 缓存命中直接返回长度；未命中则完整计算一次
  （过滤+排序，isolate）并缓存。相比上一版"计数不触发排序"的约束，本版数据集合显著变小
  （锚点+相近词 ≪ 全量）、`getWordLists` 调用低频、锚点变化低频（学习完成后看词表），
  改为"共用缓存、首次完整计算"更简单一致。
- 入口计数 = |A ∪ C|（与列表实际展示数一致）。

### 2.4 UI 不变

- 词表页入口、`ConfusableWordsProvider` 页面、排序菜单门控、只读语义等全部沿用上一版，**零改动**；
- 唯一感知差异：词表更小、加载更快；数据集合变化全部由 `WordBo` 层提供。

### 2.5 明确不做

- 不改排序算法主体（confusableSort 贪心最近邻复用，仅新增过滤函数）；
- 不改 UI/路由/只读语义（上一版已验收）；
- 不涉及服务端/同步。

## 3. 改动清单

### A. `app/lib/util/confusable_sort.dart`（新增过滤纯函数）

- `Set<String> selectConfusableNear(Set<ConfusableWord> anchors, List<ConfusableWord> candidates, {int maxDist = 2})`：
  返回 candidates 中"属于锚点 或 与某锚点编辑距离 ≤ maxDist"的 id 集合（长度分桶剪枝，纯函数可测）；
- isolate 入口扩展：`ConfusableSortParams` 增加 anchors 输入（或新参数类），
  `confusableSortInIsolate` 改为"过滤 + 排序"（内部先 selectConfusableNear 再 confusableSort）。

### B. `app/lib/api/bo/word_bo.dart`（聚合改锚点语义）

- `getConfusableWordIds(userId)`：
  1. 学习范围 B（既有 `_loadConfusableWords` 去重 + spell）；
  2. 锚点集 A：学习记录集 L = **learning_words 中 userId 的全部 wordId**（**不带 stability 过滤**，
     `getLearningWordIdSet` 现有实现过滤 stability<180 排除已毕业，与"学习过含已毕业"需求不符，
     不可复用；在 WordBo 内联 `db.select(db.learningWords) where userId` 查询，保持改动仅 2 文件）
     ∪ 已掌握词书 M（`masteredWordsDao.getMasteredWordIdSet`），与 B 求交集得 A；
  3. isolate `compute`（过滤 + 排序）得最终 id 列表；
  4. 缓存签名 = dictIds 有序 + B 有序 + A 有序（sha256，见 2.3），`_confusableInflight` 防重算（沿用）。
- `getConfusableWordCount(userId)`：共用缓存（命中返回长度，未命中完整计算一次）；
- `getWordLists()` 入口项不变（计数来源变为新逻辑）。

### C. 测试（更新/新增）

- `confusable_sort_test.dart` 新增：锚点过滤（锚点保留、距离 ≤2 相近词加入、>2 排除、空锚点返回空、
  长度分桶剪枝与朴素两两对照严格一致、阈值边界 dist=2 含/3 不含）；
- `confusable_words_bo_test.dart` 更新聚合用例为锚点语义：
  - 学习过 house + 范围内 horse → 词表含 house+horse；两者都学过 → 都含；都没学过 → 不含；
  - **有学习词书但无锚点 → 空列表 / 计数 0**；
  - 锚点来源两路（learning_words 记录 / 已掌握词书）各覆盖，**含"已毕业 learning_word（stability≥180）
    仍是锚点"用例**（验证新查询不带 stability 过滤）；
  - 阈值边界（dist=2 加入、dist=3 排除）；
  - 缓存签名失效：新增 learning_word / 移入已掌握 / **词书新增单词但锚点不变（B 变 C 应变）**均触发重算；
  - 计数与列表长度一致。
- **`confusable_words_provider_test.dart` 联动更新（必须，列入 Task 2）**：
  - `seedConfusableData` **及"含释义缺失词"等其他自带 seed 的用例**均需补 learning_words / 已掌握
    锚点记录（否则新语义下返回空列表、用例失败）；
  - 原"计数与排序解耦"断言（位于 `confusable_words_bo_test.dart` 计数组）在新"共用缓存"语义下
    **反转**——改为断言"计数与排序共用缓存"（先计数后列表，排序只计算一次）；
  - bo test "缓存与签名失效"组的既有 seed 同样需补锚点记录，新增 learning_word / 移入已掌握 /
    词书增词不改锚点的签名失效用例在该组扩展。

## 4. 架构审查要点（ppdc-architect）

1. 分层与职责 ✅：改动限数据层（confusable_sort 过滤纯函数 + WordBo 聚合），UI/路由/只读语义
   零改动；仍纯前端本地，无服务端/同步侵入。
2. 数据流与同步 ✅：只读查询（learning_words/masteredWords 均为本地只读）；不落库不产生日志
   （沿用 no-op 书签与只读覆写）；缓存签名含锚点，学习数据变化自动失效。
3. Dto/Vo ✅：复用既有结构，无新增。
4. 设计原则 ✅：复用 confusableSort/长度分桶/isolate 模式；过滤与排序合并一次 compute；
   集合规模显著缩小（锚点+相近词 ≪ 全量），性能更优；无过度设计。
5. Surgical ✅：改动集中在 2 个文件 + 测试；UI 完全不动。
6. 验证充分性 ✅：过滤函数对照朴素实现严格一致；聚合锚点语义覆盖用户三种场景；
   `flutter analyze` + 针对性 `flutter test` + 阶段 5 全量。
7. 可执行性 ✅：Task 依赖清晰（过滤函数 → 聚合改造），无前置缺失。

## 5. Task 分解

1. **Task 1（过滤函数，TDD）**：`confusable_sort.dart` 新增 `selectConfusableNear` + isolate 入口
   扩展；`confusable_sort_test.dart` 新增用例（锚点/阈值边界/空锚点/朴素对照）。
   - 验证：针对性 `flutter test` + `flutter analyze`。
2. **Task 2（聚合改造，TDD）**：`word_bo.dart` 的 `getConfusableWordIds`/`getConfusableWordCount`
   改锚点语义（学习过集合 = learning_words（无 stability 过滤）∪ 已掌握 ∩ 学习范围；过滤+排序；
   签名含 dictIds+B+A 三分量）；`confusable_words_bo_test.dart` 更新聚合用例；
   **`confusable_words_provider_test.dart` 联动更新**（seed 补 learning_words/已掌握记录、
   计数断言改为共用缓存语义）。
   - 验证：针对性 `flutter test` + `flutter analyze` + `flutter test test/confusable_words_provider_test.dart` 回归。
3. **阶段 5 集成验证**：全量 `flutter analyze`（0 issue）+ 全量 `flutter test`；
   修复所有编译错误、警告、测试失败。

## 6. 风险与注意事项

- **锚点集合变化频率**：学习过程中 learning_words 每日变化 → 签名失效重算；词表页只在用户主动
  进入时刷新，单次重算（过滤+排序，规模小于全量）在 loading 态下可接受。
- **阈值 2 的召回**：编辑距离 ≤2 覆盖常见混淆词对；若用户后续觉得词表仍偏大/偏小，可调整阈值
  （参数化 maxDist，一处改动）——记录为后续可调项。
- **空词表显示**：学习范围内无学习过的词时词表为空，入口显示 0；`WordListPage` 空列表为
  空白页（无空态提示文案，与现有词表空列表行为一致）——如需空态引导文案属产品层面后续项，
  本次不改 UI。
- **已掌握词书缺失**：`getMasteredWordIdSet` 依赖"已掌握"词书存在（核心词书校验保证），
  缺失时返回空集（与既有调用一致），不额外处理。
