#!/bin/bash
# Linux AppImage 创建脚本

set -e

echo "[INFO] ======== 创建 Linux AppImage ========"

# 检查 Flutter 构建文件是否存在
if [ ! -d "../../app/build/linux/x64/release/bundle" ]; then
    echo "[ERROR] Flutter Linux 构建文件不存在"
    echo "请先运行: cd ../../app && flutter build linux --release"
    exit 1
fi

# 创建临时目录
TEMP_DIR="$(pwd)/appimage_temp"
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi
mkdir -p "$TEMP_DIR"

echo "[INFO] 准备 AppImage 内容..."

# 复制应用文件
cp -r "../../app/build/linux/x64/release/bundle"/* "$TEMP_DIR/"

# 创建 AppImage 描述文件
cat > "$TEMP_DIR/nnbdc.desktop" << EOF
[Desktop Entry]
Name=泡泡单词
Comment=智能背单词应用
Exec=nnbdc
Icon=nnbdc
Type=Application
Categories=Education;
StartupWMClass=nnbdc
EOF

# 创建 AppImage 图标（如果有的话）
if [ -f "../../app/assets/images/logo.png" ]; then
    cp "../../app/assets/images/logo.png" "$TEMP_DIR/nnbdc.png"
fi

# 下载 AppImageTool（如果不存在）
APPIMAGE_TOOL="appimagetool-x86_64.AppImage"
if [ ! -f "$APPIMAGE_TOOL" ]; then
    echo "[INFO] 下载 AppImageTool..."
    wget -O "$APPIMAGE_TOOL" "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGE_TOOL"
fi

# 创建 AppImage
APPIMAGE_NAME="nnbdc-linux.AppImage"
echo "[INFO] 创建 AppImage..."
./"$APPIMAGE_TOOL" "$TEMP_DIR" "$APPIMAGE_NAME"

if [ -f "$APPIMAGE_NAME" ]; then
    echo "[INFO] AppImage 创建成功: $APPIMAGE_NAME"
    echo "[INFO] 文件大小: $(du -h "$APPIMAGE_NAME" | cut -f1)"
    
    # 设置执行权限
    chmod +x "$APPIMAGE_NAME"
else
    echo "[ERROR] AppImage 创建失败"
    exit 1
fi

# 清理临时文件
rm -rf "$TEMP_DIR"

echo "[INFO] Linux AppImage 创建完成"
echo "[INFO] 文件位置: $(pwd)/$APPIMAGE_NAME"
