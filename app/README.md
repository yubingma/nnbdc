# 泡泡单词 (NNBDC)

一款智能背单词 Flutter 应用。

## 平台支持

本应用支持以下平台：

- ✅ **Android** - 完整支持
- ✅ **iOS** - 完整支持  
- ✅ **Windows** - 桌面版支持（部分功能有限）
- ✅ **macOS** - 桌面版支持（部分功能有限） 
- 🌐 **Web** - 部分支持

## 快速开始

### 前提条件

- Flutter SDK 3.4.0 或更高版本
- Dart SDK 3.4.0 或更高版本

### 安装依赖

```bash
flutter pub get
```

### 运行应用

#### Android/iOS
```bash
flutter run
```

#### Windows 桌面版
```bash
flutter run -d windows
```

#### macOS 桌面版
```bash
flutter run -d macos
```

详细的构建说明：
- [Windows 构建指南](WINDOWS_BUILD_GUIDE.md)
- [macOS 构建指南](MACOS_BUILD_GUIDE.md)

## 构建发布版本

### Android
```bash
flutter build apk --release
# 或构建 App Bundle
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

### Windows
```bash
flutter build windows --release
```

### macOS
```bash
flutter build macos --release
```

## 主要功能

- 📚 多词库支持（高考、CET4/6、TOEFL、GRE 等）
- 🎯 智能背单词算法
- 🎮 游戏化学习体验
- 🔊 TTS 语音朗读
- 🎤 语音识别练习（移动端）
- 📊 学习进度统计
- 🌓 深色/浅色主题切换
- 💾 本地数据库存储
- 🔄 数据同步

## 项目结构

```
lib/
├── api/          # API 接口定义
├── db/           # 数据库相关
├── page/         # 页面组件
├── util/         # 工具类
├── widget/       # 自定义组件
└── main.dart     # 应用入口
```

## 技术栈

- **Flutter** - 跨平台 UI 框架
- **Drift** - 类型安全的 SQLite ORM
- **GetX** - 状态管理和路由
- **Dio** - 网络请求
- **Socket.IO** - 实时通信
- **Flutter TTS** - 文本转语音
- **Audioplayers** - 音频播放

## 开发

### 代码生成

项目使用代码生成器，修改数据库模型或 API 定义后需要运行：

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 代码分析

```bash
flutter analyze
```

### 运行测试

```bash
flutter test
```

## 文档

- [Windows 构建指南](WINDOWS_BUILD_GUIDE.md)
- [macOS 构建指南](MACOS_BUILD_GUIDE.md)
- [数据库外键说明](DATABASE_FOREIGN_KEYS.md)
- [错误处理示例](ERROR_HANDLER_EXAMPLES.md)
- [主题更新总结](THEME_UPDATE_SUMMARY.md)
- [代码改进建议](CODE_IMPROVEMENTS.md)

## 许可证

本项目为私有项目。

## 相关链接

- [Flutter 官方文档](https://flutter.dev/docs)
- [Dart 语言文档](https://dart.dev/guides)
