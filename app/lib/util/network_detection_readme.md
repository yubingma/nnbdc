# 网络检测功能说明

## 功能概述

本功能为应用添加了网络连接检测能力，在数据库同步前会检查网络连接状态，如果网络不可用则跳过同步操作，避免不必要的网络请求和错误。

## 主要特性

1. **网络连接检测**: 检查设备是否有网络连接
2. **互联网访问验证**: 通过ping可靠服务器验证是否能真正访问互联网
3. **连接类型识别**: 识别WiFi、移动网络、以太网等连接类型
4. **状态变化监听**: 实时监听网络状态变化
5. **全面网络控制**: 在数据库同步前和所有API请求前自动检查网络状态
6. **阻止网络访问**: 网络不可用时阻止所有网络操作，包括API调用

## 使用方法

### 基本使用

```dart
import 'package:nnbdc/util/network_util.dart';

// 创建网络检测工具实例
final networkUtil = NetworkUtil();

// 检查网络连接
bool isConnected = await networkUtil.isConnected();
if (isConnected) {
} else {
  print('网络连接不可用');
}

// 获取连接类型
String connectionType = await networkUtil.getConnectionType();
print('当前连接类型: $connectionType');
```

### 监听网络状态变化

```dart
// 监听网络状态变化
networkUtil.listenToConnectivityChanges((bool isConnected) {
  if (isConnected) {
    print('网络已连接');
    // 可以在这里触发同步操作
  } else {
    print('网络已断开');
  }
});

// 停止监听
networkUtil.stopListening();
```

### 在同步服务中的使用

网络检测功能已经集成到同步服务中，无需额外配置：

- `ThrottledDbSyncService`: 在节流同步服务中自动检查网络
- `syncDb()`: 在主同步函数中自动检查网络

### 在API请求中的使用

网络检测功能已经集成到API层面，自动阻止所有网络请求：

- `NetworkInterceptor`: 在API请求前自动检查网络连接
- 网络不可用时自动阻止API调用，避免网络错误
- 所有API请求都会经过网络检测

## 技术实现

### 网络检测策略

1. **连接类型检查**: 使用 `connectivity_plus` 检查设备网络连接类型
2. **互联网访问验证**: 通过DNS查询验证是否能访问互联网
   - 首先尝试连接 `www.baidu.com`
   - 如果失败，尝试连接 `8.8.8.8` (Google DNS)
3. **超时控制**: 设置合理的超时时间避免长时间等待

### 错误处理

- 网络检测失败时返回 `false`
- 记录详细的错误日志
- 在同步服务中优雅地跳过同步操作

## 配置说明

### 依赖项

在 `pubspec.yaml` 中添加了以下依赖：

```yaml
dependencies:
  connectivity_plus: ^6.0.5  # 网络连接检测
```

### 权限要求

- **Android**: 需要 `INTERNET` 权限（通常已包含）
- **iOS**: 无需额外权限
- **macOS**: 无需额外权限
- **Windows**: 无需额外权限

## 测试

网络检测功能包含完整的单元测试：

```bash
flutter test test/network_util_test.dart
```

测试覆盖：
- 网络连接检测
- 连接类型获取
- 状态变化监听
- 资源清理

## 注意事项

1. **测试环境**: 在测试环境中，某些网络检测功能可能无法正常工作，这是正常现象
2. **性能影响**: 网络检测会进行DNS查询，但设置了合理的超时时间，影响很小
3. **电池优化**: 网络检测不会持续运行，只在需要时进行检测
4. **错误恢复**: 网络检测失败时会记录日志，但不会影响应用的正常运行

## 日志输出

网络检测功能会输出详细的日志信息：

- `🌐 网络连接检测：无网络连接`
- `🌐 网络连接检测：有网络但无法访问互联网`
- `🌐 网络连接检测：网络连接正常`
- `🌐 网络连接不可用，跳过同步操作`

这些日志有助于调试和监控网络状态。
