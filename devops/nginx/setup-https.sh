#!/bin/bash
# HTTPS自动配置脚本 - 适用于Docker部署的nginx
# 域名: nnbdc.com
# 系统: CentOS

set -e  # 遇到错误立即退出

echo "========================================="
echo "开始配置HTTPS (Let's Encrypt)"
echo "域名: nnbdc.com"
echo "========================================="

# 1. 检查Docker
echo ""
echo "[步骤1/6] 检查Docker环境..."
if ! command -v docker &> /dev/null; then
    echo "错误: 未找到Docker，请先安装Docker"
    exit 1
fi
echo "✓ Docker已安装"

# 拉取certbot Docker镜像
echo "拉取certbot Docker镜像..."
if docker images certbot/certbot:latest | grep -q certbot; then
    echo "✓ certbot镜像已存在，跳过拉取"
else
    echo "尝试拉取certbot镜像（如果超时，请手动配置Docker镜像加速器）..."
    if ! docker pull certbot/certbot:latest 2>/dev/null; then
        echo ""
        echo "⚠ 警告: 镜像拉取失败，尝试使用已有镜像..."
        if ! docker images certbot/certbot | grep -q certbot; then
            echo ""
            echo "错误: 未找到certbot镜像，请先手动拉取或配置Docker镜像加速器"
            echo ""
            echo "解决方案1 - 配置Docker镜像加速器（推荐）："
            echo "  编辑 /etc/docker/daemon.json，添加："
            echo '  {'
            echo '    "registry-mirrors": ['
            echo '      "https://docker.mirrors.ustc.edu.cn",'
            echo '      "https://hub-mirror.c.163.com"'
            echo '    ]'
            echo '  }'
            echo "  然后执行: systemctl daemon-reload && systemctl restart docker"
            echo ""
            echo "解决方案2 - 手动拉取镜像："
            echo "  docker pull certbot/certbot:latest"
            echo ""
            exit 1
        fi
    fi
fi
echo "✓ certbot镜像准备完成"

# 2. 检查nginx容器和服务
echo ""
echo "[步骤2/6] 检查nginx容器和服务..."
NGINX_CONTAINER="nginx"
USE_SYSTEMCTL=false

# 检查是否使用systemd管理
if systemctl is-active --quiet docker.nginx.service 2>/dev/null; then
    echo "✓ 检测到systemd服务: docker.nginx.service"
    USE_SYSTEMCTL=true
elif docker ps --format "{{.Names}}" | grep -q "^${NGINX_CONTAINER}$"; then
    echo "✓ 找到运行中的nginx容器: $NGINX_CONTAINER"
else
    echo "错误: nginx容器未运行，且未找到systemd服务"
    exit 1
fi

# 3. 创建Let's Encrypt验证目录
echo ""
echo "[步骤3/6] 创建验证目录..."
docker exec $NGINX_CONTAINER mkdir -p /usr/share/nginx/html/.well-known/acme-challenge
echo "✓ 验证目录创建完成"

# 4. 申请SSL证书（使用Docker方式的certbot）
echo ""
echo "[步骤4/6] 申请SSL证书..."
DEFAULT_EMAIL="mmyybb3000@icloud.com"
echo "请输入您的邮箱地址（用于证书到期提醒，默认: $DEFAULT_EMAIL）:"
read EMAIL
if [ -z "$EMAIL" ]; then
    EMAIL="$DEFAULT_EMAIL"
    echo "使用默认邮箱: $EMAIL"
fi

# 创建证书存储目录
mkdir -p /etc/letsencrypt
mkdir -p /var/lib/letsencrypt

# 停止nginx容器以释放80端口
echo "停止nginx服务..."
if [ "$USE_SYSTEMCTL" = true ]; then
    systemctl stop docker.nginx.service
else
    docker stop $NGINX_CONTAINER
fi

echo ""
echo "申请主域名证书 (nnbdc.com, www.nnbdc.com)..."
# 使用Docker运行certbot申请主域名证书
docker run --rm \
    -p 80:80 \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    certbot/certbot certonly --standalone \
    -d nnbdc.com \
    -d www.nnbdc.com \
    --email $EMAIL \
    --agree-tos \
    --non-interactive \
    --no-eff-email

if [ $? -eq 0 ]; then
    echo "✓ 主域名证书申请成功"
else
    echo "✗ 主域名证书申请失败"
    if [ "$USE_SYSTEMCTL" = true ]; then
        systemctl start docker.nginx.service
    else
        docker start $NGINX_CONTAINER
    fi
    exit 1
fi

echo ""
echo "申请后端域名证书 (back.nnbdc.com)..."
# 申请后端域名证书
docker run --rm \
    -p 80:80 \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    certbot/certbot certonly --standalone \
    -d back.nnbdc.com \
    --email $EMAIL \
    --agree-tos \
    --non-interactive \
    --no-eff-email

if [ $? -eq 0 ]; then
    echo "✓ 后端域名证书申请成功"
else
    echo "✗ 后端域名证书申请失败"
    if [ "$USE_SYSTEMCTL" = true ]; then
        systemctl start docker.nginx.service
    else
        docker start $NGINX_CONTAINER
    fi
    exit 1
fi

# 5. 启动nginx服务
echo ""
echo "[步骤5/6] 启动nginx服务..."
# 证书目录已通过volume挂载，容器启动后可直接使用
if [ "$USE_SYSTEMCTL" = true ]; then
    # 使用systemctl重启，确保volume挂载生效
    echo "重启nginx服务以加载证书挂载..."
    systemctl restart docker.nginx.service
else
    # 完全重建容器以确保volume挂载生效
    docker stop $NGINX_CONTAINER 2>/dev/null || true
    docker rm $NGINX_CONTAINER 2>/dev/null || true
    docker start $NGINX_CONTAINER
fi

# 等待容器完全启动
echo "等待nginx容器启动..."
MAX_WAIT=30
COUNTER=0
while [ $COUNTER -lt $MAX_WAIT ]; do
    if docker ps --format "{{.Names}}" | grep -q "^${NGINX_CONTAINER}$"; then
        echo "✓ 容器已启动"
        break
    fi
    sleep 1
    COUNTER=$((COUNTER + 1))
    echo -n "."
done

if [ $COUNTER -eq $MAX_WAIT ]; then
    echo ""
    echo "✗ 错误: 容器启动超时"
    systemctl status docker.nginx.service
    exit 1
fi

# 额外等待nginx进程完全就绪
sleep 3

# 验证证书文件在容器内是否可访问
echo "验证证书文件..."
if docker exec $NGINX_CONTAINER test -f /etc/letsencrypt/live/nnbdc.com/fullchain.pem && \
   docker exec $NGINX_CONTAINER test -f /etc/letsencrypt/live/back.nnbdc.com/fullchain.pem; then
    echo "✓ 证书文件已成功挂载到容器"
else
    echo "✗ 错误: 证书文件在容器内不可访问"
    echo ""
    echo "调试信息："
    echo "1. 容器状态："
    docker ps -a | grep nginx
    echo ""
    echo "2. 检查宿主机证书："
    ls -la /etc/letsencrypt/live/nnbdc.com/ 2>/dev/null || echo "主域名证书目录不存在"
    ls -la /etc/letsencrypt/live/back.nnbdc.com/ 2>/dev/null || echo "后端域名证书目录不存在"
    echo ""
    echo "3. 检查容器挂载："
    docker inspect $NGINX_CONTAINER | grep -A 5 "Mounts"
    echo ""
    echo "请检查 /etc/systemd/system/docker.nginx.service 文件中的 volume 挂载配置"
    echo "应包含: -v /etc/letsencrypt:/etc/letsencrypt:ro"
    exit 1
fi

echo "✓ nginx服务已启动，证书已可用"

# 6. 更新nginx配置
echo ""
echo "[步骤6/6] 更新nginx配置..."

# 检查配置文件是否存在
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ ! -f "$SCRIPT_DIR/conf.d/default-https.conf" ] || [ ! -f "$SCRIPT_DIR/conf.d/back-https.conf" ]; then
    echo "错误: 未找到HTTPS配置文件"
    echo "请确保以下文件存在:"
    echo "  - $SCRIPT_DIR/conf.d/default-https.conf"
    echo "  - $SCRIPT_DIR/conf.d/back-https.conf"
    exit 1
fi

# 备份原配置
echo "备份原配置文件..."
BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
docker cp $NGINX_CONTAINER:/etc/nginx/conf.d/default.conf ./default.conf.backup.$BACKUP_TIME 2>/dev/null || true
docker cp $NGINX_CONTAINER:/etc/nginx/conf.d/back.conf ./back.conf.backup.$BACKUP_TIME 2>/dev/null || true
echo "✓ 已备份原配置文件"

# 复制新配置
echo "复制HTTPS配置..."
docker cp $SCRIPT_DIR/conf.d/default-https.conf $NGINX_CONTAINER:/etc/nginx/conf.d/default.conf
docker cp $SCRIPT_DIR/conf.d/back-https.conf $NGINX_CONTAINER:/etc/nginx/conf.d/back.conf

# 测试nginx配置
echo "测试nginx配置..."
docker exec $NGINX_CONTAINER nginx -t
if [ $? -eq 0 ]; then
    echo "✓ nginx配置测试通过"
    # 重载nginx
    docker exec $NGINX_CONTAINER nginx -s reload
    echo "✓ nginx已重载"
else
    echo "✗ nginx配置测试失败，恢复原配置"
    docker cp ./default.conf.backup.$BACKUP_TIME $NGINX_CONTAINER:/etc/nginx/conf.d/default.conf 2>/dev/null || true
    docker cp ./back.conf.backup.$BACKUP_TIME $NGINX_CONTAINER:/etc/nginx/conf.d/back.conf 2>/dev/null || true
    docker exec $NGINX_CONTAINER nginx -s reload
    exit 1
fi

# 7. 设置证书自动续期
echo ""
echo "[步骤7/7] 设置证书自动续期..."
# 创建续期脚本
cat > /root/renew-cert.sh << 'EOF'
#!/bin/bash
# SSL证书自动续期脚本

NGINX_CONTAINER="nginx"
USE_SYSTEMCTL=false

# 检查是否使用systemd管理
if systemctl is-active --quiet docker.nginx.service 2>/dev/null; then
    USE_SYSTEMCTL=true
fi

echo "开始证书续期: $(date)"

# 停止nginx以释放80端口
if [ "$USE_SYSTEMCTL" = true ]; then
    systemctl stop docker.nginx.service
else
    docker stop $NGINX_CONTAINER
fi

# 使用Docker运行certbot续期所有证书
docker run --rm \
    -p 80:80 \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    certbot/certbot renew

# 启动nginx（证书目录已通过volume挂载，会自动同步）
if [ "$USE_SYSTEMCTL" = true ]; then
    systemctl start docker.nginx.service
else
    docker start $NGINX_CONTAINER
fi
sleep 3

# 重载nginx配置
docker exec $NGINX_CONTAINER nginx -s reload

echo "证书续期完成: $(date)"
EOF

chmod +x /root/renew-cert.sh

# 添加到crontab（每月1号凌晨3点执行）
(crontab -l 2>/dev/null | grep -v renew-cert.sh; echo "0 3 1 * * /root/renew-cert.sh >> /var/log/certbot-renew.log 2>&1") | crontab -

echo "✓ 自动续期任务已配置（每月1号凌晨3点）"

echo ""
echo "========================================="
echo "HTTPS配置完成！"
echo "========================================="
echo ""
echo "证书信息:"
docker run --rm \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/lib/letsencrypt:/var/lib/letsencrypt \
    certbot/certbot certificates
echo ""
echo "现在可以通过 https://nnbdc.com 访问您的网站"
echo "HTTP请求会自动重定向到HTTPS"
echo ""
echo "证书有效期: 90天"
echo "自动续期: 每月1号凌晨3点"
echo "续期日志: /var/log/certbot-renew.log"
echo ""
echo "提示: 脚本已上传到服务器，位置: /root/renew-cert.sh"
echo ""

