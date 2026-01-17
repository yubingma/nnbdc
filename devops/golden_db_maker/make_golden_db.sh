#!/bin/bash

# 设置脚本发生错误时立即退出
set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 计算项目根目录 (假设脚本在 devops/golden_db_maker)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
# 定义最终输出目录
APP_ASSETS_DB_DIR="$PROJECT_ROOT/app/assets/db"
# 定义 SQL 清理脚本位置
SQL_SCRIPT="$SCRIPT_DIR/clean_db.sql"

# 默认的源数据库路径 (macOS Flutter Desktop Debug 版通常在此)
# 注意：路径可能因沙盒配置不同而变化，这里预设为用户已知的默认路径
DEFAULT_SOURCE_DB="/Users/myb/Library/Containers/com.nn.nnbdc.nnbdc/Data/Documents/db.sqlite"
ALTERNATE_SOURCE_DB="$HOME/Documents/db.sqlite"

# 检查是否提供了参数，否则优先使用 DEFAULT_SOURCE_DB，其次尝试 ALTERNATE
if [ "$#" -ge 1 ]; then
    SOURCE_DB="$1"
else
    if [ -f "$DEFAULT_SOURCE_DB" ]; then
        SOURCE_DB="$DEFAULT_SOURCE_DB"
    elif [ -f "$ALTERNATE_SOURCE_DB" ]; then
        SOURCE_DB="$ALTERNATE_SOURCE_DB"
    else
        # 都不存在，则保持 DEFAULT 以便报错信息明确，或者提示用户
        SOURCE_DB="$DEFAULT_SOURCE_DB"
    fi
fi

echo "🚀 开始制作黄金母版数据库..."
echo "📂 源数据库路径: $SOURCE_DB"

# 检查源文件是否存在
if [ ! -f "$SOURCE_DB" ]; then
    echo "❌ 错误: 源数据库文件 '$SOURCE_DB' 不存在。"
    echo "💡 提示: 请确保应用已运行过。如果是 Android 模拟器，请先通过 adb 导出数据库。"
    echo "   或者您可以手动指定路径: $0 <path_to_db_sqlite>"
    exit 1
fi

# 检查 SQL 脚本是否存在
if [ ! -f "$SQL_SCRIPT" ]; then
    echo "❌ 错误: 清理脚本 '$SQL_SCRIPT' 不存在。"
    exit 1
fi

# 创建临时工作目录 (避免污染当前目录)
WORK_DIR=$(mktemp -d)
echo "🔧 创建临时工作目录: $WORK_DIR"

# 注册清理函数，确保脚本退出时删除临时目录
cleanup() {
    echo "🧹 清理临时文件..."
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# 定义临时目标文件
TEMP_TARGET_DB="$WORK_DIR/initial.sqlite"

# 1. 复制源数据库到临时目录
echo "📋 正在复制数据库..."
cp "$SOURCE_DB" "$TEMP_TARGET_DB"

# 2. 执行清理 SQL
echo "🛁 正在清理用户数据..."
sqlite3 "$TEMP_TARGET_DB" < "$SQL_SCRIPT"

if [ $? -ne 0 ]; then
    echo "❌ 数据库清理失败"
    exit 1
fi

# 3. 结果验证：执行 VACUUM 以最大限度减小体积
echo "🗜️  正在压缩数据库 (VACUUM)..."
sqlite3 "$TEMP_TARGET_DB" "VACUUM;"

# 4. 确保输出目录存在
# 如果目标路径存在但不是目录（可能是之前没加斜杠导致的误操作），先删除
if [ -e "$APP_ASSETS_DB_DIR" ] && [ ! -d "$APP_ASSETS_DB_DIR" ]; then
    echo "⚠️  发现目标路径被文件占用: $APP_ASSETS_DB_DIR"
    echo "🗑️  正在清理该文件以创建目录..."
    rm -f "$APP_ASSETS_DB_DIR"
fi

if [ ! -d "$APP_ASSETS_DB_DIR" ]; then
    echo "📂 创建目标目录: $APP_ASSETS_DB_DIR"
    mkdir -p "$APP_ASSETS_DB_DIR"
fi

# 5. 移动到最终目标目录 (强制覆盖)
echo "打包部署..."
FINAL_DB_PATH="$APP_ASSETS_DB_DIR/initial.sqlite"
mv -f "$TEMP_TARGET_DB" "$FINAL_DB_PATH"

# 6. 打印结果
FILE_SIZE=$(ls -lh "$FINAL_DB_PATH" | awk '{print $5}')
echo "✅ 成功！黄金母版已更新至: $FINAL_DB_PATH"
echo "📊 文件大小: $FILE_SIZE"
echo "👉 请确保在 app/pubspec.yaml 中已注册: - assets/db/initial.sqlite"
