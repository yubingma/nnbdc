#!/bin/bash

# 设置脚本发生错误时立即退出
set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 计算项目根目录
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
# 定义最终输出目录
APP_ASSETS_DB_DIR="$PROJECT_ROOT/app/assets/db"

# 默认的源数据库路径 (macOS Flutter Desktop Debug 版)
DEFAULT_SOURCE_DB="/Users/myb/Library/Containers/com.nn.nnbdc.nnbdc/Data/Documents/db.sqlite"

# 检查是否提供了参数
if [ "$#" -ge 1 ]; then
    SOURCE_DB="$1"
else
    SOURCE_DB="$DEFAULT_SOURCE_DB"
fi

echo "🚀 部署黄金母版数据库..."
echo "📂 源数据库路径: $SOURCE_DB"

# 检测对应的 gz 压缩文件与未压缩文件
if [ "${SOURCE_DB##*.}" = "gz" ]; then
    SOURCE_GZ="$SOURCE_DB"
    SOURCE_UNCOMPRESSED="${SOURCE_DB%.gz}"
else
    SOURCE_UNCOMPRESSED="$SOURCE_DB"
    SOURCE_GZ="${SOURCE_DB}.gz"
fi

# 检查源文件是否存在
if [ ! -f "$SOURCE_UNCOMPRESSED" ] && [ ! -f "$SOURCE_GZ" ]; then
    echo "❌ 错误: 源数据库文件均不存在 (检查了 '$SOURCE_UNCOMPRESSED' 和 '$SOURCE_GZ')。"
    echo "💡 提示: 请确保在 App 中已成功完成'制作黄金母版'操作。"
    exit 1
fi

# 确保输出目录存在
mkdir -p "$APP_ASSETS_DB_DIR"

# 定义目标文件
FINAL_DB_PATH="$APP_ASSETS_DB_DIR/initial.sqlite.gz"
OLD_DB_PATH="$APP_ASSETS_DB_DIR/initial.sqlite"

# 复制并部署数据库
if [ -f "$SOURCE_GZ" ]; then
    echo "📦 发现 App 已生成的 Gzip 压缩包，直接进行同步部署..."
    cp "$SOURCE_GZ" "$FINAL_DB_PATH"
else
    echo "⚠️ 未发现 App 已生成的压缩包，将在本地进行 Gzip 压缩部署..."
    gzip -c "$SOURCE_UNCOMPRESSED" > "$FINAL_DB_PATH"
fi

# 清理旧的未压缩文件，避免残留无用的大文件
if [ -f "$OLD_DB_PATH" ]; then
    rm "$OLD_DB_PATH"
fi

# 打印结果
FILE_SIZE=$(ls -lh "$FINAL_DB_PATH" | awk '{print $5}')
GZ_SHA256=$(shasum -a 256 "$FINAL_DB_PATH" | awk '{print $1}')

if [ -f "$SOURCE_UNCOMPRESSED" ]; then
    ORIG_SIZE=$(ls -lh "$SOURCE_UNCOMPRESSED" | awk '{print $5}')
    ORIG_SHA256=$(shasum -a 256 "$SOURCE_UNCOMPRESSED" | awk '{print $1}')
    echo "✅ 成功！黄金母版已部署并压缩至: $FINAL_DB_PATH"
    echo "📊 原始大小: $ORIG_SIZE | 压缩后大小: $FILE_SIZE"
    echo "🔒 原始 SHA-256 (与 App 的 'SHA-256' 行核对): $ORIG_SHA256"
    echo "🔒 Gzip SHA-256 (与 App 的 'Gzip 压缩包 SHA-256' 行核对): $GZ_SHA256"
else
    echo "✅ 成功！黄金母版已部署并压缩至: $FINAL_DB_PATH"
    echo "📊 压缩后大小: $FILE_SIZE"
    echo "🔒 Gzip SHA-256 (与 App 的 'Gzip 压缩包 SHA-256' 行核对): $GZ_SHA256"
fi
echo "👉 请确认此校验码与 App 界面中显示的一致。"
