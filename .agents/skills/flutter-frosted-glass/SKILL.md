---
name: flutter-frosted-glass
description: Flutter 局部毛玻璃（Frosted Glass / 磨砂质感）弹窗与卡片开发规范。解决 BackdropFilter 失效变成纯白实心卡片、文字无法晕开成暗色色块、以及 OpacityLayer/FadeTransition 阻断底层采样的深度渲染坑。
whenToUse: 当在 Flutter 中开发带有毛玻璃/磨砂半透效果的弹出菜单（PopupMenu）、Dialog、悬浮卡片、Bottom Bar 或 Drawer，且需要让底层文字/内容自然晕开呈现高级质感时使用。
---

# Flutter 局部毛玻璃质感规范与避坑指南

## 核心表现目标
1. **局部精确模糊**：磨砂仅限于菜单/卡片自身的圆角几何区域内，屏幕其余部分保持 100% 清晰锐利，不搞全局死黑/死白遮罩。
2. **通透墨水色块**：透过毛玻璃，底层文字不应该消失为纯白，而是恰到好处地晕开为**朦胧柔和的墨水暗色色块**。

---

## 避坑铁律（三大常见致命问题）

### 1. 严禁在 BackdropFilter 祖先节点使用 `FadeTransition` / `Opacity`（最隐蔽的渲染引擎坑）
- **现象**：明明配置了 `BackdropFilter` 和半透明背景，但在真机/模拟器上渲染出来完全是纯白/实心卡片，底下什么都透不出来。
- **底层原理**：在 Flutter 渲染管线中，`FadeTransition`、`AnimatedOpacity`、`Opacity`（当 `alpha > 0` 时）会强制推入独立的离屏缓冲图层（`OpacityLayer` / `saveLayer`）。在该离屏缓冲区内，底层页面尚未绘制，`BackdropFilter` 采样到的背景为空（全黑/透明），与半透明白叠合后直接变成了死白。
- **正确做法**：
  - 弹窗转场统一使用 **`ScaleTransition`**（纯 `TransformLayer` 矩阵变换）或 `SlideTransition`，**绝对不要使用 `FadeTransition`**。

### 2. 模糊核半径（`sigma`）大小取值陷阱（“为什么看不到文字色块？”）
- **现象**：底下的汉字和英文字完全看不见了，整体一片泛白。
- **底层原理**：常规汉字、英文字号一般为 12~16px，笔画线条宽度仅 1~1.5px。如果设置 `sigmaX: 14~30`（高斯采样窗口高达 `3 * sigma = 42~90px`），细线黑色像素会被 1000+ 个像素均化稀释，黑色对比度衰减 99.9%，在白底上直接被抹平蒸发为纯白。
- **黄金参数推荐**：
  - **文字朦胧墨水色块（推荐）**：`ImageFilter.blur(sigmaX: 6, sigmaY: 6)`（在 5~7 之间）。能精准抹去汉字字形可读性，同时保留凝聚的深色暗斑质感。
  - **图片/大色块柔焦**：`ImageFilter.blur(sigmaX: 12, sigmaY: 16)`。

### 3. 双重叠白与遮罩过厚（“白加白变成实心白”）
- **现象**：浅色模式下底层卡片通常本身就是白色（`#FFFFFF`）。如果毛玻璃表面再盖一层厚半透白（如 40% `0x66FFFFFF` 或 `CupertinoPopupSurface` 默认刷的 80% `0xCCF2F2F2`），白白相叠，直接彻底掩盖底下的暗色色块。
- **标准调色配方**：
  - **浅色模式（Light Mode）**：
    - 背景：`const Color(0x33FFFFFF)`（20% 通透超薄白）或 `const Color(0x26FFFFFF)`（15%）
    - 微光边框：`Border.all(color: const Color(0x80FFFFFF), width: 1.0)`
    - 阴影：`BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 6))`
  - **深色模式（Dark Mode）**：
    - 背景：`const Color(0xB81C2127)`（72% 细腻黑灰）
    - 微光边框：`Border.all(color: const Color(0x33FFFFFF), width: 1.0)`
    - 阴影：`BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 6))`

---

## 标准模版代码（可复用）

以右上角触发的局部毛玻璃弹出菜单为例：

```dart
import 'dart:ui';
import 'package:flutter/material.dart';

Future<T?> showFrostedMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget Function(BuildContext dialogCtx) contentBuilder,
  required bool isDarkMode,
  double menuWidth = 172.0,
}) {
  // 1. 精确获取触发锚点屏幕坐标
  final RenderBox? renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final Offset offset = renderBox?.localToGlobal(Offset.zero) ?? const Offset(0, 80);
  final Size size = renderBox?.size ?? Size.zero;

  final double menuTop = offset.dy + size.height + 6.0;
  final double menuRight = (MediaQuery.sizeOf(context).width - offset.dx - size.width).clamp(8.0, 30.0);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dismiss_menu',
    barrierColor: Colors.transparent, // 保持全屏清爽透亮，不加全屏暗色遮罩
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogCtx, anim1, anim2) {
      return Stack(
        children: [
          // 局部透明点击退出遮罩
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(dialogCtx),
            ),
          ),
          // 局部毛玻璃主体
          Positioned(
            top: menuTop,
            right: menuRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: menuWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    // 关键参数：sigma=6 既打散轮廓，又保留文字墨水色块
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xB81C2127)
                            : const Color(0x33FFFFFF), // 20% 通透度，避免双重叠白
                        border: Border.all(
                          color: isDarkMode
                              ? const Color(0x33FFFFFF)
                              : const Color(0x80FFFFFF),
                          width: 1.0,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: contentBuilder(dialogCtx),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    // 关键转场：使用 ScaleTransition，坚决避免使用 FadeTransition 引起 OpacityLayer 阻断
    transitionBuilder: (context, anim1, anim2, child) {
      return ScaleTransition(
        alignment: Alignment.topRight,
        scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}
```

---

## 检查清单（上线前速查）
- [ ] 祖先链路中**没有任何 `FadeTransition` / `Opacity`** 包含 `BackdropFilter`
- [ ] 转场采用 `ScaleTransition`（锚点设为靠近按钮的方位，如 `topRight`）
- [ ] 模糊半径 `sigma` 是否在 5~7 之间（避免文字被均化蒸发成全白）
- [ ] 浅色模式背景白色 alpha 是否在 `0x26`~`0x33` 之间（15%~20%），没有实心感
- [ ] 弹窗使用 `showGeneralDialog` + `barrierColor: Colors.transparent`，周围内容无多余全屏发暗或模糊
