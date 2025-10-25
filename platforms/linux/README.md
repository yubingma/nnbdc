# Linux 平台构建和分发

## 📁 文件说明

- `create_linux_appimage.sh` - AppImage 创建脚本

## 🚀 使用方法

### 本地构建
```bash
# 1. 构建 Flutter 应用
cd app
flutter build linux --release

# 2. 创建 AppImage
cd ../platforms/linux
chmod +x create_linux_appimage.sh
./create_linux_appimage.sh
```

### GitHub Actions 构建
- 自动构建 Linux AppImage
- 生成 `nnbdc-linux.AppImage`
- 单文件便携运行

## 📦 输出文件

- `nnbdc-linux.AppImage` - Linux 便携应用
- 单文件运行，无需安装
- 支持自更新

## 🔧 技术特性

- AppImage 格式
- 便携运行
- 自包含依赖
- 支持自更新
