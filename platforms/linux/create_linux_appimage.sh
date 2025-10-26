#!/bin/bash
# Linux AppImage 创建脚本

set -e

echo "[INFO] ======== 创建 Linux AppImage ========"

# 检查 Flutter 构建文件是否存在
# 尝试多个可能的路径
BUNDLE_PATH=""
if [ -d "../../app/build/linux/x64/release/bundle" ]; then
    BUNDLE_PATH="../../app/build/linux/x64/release/bundle"
elif [ -d "app/build/linux/x64/release/bundle" ]; then
    BUNDLE_PATH="app/build/linux/x64/release/bundle"
elif [ -d "build/linux/x64/release/bundle" ]; then
    BUNDLE_PATH="build/linux/x64/release/bundle"
else
    echo "[ERROR] Flutter Linux 构建文件不存在"
    echo "请先运行: cd app && flutter build linux --release"
    echo "当前目录: $(pwd)"
    echo "检查构建目录结构:"
    echo "检查 ../../app/build/linux/x64/release/:"
    ls -la ../../app/build/linux/x64/release/ 2>/dev/null || echo "release 目录不存在"
    echo "检查 app/build/linux/x64/release/:"
    ls -la app/build/linux/x64/release/ 2>/dev/null || echo "release 目录不存在"
    echo "检查 build/linux/x64/release/:"
    ls -la build/linux/x64/release/ 2>/dev/null || echo "release 目录不存在"
    exit 1
fi

echo "[INFO] 找到 Flutter Linux 构建文件"
echo "[INFO] 构建文件位置: $BUNDLE_PATH"
ls -la "$BUNDLE_PATH/"

# 创建临时目录
TEMP_DIR="$(pwd)/appimage_temp"
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi
mkdir -p "$TEMP_DIR"

echo "[INFO] 准备 AppImage 内容..."

# 复制应用文件
cp -r "$BUNDLE_PATH"/* "$TEMP_DIR/"

# 查找应用图标（可能在 data/flutter_assets/assets/images/ 或其他位置）
ICON_COPIED=false
for icon_search_path in "$TEMP_DIR/data/flutter_assets/assets/images/logo.png" "$TEMP_DIR/data/flutter_assets/logo.png" "$TEMP_DIR/logo.png"; do
    if [ -f "$icon_search_path" ]; then
        cp "$icon_search_path" "$TEMP_DIR/nnbdc.png"
        echo "[INFO] 复制图标: $icon_search_path -> nnbdc.png"
        ICON_COPIED=true
        break
    fi
done

# 如果未找到，尝试从项目目录查找
if [ "$ICON_COPIED" = false ]; then
    for logo_path in "../../app/assets/images/logo.png" "../app/assets/images/logo.png" "app/assets/images/logo.png"; do
        if [ -f "$logo_path" ]; then
            cp "$logo_path" "$TEMP_DIR/nnbdc.png"
            echo "[INFO] 复制图标: $logo_path -> nnbdc.png"
            ICON_COPIED=true
            break
        fi
    done
fi

# 如果还是未找到，创建一个简单的占位图标
if [ "$ICON_COPIED" = false ]; then
    echo "[WARN] 未找到应用图标，创建占位图标"
    if command -v convert >/dev/null 2>&1; then
        convert -size 256x256 xc:white -pointsize 72 -fill black -gravity center -annotate +0+0 "N" "$TEMP_DIR/nnbdc.png" 2>/dev/null || true
    fi
fi

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
