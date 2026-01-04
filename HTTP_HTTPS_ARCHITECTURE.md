# NNBDC HTTP/HTTPS 架构设计

## 维护速查（路径汇总）

### 证书目录（宿主机）

- **主域名证书（用于 www/nnbdc.com）**：
  - `/etc/letsencrypt/live/nnbdc.com/fullchain.pem`
  - `/etc/letsencrypt/live/nnbdc.com/privkey.pem`
- **后端域名证书（用于 back.nnbdc.com）**：
  - `/etc/letsencrypt/live/back.nnbdc.com/fullchain.pem`
  - `/etc/letsencrypt/live/back.nnbdc.com/privkey.pem`
- **续期配置**：
  - `/etc/letsencrypt/renewal/*.conf` 
- **续期 Hook（示例：CDN 证书同步）**：
  - `/etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh`

### 运维脚本与服务（生产机）

- **证书续签脚本（crontab 调用）**：`/root/renew-cert.sh`
- **crontab**：`crontab -l`
- **nginx 容器**：`nginx`（systemd + Docker）

### 日志路径（生产机）

- **续签执行日志**：`/var/log/certbot-renew.log`
- **certbot 详细日志**：`/var/log/letsencrypt/letsencrypt.log`

## 架构概述

本文档说明 NNBDC 应用与服务器之间的 HTTP/HTTPS 通信架构设计。

## 域名配置

| 域名 | 用途 | DNS 指向 | 协议支持 |
|------|------|---------|---------|
| www.nnbdc.com | 前端服务（含下载/更新/公共资源） | 昆仑灿 CDN | HTTP + HTTPS |
| back.nnbdc.com | 后端服务（API/WebSocket/私有资源） | 47.108.27.205 | HTTPS（主） + HTTP（兼容/ACME） |

## HTTPS 证书说明

- **back.nnbdc.com**: 使用 Let's Encrypt 证书（有效期90天），实际启用 HTTPS
- **www.nnbdc.com / nnbdc.com**: 使用 Let's Encrypt 证书（证书 SAN 同时包含 `nnbdc.com` 与 `www.nnbdc.com`），并在 CDN 侧启用 HTTPS
- **自动续签**: 通过 crontab + certbot 实现自动续签；若前端启用了 CDN HTTPS，需配合 deploy-hook 将新证书同步到 CDN

## 架构图

```mermaid
graph TB
    subgraph "客户端"
        APP[移动应用 App]
    end
    
    subgraph "DNS解析"
        DNS1[www.nnbdc.com<br/>DNS → 昆仑灿CDN]
        DNS2[back.nnbdc.com<br/>DNS → 47.108.27.205]
    end
    
    subgraph "CDN层"
        CDN[昆仑灿 CDN<br/>HTTP + HTTPS]
    end
    
    subgraph "服务器 47.108.27.205"
        FRONTEND[前端服务<br/>www.nnbdc.com<br/>HTTP + HTTPS]
        BACKEND[后端服务<br/>back.nnbdc.com<br/>HTTP + HTTPS]
        CERT[Let's Encrypt 证书<br/>有效期90天<br/>crontab+certbot自动续签]
    end
    
    subgraph "第三方服务"
        WECHAT[微信登录服务]
    end
    
    %% API 调用流程 - HTTPS
    APP -->|"① 后端 API 调用<br/>HTTPS"| DNS2
    DNS2 -->|"HTTPS"| BACKEND
    
    %% 共享词书资源 - HTTPS（经 CDN）
    APP -->|"② 共享词书资源<br/>HTTPS"| DNS1
    DNS1 -->|"HTTPS"| CDN
    CDN -->|"HTTPS<br/>CDN 加速"| FRONTEND
    FRONTEND -->|"HTTP/HTTPS<br/>转发"| BACKEND
    
    %% 用户词书资源 - HTTPS
    APP -->|"③ 用户词书<br/>HTTPS"| DNS2
    
    %% 微信登录 - HTTPS
    WECHAT -->|"④ 微信回调<br/>HTTPS"| BACKEND
    
    %% 证书关联
    CERT -.->|SSL/TLS| BACKEND
    
    %% 样式定义 - 使用更高对比度的配色
    style APP fill:#4FC3F7,stroke:#01579B,stroke-width:2px,color:#000
    style CDN fill:#FFE082,stroke:#F57F17,stroke-width:2px,color:#000
    style FRONTEND fill:#E0E0E0,stroke:#424242,stroke-width:2px,color:#000
    style BACKEND fill:#81C784,stroke:#2E7D32,stroke-width:2px,color:#000
    style WECHAT fill:#F48FB1,stroke:#C2185B,stroke-width:2px,color:#000
    style CERT fill:#FFF59D,stroke:#F57F17,stroke-width:2px,color:#000
    
    %% 连接线颜色 - 蓝色表示HTTP，绿色表示HTTPS
    linkStyle 0 stroke:#4CAF50,stroke-width:3px
    linkStyle 1 stroke:#4CAF50,stroke-width:3px
    linkStyle 2 stroke:#4CAF50,stroke-width:3px
    linkStyle 3 stroke:#4CAF50,stroke-width:3px
    linkStyle 4 stroke:#2196F3,stroke-width:3px
    linkStyle 5 stroke:#2196F3,stroke-width:3px
    linkStyle 6 stroke:#4CAF50,stroke-width:3px
    linkStyle 7 stroke:#4CAF50,stroke-width:3px
    linkStyle 8 stroke:#FFC107,stroke-width:2px,stroke-dasharray: 5 5
```

### 图例说明

- 🔵 **蓝色实线** - HTTP 连接
- 🟢 **绿色实线** - HTTPS 连接（安全加密）
- 🟡 **黄色虚线** - SSL/TLS 证书关联

## 资源访问策略

### 1. 后端 API 访问
- **URL**: `https://back.nnbdc.com/*`（当前后端接口多为 `*.do`，不强制 `/api/` 前缀）
- **协议**: **HTTPS（强制）**
- **路由**: App → back.nnbdc.com (直连)
- **用途**: 所有后端业务 API 调用
- **安全**: TLS 1.2/1.3 加密，HSTS 保护

### 2. 共享词书资源
- **URL**: `https://www.nnbdc.com/back/getDictResById.do`
- **协议**: **HTTPS（推荐）**（CDN 对外终端可同时支持 HTTP/HTTPS）
- **路由**: App → www.nnbdc.com (CDN) → 前端 nginx (`/back/` 代理) → 后端服务
- **优势**: 利用昆仑灿 CDN 加速资源分发
- **适用**: 公共词书、共享词典等静态资源
- **nginx 配置**: 前端配置中的 `location /back/` 将请求代理到 `127.0.0.1:5200`

### 3. 用户词书资源（生词本）
- **URL**: `https://back.nnbdc.com/getDictResById.do`
- **协议**: **HTTPS（强制）**
- **路由**: App → back.nnbdc.com (直连)
- **用途**: 用户私有数据，不经过 CDN
- **安全**: 加密传输，保护用户隐私

### 4. 微信登录回调
- **URL**: `https://back.nnbdc.com/wechat/callback`
- **协议**: HTTPS（**必须**）
- **原因**: 微信要求回调地址必须使用 HTTPS
- **证书**: Let's Encrypt 自动续签

## 通信流程时序图

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#4FC3F7','primaryTextColor':'#000','primaryBorderColor':'#01579B','lineColor':'#64B5F6','secondaryColor':'#81C784','tertiaryColor':'#FFE082','noteBkgColor':'#FFF9C4','noteTextColor':'#000','noteBorderColor':'#F57F17','actorBkg':'#E0E0E0','actorBorder':'#424242','actorTextColor':'#000','actorLineColor':'#64B5F6','signalColor':'#64B5F6','signalTextColor':'#FFFFFF','labelBoxBkgColor':'#FFE082','labelBoxBorderColor':'#F57F17','labelTextColor':'#000','activationBorderColor':'#42A5F5','activationBkgColor':'#90CAF9'}}}%%
sequenceDiagram
    participant App as 移动应用
    participant CDN as 昆仑灿CDN
    participant Front as 前端服务<br/>(www.nnbdc.com)
    participant Back as 后端服务<br/>(back.nnbdc.com)
    participant WeChat as 微信服务

    Note over App,Back: 场景1: 普通 API 调用 (HTTPS)
    App->>Back: HTTPS: back.nnbdc.com/api/xxx
    Back-->>App: JSON Response (加密)

    Note over App,Back: 场景2: 共享词书资源 (HTTPS + CDN加速)
    App->>CDN: HTTPS: www.nnbdc.com/back/getDictResById.do
    CDN->>Front: HTTPS 转发
    Front->>Back: HTTP/HTTPS 内部转发
    Back-->>Front: 资源数据
    Front-->>CDN: 返回资源
    CDN-->>App: 缓存并返回（加速）

    Note over App,Back: 场景3: 用户词书资源 (HTTPS 直连)
    App->>Back: HTTPS: back.nnbdc.com/getDictResById.do
    Back-->>App: 用户私有数据 (加密)

    Note over App,WeChat: 场景4: 微信登录 (HTTPS)
    App->>Back: HTTPS: 发起微信登录
    Back-->>App: 返回微信授权URL
    App->>WeChat: 打开微信授权页面
    rect rgba(129, 199, 132, 0.3)
        Note right of WeChat: 🔒 HTTPS 安全连接
        WeChat->>+Back: HTTPS: back.nnbdc.com/wechat/callback
        Back-->>-WeChat: 处理回调
    end
    Back-->>App: 登录成功通知
```

## 设计决策说明

### 为什么 www.nnbdc.com 需要 HTTPS？

前端已启用 HTTPS，主要原因：

1. **平台合规与用户信任**：iOS/macOS（ATS）与现代浏览器对 HTTPS 越来越“默认要求”
2. **避免混合内容**：App/Web 访问更新/下载/资源链接时统一走 HTTPS，减少线上大改风险
3. **统一入口**：用户侧永远访问 `https://www.nnbdc.com`，HTTPS 由 CDN 终端提供，回源可按成本选择 HTTP/HTTPS

> **说明**：`nnbdc.com` 的 Let's Encrypt 证书包含 `www.nnbdc.com`（SAN），可用于 CDN 侧配置 www 的 HTTPS。

### 为什么 back.nnbdc.com 强制使用 HTTPS？

1. **微信登录要求**: 微信 OAuth 回调必须使用 HTTPS
2. **数据安全**: 
   - 用户登录凭证、个人信息需要加密传输
   - 学习记录、生词本等私密数据保护
   - 防止中间人攻击和数据劫持
3. **WebSocket 安全**: Socket.IO 实时通信需要加密保护
4. **行业最佳实践**: 
   - 现代 Web 应用标准要求
   - 符合 GDPR、等保等合规要求
   - 提升用户信任度
5. **技术优势**: 
   - HTTP/2 性能提升（必须基于 HTTPS）
   - HSTS 防护，增强安全性
   - 直连服务器，证书配置简单

### 资源分流策略

- **公共资源** → 走 CDN（www.nnbdc.com）：充分利用 CDN 缓存和加速能力
- **私有数据** → 直连后端（back.nnbdc.com）：保证数据安全性和实时性

## 自动化运维

### 证书自动续签

本项目使用 Docker 容器化部署 certbot，通过 cron 定时任务实现证书自动续签。

#### crontab 配置

```bash
# 每月1号凌晨3点执行证书续签
0 3 1 * * /root/renew-cert.sh >> /var/log/certbot-renew.log 2>&1
```

#### 续签脚本 (`/root/renew-cert.sh`)

```bash
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
```

#### 续签说明

- **工具**: certbot Docker 镜像 (certbot/certbot)
- **部署方式**: Docker 容器化（nginx 通过 systemd 管理）
- **续签模式**: **webroot 模式（零停机）** ⚡
- **执行时间**: 每月1号凌晨3点
- **执行方式**: 
  1. 在宿主机上创建验证目录 `/var/www/html/.well-known/acme-challenge/`
  2. 运行 certbot 容器执行续签（**nginx 保持运行**）
  3. certbot 将验证文件写入宿主机 `/var/www/html`（容器内映射为 `/usr/share/nginx/html`）
  4. Let's Encrypt 通过 HTTP 访问验证文件
  5. certbot 更新宿主机 `/etc/letsencrypt` 的证书（容器只读挂载，但宿主机可写）
  6. 重载 nginx 配置（仅重载，无需重启）
- **服务中断时间**: **0 秒**（零停机）✅
- **证书有效期**: 90天（Let's Encrypt 标准）
- **续签时机**: 证书剩余30天时自动续签
- **日志位置**: `/var/log/certbot-renew.log`
- **申请的证书**: 
  - nnbdc.com + www.nnbdc.com（已启用：用于 CDN HTTPS）
  - back.nnbdc.com（**实际使用中**）

> **提示**：若使用 deploy-hook（例如同步证书到阿里云 CDN），脚本通常位于：
> `/etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh`

**Docker 部署关键配置**：
```bash
# docker.nginx.service 中的关键挂载
-v /var/www/html:/usr/share/nginx/html       # webroot 映射
-v nginxcnf:/etc/nginx                       # nginx 配置（named volume）
-v /etc/letsencrypt:/etc/letsencrypt:ro      # 证书目录（只读）
```

#### 零停机续签原理

**webroot 模式工作流程（Docker 环境）**：

1. 续签脚本在宿主机创建目录 `/var/www/html/.well-known/acme-challenge/`
2. certbot 容器将验证文件写入该目录（通过 volume 挂载）
3. nginx 容器通过 volume 挂载访问该目录（容器内路径 `/usr/share/nginx/html/.well-known/acme-challenge/`）
4. Let's Encrypt 服务器通过 HTTP 访问 `http://back.nnbdc.com/.well-known/acme-challenge/xxx`
5. nginx 根据配置直接返回验证文件（**无需停止服务**）
6. 验证成功后，certbot 更新宿主机 `/etc/letsencrypt` 的证书文件
7. nginx 容器通过只读挂载自动看到新证书
8. nginx reload 加载新证书（**仅重载配置，连接不中断**）

**路径映射关系**：

| 宿主机路径 | 容器内路径 | 说明 |
|-----------|-----------|------|
| `/var/www/html` | `/usr/share/nginx/html` | webroot 目录 |
| `/etc/letsencrypt` | `/etc/letsencrypt` | 证书目录（只读） |
| `nginxcnf` volume | `/etc/nginx` | nginx 配置 |

**对比两种续签模式**：

| 模式 | standalone | webroot（当前方案）|
|------|-----------|------------------|
| nginx 状态 | 需要停止 | 保持运行 ✅ |
| 服务中断 | 5-15秒 | 0秒 ✅ |
| 配置要求 | 无 | 需要 acme-challenge 配置 |
| 适用场景 | 初次申请 | 自动续签 |
| Docker 兼容 | 需要停止容器 | 完美兼容 ✅ |

#### 证书使用说明

虽然 `setup-https.sh` 脚本会为主域名（nnbdc.com, www.nnbdc.com）和后端域名（back.nnbdc.com）同时申请证书，但在实际部署中：

- ✅ **back.nnbdc.com 证书正在使用** - 用于微信登录回调等需要 HTTPS 的场景
- ✅ **主域名证书正在使用** - www.nnbdc.com 已在 CDN 侧启用 HTTPS（证书 SAN 覆盖 www）

说明：
1. **www.nnbdc.com 的 HTTPS 在 CDN 层终止**：证书需配置在 CDN（或由 CDN 托管/自动续期）
2. **源站 nginx 是否启用 www 的 HTTPS**：与 CDN 回源策略相关（可选 HTTP 或 HTTPS）

## 部署步骤

### 1. 更新 nginx 配置

#### 部署后端配置

```bash
# 在本地上传后端配置文件
scp devops/nginx/conf.d/back.conf root@47.108.27.205:/tmp/

# 在服务器上应用配置
docker cp /tmp/back.conf nginx:/etc/nginx/conf.d/back.conf
docker exec nginx nginx -t
docker exec nginx nginx -s reload

# 验证配置
docker exec nginx cat /etc/nginx/conf.d/back.conf | grep "well-known"
```

#### 部署前端配置

```bash
# 在本地上传前端配置文件
scp devops/nginx/conf.d/default.conf root@47.108.27.205:/tmp/

# 在服务器上应用配置
docker cp /tmp/default.conf nginx:/etc/nginx/conf.d/default.conf
docker exec nginx nginx -t
docker exec nginx nginx -s reload

# 验证 /back/ 代理配置
curl -I https://www.nnbdc.com/back/
```

### 2. 确保 webroot 目录存在

```bash
# 在服务器上创建验证目录
mkdir -p /var/www/html/.well-known/acme-challenge
```

### 3. 部署零停机续签脚本

```bash
# 在本地上传脚本
scp devops/renew-cert.sh root@47.108.27.205:/root/

# 在服务器上设置权限
chmod +x /root/renew-cert.sh

# 测试脚本
/root/renew-cert.sh
```

### 4. 配置自动续签

```bash
# 编辑 crontab
crontab -e

# 添加以下内容（每月1号凌晨3点执行）
0 3 1 * * /root/renew-cert.sh >> /var/log/certbot-renew.log 2>&1

# 验证配置
crontab -l
```

### 5. 测试零停机续签

```bash
# 在服务器上手动运行脚本测试
/root/renew-cert.sh

# 查看续签日志
tail -f /var/log/certbot-renew.log

# 验证证书信息(可查看证书有效期)
docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot certificates
```

## 配置部署指南

### 部署前检查

```bash
# 1. 确认 HTTPS 证书有效
docker exec nginx ls -l /etc/letsencrypt/live/back.nnbdc.com/

# 2. 测试 HTTPS 访问是否正常
curl -I https://back.nnbdc.com

# 3. 备份当前配置
docker cp nginx:/etc/nginx/conf.d/back.conf /root/back.conf.backup.$(date +%Y%m%d)
```

### 部署配置

```bash
# 1. 从本地上传配置到服务器（在本地执行）
scp devops/nginx/conf.d/back.conf root@47.108.27.205:/tmp/

# 2. 在服务器上应用配置
docker cp /tmp/back.conf nginx:/etc/nginx/conf.d/back.conf

# 3. 测试配置
docker exec nginx nginx -t

# 4. 重载配置
docker exec nginx nginx -s reload
```

### 部署后验证

```bash
# 1. 测试 HTTP 自动跳转 HTTPS
curl -I http://back.nnbdc.com
# 应该看到: HTTP/1.1 301 Moved Permanently
# Location: https://back.nnbdc.com/

# 2. 测试 HTTPS 访问
curl -I https://back.nnbdc.com
# 应该看到: HTTP/2 200

# 3. 查看 nginx 日志
docker logs --tail 50 nginx
```

### 回滚方案

```bash
# 如有问题，恢复备份配置
docker cp /root/back.conf.backup.YYYYMMDD nginx:/etc/nginx/conf.d/back.conf
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

## Docker 部署架构说明

本项目的 nginx 通过 **systemd + Docker** 方式部署，服务定义在 `/devops/nginx/docker.nginx.service`。

### Docker 运行配置

```bash
docker run --rm --name nginx --network host  \
    -v /var/www/html:/usr/share/nginx/html \              # webroot 映射
    -v /var/nnbdc/res/img:/var/nnbdc/res/img \            # 图片资源
    -v /var/nnbdc/res/sound:/var/nnbdc/res/sound \        # 音频资源
    -v nginxcnf:/etc/nginx \                              # nginx 配置（named volume）
    -v /etc/localtime:/etc/localtime \                    # 时区
    -v /etc/timezone:/etc/timezone \                      # 时区
    -v /etc/letsencrypt:/etc/letsencrypt:ro \             # SSL 证书（只读）
    nginx
```

### 关键特性

1. **named volume `nginxcnf`**: 
   - nginx 配置存储在 Docker named volume 中
   - 更新配置需使用 `docker cp` 命令
   - 优势：配置持久化，容器重建不丢失

2. **证书只读挂载**:
   - 容器内 `/etc/letsencrypt` 是只读的
   - certbot 直接更新宿主机的 `/etc/letsencrypt`
   - nginx 通过 reload 加载新证书

3. **webroot 映射**:
   - 宿主机 `/var/www/html` → 容器 `/usr/share/nginx/html`
   - certbot 和 nginx 共享同一目录
   - 实现零停机证书续签

### 管理命令

```bash
# 启动/停止/重启服务
systemctl start docker.nginx.service
systemctl stop docker.nginx.service
systemctl restart docker.nginx.service

# 查看服务状态
systemctl status docker.nginx.service

# 查看容器日志
docker logs -f nginx

# 进入容器
docker exec -it nginx bash

# 测试/重载配置
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

## 相关配置文件

- Nginx 后端配置: `/devops/nginx/conf.d/back.conf`（生产环境配置）
  - ✅ 强制 HTTPS（HTTP 自动跳转）
  - ✅ 零停机证书续签支持
  - ✅ TLSv1.2 + TLSv1.3 支持
  - ✅ Mozilla Intermediate 加密套件
  - ✅ HSTS 安全头（includeSubDomains）
  
- Nginx 前端配置: `/devops/nginx/conf.d/default.conf`
  - ✅ `/back/` 代理到后端服务（利用 CDN 加速共享资源）
  - ✅ 静态资源缓存配置
  - ✅ CORS 跨域配置
  
- HTTPS 设置脚本: `/devops/nginx/setup-https.sh`
- 续签脚本: `/devops/renew-cert.sh`（零停机方案，适配 Docker）
- Systemd 服务: `/devops/nginx/docker.nginx.service`
- 前端配置: `/app/lib/config.dart`

## 安全性配置

### back.nnbdc.com 安全特性

本项目后端服务采用现代化的 HTTPS 安全配置：

#### 1. 强制 HTTPS
- 所有 HTTP 请求自动重定向到 HTTPS（301 永久重定向）
- 保护所有 API 和 WebSocket 连接
- 符合微信等第三方服务的安全要求
- Let's Encrypt 证书验证不受重定向影响

#### 2. TLS 协议支持
- **TLS 1.2** - 广泛兼容性
- **TLS 1.3** - 最新标准，更快的握手速度，更强的安全性
- 禁用过时的 TLS 1.0/1.1 协议

#### 3. 加密套件
采用 **Mozilla Intermediate** 配置：
- 支持现代浏览器和操作系统
- 兼顾安全性和兼容性
- 包含 ECDHE、RSA、CHACHA20 等多种加密算法

#### 4. HSTS (HTTP Strict Transport Security)
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```
- 强制浏览器使用 HTTPS 访问（1年有效期）
- 包含所有子域名保护
- 防止中间人攻击和协议降级

#### 5. 会话优化
- 会话缓存：50MB 共享缓存
- 会话超时：1天
- 禁用 session tickets（增强安全性）

### SSL Labs 评级

使用以上配置，预期可获得：
- **SSL Labs 评分**: A 或 A+
- **支持的浏览器**: 覆盖 95%+ 的现代浏览器
- **安全性**: 符合 PCI DSS 等行业标准

测试地址：https://www.ssllabs.com/ssltest/analyze.html?d=back.nnbdc.com

## 注意事项

1. 🔐 **证书申请 vs 证书使用**: 
   - `setup-https.sh` 会为 nnbdc.com, www.nnbdc.com 和 back.nnbdc.com 三个域名申请证书
   - **back.nnbdc.com** 证书用于后端 HTTPS
   - **nnbdc.com / www.nnbdc.com** 证书用于 CDN 侧前端 HTTPS（SAN 覆盖 www）
   
2. ⚠️ **强制 HTTPS**: 
   - back.nnbdc.com 推荐仅用 HTTPS（HTTP 可保留给 ACME/兼容路径）
   - App 客户端必须使用 HTTPS URL（`https://back.nnbdc.com`）
   - Let's Encrypt 证书验证通过 `/.well-known/acme-challenge/` 特殊路径，不受重定向影响

3. ⚠️ **微信回调依赖**: 微信登录功能严格依赖 back.nnbdc.com 的 HTTPS 证书，证书过期会导致登录失败

4. ⚠️ **CDN 缓存策略**: 注意公共资源更新时的缓存失效问题

5. ⚠️ **证书过期监控**: 虽然有自动续签，但建议配置证书过期监控作为备份

6. ⚠️ **混合内容警告**: 前端已启用 HTTPS，需确保所有资源请求也使用 HTTPS（更新/下载/静态资源等）

7. 🔧 **配置变更**: 修改配置后建议在低峰期操作，并验证：
   - HTTP 到 HTTPS 重定向是否正常
   - HTTPS 访问是否正常
   - WebSocket 连接是否稳定
   - App 客户端连接是否正常
   - 微信登录功能是否正常

