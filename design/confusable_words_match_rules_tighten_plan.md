# 易混淆单词匹配规则收紧：距离 ≤1 + 词长 ≥3 + 长度相同（Plan）

> 状态：待架构审查 → 待用户审批
> 目标：修改"易混淆单词"（锚点语义版）的**相近词匹配规则**——编辑距离 ≤ 1（原 ≤ 2）、
> 参与匹配的词至少 3 个字母、相近词对字母数相同。纯前端本地修改，改动集中在过滤函数与测试。

## 1. 背景与需求变更

当前实现（design/confusable_words_anchor_plan.md，已验收）：词表 = 锚点 A（学习范围内 ∩
（学习记录 ∪ 已掌握））∪ 学习范围内与锚点**编辑距离 ≤ 2** 的词 C，再贪心排序。

用户要求收紧匹配规则：
1. 编辑距离 **≤ 1**（原 ≤ 2）；
2. 单词**至少 3 个字母**；
3. 相近单词**字母数相同**。

**精确语义**（三条叠加，本 Plan 的约定）：

- 匹配条件 = `len(a) == len(b) && len(a) >= 3 && EditDistance(a, b) ≤ 1`。
  由于长度相同且距离 ≤1 ⇒ 只能是一次**字母替换**（一字之差），插入/删除类（长度不同）被排除。
- 词表集合 = { 学习过的词（锚点）中 len ≥ 3 的词 } ∪ { 学习范围内 len ≥ 3 且与某锚点
  长度相同且距离 ≤ 1 的词 }。
- **锚点 len < 3 的词不进入词表**（"单词至少三个字母"对锚点与候选同样适用，2 字母词无易混淆意义）。
- **孤立锚点保留**：len ≥ 3 的学习过的词即使当前没有相近词仍留在词表（用户学过、值得复习，
  与锚点语义一致）；学习范围内新增相近词后自动加入（签名失效重算）。

示例：house/horse（5=5，距离 1）✓；cat/cot（3=3，距离 1）✓；weather/whether（距离 2）✗；
cat/cart（长度 3≠4）✗；at（len<3）✗。

## 2. 设计决策

### 2.1 `selectConfusableNear` 语义更新（confusable_sort.dart）

现有函数：`Set<String> selectConfusableNear(Set<ConfusableWord> anchors, List<ConfusableWord> candidates, {int maxDist = 2})`
——长度分桶剪枝（只扫 |len差| ≤ maxDist 桶），返回"属于锚点 或 与某锚点距离 ≤ maxDist"的候选。

更新为（保持纯函数、与朴素全量严格一致）：

- 默认 `maxDist = 1`；
- **长度相同约束**：分桶剪枝从"扫 len±maxDist 桶"收窄为**只查同长度桶**（len(b) 精确桶）；
- **len ≥ 3 约束**：len < 3 的锚点与候选均不参与（不进桶、不返回）——即"锚点 len<3 不在结果集、
  候选 len<3 不返回"，与词表集合语义一致（函数返回的就是词表 id 集合）；
- 其余不变：候选是锚点（len≥3）直接包含、距离计算复用 `EditDistance.forStrings`、短路。

### 2.2 isolate 入口（confusable_sort.dart）

- `confusableSortInIsolate` 内部 `maxDist: 2` 改为 `1`（"阈值参数化一处改动"的既定可调点）；
- **空锚点退化路径（显式传空锚点）**：排序前先按 len ≥ 3 过滤候选（与正常路径的过滤语义
  一致——退化只是"无锚点可匹配"，不豁免最短词长约束）；同步更新 confusable_sort.dart 相关
  doc 注释；现有"无锚点 == confusableSort"用例的词均 ≥3 字母，不受影响；
  生产路径 WordBo 空锚点短路缓存空列表不变（语义无冲突，退化仅对显式传空锚点的调用成立）。

### 2.3 WordBo 层（word_bo.dart）

- **零逻辑改动**：`getConfusableWordIds` 调 `confusableSortInIsolate`（阈值与过滤规则在
  confusable_sort.dart 内部），锚点判定（A = B ∩ (L∪M)）、签名三分量、计数共用缓存均不受影响；
- **仅注释同步**：word_bo.dart 中 `getConfusableWordIds`/`getWordLists` 入口处"编辑距离 ≤ 2"
  的描述改为新规则（≤1 且长度相同且 ≥3 字母）；`confusable_words.dart` 类文档注释同步。

## 3. 改动清单

### A. `app/lib/util/confusable_sort.dart`（实现，见上）

### B. 测试（见上）

### C. 注释同步（word_bo.dart / confusable_words.dart）

- `word_bo.dart` 的 `getConfusableWordIds` 入口 doc 中"编辑距离 ≤ 2"描述改为
  "≤1 且长度相同且 ≥3 字母"（getWordLists 入口与计数注释无"编辑距离 ≤ 2"字样，不需改）；
- `confusable_words.dart` 类文档注释同步（"编辑距离 ≤ 2"→新规则）。
- 逻辑零改动（WordBo/UI）。

## 4. 架构审查要点（ppdc-architect）

1. 分层与职责 ✅：规则收紧全部落在过滤纯函数（util 层）与测试，WordBo/UI 零逻辑改动
   （仅注释同步）；纯前端本地，无服务端/同步侵入。
2. 数据流与同步 ✅：只读查询不变；不落库不产生日志（沿用）；缓存签名语义不变（词表集合
   变小，失效条件不变）。
3. Dto/Vo ✅：不涉及。
4. 设计原则 ✅：复用既有分桶/isolate 机制，仅收紧参数与桶范围；同长度桶使分桶剪枝更强
   （每候选只查 1 个桶），性能更优；"阈值参数化一处改动"兑现。
5. Surgical ✅：改动集中在 confusable_sort.dart + 3 个测试文件；word_bo.dart 零逻辑改动
   （仅注释同步）。
6. 验证充分性 ✅：阈值/长度/最短词长边界用例 + 朴素对照 + 既有 44 用例回归；
   `flutter analyze` + 针对性 `flutter test` + 阶段 5 全量。
7. 可执行性 ✅：单 Task 即可完成，无前置依赖。

## 5. Task 分解

1. **Task 1（规则收紧，TDD）**：confusable_sort.dart 的 `selectConfusableNear`（maxDist=1、
   同长度桶、len≥3 过滤、空锚点退化路径排序前过滤 len<3）与 `confusableSortInIsolate`
   （maxDist=1）；**注释同步**（word_bo.dart 的 getConfusableWordIds 入口、confusable_words.dart
   类文档，两处"编辑距离 ≤ 2"改为新规则）；`confusable_sort_test.dart`
   更新/新增（阈值/长度/最短词长边界、dist=0 显式用例、朴素对照、锚点保留语义）；
   `confusable_words_bo_test.dart`（阈值边界、len<3 锚点新语义、house/horse/hose 签名失效
   断言修正为 **{w_house, w_horse}**——hose 长度 4≠5 被排除）与
   `confusable_words_provider_test.dart`（seed 核对）联动更新。
   - 验证：`flutter test`（3 个 confusable 测试文件）+ `flutter analyze`（相关文件）。
2. **阶段 5 集成验证**：全量 `flutter analyze`（0 issue）+ 全量 `flutter test`；
   修复所有编译错误、警告、测试失败。

## 6. 风险与注意事项

- **词表进一步缩小**：距离 ≤1 + 同长度 + ≥3 字母 是"一字之差"的严格定义，词表聚焦真正的
  形近词；若用户后续觉得太严（如想包含 cat/cart 这类插入型），可放宽"长度相同"约束
  （一处条件）——记录为可调项。
- **既有用例的连锁更新**：confusable_sort_test 的阈值边界、bo_test 的阈值与锚点用例、provider
  的 seed 词需逐一核对新语义，避免残留旧规则断言（TDD 红阶段应暴露）。
- **锚点 len<3 从词表消失**：2 字母学习词不再出现在易混淆词表（新语义），属预期；
  若用户希望"学习过的词无论如何都显示"，可改为仅候选受 len≥3 限制（记录为可调项，默认按本
  Plan 语义）。
