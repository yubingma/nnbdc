#!/bin/bash
# NBDC SSL 证书全自动续期与同步脚本

# 确保能找到 aliyun 命令
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

NGINX_CONTAINER="nginx"
WEBROOT_HOST="/var/www/html"

echo "=========================================="
echo "开始自动续期任务: $(date)"

# 1. 确保验证目录存在
mkdir -p $WEBROOT_HOST/.well-known/acme-challenge

# 2. 在 Docker 中执行证书续签
# 优化点 1：增加 --non-interactive 和 --agree-tos 参数，防止在无交互环境或出错时后台挂起死锁
echo "[步骤1/3] 正在通过 Docker 检查/续签证书..."
docker run --rm \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    -v $WEBROOT_HOST:/webroot \
    certbot/certbot renew \
    --webroot -w /webroot \
    --non-interactive \
    --agree-tos

# 优化点 2：添加退出状态码校验。若续签失败，则不应盲目重载 Nginx 并强行触发 CDN 同步
if [ $? -ne 0 ]; then
    echo "[错误] Certbot 证书续签失败！请检查网络或 CDN 回源规则配置。"
    exit 1
fi

# 3. 让本地 Nginx 应用新证书
echo "[步骤2/3] 正在重载本地 Nginx..."
if ! docker exec $NGINX_CONTAINER nginx -s reload; then
    echo "[错误] 本地 Nginx 重载失败！"
    exit 1
fi

# 4. 在宿主机手动触发同步到 CDN
echo "[步骤3/3] 正在同步证书到阿里云 CDN (宿主机模式)..."
if [ -f "/etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh" ]; then
    # 直接在宿主机环境运行同步脚本
    sh /etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh
    if [ $? -ne 0 ]; then
        echo "[错误] 同步证书到阿里云 CDN 失败！"
        exit 1
    fi
else
    echo "[错误] 未找到同步脚本: /etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh"
    exit 1
fi

echo "任务圆满完成: $(date)"
echo "=========================================="
