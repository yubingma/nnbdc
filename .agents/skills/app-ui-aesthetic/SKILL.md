---
name: app-ui-aesthetic
description: NBDC App 现代极简美学与排版规范（对标「不背单词」极简高级感）。涵盖零多余容器原则、中西文字阶与字重铁律、指标数据卡片排版、图标轻量化与选中态表达。
whenToUse: 当在项目中设计、开发或重构任何界面（如词表、学习、设置、卡片、列表项、导航栏、弹窗）时使用，确保全 App 视觉风格纯粹、通透、高度统一。
---

# NBDC 现代极简美学与排版设计规范

本规范旨在将全 App 视觉语言统一至 **「不背单词」同级别的极简、通透、排版驱动（Typography-driven）** 高级美感，坚决摒弃生硬厚重、随意套框的粗糙设计。

---

## 核心设计哲学

1. **排版驱动（Typography-driven），而非容器驱动**：靠精准的字阶比例（Type Scale）、修长的西文字体和自然的字重落差来建立视觉层级，而不是给每个元素套一个圆角矩形。
2. **克制透气（Breathing Room）**：善用留白（White Space）和弱透明度辅助色。界面应当像悬浮在清澈水面上一样轻灵通透。
3. **零伪粗体（Zero Faux Bold）**：不盲目使用过重字重（如 `w900`/`w800`），避免汉字因缺少专有字库而被引擎通过算法描边发胀发糊。

---

## 一、零多余容器铁律（Zero Redundant Containers）

告别典型的“盒中盒（Box-in-Box）”综合征：

### 1. 词数/数量徽章（Badges）
- ❌ **严禁**：给数量外包一层实心灰色或彩色小药丸（Pill Container）。
- ✅ **正确做法**：纯文本直接裸露呈现。西文数字（Roboto）与汉字自然排版，跟随一个微透明极淡箭头：
  ```dart
  Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '4428 词',
        style: TextStyle(
          fontSize: 13,
          fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
          color: isHighlighted ? accentColor : textSub,
          fontFamily: 'Roboto',
        ),
      ),
      const SizedBox(width: 4),
      Icon(Icons.arrow_forward_ios_rounded, size: 11, color: textSub.withValues(alpha: 0.4)),
    ],
  )
  ```

### 2. 底部导航栏（Bottom Navigation Bar）
- ❌ **严禁**：在当前选中的 Tab 图标后塞入浅色圆角实心底块（胶囊衬垫）。
- ✅ **正确做法**：纯粹色彩高亮（Brand Color）+ 文字微加粗。未选中态使用低饱和灰（`alpha: 0.4~0.5`）。整条导航栏无多余气泡，保持悬浮平整。

### 3. 区域次级行动（Section Actions）
- ❌ **严禁**：在卡片分栏标题右侧使用厚重的实心/胶囊按钮（如 `[+ 选词书]`）。
- ✅ **正确做法**：使用轻灵的行内文字链接（Text Action），如 `选词书 ›` 或 `换一本 ›`：
  ```dart
  Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '选词书',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: accentColor),
      ),
      const SizedBox(width: 2),
      Icon(Icons.arrow_forward_ios_rounded, size: 10, color: accentColor.withValues(alpha: 0.8)),
    ],
  )
  ```

### 4. 图标背景
- ❌ **严禁**：随意给列表项、小图标外层包裹彩色正方形/圆形实心底块。
- ✅ **正确做法**：常规功能列表与卡片直接展示矢量图标本身，色彩采用主题色或语义色，让卡片底色完整连贯。

---

## 二、字阶比与字重层级体系（Type Scale System）

| UI 层级 | 标准字号 | 推荐字重 | 字间距 (letterSpacing) | 设计意图与规则 |
| :--- | :--- | :--- | :--- | :--- |
| **页面大标题** | `20~22pt` | **`w700 (Bold)`** | `-0.3` | **严禁使用 w900/w800**。骨架必须锋利清晰，杜绝中文字体笔画黏连。 |
| **副标题 / Slogan** | `11.5~12pt` | **`w400 (Regular)`** | `+0.3 ~ +0.4` | 字重放轻，字间距微张，呈现杂志印刷品的诗意留白与呼吸感。 |
| **板块分节标题** | `15pt` | **`w600 (SemiBold)`** | `-0.2` | 如「我的书桌」、「今日学习」，端庄利落，不抢占主体卡片风头。 |
| **列表/卡片主标题** | `14~14.5pt` | **`w600 (SemiBold)`** | `-0.1` | 如词书名称、词表分类，字形分明。 |
| **列表/卡片副说明** | `11.5~12pt` | **`w400 (Regular)`** | `+0.1` | 次级灰色，与主标题形成清晰的对比层级。 |
| **核心指标数据** | `22~26pt` | **`w700 (Bold)`** | `-0.4 ~ -0.5` | **必须指定 `fontFamily: 'Roboto'`**。修长挺拔、现代感十足。 |
| **指标伴随标签** | `12~12.5pt` | **`w500 (Medium)`** | `0.0` | 次级灰阶（`textSecondary`），温润退后，衬托大数字。 |

---

## 三、指标卡片（Metric Cards）排版范式

参考 Apple 健身/健康与「不背单词」的现代卡片设计：

```dart
// 2x2 或横向数据卡片排版黄金结构
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // 顶部：精巧图标 + 极淡导向箭头
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, size: 20, color: iconColor),
        Icon(Icons.arrow_forward_ios_rounded, size: 11, color: themeConfig.textSecondary.withValues(alpha: 0.35)),
      ],
    ),
    const SizedBox(height: 10),
    // 底部：左侧温润标签 + 右侧挺拔醒目大数字（基线对齐）
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: themeConfig.textSecondary,
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: (isAlert && count > 0) ? alertColor : textMain,
            fontFamily: 'Roboto',
            letterSpacing: -0.4,
          ),
        ),
      ],
    ),
  ],
)
```

---

## 四、选中与高亮态表达规范（Selected & Active States）

- ❌ **避免**：
  - 在卡片左侧贴一条粗黑或粗彩色垂直竖条（生硬、割裂）。
  - 填满高饱和度纯色实心背景（压抑、破坏透光）。
- ✅ **推荐**：
  - **主题色精细描边**：`Border.all(color: accentColor.withValues(alpha: 0.75), width: 1.2)`。
  - **背景柔和薄雾**：`accentColor.withValues(alpha: 0.05 ~ 0.08)`。
  - **外发光/漫反射微阴影**：`BoxShadow(color: accentColor.withValues(alpha: 0.12), blurRadius: 12, offset: Offset(0, 3))`。
  - **主色文字与图标高亮**。

---

## 五、毛玻璃与背景底色协同

- 遵循 `.agents/skills/flutter-frosted-glass/SKILL.md` 规范。
- 浅色模式采用 `Color(0x4DFFFFFF)`（30% 通透乳白磨砂）配合 `sigma: 6`，保留底层文字模糊成暗色墨水斑的高级质感。
- 深色模式采用 `Color(0xB81C2127)`（72% 细腻黑灰磨砂）。

---

## 六、列表与分组聚合原则（Grouped Inset Card）

- ❌ **避免**：将同类列表项全部做成独立浮起的小卡片（卡片碎片化，零碎繁杂）。
- ✅ **推荐**：将属于同一分区的项目聚合为**一体化大圆角卡片**（`borderRadius: 16`），内部项之间使用**内缩极细分割线（Hairline Divider）**隔开：
  ```dart
  Padding(
    padding: const EdgeInsets.only(left: 48, right: 14),
    child: Divider(
      height: 1,
      thickness: 0.5,
      color: isDarkMode
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.055), // 严禁使用深黑或过厚粗线
    ),
  )
  ```

---

## 七、书桌词书统一样式与进度设计

- ❌ **避免**：
  - 仅显示冷冰冰的数字（如 `4428 词`），用户缺乏直观的学习进度与成就感；
  - 单独给第一本词书套一层绿色发光边框或特殊背景（导致视觉风格分裂、不协调）。
- ✅ **推荐**：
  - **书桌上所有词书卡片完全同构统一**，无高光或特殊边框差异；
  - **多本词书一体化聚合收拢**：多本词书统一收纳在同一个 Grouped Inset Card 大卡片内，各行之间由发丝分割线隔开，杜绝独立碎卡片堆叠；
  - **双重进度深度呈现（取词 + 掌握）**：副标题统一为 `已掌握 $mastered · 已取 $fetched · $percent%`（右侧已有 `$total 词 >`，副标题杜绝重复），并嵌入**双段极简微细胶囊进度条**（高度 3.5px）：
    - **实心主题色**：已掌握进度（牢固掌握）；
    - **浅半透主题色**：已取词进度（学习中/已进入学习计划词库）；
    - **底层中性浅灰轨**：未取词部分（严禁使用带绿底轨，避免与取词进度混淆）。
  ```dart
  // 统一副标题（精炼去重）
  '已掌握 $mastered · 已取 $fetched · $percent%'

  // 双段微细进度条
  ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 3.5,
      child: Stack(
        children: [
          Container(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.055),
          ),
          if (fetchProgress != null && fetchProgress > 0)
            FractionallySizedBox(
              widthFactor: fetchProgress.clamp(0.0, 1.0),
              alignment: Alignment.centerLeft,
              child: Container(
                color: accentColor.withValues(alpha: isDarkMode ? 0.45 : 0.35),
              ),
            ),
          if (progress != null && progress > 0)
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              alignment: Alignment.centerLeft,
              child: Container(
                color: accentColor,
              ),
            ),
        ],
      ),
    ),
  )
  ```

---

## 八、语义微色谱与图标状态表达（Semantic Pastels & State）

- ❌ **避免**：整屏 10 多个图标全部使用同一档纯绿色（单色视觉疲劳），或者错词为 0 时依然显示红色/禁止符。
- ✅ **推荐**：
  - 核心功能引入克制、自洽的**微语义色彩（Semantic Pastels）**：
    - **书桌词书主线**：统一使用当前 App 主题色（`accentColor`，主线聚焦）；
    - **今日单词（总览）**：稳重靛青（`Color(0xFF4F46E5)`，全局日程计划）；
    - **今日新词（新知）**：明快天蓝（`Color(0xFF0EA5E9)`，新鲜知识注入与探索）；
    - **今日旧词（复习）**：沉静青碧（`Color(0xFF0D9488)`，记忆沉淀与温故知新）；
    - **核心学习中**：专注活力蓝（`Color(0xFF3B82F6)`，知识深度加工与记忆）；
    - **核心已掌握**：通关翡翠绿（`Color(0xFF10B981)`，牢固掌握达标成就感）；
    - **核心生词本**：温暖琥珀金（`Color(0xFFF59E0B)`，重点精选与标记）；
    - **专项形近词**：思辨电光紫（`Color(0xFF6366F1)`，形态对比攻坚）；
  - **动态状态联动**：
    - 错词为 0 时：显示温和弱灰的完成态对勾图标（`Icons.check_circle_outline_rounded`）；
    - 错词 > 0 时：动态亮起醒目的暖珊瑚色（`Color(0xFFE54D3B)` / `0xFFFF7E6C`）与感叹号，形成视觉提醒。

