# 今日最少新词数量配置 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 今日学习计划页面准备今日单词时，支持配置"今日最少新词数量"，保证复习词很多时也能每天学到至少 N 个新词。

**Architecture:** 在用户级配置 `StudyConfig`（user.studyConfig JSON 字段，跨端同步）中新增 `minNewWordsPerDay` 字段；修改 `LearningService.genTodayWords` 填词算法为"配额内保证"（总词数保持 wordsPerDay，新词优先填到配置值，复习词填剩余）；`prepareTodayStudy` 增加"今日新词不足配置值"时的补充触发；今日计划页新增"高级"按钮弹出配置对话框。

**Tech Stack:** Flutter (Dart), Drift (SQLite), StudyConfig JSON, LearningService

---

## 影响范围

- Flutter: 是
  - `app/lib/util/study_config.dart`（配置字段）
  - `app/lib/util/learning_service.dart`（取词算法）
  - `app/lib/page/today_plan.dart`（高级按钮 + 配置对话框）
- 测试: `app/test/learning_service_test.dart`
- iOS/Android 原生: 否
- 服务端: 否（StudyConfig 已随 user 同步）

---

## 需求（已与用户确认）

1. **语义 = 配额内保证**：每日总单词数保持 `wordsPerDay` 不变，从复习词中腾出位置给新词，保证新词 ≥ 配置值。被挤出的复习词顺延到后续几天。
2. **配置入口**：今日学习计划页面放一个"高级"按钮，点进去可配置"今日最少新词数量"。
3. **默认值**：0（不启用，行为与现状完全一致）；可选范围 0~wordsPerDay。
4. **新词枯竭时**：新词尽力而为，剩余位置由复习词填满（总词数仍保持 wordsPerDay）。

---

## 当前取词逻辑（genTodayWords）

1. 从 `learningWords` 取未毕业候选词，排除今日已选 + 已掌握
2. 识别到期词 `dueWords`（新词 `lastLearningDate == null` 直接到期；复习词按 FSRS scheduledDays 判断）
3. 排序：`state > 0`（已建立进度）优先 → 稳定性低优先 → addTime 久优先
4. 填 `dueWords` 直到填满 `wordsPerDay`
5. 不足则从词书抓绝对新词补足

**问题场景**：到期复习词 ≥ wordsPerDay 时，新词数量 = 0。

---

## Task 分解

### Task 1: StudyConfig 增加 `minNewWordsPerDay` 字段

**Files:**
- Modify: `app/lib/util/study_config.dart`
- Test: `app/test/learning_service_test.dart`（复用现有 DB 测试基建，新增序列化断言）

**Step 1: 写失败测试**（在 learning_service_test.dart 新增 group）

```dart
group('StudyConfig - minNewWordsPerDay 序列化', () {
  test('minNewWordsPerDay 字段 round-trip', () {
    final config = StudyConfig(minNewWordsPerDay: 5);
    final json = config.toJson();
    expect(json['minNewWordsPerDay'], 5);
    final restored = StudyConfig.fromJson(json);
    expect(restored.minNewWordsPerDay, 5);
  });

  test('缺失字段时默认 0', () {
    final restored = StudyConfig.fromJson({});
    expect(restored.minNewWordsPerDay, 0);
  });
});
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/learning_service_test.dart --plain-name "minNewWordsPerDay"`
Expected: FAIL（`StudyConfig` 无此字段，编译错误）

**Step 3: 实现**

在 `study_config.dart`：
```dart
// 字段声明
int minNewWordsPerDay;

// 构造函数默认参数
this.minNewWordsPerDay = 0,

// fromJson
minNewWordsPerDay: _toInt(json['minNewWordsPerDay']),

// toJson
'minNewWordsPerDay': minNewWordsPerDay,
```

新增静态辅助方法（与 `_toBool` 同风格）：
```dart
static int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}
```

**Step 4: 运行测试确认通过**

Run: `flutter test test/learning_service_test.dart --plain-name "minNewWordsPerDay"`
Expected: PASS

**Step 5: 不 commit（项目约定：不得自行 git commit）**

---

### Task 2: LearningService 取词算法改造（核心）

**Files:**
- Modify: `app/lib/util/learning_service.dart`（`prepareTodayStudy` + `genTodayWords`）
- Test: `app/test/learning_service_test.dart`

**Step 1: 写失败测试**

```dart
group('LearningService - 今日最少新词数量配置', () {
  Future<void> seedDueReviewWords(int count) async {
    final pastDate = now.subtract(const Duration(days: 3));
    for (int i = 1; i <= count; i++) {
      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'due_$i',
        addTime: pastDate,
        addDay: 1,
        stability: 2.5,
        difficulty: 5.0,
        elapsedDays: 3,
        scheduledDays: 1, // 到期
        reps: 1,
        lapses: 0,
        state: 1,
        lastLearningDate: pastDate,
        isTodayNewWord: false,
        learnedTimes: 1,
        todayLearnedTimes: 0,
        learningOrder: 0,
        createTime: pastDate,
        updateTime: pastDate,
      ));
    }
  }

  test('复习词充足时配置最少新词后仍保证新词数量', () async {
    // wordsPerDay = 5，先造 8 个到期复习词（≥ wordsPerDay）
    await seedDueReviewWords(8);

    // 配置 minNewWordsPerDay = 3
    final config = StudyConfig(minNewWordsPerDay: 3);
    await config.saveToCurrentUser(); // 写入 user.studyConfig 并更新缓存

    final result = await LearningService.prepareTodayStudy(true);
    expect(result.success, true);

    var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
    // 总词数保持 wordsPerDay = 5
    expect(todayWords.length, 5);

    int newCount = todayWords.where((w) => w.isTodayNewWord).length;
    int reviewCount = todayWords.where((w) => !w.isTodayNewWord).length;
    // 新词 ≥ 配置值 3
    expect(newCount, 3);
    // 复习词 = 5 - 3 = 2
    expect(reviewCount, 2);
  });

  test('默认配置(0)行为不变：复习词填满时新词为 0', () async {
    await seedDueReviewWords(8);
    // 不配置，保持默认 0
    final result = await LearningService.prepareTodayStudy(true);
    expect(result.success, true);
    var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
    expect(todayWords.length, 5);
    int newCount = todayWords.where((w) => w.isTodayNewWord).length;
    expect(newCount, 0); // 复习词优先填满，新词为 0（现状行为）
  });

  test('新词枯竭时尽力而为，复习词填满剩余位置', () async {
    // 词书只有 10 个词（setUp 生成 word_1..word_10），wordsPerDay = 5
    // 先把 7 个词占为复习词（learningWords 中 lastLearningDate != null），只剩 3 个绝对新词可抓
    final pastDate = now.subtract(const Duration(days: 3));
    for (int i = 1; i <= 7; i++) {
      await db.into(db.learningWords).insert(LearningWord(
        userId: testUser.id,
        wordId: 'word_$i', // 占用词书中的词，使其不再可被抓为新词
        addTime: pastDate,
        addDay: 1,
        stability: 2.5,
        difficulty: 5.0,
        elapsedDays: 3,
        scheduledDays: 1,
        reps: 1,
        lapses: 0,
        state: 1,
        lastLearningDate: pastDate,
        isTodayNewWord: false,
        learnedTimes: 1,
        todayLearnedTimes: 0,
        learningOrder: 0,
        createTime: pastDate,
        updateTime: pastDate,
      ));
    }

    final config = StudyConfig(minNewWordsPerDay: 5);
    await config.saveToCurrentUser();

    final result = await LearningService.prepareTodayStudy(true);
    var todayWords = await LearningService.getTodayLearningWordsFromDb(testUser.id);
    // 词书只剩 3 个新词可抓（word_8, word_9, word_10）
    // 复习词 = 7 个到期词，但总词数上限 wordsPerDay = 5
    expect(todayWords.length, 5);
    int newCount = todayWords.where((w) => w.isTodayNewWord).length;
    expect(newCount, 3); // 尽力而为：3 个新词
    expect(todayWords.where((w) => !w.isTodayNewWord).length, 2); // 复习词填满剩余
  });
});
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/learning_service_test.dart --plain-name "今日最少新词数量配置"`
Expected: FAIL（前两个测试断言失败：newCount 为 0 而非 3）

**Step 3: 实现**

在 `prepareTodayStudy`：
```dart
// 读取配置（在 needAddNewWords 判断之前）
final int minNewWordsPerDay = StudyConfig.fromCurrentUser().minNewWordsPerDay;

// 修改补充触发条件：今日新词不足配置值也触发
int todayNewCount = todayWords.where((w) => w.isTodayNewWord).length;
bool needAddNewWords = todayWords.isEmpty ||
    (todayWords.length < user.effectiveWordsPerDay && addNewWordsIfNotEnough) ||
    (minNewWordsPerDay > 0 && todayNewCount < minNewWordsPerDay);
```

在 `genTodayWords` 签名增加参数：
```dart
static Future<List<LearningWord>> genTodayWords(
    String userId, DateTime now, List<LearningWord> todayLearningWords,
    {int minNewWordsPerDay = 0}) async {
```

`genTodayWords` 核心算法改造（替换第 2、3 步填词逻辑）：

```dart
// 2. 拆分到期词：新词（从未学过）与复习词
final List<LearningWord> dueNewWords = dueWords.where((w) => w.lastLearningDate == null).toList();
final List<LearningWord> dueReviewWords = dueWords.where((w) => w.lastLearningDate != null).toList();

// 新词配额（不超过总目标）
final int newQuota = min(minNewWordsPerDay, user.effectiveWordsPerDay);

// 2a. 若今日计划中"已有词数 + 新词缺口"超过 wordsPerDay：挤出未学复习词为新词腾位
// 关键：不是"计划已满才挤出"，而是按需要的额外空间判断。
// 例：已有 4 复习词、wordsPerDay=5、配置=3 → length(4)+deficit(3)=7 > 5 → 挤出 2 个复习词
if (newQuota > 0) {
  int existingNewCount = todayLearningWords.where((w) => w.isTodayNewWord).length;
  int newDeficit = newQuota - existingNewCount;
  if (newDeficit > 0) {
    int neededRoom = todayLearningWords.length + newDeficit - user.effectiveWordsPerDay;
    if (neededRoom > 0) {
      final evictable = todayLearningWords
          .where((w) => !w.isTodayNewWord && w.todayLearnedTimes == 0)
          .toList();
      int toEvict = min(neededRoom, evictable.length);
      for (var w in evictable.take(toEvict)) {
        await db.learningWordsDao.saveEntity(
            w.copyWith(batchId: const Value(0), learningOrder: 0), true);
        todayLearningWords.remove(w);
      }
      Global.logger.d('[FETCH-WORD] [genTodayWords] 为新词配额挤出 $toEvict 个未学复习词');
    }
  }
}

// 2b. 先填新词到配额（幽灵新词优先，不足从词书抓绝对新词）
int newCountNow = todayLearningWords.where((w) => w.isTodayNewWord).length;
for (var word in dueNewWords) {
  if (newCountNow >= newQuota) break;
  if (todayLearningWords.length >= user.effectiveWordsPerDay) break;
  todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId), learningOrder: 0));
  newCountNow++;
  dueAddedCount++;
}

// 2c. 新词仍不足配额时，从词书抓绝对新词补足
if (newCountNow < newQuota && todayLearningWords.length < user.effectiveWordsPerDay) {
  int needNewCount = min(newQuota - newCountNow,
      user.effectiveWordsPerDay - todayLearningWords.length);
  // 计算 todayDayNumber（复用原第 3 步逻辑，提前到这里）
  // ...（将原第 3 步的 todayDayNumber 计算移到此处）
  final newWords = await fetchNewWordsToLearn(
    userId, todayDayNumber, needNewCount,
    excludeWordIds: todayLearningWords.map((e) => e.wordId).toSet(),
  );
  for (var word in newWords) {
    todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId), learningOrder: 0));
    newCountNow++;
  }
}

// 2d. 填复习词填满剩余位置
for (var word in dueReviewWords) {
  if (todayLearningWords.length >= user.effectiveWordsPerDay) break;
  todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId), learningOrder: 0));
  dueAddedCount++;
}

// 2e. 复习词不足时，先填剩余幽灵新词，再从词书抓绝对新词（保留原第 3 步行为）
if (todayLearningWords.length < user.effectiveWordsPerDay) {
  for (var word in dueNewWords) {
    if (todayLearningWords.length >= user.effectiveWordsPerDay) break;
    if (todayLearningWords.any((w) => w.wordId == word.wordId)) continue;
    todayLearningWords.add(word.copyWith(batchId: Value(targetBatchId), learningOrder: 0));
  }
}
if (todayLearningWords.length < user.effectiveWordsPerDay) {
  // ...（原第 3 步的抓取逻辑，todayDayNumber 已提前计算）
  int needNewCount = user.effectiveWordsPerDay - todayLearningWords.length;
  final newWords = await fetchNewWordsToLearn(...);
  ...
}
```

调用处（prepareTodayStudy 内）：
```dart
todayWords = await genTodayWords(user.id, AppClock.now(), todayWords,
    minNewWordsPerDay: minNewWordsPerDay);
```

**实现注意事项：**
- 原 `todayDayNumber` 计算块（第 3 步）需要提前到 2c 之前，供 2c 与 2e 共用
- `dueAddedCount` 日志保持
- `wordExhausted` 判断不变（`todayWords.length < effectiveWordsPerDay`）

**Step 4: 运行测试确认通过**

Run: `flutter test test/learning_service_test.dart`
Expected: 全部 PASS（含原有 1107 行中的所有既有用例）

**Step 5: 不 commit**

---

### Task 3: 今日计划页"高级"按钮 + 配置对话框

**Files:**
- Modify: `app/lib/page/today_plan.dart`
- Test: 手动验证 + flutter analyze（本项目无今日计划页 widget 测试）

**Step 1: 实现**

在 `renderMissionCard` 的 Header 行（今日目标标题与 `renderGoalDropdown` 之间）新增"高级"按钮，或放在 Stats Grid 下方一行右对齐。采用 Header 行方案：

```dart
// Header Row 内，renderGoalDropdown() 之前：
IconButton(
  tooltip: '高级设置',
  icon: Icon(Icons.tune_rounded, size: 20),
  color: isDarkMode ? Colors.white54 : Colors.black45,
  onPressed: () => _showAdvancedSettingsDialog(),
)
```

新增方法：
```dart
void _showAdvancedSettingsDialog() {
  final isStarted = user?.todayStudyStarted == true;
  final config = StudyConfig.fromCurrentUser();
  final wordsPerDay = user?.effectiveWordsPerDay ?? 20;
  int selected = config.minNewWordsPerDay.clamp(0, wordsPerDay);

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('高级设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('今日最少新词数量'),
                if (isStarted)
                  const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.orangeAccent)
                else
                  DropdownButton<int>(
                    value: selected,
                    isDense: true,
                    items: [
                      for (int v = 0; v <= wordsPerDay; v++)
                        DropdownMenuItem(value: v, child: Text(v == 0 ? '0（不限制）' : '$v')),
                    ],
                    onChanged: isStarted
                        ? null
                        : (v) => setDialogState(() => selected = v ?? 0),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '保证每天至少学习指定数量的新词（0 表示不限制）',
              style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white54 : Colors.black45),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: isStarted
                ? null
                : () async {
                    config.minNewWordsPerDay = selected;
                    await config.saveToCurrentUser();
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    // 重新生成今日计划，使配置生效
                    loadData(forceSupplement: true);
                  },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
```

**注意：**
- `StudyConfig` 需 import：`import 'package:nnbdc/util/study_config.dart';`
- 已开始学习（todayStudyStarted）时锁定配置（与 renderGoalDropdown 行为一致）
- 保存后调用 `loadData(forceSupplement: true)` 触发重新取词
- `_showAdvancedSettingsDialog` 内 `ctx.mounted` 检查避免 async gap

**Step 2: 验证**

Run: `flutter analyze`
Expected: No issues found

**Step 3: 不 commit**

---

### Task 4: 集成验证

**Step 1: 运行全部相关测试**

Run: `cd app && flutter test test/learning_service_test.dart`
Expected: 全部 PASS

Run: `cd app && flutter analyze`
Expected: No issues found

**Step 2: 手动验证（可选）**
- 今日计划页点击"高级"→ 配置最少新词数量 → 保存 → 计划重新生成，新词数 ≥ 配置值
- 复习词多时：总词数仍 = wordsPerDay，新词 = 配置值，复习词被挤出顺延

---

## 边界情况

| 场景 | 行为 |
|---|---|
| minNewWordsPerDay = 0（默认） | 与现状完全一致（复习词优先填满） |
| 配置值 ≥ wordsPerDay | 新词配额 = wordsPerDay，全部位置给新词（若有足够新词） |
| 新词枯竭 | 新词尽力而为，复习词填满剩余，总词数保持 wordsPerDay |
| 已开始学习（todayStudyStarted） | 配置锁定不可改（与 wordsPerDay 一致） |
| 幽灵新词（learningWords 中 lastLearningDate==null） | 优先于词书绝对新词被填入选（保持现状兼容） |

---

## 架构审查结论（2026-08-02）

**总体结论：有条件通过**

### 已修正问题

**P1（重要）— 2a 挤出条件错误**：原方案"若计划已满但新词不足配额才挤出"存在漏洞：
- 场景：已有 4 个复习词、wordsPerDay=5、配置 minNewWords=3 → 计划未满（4<5），不触发挤出，但 2c 抓新词时 `length >= wordsPerDay` 上限拦截，最终只能加 1 个新词，配额 3 无法满足。
- 修正：改为按"需要的额外空间"判断——`todayLearningWords.length + newDeficit > wordsPerDay` 时挤出 `(length + newDeficit - wordsPerDay)` 个未学复习词。计划文档已更新。

### 已验证正确的点

1. **三个测试场景数据流模拟全部通过**：
   - 测试1（8 到期复习词 + 配置3）：due_1..due_8 全部进入 candidateWords（stability=2.5 < 180.0 未毕业）→ 幽灵新词为空 → 2c 从词书抓 word_1..word_3 共 3 新词 → 2d 填 due_1、due_2 → 最终 5 词 = 3 新 + 2 复习 ✓
   - 测试2（默认0）：newQuota=0，2b/2c 直接跳过，2d 填满 5 个复习词 → 0 新词，与现状完全一致 ✓
   - 测试3（词书枯竭）：word_1..word_7 已占为复习词 → existingWordIdsSet 排除它们 → 词书只剩 word_8..word_10 可抓 3 个 → 2d 填 word_1、word_2 → 5 词 = 3 新 + 2 复习 ✓
2. **配置缓存一致性**：`saveToCurrentUser()` 内部调用 `Global.updateUserCache(updatedUser)` 并写入 DB；prepareTodayStudy 中重置逻辑后的 `Global.loadUserFromDb()` 从 DB 重新加载，能读到新配置 ✓
3. **todayDayNumber 提前无副作用**：该值仅由 allLearningWords 的 addTime 推导，纯本地计算，提前不影响结果 ✓
4. **needAddNewWords 触发闭环**：今日新词不足配置值时即使计划已满也会触发 genTodayWords → 2a 挤出 → 2c 补新词 ✓

### 实现注意事项（供执行时参考）
- 2c/2e 中的 `fetchNewWordsToLearn` 需共用提前计算的 `todayDayNumber`
- 2e 遍历幽灵新词时用 `todayLearningWords.any((w) => w.wordId == word.wordId)` 去重，防止与 2b 已添加的重复
- `wordExhausted` 判断（`todayWords.length < effectiveWordsPerDay`）保持不变
