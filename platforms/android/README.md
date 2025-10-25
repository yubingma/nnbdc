# Android 平台构建和分发

## 📁 文件说明

- 通过 Google Play Store 分发
- 或直接 APK 安装

## 🚀 使用方法

### 本地构建
```bash
# 1. 构建 Flutter 应用
cd app
flutter build apk --release

# 2. 输出文件
# app/build/app/outputs/flutter-apk/app-release.apk
```

### GitHub Actions 构建
- 自动构建 Android APK
- 生成 `nnbdc-android.apk`
- 支持直接安装

## 📦 输出文件

- `nnbdc-android.apk` - Android 安装包
- 支持直接安装
- 支持自更新

## 🔧 技术特性

- APK 格式
- 支持自更新
- 兼容 Android 5.0+
- 可通过应用内更新
