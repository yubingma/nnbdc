#!/bin/bash
# sync_prod_to_local.sh
# 作用: 自动备份远程生产环境的 PostgreSQL 数据库，并拉取至本地导入到本地 PostgreSQL 数据库中。
# 使用说明: 本脚本在本地执行。

# 设置发生错误时立即退出
set -e

# 解析参数支持非交互模式
AUTO_CONFIRM=false
if [ "$1" = "-y" ] || [ "$1" = "--yes" ]; then
    AUTO_CONFIRM=true
fi

# 本地数据库配置（读取环境变量，若无则使用默认值）
LOCAL_DB_HOST="${db_host:-127.0.0.1}"
LOCAL_DB_PORT="${db_port:-5432}"
LOCAL_DB_NAME="${db:-bdc}"
LOCAL_DB_USER="${db_username:-myb}"
LOCAL_DB_PASSWORD="${db_password:-myb}"

# 远程服务器配置
REMOTE_HOST="47.108.27.205"
REMOTE_USER="root"
REMOTE_PORT="22"

# 检查远程服务器连接所需的密码环境变量
if [ -z "$nnbdc_server_pwd" ]; then
    echo "❌ 错误: 未检测到环境变量 nnbdc_server_pwd，请先设置生产服务器密码。"
    exit 1
fi

# 检查本地是否安装了 sshpass
if ! command -v sshpass &> /dev/null; then
    echo "❌ 错误: 本地未安装 sshpass，请使用 'brew install sshpass' 安装后再运行此脚本。"
    exit 1
fi

# 临时备份文件路径 (本地)
TEMP_BACKUP_FILE="/tmp/prod_bdc_backup_$(date +%Y%m%d_%H%M%S).sql.gz"

echo "============================================="
echo "🔄 开始从生产环境同步数据库到本地..."
echo "📍 生产服务器: $REMOTE_USER@$REMOTE_HOST"
echo "📍 本地目标库: $LOCAL_DB_NAME ($LOCAL_DB_USER@$LOCAL_DB_HOST:$LOCAL_DB_PORT)"
echo "============================================="

# 第一步：在生产环境备份数据库，并通过管道压缩后传输到本地
echo "1️⃣ 正在备份生产环境数据库并传输到本地..."

if command -v pv &> /dev/null; then
    echo "🧪 [DEBUG] 正在使用 [pv] 进度条分支执行备份..."
    sshpass -p "$nnbdc_server_pwd" ssh -o StrictHostKeyChecking=no -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" \
        'docker exec -i pg pg_dump --exclude-table-data=sys_db_log --exclude-table-data=word_embedding --exclude-table-data=user_db_log\* -Umyb bdc | gzip' | pv > "$TEMP_BACKUP_FILE"
elif dd status=progress < /dev/null &> /dev/null; then
    echo "💡 提示: 安装 'pv' 可以显示更精美的进度 (brew install pv)"
    echo "🧪 [DEBUG] 正在使用 [dd] 进度条分支执行备份..."
    sshpass -p "$nnbdc_server_pwd" ssh -o StrictHostKeyChecking=no -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" \
        'docker exec -i pg pg_dump --exclude-table-data=sys_db_log --exclude-table-data=word_embedding --exclude-table-data=user_db_log\* -Umyb bdc | gzip' | dd status=progress > "$TEMP_BACKUP_FILE"
else
    echo "🧪 [DEBUG] 正在使用 [无进度条] 分支执行备份..."
    sshpass -p "$nnbdc_server_pwd" ssh -o StrictHostKeyChecking=no -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" \
        'docker exec -i pg pg_dump --exclude-table-data=sys_db_log --exclude-table-data=word_embedding --exclude-table-data=user_db_log\* -Umyb bdc | gzip' > "$TEMP_BACKUP_FILE"
fi

if [ ! -f "$TEMP_BACKUP_FILE" ] || [ ! -s "$TEMP_BACKUP_FILE" ]; then
    echo "❌ 备份传输失败，生成的文件为空。"
    exit 1
fi

echo "✅ 备份下载成功，临时文件: $TEMP_BACKUP_FILE"

# 第二步：提示用户是否清空本地数据库再导入
echo "---------------------------------------------"
if [ "$AUTO_CONFIRM" = "true" ]; then
    CONFIRM="y"
else
    read -p "⚠️ 是否【重建】本地数据库 '$LOCAL_DB_NAME' (清空所有本地数据)？ (y/n): " CONFIRM
fi

export PGPASSWORD="$LOCAL_DB_PASSWORD"

if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
    echo "2️⃣ 正在重建本地数据库..."
    
    # 终止现有的连接以防止删除数据库失败
    # 使用 dropdb --force 可以强行删除被占用的数据库，如果 pg 版本较低不支持 --force，则使用 SQL 强杀连接作为备用
    if dropdb -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" --if-exists --force "$LOCAL_DB_NAME" 2>/dev/null; then
        echo "✅ 本地数据库 '$LOCAL_DB_NAME' 已强行重置(使用 --force)。"
    else
        # 降级备用方案：先杀连接，再普通删除
        psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d postgres -c \
            "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$LOCAL_DB_NAME' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
        dropdb -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" --if-exists "$LOCAL_DB_NAME"
        echo "✅ 本地数据库 '$LOCAL_DB_NAME' 已重置。"
    fi
    createdb -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" "$LOCAL_DB_NAME"
else
    echo "2️⃣ 跳过数据库重建，将直接进行覆盖导入..."
fi

# 第三步：导入备份数据到本地
echo "3️⃣ 正在导入数据到本地数据库..."
gunzip -c "$TEMP_BACKUP_FILE" | psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME"

echo "✅ 数据导入成功！"

# 第四步：自动修正本机的特殊配置
echo "4️⃣ 正在自动修正本机特殊配置 (imgBaseDir)..."
psql -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -c \
    "UPDATE sys_param SET param_value = '/opt/homebrew/opt/nginx/html/img', update_time = CURRENT_TIMESTAMP WHERE param_name = 'imgBaseDir';"
echo "✅ 本机特殊配置修正成功。"

# 第五步：清理临时文件
rm -f "$TEMP_BACKUP_FILE"
echo "🧹 临时备份文件已清理。"
echo "============================================="
echo "🎉 数据库同步完成！"
