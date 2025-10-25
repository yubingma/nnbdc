# macOS 平台构建和分发

## 📁 文件说明

- 通过 App Store 分发
- 使用 Xcode 上传到 App Store Connect

## 🚀 使用方法

### 本地构建
```bash
# 1. 构建 Flutter 应用
cd app
flutter build macos --release

# 2. 使用 Xcode 打包
open app/macos/Runner.xcworkspace
# 在 Xcode 中：
# - 选择 "Any Mac (Apple Silicon)" 或 "Any Mac (Intel)"
# - Product → Archive
# - 上传到 App Store Connect
```

### GitHub Actions 构建
- 自动构建 macOS 应用
- 生成 `nnbdc-macos-appstore.zip`
- 用于 Xcode 上传

## 📦 输出文件

- `nnbdc-macos-appstore.zip` - App Store 版本
- 需要通过 Xcode 上传到 App Store Connect

## 🔧 技术特性

- App Store 分发
- 自动更新（通过 App Store）
- 符合苹果政策
- 用户信任度高
