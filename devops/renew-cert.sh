#!/bin/bash
# NBDC SSL 证书全自动续期与同步脚本
#   back.nnbdc.com           ：certbot 文件校验。校验请求直连源站 80 端口，境外可达，实测可自动续。
#   nnbdc.com + www.nnbdc.com：acme.sh DNS 校验。只往阿里云云解析写一条 TXT 记录，
#                              不依赖任何外部节点访问 www 或源站。
#
# 为什么 www 这张不能用文件校验：www.nnbdc.com 的 HTTPS 终结在阿里云 CDN（加速区域仅中国内地，
# 源站 47.108.27.205:80）。Let's Encrypt 的域名校验会从多个地理位置各查一遍，境外那几路到
# CDN 节点会超时，只要 www 这一项不过，整张证书就签不下来（2026-10-13 干跑实测）。
# 详见 .agents/skills/nnbdc-ssl-renewal/SKILL.md

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

NGINX_CONTAINER="nginx"
WEBROOT_HOST="/var/www/html"
ACME_SH="/root/.acme.sh/acme.sh"
CREDS="/root/.aliyun_dns_creds"

echo "=========================================="
echo "开始自动续期任务: $(date)"

# 1. 确保 back.nnbdc.com 的文件校验目录存在
mkdir -p $WEBROOT_HOST/.well-known/acme-challenge

# 2. back.nnbdc.com：certbot 文件校验
#    这里不再传 --webroot，让每条 renewal 配置用自己保存的校验方式
#    （nnbdc.com 那条已停用，见 /etc/letsencrypt/renewal/nnbdc.com.conf.disabled-20261013）
echo "[步骤1/3] certbot 检查/续签 back.nnbdc.com..."
if ! docker run --rm \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    -v $WEBROOT_HOST:/webroot \
    certbot/certbot renew \
    --non-interactive \
    --agree-tos
then
    echo "[错误] certbot 证书续签失败！"
    exit 1
fi

# 3. 让本地 Nginx 应用新证书
echo "[步骤2/3] 正在重载本地 Nginx..."
if ! docker exec $NGINX_CONTAINER nginx -s reload; then
    echo "[错误] 本地 Nginx 重载失败！"
    exit 1
fi

# 4. nnbdc.com + www.nnbdc.com：acme.sh DNS 校验
#    真正续期成功时，acme.sh 会自动执行 /root/deploy-nnbdc-cert.sh：
#    写入 /etc/letsencrypt/archive 新版本 → 切换 live 软链 → 重载 nginx → 上传证书到 CDN
echo "[步骤3/3] acme.sh 检查/续签 nnbdc.com + www.nnbdc.com（DNS 校验）..."
. $CREDS
if ! $ACME_SH --cron --home /root/.acme.sh; then
    echo "[错误] acme.sh 证书续签失败！"
    exit 1
fi

echo "任务圆满完成: $(date)"
echo "=========================================="
