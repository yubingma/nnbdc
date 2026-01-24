# Android Logcat 过滤器配置

## 快速过滤命令

### 过滤掉 ImageDecoder 错误
```bash
adb logcat | grep -v "ImageDecoder"
```

### 过滤掉所有 FlutterJNI 的 ImageDecoder 相关错误
```bash
adb logcat | grep -v "E/FlutterJNI.*Failed to decode image"
```

### 只显示应用的日志（排除 FlutterJNI 错误）
```bash
adb logcat | grep "com.nn.nnbdc" | grep -v "ImageDecoder"
```

### 只显示 Flutter 层的日志
```bash
adb logcat | grep "I/flutter"
```

## Android Studio 配置

### 创建自定义 Logcat 过滤器

1. 打开 Android Studio
2. 打开 Logcat 窗口
3. 点击右上角的过滤器下拉菜单
4. 选择 "Edit Filter Configuration"
5. 创建新过滤器，名称：`App Logs (No Image Errors)`
6. 配置如下：

**Filter Name**: App Logs (No Image Errors)

**Log Tag**: 留空或填写 `flutter`

**Log Message**: 留空

**Package Name**: `com.nn.nnbdc`

**Log Level**: `Info` 或更高

**Regex**: 
```
^(?!.*ImageDecoder).*$
```

### 使用预定义过滤器

在 Logcat 的搜索框中输入：

```
-tag:FlutterJNI package:com.nn.nnbdc
```

这将显示所有来自您的应用的日志，但排除 FlutterJNI 标签的日志。

## VS Code 配置（如果使用 VS Code）

在 `.vscode/launch.json` 中添加：

```json
{
  "name": "Flutter (Android - No Image Errors)",
  "request": "launch",
  "type": "dart",
  "args": [
    "--dart-define=FLUTTER_LOG_FILTER=^(?!.*ImageDecoder).*$"
  ]
}
```

## 命令行工具脚本

### Bash 脚本 (macOS/Linux)

创建文件 `scripts/logcat-filter.sh`:

```bash
#!/bin/bash

# 过滤 Android logcat，排除 ImageDecoder 错误

echo "正在启动 logcat 过滤器..."
echo "排除: ImageDecoder 相关错误"
echo "-----------------------------------"

adb logcat | grep --line-buffered -v "ImageDecoder" | \
             grep --line-buffered -v "E/FlutterJNI.*Failed to decode"
```

使用方法：
```bash
chmod +x scripts/logcat-filter.sh
./scripts/logcat-filter.sh
```

### 高级过滤脚本

创建文件 `scripts/logcat-advanced.sh`:

```bash
#!/bin/bash

# 高级 logcat 过滤器
# 只显示重要的应用日志

echo "启动高级 logcat 过滤器..."
echo "包含: Flutter 日志, 应用错误"
echo "排除: ImageDecoder, 系统噪音"
echo "-----------------------------------"

adb logcat -v color | \
  grep --line-buffered -E "(I/flutter|E/.*nnbdc|W/.*nnbdc)" | \
  grep --line-buffered -v "ImageDecoder" | \
  grep --line-buffered -v "Failed to decode image"
```

## 持久化配置

### 方法 1: Shell 别名

在 `~/.bashrc` 或 `~/.zshrc` 中添加：

```bash
# Android logcat 别名
alias logcat-clean='adb logcat | grep -v "ImageDecoder"'
alias logcat-flutter='adb logcat | grep "I/flutter"'
alias logcat-app='adb logcat | grep "com.nn.nnbdc" | grep -v "ImageDecoder"'
```

然后运行：
```bash
source ~/.bashrc  # 或 source ~/.zshrc
```

使用：
```bash
logcat-clean
logcat-flutter
logcat-app
```

### 方法 2: ADB 配置文件

创建 `~/.adbrc`:

```bash
# 默认 logcat 过滤器
export ADB_LOGCAT_FILTER="-v color | grep -v ImageDecoder"
```

## 推荐的开发工作流

### 日常开发
```bash
# 使用干净的日志输出
adb logcat -v color | grep -v "ImageDecoder" | grep -v "Failed to decode"
```

### 调试图片问题
```bash
# 临时启用所有日志
adb logcat -v color
```

### 性能分析
```bash
# 只看 Flutter 性能日志
adb logcat | grep -E "(I/flutter|Timeline)"
```

### 错误追踪
```bash
# 只看错误和警告
adb logcat *:E *:W | grep -v "ImageDecoder"
```

## 注意事项

1. **不要完全忽略所有错误**：ImageDecoder 错误可以忽略，但其他错误可能很重要
2. **定期检查完整日志**：偶尔查看未过滤的日志，确保没有遗漏重要信息
3. **团队共享配置**：将这些过滤器配置分享给团队成员
4. **CI/CD 环境**：在 CI/CD 中可能需要看到所有日志，不要应用过滤器

## 故障排除

### 如果过滤器不工作

1. 检查 `grep` 版本：
   ```bash
   grep --version
   ```

2. 尝试使用 `egrep` 代替 `grep -E`

3. 确保 ADB 连接正常：
   ```bash
   adb devices
   ```

4. 清除 logcat 缓冲区：
   ```bash
   adb logcat -c
   ```

### 如果需要查看被过滤的日志

临时禁用过滤器：
```bash
adb logcat -v color
```

或者只看 ImageDecoder 相关的日志：
```bash
adb logcat | grep "ImageDecoder"
```
