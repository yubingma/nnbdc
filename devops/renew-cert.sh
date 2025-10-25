#!/bin/bash
# SSL证书自动续期脚本 - 零停机方案
# 适配 Docker 容器化部署

# 设置 PATH 环境变量（crontab 环境中可能不包含 /usr/bin）
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

NGINX_CONTAINER="nginx"
WEBROOT_HOST="/var/www/html"  # 宿主机 webroot 目录（映射到容器的 /usr/share/nginx/html）

echo "开始证书续期（零停机模式）: $(date)"

# 确保验证目录存在（在宿主机上）
mkdir -p $WEBROOT_HOST/.well-known/acme-challenge

# 使用 webroot 模式续期所有证书（nginx 无需停止）
# 注意：webroot 路径使用宿主机路径，因为 volume 挂载的是 /var/www/html
docker run --rm \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    -v $WEBROOT_HOST:/webroot \
    certbot/certbot renew \
    --webroot -w /webroot

# 重载nginx配置以应用新证书
docker exec $NGINX_CONTAINER nginx -s reload

echo "证书续期完成（服务未中断）: $(date)"

