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

# 检查源文件是否存在
if [ ! -f "$SOURCE_DB" ]; then
    echo "❌ 错误: 源数据库文件 '$SOURCE_DB' 不存在。"
    echo "💡 提示: 请确保在 App 中已成功完成'制作黄金母版'操作。"
    exit 1
fi

# 确保输出目录存在
mkdir -p "$APP_ASSETS_DB_DIR"

# 定义目标文件
FINAL_DB_PATH="$APP_ASSETS_DB_DIR/initial.sqlite"

# 复制并压缩数据库
echo "🗜️  正在同步并压缩数据库 (VACUUM)..."
# 使用临时文件处理，避免直接操作源文件（虽然 App 已退出，但养成好习惯）
WORK_DIR=$(mktemp -d)
TEMP_DB="$WORK_DIR/temp.sqlite"
cp "$SOURCE_DB" "$TEMP_DB"
sqlite3 "$TEMP_DB" "VACUUM;"

# 部署
mv -f "$TEMP_DB" "$FINAL_DB_PATH"
rm -rf "$WORK_DIR"

# 打印结果
FILE_SIZE=$(ls -lh "$FINAL_DB_PATH" | awk '{print $5}')
echo "✅ 成功！黄金母版已部署至: $FINAL_DB_PATH"
echo "📊 最终大小: $FILE_SIZE"
echo "👉 请提交更改并重新构建 App。"
