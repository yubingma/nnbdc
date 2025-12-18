#!/bin/bash
# 使用 Docker 容器内的 pg_dump 命令进行数据库备份
# 容器名: pg
# 备份文件输出到宿主机: /var/nnbdc/dbdump/

# 确保备份目录存在
mkdir -p /var/nnbdc/dbdump

# 使用容器内的 pg_dump 命令，输出重定向到宿主机
docker exec pg pg_dump -Umyb bdc > /var/nnbdc/dbdump/bdc_$(date +%Y%m%d-%H%M%S).sql
