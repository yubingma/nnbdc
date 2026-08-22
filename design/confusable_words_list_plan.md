# 易混淆单词词表：学习词书聚合 + 拼写相似度贪心排序（Plan）

> 状态：架构审查修改后重审（6 点已修正）→ 待复审 → 待用户审批
> 目标：词表页新增"易混淆单词"动态虚拟词表——聚合用户**加入学习的词书**的全部单词（去重），
> 按拼写编辑距离**贪心最近邻**排序，把拼写相近易混淆的单词排在一起，点词进详情复习。
> 纯前端本地功能：不落库、不产生同步日志、不涉及服务端。

## 1. 背景与需求

用户需求：在词表页面加一个"易混淆单词"词表——把用户学习范围内所有词书的单词，
拼写比较接近容易混淆的排得比较靠近。

**已与用户确认的三个决策**：

| 维度 | 决策 |
|---|---|
| 数据范围 | **加入学习的词书**（`learning_dicts` 表，用户在"选择词书"里勾选加入学习的词书） |
| 词表形态 | **动态虚拟词表**（词表页新增入口卡片，点击进入动态聚合列表；不落库、不影响同步体系） |
| 排序方式 | **贪心最近邻（Levenshtein 编辑距离）**：从首词起每次选拼写最接近的未访问词 |

## 2. 设计决策

### 2.1 数据源与去重

- 词书集合：`learningDictsDao.getLearningDictsOfUser(userId)` → dictId 列表。
- 单词聚合：`dict_words WHERE dict_id IN (dictIds)`，按 **wordId 去重**（同一单词出现在多本词书
  只算一次；`dict_words` 主键 (dictId, wordId)，本地已下载词书才有行，聚合天然只含已就绪词书），
  关联 `words` 表取 spell。
- 单词总量 = 去重后数量（用于词表页入口卡片计数与排序规模预估）。

### 2.2 排序算法：贪心最近邻 + 长度分桶剪枝（isolate 计算，与朴素贪心严格一致）

输入：去重后的 `(wordId, spell)` 列表（规模：学习词书通常数百～数千词，极端上万）。

算法（isolate 计算，复用现有语义排序 TSP 的 `compute`/`TspParams` 模式）：

```
start = 字典序最小的词（确定性好、便于测试）
order = [start]; visited = {start}
while order.length < n:
    cur = order.last
    # 候选 = 未访问且 |len(spell)-len(cur)| <= DELTA 的词
    #   长度差 > DELTA ⇒ 编辑距离必 > DELTA（下界），可安全剪枝
    candidates = 桶[len-DELTA .. len+DELTA] 中未访问的词
    if candidates 非空:
        best = argmin_{cand∈candidates} editDistance(cur.spell, cand.spell)
        if bestDist <= DELTA:            # 桶内全局最优，任何桶外词距离都 > DELTA ≥ bestDist
            order.add(best); visited.add(best); continue
    # 回退：桶内候选为空，或桶内最优距离仍 > DELTA（桶外可能存在更近词）
    #   —— 此时必须全量扫描未访问集，保证与朴素全量贪心严格一致
    best = argmin_{cand∈未访问} editDistance(cur.spell, cand.spell)
    order.add(best); visited.add(best)
    # 距离相同取字典序更小
```

- **正确性**：长度差 > DELTA ⇒ 编辑距离 > DELTA（编辑距离 ≥ |len 差|，下界成立）。
  当桶内最优距离 ≤ DELTA 时，桶外词（距离 > DELTA ≥ 桶内最优）不可能胜出，剪枝安全；
  否则回退全量扫描——因此**结果与朴素全量贪心严格一致**（桶内最优 > DELTA 的情形实际很少发生，
  回退性能损失可忽略）。
- **性能**：n=3000 时每步候选数百、共 3000 步 → 百万级距离计算，isolate 内 1 秒内；
  n=10000 时数千万级、约 2-5 秒，需 loading 态（首次进入）。
- **isolate 传参**：(wordId, spell) 列表，n=10000 约 1-3MB，`compute` 拷贝可接受。

### 2.3 缓存（与入口计数解耦）

- 内存缓存：`static Map<String, List<String>>`（key = userId；value = 排序后的 wordId 列表），
  参照 `_dictTspCache`（word_bo.dart:126）。签名 = 学习词书 dictId 有序集合 + 去重 wordId 集合
  哈希；学习词书增删/词书单词增删 → 签名变化 → 重算。并发双请求用 Future 缓存防重算（可选）。
- **计数与排序解耦（必须）**：`getConfusableWordCount` 只做去重 count + 签名校验，
  **不得触发 isolate 排序**——否则词表页每次切 Tab 刷新都会被拖慢数秒。
  排序只在该词表页面首次进入（loading 态）时触发。
- 不落库（不引入 semanticSeq 式持久化；本词表是纯浏览视图）。

### 2.4 页面与复用

- **词表页入口**（`app/lib/page/word_lists.dart`）：
  - `WordBo.getWordLists()` 末尾追加 `WordList("易混淆单词", 去重单词数)`（count distinct，
    复用计数缓存，不触发排序）；
  - `renderAWordList` 的 onTap 分派新增分支 → 导航（`.then((value) => loadData())` 刷新计数，
    照抄现有 7 个分支模式）；入口卡片 index=7 走 `gradientColorsByIndex`/`iconByIndex` 的
    default 分支（现有兜底，无需新增映射）。
- **新页面/导航**（`app/lib/page/word_list/confusable_words.dart` 新增）：
  - 导航助手 `toConfusableWordsListPage()` 放本文件内，**复用既有 `/word_list` 路由** push
    （照抄 `dict_words.dart` 的 `toDictWordsListPage` 模式）——**router.dart 无需改动**；
  - `ConfusableWordsProvider implements WordsProvider`（复用 `WordListPage` 框架）：
    - `getAPageOfWords(fromIndex, pageSize)`：内部"全量排序 id 列表（缓存/重算）→ 一次性批量
      查详情（非逐词循环）"；控制器对非 DictWordsProvider 走 `getAPageOfWords(0, 999999)`
      全量加载 + 内存切片路径，provider 只需支持一次全量请求；
    - **批量释义加载**（新增方法，语义与 `getWordMeaningItems` 一致）：学习词书定制释义优先 +
      通用释义按**所有学习词书的最大 popularityLimit** 过滤 + min-3 保底，一次批量查询，
      避免逐词循环（数千词 × 每词多查询不可用）；
    - `getSortAlg()` **固定返回 `WordSortAlg.original`**（返回 semantic 会触发控制器 TSP 分支，
      必须避免）；`hasUnits=false`；
    - **BookMarkProvider 实现为内存 no-op**：`getBookMark() → null`、`saveBookMark() → true`，
      **不写 bookMarks 表、不产生 DbLog、不触发同步**（否则控制器自动保存书签会违反
      "不产生同步日志"）；会话内书签定位由页面内存态维持，不跨会话恢复（与纯浏览视图一致）；
    - **排序设置菜单门控隐藏**（按 provider 能力，不提供排序切换）；**覆写 `masterWord` 弹
      Toast 提示"仅浏览"**（避免惰性"掌握"按钮静默无效）；
    - 只读浏览：`showDelBtn=false`、`canAddWord/canEditWord=false`；点词进详情、进度条、ASR
      等继承 WordListPage 既有实现。

### 2.5 明确不做

- **不做**：真实词书/落库/同步/服务端改动（用户已选虚拟词表）；
- **不做**：词表内学习（仅浏览复习，不进学习轨道）；
- **不做**："易混淆度"阈值过滤（全部单词参与排序，只是相近的相邻）；
- **不做**：改现有词书的排序算法（语义/字母序等不动）。

## 3. 改动清单

### A. 排序算法（新文件 `app/lib/util/confusable_sort.dart`）

- `List<String> confusableSort(List<({String id, String spell})> words)`：公开纯函数，
  贪心最近邻 + 长度分桶剪枝 + **回退全量扫描（桶空或桶内最优 > DELTA）**，结果与朴素全量
  贪心严格一致（isolate 入口在 lib 内调用它，故不标 @visibleForTesting，测试直接调用公开函数）。
- isolate 入口：复用 `TspParams`/`compute` 模式（回传排序后 id 列表）。

### B. 数据聚合与缓存（`app/lib/api/bo/word_bo.dart`）

- `getConfusableWordIds(String userId)`：learning_dicts → dict_words 去重 → confusableSort →
  内存缓存（签名校验 + Future 防重算）；
- `getConfusableWordCount(String userId)`：去重计数 + 签名校验（**不触发排序**，复用
  getConfusableWordIds 缓存长度）；
- **批量释义加载方法**（与 `getWordMeaningItems` 语义一致：定制释义优先、max popularityLimit
  过滤、min-3 保底，一次性批量查询）；
- `getWordLists()` 追加"易混淆单词"项（计数不触发排序）。

### C. 页面（新增 `app/lib/page/word_list/confusable_words.dart` + 改 `word_lists.dart`）

- `ConfusableWordsProvider`（含内存 no-op BookMarkProvider、getSortAlg 固定 original、
  masterWord 覆写提示、排序菜单门控）+ 导航助手（复用 `/word_list` 路由）；
- `word_lists.dart` 入口卡片与 onTap 分支（index=7 走 default 渐变/图标）；
- 首次进入 loading 态（覆盖 isolate 排序 + 全量详情加载耗时）。

## 4. 架构审查要点（ppdc-architect）

1. 分层与职责 ✅：纯前端本地功能；排序纯函数独立可测；聚合在 WordBo（getWordLists/
   getDictWordsForAPage 既有归属层）；UI 复用 WordListPage 框架；无服务端/同步侵入。
2. 数据流与同步 ✅：不落库、不生成日志（BookMarkProvider 内存 no-op 保证）、不改任何表；
   缓存签名校验可靠；计数与排序解耦不拖慢词表页。
3. Dto/Vo ✅：复用 DictWordVo/WordVo/WordList；聚合视图用占位 DictVo（name='易混淆单词'，
   单元标题仅 DictWordsProvider 渲染，无副作用）。
4. 设计原则 ✅：复用 EditDistance/WordListPage/isolate 模式；剪枝有下界证明且回退保证与
   朴素贪心一致（无"近似"妥协）；不引入持久化。
5. Surgical ✅：改动集中在排序工具（新）、WordBo（聚合/计数/批量释义/入口）、词表页（入口）、
   新页面（复用框架）；router.dart 不动。
6. 验证充分性 ✅：Task 1 含剪枝回退正确性对照用例；Task 2 含批量释义一致性、计数不触发排序、
   全量路径用例；Task 3 冒烟覆盖 loading 态与返回刷新。
7. 可执行性 ✅：Task 依赖清晰（算法 → 聚合/批量释义 → UI），无遗漏前置。

## 5. Task 分解

1. **Task 1（排序算法，TDD）**：`app/lib/util/confusable_sort.dart` + `app/test/confusable_sort_test.dart`。
   - 用例：含拼写相近组（cart/cat/cot/cut、there/their、weather/whether）的词集，断言贪心结果
     同族词相邻；空/单元素；全等长与混合长度；平局按字典序；**剪枝回退正确性**：构造"桶内最优
     距离 > DELTA 而桶外存在更近词"场景（如 DELTA=3 时 cur 与桶内剩词距离 ≥4、与桶外词距离 3），
     断言结果与朴素全量贪心**严格一致**（小规模对照）。
   - 验证：针对性 `flutter test` + `flutter analyze`。
2. **Task 2（聚合/计数/批量释义，TDD）**：WordBo 三个新方法 + `getWordLists()` 入口项；
   `app/test/` 新增用例：学习词书 → 去重聚合 → 排序 → 计数（**断言计数不触发排序缓存生成**）；
   缓存签名失效（增删学习词书/词书单词后重算）；**批量释义与 `getWordMeaningItems` 结果一致**
   （定制释义优先、max popularityLimit、min-3 保底）。
   - 验证：针对性 `flutter test` + `flutter analyze`。
3. **Task 3（UI）**：`confusable_words.dart`（provider + no-op bookmark + 菜单门控 +
   masterWord 提示 + 导航助手 + loading 态）、`word_lists.dart` 入口卡片与 onTap。
   实施细节：① 排序菜单门控需改 `word_list.dart` 菜单构建处（约 2332 行 `menuSortSettings`
   无条件入菜单，按 provider 能力隐藏）；② `WordListPageArgs` 构造要求
   `wordProgressProvider`，为 ConfusableWordsProvider 配一个静态进度 provider 实例。
   - 验证：`flutter analyze` + 词表页相关回归测试 + 手动冒烟（模拟器：首次进入 loading、
     返回词表页计数刷新、点词进详情、删除/添加词书后重算）。
4. **阶段 5 集成验证**：全量 `flutter analyze`（0 issue）+ 全量 `flutter test`。
   修复所有编译错误、警告、测试失败。

## 6. 风险与注意事项

- **首次进入耗时**：isolate 贪心（1-5s 取决于规模）+ 全量详情批量加载（数百 ms），loading 态
  一并覆盖；后续内存缓存复用（学习内容不变时零等待）。若实测大词库仍慢，可升级近似最近邻
  （记录为后续优化项，本次按严格贪心实现）。
- **去重语义**：同词多词书只展示一次；释义按"用户级"聚合口径（max popularityLimit + min-3），
  与详情页一致。
- **入口计数成本**：count distinct 本地索引轻量，且与排序缓存共享，不触发排序。
- **缓存一致性**：签名 = 学习词书集合 + 去重词集合，任何增删触发重算；词表页每次刷新校验签名。
- **与词书排序的关系**：独立虚拟视图，不改变任何现有词书排序偏好与学习逻辑。
