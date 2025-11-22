# Windows 平台构建和分发

## 📁 文件说明

- `installer.nsi` - NSIS 安装脚本
- `create_installer.bat` - 本地构建脚本

## 🚀 使用方法

### 本地构建
```bash
# 1. 构建 Flutter 应用
cd app
flutter build windows --release

# 2. 创建安装包
cd ../platforms/windows
create_installer.bat
```

### GitHub Actions 构建
- 自动构建 Windows 安装包
- 生成 `nnbdc-setup.exe` 并打包为 `nnbdc-windows.zip`
- 包含 Visual C++ Redistributable

## 📦 输出文件

- `nnbdc-windows.zip` - Windows 安装包（zip 格式，避免浏览器警告）
  - 解压后包含 `nnbdc-setup.exe` 安装程序
- 支持升级安装
- 自动安装 Visual C++ Redistributable

## 🔧 技术特性

- NSIS 安装程序
- 静态链接运行时库
- 开始菜单和桌面快捷方式
- 完整的卸载程序
