---
name: nnbdc-ssl-renewal
description: 处理 NBDC 线上站点 SSL 证书到期告警/续期（www.nnbdc.com 前端走阿里云 CDN、back.nnbdc.com 后端走源站 nginx）。当阿里云推送"证书即将过期"、或服务器自动续期(cron renew-cert.sh)失败、或用户反馈 HTTPS 证书失效时使用。
whenToUse: 用户提到"SSL 证书快过期"、"阿里云证书告警"、"back.nnbdc.com / www.nnbdc.com 证书问题"、"certbot 续期失败"、"定时续期又没生效"等情况。
---

# NBDC SSL 证书续期 诊断与修复

## 0. 一句话定位

> 证书到期告警 + 自动续期失败，根因有两类，都跟「Let's Encrypt 要跨境」有关：
> ① **服务器 → LE 出网时通时断**（`acme-v02.api.letsencrypt.org` 超时）；
> ② **`www.nnbdc.com` 的 HTTPS 终结在只做中国内地加速的阿里云 CDN 上**，而 LE 的域名校验要从多个地理位置各查一遍，境外那几路连内地边缘节点会超时——只要 www 这一项不过，`nnbdc.com` 这张证书（SAN 含 apex + www）整体就签不下来。**这不是概率问题，是结构性问题。**
>
> 绕开办法是 **DNS-01**（LE 只查 DNS TXT 记录，不访问 www、不访问源站），前提是有一把能写阿里云云解析的 AccessKey。
>
> **2026-10-13 起已落地**：`nnbdc.com` + `www.nnbdc.com` 由服务器上的 acme.sh 走 DNS 校验（每天 cron 自动跑，续期成功自动部署 + 上传 CDN）；`back.nnbdc.com` 继续用 certbot 文件校验（A 记录直连源站，境外可达，实测能自动续）。
>
> ⚠️ **判断"到底续没续上"的唯一硬证据**：`/etc/letsencrypt/archive/<域名>/` 里出现了新的版本号文件（连同 `openssl x509 -noout -dates` 的 notAfter 推后）。日志里那句 `任务圆满完成` / `Reload successful` 只代表**脚本三步跑完了**，证书可能一个字都没换（certbot 判 `not yet due` 时会跳过签发，但脚本照旧 reload nginx 并重新上传旧证书到 CDN）。2026-10 那几次"续期成功"就是这么被误读的。

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

`/root/renew-cert.sh` 每天跑三件事（2026-10-13 起）：

1. **`back.nnbdc.com`：certbot 文件校验**（Docker 里 `certbot renew`，不带 `--webroot`，让每条 renewal 配置用自己保存的校验方式）。
2. `docker exec nginx nginx -s reload`。
3. **`nnbdc.com` + `www.nnbdc.com`：acme.sh DNS 校验**（`/root/.acme.sh/acme.sh --cron`，先 `source /root/.aliyun_dns_creds` 提供阿里云密钥）。真正续期成功时，acme.sh 自动执行 `/root/deploy-nnbdc-cert.sh`：写入 `archive/nnbdc.com` 下一个版本号 → 切换 live 软链 → `nginx -t` + reload → `aliyun cdn SetCdnDomainSSLCertificate` 上传到 `www.nnbdc.com`。

**关键坑**：`www` 那张不能用文件校验（见 §0 的根因②，2026-10-13 干跑实测两次校验点都因超时失败）；`back` 那张反而可以，因为它直连源站、不经 CDN。

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
> 2026-10-13 起这套步骤已脚本化为 **`/root/deploy-nnbdc-cert.sh`**（由 acme.sh 的 `--reloadcmd` 在续期成功后自动调用），正常情况下不需要再手敲。下面保留手工步骤备查。
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

## 5. 凭证来源（本地 + 服务器，勿外泄）

- **服务器上（自动续期用，2026-10-13 起）**：`/root/.aliyun_dns_creds`（权限 600，仅 root）。里面同时导出 `ALIBABA_CLOUD_ACCESS_KEY_ID/SECRET/REGION_ID`（给 `aliyun` 命令行用）和 `Ali_Key`/`Ali_Secret`（给 acme.sh 的 `dns_ali` 用）。`/root/renew-cert.sh` 与 `/root/deploy-nnbdc-cert.sh` 都 `source` 它。acme.sh 自己还会在 `/root/.acme.sh/account.conf`（600）存一份 `SAVED_Ali_Key`，属正常。
- 证书续期用的阿里云 RAM AccessKey 也存在本机 **`~/.nnbdc_aliyun_creds`**（权限 600，**不要提交 git / 不要云同步**）。内容两行：`ALIYUN_SSL_AK_ID=...`、`ALIYUN_SSL_AK_SECRET=...`。用 `source` 加载。
- 我的沙箱**写不进** home（所以该文件由用户在本机创建），但**能读取**；下次直接 `source` 即可，无需用户重新提供。
- SSH 服务器密码在 `~/.zprofile`（`PROD_DB_SSH_PASSWORD` / `nnbdc_server_pwd`）。

## 6. 安全红线

- 生产环境**默认只读**；涉及证书部署/替换/上传 CDN/改 nginx 需**用户明确授权**。
- **不要**在对话/输出里回显 AccessKey Secret 或私钥明文；一律 `source ~/.nnbdc_aliyun_creds`。
- `~/.zprofile` 里那把旧 AccessKey（`aliyun_access_key_id`，ID 前缀 `LTAI5tFX`）**已被阿里云判"泄露风险"**。✅ 2026-10-12 服务器脚本里的 key 已换成新那把（ID 前缀 `LTAI5t7H`）。⚠️ **2026-10-13 实测：这把旧 key 目前仍然能正常调用阿里云接口**（`aliyun alidns DescribeDomains` 成功返回域列表），也就是说它还在生效、风险是活的，**必须在 RAM 里禁用或删除**（需要账号管理权限，我这边只有 DNS + CDN 权限，做不了）。
- 服务器上含明文 key 的文件及权限：`/root/.aliyun_dns_creds`（600）、`/root/.acme.sh/account.conf`（600）、`/root/nnbdc-cert-backup-20261013/aliyun-cdn.sh*.orig|retired*`（600，历史备份，含当时那把 key）。
- 容器内那个必然报错的 certbot deploy 钩子（`/etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh`，容器里没有 `aliyun` 命令）已于 2026-10-13 **退休**，挪到 `/root/nnbdc-cert-backup-20261013/`；CDN 上传改由 `/root/deploy-nnbdc-cert.sh` 在宿主机做。
- 私钥副本（`/root/certdeploy`、`/tmp/acmehome`）处理完务必删除；`archive/*/privkey*.pem` 保持 `root:root 600`。
- 若用户决定把 RAM 子账号 key 存进 `~/.nnbdc_aliyun_creds` 留作长期自动续期 → 就别删；否则处理完禁用/删除。

## 7. 长期续期方案

证书 90 天、LE 按 ARI 窗口在到期前约 30 天续期。三条路：
- **A'（2026-10-13 已在服务器上落地，现在的正式方案）**：服务器上用 **acme.sh + 阿里云 DNS 校验（`--dns dns_ali`）** 续 `nnbdc.com`+`www`，每天由 `/root/renew-cert.sh` 调 `--cron`；`back` 继续用 certbot 文件校验。不需要手工、不需要 Mac 参与、不依赖任何入站可达性（新增脚本 `/root/deploy-nnbdc-cert.sh` 负责部署 + 上传 CDN）。
- **B（用户 2026-10-13 明确不做）**：阿里云免费 DV 证书（内网签发/续期，CDN 一键部署）。用户反馈"不好弄"，不要再反复推荐。
- **C**：给服务器配到 LE 的代理/隧道，让 certbot 能直连（需长期维护网络）。
- 另有一条"让文件校验重新可用"的路：给 CDN 开通**全球加速**（现在 `Scope=domestic`、`GlobalResourcePlan=off`）——要花钱且改变 CDN 结构，用户未采纳。

## 8. 历史基线（2026-09-03）

- `www.nnbdc.com` / `back.nnbdc.com` 证书均有效至 **2026-12-02**；归档版本 nnbdc.com=v9、back.nnbdc.com=v10；nginx 已 reload、CDN 已更新（`ServerCertificateStatus:on`）。
- 下次到期提醒 ≈ **2026-11-02**，届时按本 skill 处理；优先考虑切到方案 B（阿里云证书）根治。

## 9. 2026-10-12 巡检结论与改动

- **巡检结果**：两张证书仍是 2026-09-03 签发、**2026-12-02 到期（剩 50 天）**；公网呈现正确（`www` 由 CDN、`back` 由源站 nginx，issuer=`Let's Encrypt YR2`）。cron 与 crond 均正常。
- **历史失败记录**（`/var/log/certbot-renew.log`）：2026-06-01 `nnbdc.com` 挑战失败（`Some challenges have failed`，HTTP-01 webroot）；**2026-09-01 两张证书都因连 `acme-v02.api.letsencrypt.org` 超时 45 秒失败**（跨境断链），靠 09-03 手工 DNS-01 补签才续到 12-02；2026-10-01 正常（`not yet due`）。
- **改动 1**：cron 由 `0 3 1 * *` 改为 `0 3 * * *`，备份 `/root/crontab.bak.20261012`。
- **改动 2**：`aliyun-cdn.sh` 的旧 key 换成 `~/.nnbdc_aliyun_creds` 那把，实测上传 CDN 成功，备份 `aliyun-cdn.sh.bak.20261012`。
- **全链路演练**：手动执行 `renew-cert.sh` 通过（certbot `not due` → nginx reload → 新 key 上传 CDN 成功，`RequestId: 01A1308A-B385-5FA0-9819-EA3CAA254228`）。
- 巡检时实测服务器到 LE 连通性为 **HTTP 200（通的）**，说明跨境链路是**时通时断**而非永久不通——这正是必须靠"每天跑"来兜住的原因。
- **待办（已被 §10 取代）**：① `~/.zprofile` 里那把被判泄露的旧 key 需在 RAM 删除/禁用（2026-10-13 实测**仍然有效**，见 §6）；② ~~11-02 之后留意自动续期~~（已查明 11-02 起的 HTTP 文件校验对 www 必失败，见 §10）；③ 不再建议切阿里云 DV 证书（用户明确不做）。

## 10. 2026-10-13 巡检结论与改动（换了续期机制）

### 10.1 巡检发现

- 两张证书当时仍是 **2026-09-03 签发、2026-12-02 到期**；`/etc/letsencrypt/archive/` 里 nnbdc.com 最新是 `cert9.pem`、back 最新是 `cert10.pem`，**整个 10 月没有产生任何新版本文件**。
- **10 月那几次"续期成功"是误读**：`/var/log/certbot-renew.log` 里 2026-10-01（以及 10-12 的手工演练）中，certbot 明确写的是 `Certificate not yet due for renewal` / `No renewals were attempted`，**一张都没签**；脚本照旧 reload nginx、把**旧证书**重新上传 CDN，最后打印"任务圆满完成"。LE 只在到期前 30 天内才真续（12-02 到期 → **11-02** 才第一次真尝试），所以 10 月怎么看都"成功"。
- 一次 `certbot renew --dry-run`（staging、不签发/不替换/不部署）当场测出真相：
  - ✅ `back.nnbdc.com` 模拟续期成功；
  - ❌ `nnbdc.com` + `www.nnbdc.com` 失败，LE 原话：`During secondary validation: 103.228.211.36: Fetching http://www.nnbdc.com/.well-known/acme-challenge/…: Timeout during connect (likely firewall problem)`，另一个地址是 `45.123.128.188`。注意这两个 IP 是**校验时 www 被解析出来的目标地址**（广西广电 AS63581 / 吉视传媒 AS63701），**不是** LE 校验机的地址。
- 两个根因：
  1. **nginx 写错位置**：`conf.d/default.conf` 里 `nnbdc.com` 服务器块把 `return 301 http://www.nnbdc.com$request_uri;` 写在 **server 级**，nginx 在挑选 location 之前就执行它 → 那个 `location /.well-known/acme-challenge/` 等于不存在，校验请求被 301 到 www（实测：apex 挑战路径 301；在源站上用 `Host: nnbdc.com` 直连也是 301）。2026-06-01 的 `403`、以及 `cert7` 于 06-12 到期而 06-14 才补上（www 真断 2 天），都是这个坑。
  2. **结构性**：`www.nnbdc.com` → 阿里云 CDN（`Scope=domestic` 仅内地加速，`GlobalResourcePlan=off`），源站 `47.108.27.205:80`。LE 的多地校验必然有境外几路连内地边缘节点超时，www 一项不过 → 整张证书签不下来。**只修 nginx 解决不了这个**（这也是当初不再走 HTTP 校验、直接切 DNS 校验的原因）。

### 10.2 本次改动（已执行）

| 项 | 内容 |
|---|---|
| 续期工具 | 服务器装 **acme.sh v3.1.7**（`/root/.acme.sh`，`--nocron`，不登记它自己的 cron） |
| 密钥 | 新建 `/root/.aliyun_dns_creds`（600），从原 `aliyun-cdn.sh` 取同一把 key（ID 前缀 `LTAI5t7H…`） |
| 校验方式 | `nnbdc.com`+`www` 改 **DNS-01**；`/etc/letsencrypt/renewal/nnbdc.com.conf` 停用（改名 `…conf.disabled-20261013`，certbot 只扫 `*.conf`） |
| 每日脚本 | `/root/renew-cert.sh` 重写：certbot 只管 back → reload nginx → `acme.sh --cron` 管 nnbdc.com |
| 部署脚本 | 新增 `/root/deploy-nnbdc-cert.sh`（700）：archive 版本 +1 → 切 live 软链 → `nginx -t` + reload → 上传 CDN；由 acme.sh 的 `--reloadcmd` 自动调用 |
| nginx | `conf.d/default.conf`：`return 301` 挪进 `location / {}`，校验目录恢复生效（apex 挑战路径由 301 变为 404） |
| 清理 | 删 `/var/www/html/.well-known/acme-challenge/test.txt`（6-14 残留）；容器内那个必报错的 deploy 钩子挪进备份目录；`/root/nnbdc-cert-backup-20261013/` 统一 700/600 |
| 仓库同步 | `devops/renew-cert.sh`、`devops/deploy-nnbdc-cert.sh`、`devops/nginx/conf.d/default.conf` 与服务器文件 md5 完全一致 |

### 10.3 验证结果

- 新证书 **2026-10-13 01:08 签发，有效至 2027-01-10 16:15:28 UTC**（首签写 archive v10，强制续期演练写 v11，live 软链指向 v11；私钥 600、证书与私钥配对）。
- 源站与 CDN 都换了新证书：服务器 `curl https://www.nnbdc.com/` → 200，链为 `nnbdc.com → YR1 → ISRG Root YR`，`Verify return code: 0 (ok)`；指定边缘节点 `1.194.31.54`、`111.62.97.177` 出示的都是新证书；CDN 证书列表里出现到期 2027-01-10 的新条目。
- **强制演练了一次真实续期**（`acme.sh --cron --force`，等同 2026-12-12 那次）：DNS TXT 增删 → 签发 → 自动部署 v11 → reload nginx → 上传 CDN，全程零人工，结尾 `Reload successful`。
- 手动跑 `/root/renew-cert.sh` 退出码 0：certbot 只处理 back（`not yet due`），acme.sh 打印 `Skipping. Next renewal time is: 2026-12-12T04:20:41Z`。
- `back.nnbdc.com` 的证书与 renewal 配置**未被本次改动碰到**（仍是 certbot webroot 方式）。
- ⚠️ 巡检时我这台 Mac 访问 `www.nnbdc.com` 一度失败（`SSL_ERROR_SYSCALL`），原因是我这条线路到北京联通 `124.200.113.7x` 那几个边缘节点不通——**同一节点从成都服务器访问是 200，境外 11 国节点也是 200**。与证书更换无关，别被它带偏。

### 10.4 下次要做的

- **2026-12-12 之后**核对 `/var/log/certbot-renew.log` 与 `/etc/letsencrypt/archive/nnbdc.com/` 里是否出现 v12（判据见 §0 警示）。若迟迟不出现，只查服务器 → LE 的出网，不要去查 www/CDN。
- RAM 里那把旧 key（§6）需用户处理。
