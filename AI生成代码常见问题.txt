# AI生成代码常见问题总结
注意: 这里列出的问题, 都是本项目实际发生过的, 解决方案也是实际验证过的

## Flutter 文字变糊问题

### 问题原因
字体粗细过重导致文字渲染模糊，特别是 `FontWeight.bold` (w700)。

### 解决方案
将 `FontWeight.bold` 改为 `FontWeight.w400`：

```dart
// 问题代码
Text(
  '标题',
  style: TextStyle(
    fontWeight: FontWeight.bold,  // 容易变糊
  ),
)

// 修复后
Text(
  '标题',
  style: TextStyle(
    fontWeight: FontWeight.w400,  // 正常粗细，清晰
  ),
)
```

### 关键点
- **使用 w400**：正常粗细最清晰，避免变糊
- **避免 w700+**：粗体容易变糊
- **统一设置**：所有文本组件使用相同的字重策略

---
*问题来源：词典管理页面编辑对话框文字变糊问题*
