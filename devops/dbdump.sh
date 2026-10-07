#!/bin/bash
# 使用 Docker 容器内的 pg_dump 命令进行 PostgreSQL 数据库备份
# 容器名: pg
# 备份文件压缩后输出到宿主机: /var/nnbdc/dbdump/
# 每次备份后只保留最新的 2 个备份（含本次产生的备份）

set -o pipefail

DUMP_DIR=/var/nnbdc/dbdump
BACKUP_FILE="$DUMP_DIR/bdc_$(date +%Y%m%d-%H%M%S).sql.gz"

# 确保备份目录存在
mkdir -p "$DUMP_DIR"

# 使用容器内的 pg_dump 命令，gzip 压缩后输出到宿主机
if ! docker exec pg pg_dump -Umyb bdc | gzip > "$BACKUP_FILE"; then
    # 备份失败：删掉残缺文件，保留已有备份，直接报错退出
    rm -f "$BACKUP_FILE"
    echo "备份失败: $BACKUP_FILE" >&2
    exit 1
fi

# 只保留最新的 2 个备份，删除更早的
ls -1t "$DUMP_DIR"/bdc_*.sql* | tail -n +3 | while read -r f; do
    rm -f "$f"
done
