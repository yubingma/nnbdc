#!/bin/bash
# 使用 Docker 容器内的 psql 命令进行数据库还原
# 容器名: pg
# 备份文件路径从宿主机传入容器

# 检查参数
if [ $# -eq 0 ]; then
    echo "用法: $0 <备份文件路径>"
    echo "示例: $0 /var/nnbdc/dbdump/bdc_20241218-123456.sql"
    exit 1
fi

BACKUP_FILE="$1"
DB_NAME="bdc"
DB_USER="myb"

# 检查备份文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    echo "错误: 备份文件不存在: $BACKUP_FILE"
    exit 1
fi

echo "开始还原数据库..."
echo "备份文件: $BACKUP_FILE"
echo "目标数据库: $DB_NAME"

# 检查数据库是否存在，如果不存在则创建
DB_EXISTS=$(docker exec pg psql -U$DB_USER -lqt | cut -d \| -f 1 | grep -w $DB_NAME | wc -l)

if [ "$DB_EXISTS" -eq 0 ]; then
    echo "数据库 $DB_NAME 不存在，正在创建..."
    docker exec pg psql -U$DB_USER -d postgres -c "CREATE DATABASE $DB_NAME;"
    if [ $? -ne 0 ]; then
        echo "错误: 创建数据库失败"
        exit 1
    fi
    echo "数据库 $DB_NAME 创建成功"
else
    echo "数据库 $DB_NAME 已存在"
fi

# 使用容器内的 psql 命令，从宿主机文件读取并执行
cat "$BACKUP_FILE" | docker exec -i pg psql -U$DB_USER $DB_NAME

if [ $? -eq 0 ]; then
    echo "数据库还原完成"
else
    echo "数据库还原失败"
    exit 1
fi






