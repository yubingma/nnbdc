---
name: nnbdc-ssl-renewal
description: 处理 NBDC 线上站点 SSL 证书到期告警/续期（www.nnbdc.com 前端走阿里云 CDN、back.nnbdc.com 后端走源站 nginx）。当阿里云推送"证书即将过期"、或服务器自动续期(cron renew-cert.sh)失败、或用户反馈 HTTPS 证书失效时使用。
whenToUse: 用户提到"SSL 证书快过期"、"阿里云证书告警"、"back.nnbdc.com / www.nnbdc.com 证书问题"、"certbot 续期失败"、"定时续期又没生效"等情况。
---

# NBDC SSL 证书续期 诊断与修复

## 0. 一句话定位

> 证书到期告警 + 服务器自动续期失败，**根因几乎都是「大陆 ↔ Let's Encrypt 跨境链路双向不通」**，不是脚本/cron/配置坏了。绕开办法是 **DNS-01**（LE 只查 DNS TXT，不连服务器，天然无跨境连接），前提是有一把能写阿里云 DNS 的 AccessKey。

## 1. 架构（两个域名、两张证书、各管各的）

| 域名 | HTTPS 在哪终结 | 证书位置 | 到期 |
|---|---|---|---|
| `www.nnbdc.com`（前端） | **阿里云 CDN**（源站回源 HTTP 80，源站 nginx 只有 80 无 443） | `/etc/letsencrypt/live/nnbdc.com/` + 上传到 CDN | 前端那把 |
| `back.nnbdc.com`（后端 API） | **源站 nginx 443**（`back.conf`） | `/etc/letsencrypt/live/back.nnbdc.com/` | 后端那把 |

- 服务器：`47.108.27.205`（CentOS 7，root），nginx 跑在 Docker（`/etc/letsencrypt` 只读挂载进容器）。
- DNS：阿里云云解析（`dns1/dns2.hichina.com`），域 `nnbdc.com`；`www` 是 CNAME → `www.nnbdc.com.w.kunlunaq.com`（阿里云 CDN），`back`、`@` 均 A → `47.108.27.205`。

## 2. 自动续期链路（cron → 脚本）

```bash
# root crontab（2026-10-12 起改为每天执行，原来错写成每月 1 号）
0 3 * * * /root/renew-cert.sh >> /var/log/certbot-renew.log 2>&1
```
`/root/renew-cert.sh`：① Docker 内 `certbot renew --webroot -w /webroot`（HTTP-01）→ ② 成功则 `docker exec nginx nginx -s reload` → ③ 调 `/etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh` 把 `live/nnbdc.com` 证书上传到 `www.nnbdc.com` CDN。

**关键坑**：这条链路（证书签发 + LE 反向校验域名）都依赖大陆↔LE 跨境网络；它不稳定 → 续期静默失败，误以为"定时任务坏了"。

**节律坑（2026-10-12 修掉）**：原为 `0 3 1 * *`（每月 1 号），而 certbot 只在距到期 ≤30 天时才真正续期。证书 12-02 到期时，11-01 执行距到期还有 31.75 天 → 仍判 `not yet due`；真正第一次尝试要等到 **12-01**，那时距到期只剩 1.75 天。若那天跨境不通（2026-06-01、2026-09-01 都失败过），下次 cron 要等到次年 1-01，证书会整整失效一个月——这就是历史上"到期证书失效"的物理根因。改成每天执行后，容错窗口由 1 天扩到 30 天。

## 3. 诊断（生产环境默认只读）

> SSH 无免密 key、且沙箱禁伪终端，用 `SSH_ASKPASS` 连接：

```bash
printf '#!/bin/bash\necho "<服务器密码>"\n' > /tmp/askpass.sh && chmod +x /tmp/askpass.sh
export SSH_ASKPASS=/tmp/askpass.sh SSH_ASKPASS_REQUIRE=force DISPLAY=:0
ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 22 \
    root@47.108.27.205 'bash -s' </dev/null <<'REMOTE'
crontab -l; cat /root/renew-cert.sh
tail -40 /var/log/certbot-renew.log
for d in nnbdc.com back.nnbdc.com; do
  openssl x509 -in /etc/letsencrypt/live/$d/cert.pem -noout -subject -issuer -dates
done
# 连通性：LE 超时、百度/腾讯/阿里云通 → 跨境问题
curl -4 -sS -o /dev/null -w '%{http_code}\n' --connect-timeout 12 --max-time 15 https://acme-v02.api.letsencrypt.org/directory
curl -4 -sS -o /dev/null -w '%{http_code}\n' --connect-timeout 10 --max-time 15 https://www.baidu.com
REMOTE
```

判断链条：`crontab` 在跑 + `crond` enabled → 任务没坏；`certbot-renew.log` 报 `Read timed out` 连 `acme-v02...` → 服务器连不上 LE；连通性对比 → 大陆↔LE 跨境不通；反向用 certbot 做 HTTP-01，LE 报 `Network unreachable` → LE 也连不上大陆域名。**结论：跨境双向不通。**

## 4. 修复步骤（可复用）

> 前提：在**能连 Let's Encrypt 的机器**（如本 Mac）上签发，再部署到服务器+CDN。密钥从本地文件读（见 §5），**不要**显式回显 Secret。

### 4.1 确认 AccessKey 能写 DNS
```bash
# 服务器上（用证书续期用的 RAM 子账号 key，已授权 AliyunDNSFullAccess + AliyunCDNFullAccess）
export ALIBABA_CLOUD_ACCESS_KEY_ID="<key>" ALIBABA_CLOUD_ACCESS_KEY_SECRET="<secret>" ALIBABA_CLOUD_REGION_ID="cn-hangzhou"
aliyun alidns AddDomainRecord --DomainName nnbdc.com --RR acmetest --Type TXT --Value check123   # 能返回 RecordId 即 OK
# 删掉测试记录（记下上一步 RecordId）
aliyun alidns DeleteDomainRecord --RecordId <RecordId>
```
- 若报 `Forbidden` + "leakage of this AccessKey" → 这把 key 被阿里云风控判"泄露"，写操作被禁，需换一把新的 RAM AccessKey（授权范围选"整个云账号"）。
- 若报 `Forbidden.RAM` → key 没授权，去 RAM 给该用户挂 `AliyunDNSFullAccess` + `AliyunCDNFullAccess`。

### 4.2 用 acme.sh 走 DNS-01 签发（本机）
```bash
source ~/.nnbdc_aliyun_creds   # 本地密钥文件，见 §5
export Ali_Key="$ALIYUN_SSL_AK_ID" Ali_Secret="$ALIYUN_SSL_AK_SECRET"
git clone --depth 1 https://github.com/acmesh-official/acme.sh.git /tmp/acmesh; cd /tmp/acmesh
./acme.sh --issue --dns dns_ali -d nnbdc.com -d www.nnbdc.com --server letsencrypt --keylength 2048 --home /tmp/acmehome --email <your@email>
./acme.sh --issue --dns dns_ali -d back.nnbdc.com     --server letsencrypt --keylength 2048 --home /tmp/acmehome --email <your@email>
# 产物：/tmp/acmehome/<domain>/{fullchain.cer, <domain>.key, <domain>.cer, ca.cer}
```

### 4.3 部署到服务器（archive 新版本 + 改 live 软链 + reload）
```bash
# 先看当前归档最大版本号，+1 作为新版本（本次：nnbdc.com=9，back.nnbdc.com=10）
scp -o StrictHostKeyChecking=no /tmp/acmehome/nnbdc.com/fullchain.cer  root@47.108.27.205:/root/certdeploy/nnbdc.fullchain.pem
# ... 其余 3 个文件（nnbdc.privkey.pem / nnbdc.cert.pem / nnbdc.chain.pem）与 back 同理（back.*）
# 服务器上：
set -e; D=/root/certdeploy; AN=/etc/letsencrypt/archive/nnbdc.com; AB=/etc/letsencrypt/archive/back.nnbdc.com
LN=/etc/letsencrypt/live/nnbdc.com; LB=/etc/letsencrypt/live/back.nnbdc.com
cp $D/nnbdc.fullchain.pem $AN/fullchain9.pem;  cp $D/nnbdc.privkey.pem $AN/privkey9.pem
cp $D/nnbdc.cert.pem $AN/cert9.pem;  cp $D/nnbdc.chain.pem $AN/chain9.pem
chown root:root $AN/cert9.pem $AN/chain9.pem $AN/fullchain9.pem $AN/privkey9.pem
chmod 644 $AN/cert9.pem $AN/chain9.pem $AN/fullchain9.pem; chmod 600 $AN/privkey9.pem
ln -sf ../../archive/nnbdc.com/cert9.pem $LN/cert.pem
ln -sf ../../archive/nnbdc.com/chain9.pem $LN/chain.pem
ln -sf ../../archive/nnbdc.com/fullchain9.pem $LN/fullchain.pem
ln -sf ../../archive/nnbdc.com/privkey9.pem $LN/privkey.pem
# back 同理用 10（cert10/chain10/fullchain10/privkey10）
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```
> 旧版本归档保留（如 cert8.* / cert9.*），便于回滚（回滚 = 把 live 软链指回旧版本）。

### 4.4 上传新证书到 CDN（www.nnbdc.com）
```bash
export ALIBABA_CLOUD_ACCESS_KEY_ID="<key>" ALIBABA_CLOUD_ACCESS_KEY_SECRET="<secret>" ALIBABA_CLOUD_REGION_ID="cn-hangzhou"
aliyun cdn SetCdnDomainSSLCertificate --DomainName www.nnbdc.com --CertType upload --SSLProtocol on \
  --SSLPub "$(cat /etc/letsencrypt/live/nnbdc.com/fullchain.pem)" \
  --SSLPri "$(cat /etc/letsencrypt/live/nnbdc.com/privkey.pem)"
# 返回 {"RequestId":...} 即成功
```

### 4.5 验证（端到端，从公网抓实际呈现的证书）
```bash
for h in www.nnbdc.com back.nnbdc.com; do
  echo "== $h =="; openssl s_client -connect $h:443 -servername $h </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
done
```
成功：`issuer=Let's Encrypt`，`notAfter≈90 天后`；`www` 由 CDN 呈现、`back` 由源站 nginx 呈现。

## 5. 凭证来源（本地，勿外泄）

- 证书续期用的阿里云 RAM AccessKey 存在本机 **`~/.nnbdc_aliyun_creds`**（权限 600，**不要提交 git / 不要云同步**）。内容两行：`ALIYUN_SSL_AK_ID=...`、`ALIYUN_SSL_AK_SECRET=...`。用 `source` 加载。
- 我的沙箱**写不进** home（所以该文件由用户在本机创建），但**能读取**；下次直接 `source` 即可，无需用户重新提供。
- SSH 服务器密码在 `~/.zprofile`（`PROD_DB_SSH_PASSWORD` / `nnbdc_server_pwd`）。

## 6. 安全红线

- 生产环境**默认只读**；涉及证书部署/替换/上传 CDN/改 nginx 需**用户明确授权**。
- **不要**在对话/输出里回显 AccessKey Secret 或私钥明文；一律 `source ~/.nnbdc_aliyun_creds`。
- `~/.zprofile` 里那把旧 AccessKey（`aliyun_access_key_id`，ID 前缀 `LTAI5tFX`）**已被阿里云判"泄露风险"**：在 RAM 删除/禁用，并替换服务器 `aliyun-cdn.sh` 硬编码的旧 key。✅ **2026-10-12 已完成替换**：服务器 `aliyun-cdn.sh` 第 6/7 行已换成 `~/.nnbdc_aliyun_creds` 那把（ID 前缀 `LTAI5t7H`），旧版备份在 `aliyun-cdn.sh.bak.20261012`；但 `~/.zprofile` 里那把旧 key 本身**尚未在 RAM 里删除/禁用**，仍待处理。
- 私钥副本（`/root/certdeploy`、`/tmp/acmehome`）处理完务必删除；`archive/*/privkey*.pem` 保持 `root:root 600`。
- 若用户决定把 RAM 子账号 key 存进 `~/.nnbdc_aliyun_creds` 留作长期自动续期 → 就别删；否则处理完禁用/删除。

## 7. 长期续期方案（避免 3 个月后又来一遍）

证书 90 天、LE 约到期前 30 天续期。服务器直连 LE 不可靠 → **服务器上的 certbot cron 注定还会失败**。三选一：
- **A'（本次采用）**：在能连 LE 的机器（Mac）用 acme.sh DNS-01 续期 + 自动部署到服务器/CDN。
- **B（最稳，推荐后续切）**：改用阿里云免费 DV 证书（单域名、3 个月、每账号一年 20 张），内网签发/续期，CDN 一键部署 → 彻底摆脱 LE 跨境。（需两张：www + back）
- **C**：给服务器配到 LE 的代理/隧道，让 certbot 能直连（需长期维护网络）。

## 8. 本次基线（2026-09-03 处理完成）

- `www.nnbdc.com` / `back.nnbdc.com` 证书均有效至 **2026-12-02**；归档版本 nnbdc.com=v9、back.nnbdc.com=v10；nginx 已 reload、CDN 已更新（`ServerCertificateStatus:on`）。
- 下次到期提醒 ≈ **2026-11-02**，届时按本 skill 处理；优先考虑切到方案 B（阿里云证书）根治。

## 9. 2026-10-12 巡检结论与改动

- **巡检结果**：两张证书仍是 2026-09-03 签发、**2026-12-02 到期（剩 50 天）**；公网呈现正确（`www` 由 CDN、`back` 由源站 nginx，issuer=`Let's Encrypt YR2`）。cron 与 crond 均正常。
- **历史失败记录**（`/var/log/certbot-renew.log`）：2026-06-01 `nnbdc.com` 挑战失败（`Some challenges have failed`，HTTP-01 webroot）；**2026-09-01 两张证书都因连 `acme-v02.api.letsencrypt.org` 超时 45 秒失败**（跨境断链），靠 09-03 手工 DNS-01 补签才续到 12-02；2026-10-01 正常（`not yet due`）。
- **改动 1**：cron 由 `0 3 1 * *` 改为 `0 3 * * *`，备份 `/root/crontab.bak.20261012`。
- **改动 2**：`aliyun-cdn.sh` 的旧 key 换成 `~/.nnbdc_aliyun_creds` 那把，实测上传 CDN 成功，备份 `aliyun-cdn.sh.bak.20261012`。
- **全链路演练**：手动执行 `renew-cert.sh` 通过（certbot `not due` → nginx reload → 新 key 上传 CDN 成功，`RequestId: 01A1308A-B385-5FA0-9819-EA3CAA254228`）。
- 巡检时实测服务器到 LE 连通性为 **HTTP 200（通的）**，说明跨境链路是**时通时断**而非永久不通——这正是必须靠"每天跑"来兜住的原因。
- **待办**：① `~/.zprofile` 里那把被判泄露的旧 key 需在 RAM 删除/禁用；② 11-02 之后留意自动续期是否真的签下来（每天都有机会）；③ 建议切方案 B（阿里云免费 DV 证书）彻底摆脱跨境。
