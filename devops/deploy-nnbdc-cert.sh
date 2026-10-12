#!/bin/bash
# 把 acme.sh 刚签下来的 nnbdc.com（含 www.nnbdc.com）证书部署上线。
# 由 acme.sh 的 --reloadcmd 调用，只在新证书真正签下来之后执行：
#   写入 /etc/letsencrypt/archive/nnbdc.com 的下一个版本号 → 切换 live 软链 → 重载 nginx → 上传证书到阿里云 CDN
# 回滚：把 /etc/letsencrypt/live/nnbdc.com/*.pem 四个软链指回上一个版本号，再 docker exec nginx nginx -s reload

set -euo pipefail

ACME_HOME=/root/.acme.sh/nnbdc.com
ARCHIVE=/etc/letsencrypt/archive/nnbdc.com
LIVE=/etc/letsencrypt/live/nnbdc.com
CREDS=/root/.aliyun_dns_creds
CDN_DOMAIN=www.nnbdc.com

log() { echo "[$(date '+%F %T')] $*"; }

# 1. 确认 acme.sh 的产物齐全（缺文件就立刻报错，不部署半张证书）
for f in fullchain.cer nnbdc.com.cer ca.cer nnbdc.com.key; do
    [ -s "$ACME_HOME/$f" ] || { echo "[错误] acme.sh 产物缺失或为空: $ACME_HOME/$f"; exit 1; }
done

# 2. 取下一个归档版本号
ver=1
for f in "$ARCHIVE"/fullchain*.pem; do
    [ -e "$f" ] || continue
    n=${f##*fullchain}; n=${n%.pem}
    [ "$n" -gt "$ver" ] && ver=$n
done
ver=$((ver + 1))

# 3. 写入新版本
cp "$ACME_HOME/fullchain.cer"  "$ARCHIVE/fullchain$ver.pem"
cp "$ACME_HOME/nnbdc.com.key"  "$ARCHIVE/privkey$ver.pem"
cp "$ACME_HOME/nnbdc.com.cer"  "$ARCHIVE/cert$ver.pem"
cp "$ACME_HOME/ca.cer"         "$ARCHIVE/chain$ver.pem"
chown root:root "$ARCHIVE"/cert$ver.pem "$ARCHIVE"/chain$ver.pem "$ARCHIVE"/fullchain$ver.pem "$ARCHIVE"/privkey$ver.pem
chmod 644 "$ARCHIVE"/cert$ver.pem "$ARCHIVE"/chain$ver.pem "$ARCHIVE"/fullchain$ver.pem
chmod 600 "$ARCHIVE"/privkey$ver.pem
log "已写入归档版本 $ver"

# 4. 切换 live 软链
ln -sfn ../../archive/nnbdc.com/cert$ver.pem      "$LIVE/cert.pem"
ln -sfn ../../archive/nnbdc.com/chain$ver.pem     "$LIVE/chain.pem"
ln -sfn ../../archive/nnbdc.com/fullchain$ver.pem "$LIVE/fullchain.pem"
ln -sfn ../../archive/nnbdc.com/privkey$ver.pem   "$LIVE/privkey.pem"

# 5. 重载 nginx
docker exec nginx nginx -t
docker exec nginx nginx -s reload
log "nginx 已加载归档版本 $ver"

# 6. 上传到阿里云 CDN
. "$CREDS"
aliyun cdn SetCdnDomainSSLCertificate \
    --DomainName "$CDN_DOMAIN" \
    --CertType upload \
    --SSLProtocol on \
    --SSLPub "$(cat "$LIVE/fullchain.pem")" \
    --SSLPri "$(cat "$LIVE/privkey.pem")"
log "CDN 证书已更新（归档版本 $ver）"
