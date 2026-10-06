#!/bin/bash
# ==============================================================================
# 官网静态文件发布：上传源站 + 刷新阿里云 CDN + 校验公网内容
#
# 为什么需要这条命令：
#   www.nnbdc.com 走阿里云 CDN。只把文件 scp 到源站（/var/www/html）是不够的 ——
#   CDN 会继续返回旧缓存（实测缓存了 11 小时仍在发旧内容）。商店核验隐私政策链接时
#   读的就是公网 URL，漏刷新会被判「公示信息不符」。所以上传、刷新、校验必须一体完成。
#
# 用法：
#   bash devops/publish-web.sh privacy_android.html
#   bash devops/publish-web.sh index.html privacy_android.html protocol_android.html
#
# 传入的路径相对于仓库根目录，远程落到 /var/www/html/ 下的同名相对路径，
# 公网 URL 即 https://www.nnbdc.com/<相对路径>。
#
# 凭证：
#   服务器密码   取环境变量 nnbdc_server_pwd（~/.zprofile 里已有）
#   阿里云 AK/SK 复用服务器上已有的 /etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh
#   本仓库不保存、也不在命令行上传递任何密钥。
# ==============================================================================
set -e

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SERVER_HOST="47.108.27.205"
SERVER_PORT="22"
SERVER_USER="root"
WEB_ROOT="/var/www/html"
SITE_HOST="www.nnbdc.com"
CDN_REGION="cn-hangzhou"
CDN_CRED_FILE="/etc/letsencrypt/renewal-hooks/deploy/aliyun-cdn.sh"

VERIFY_RETRIES=12     # 公网校验重试次数
VERIFY_WAIT=5         # 每次间隔（秒）

usage() {
    cat << EOF
用法: $0 <相对仓库根的文件路径> [更多文件...]

示例:
  $0 privacy_android.html
  $0 index.html privacy_android.html protocol_android.html

做的事: 上传到源站 /var/www/html/ → 刷新阿里云 CDN 缓存 → 校验公网内容与本地一致
EOF
}

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

if [ -z "${nnbdc_server_pwd:-}" ]; then
    echo "❌ 缺少服务器密码环境变量 nnbdc_server_pwd（应写在 ~/.zprofile 里）"
    exit 1
fi
command -v expect >/dev/null 2>&1 || { echo "❌ 依赖 expect（macOS 自带），未找到"; exit 1; }
command -v scp    >/dev/null 2>&1 || { echo "❌ 依赖 scp，未找到"; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 上传：路径经环境变量传给 expect，避免拼进 ssh/scp 命令行
cat > "$TMP_DIR/upload.exp" <<'EXPECT'
#!/usr/bin/expect -f
set timeout 600
set password $env(nnbdc_server_pwd)
spawn scp -P $env(UP_PORT) -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 \
    $env(UP_LOCAL) $env(UP_USER)@$env(UP_HOST):$env(UP_REMOTE)
expect {
    "password:" { send "$password\r"; exp_continue }
    "yes/no"    { send "yes\r"; exp_continue }
    eof
}
catch wait result
exit [lindex $result 3]
EXPECT

# 刷新：远程命令整体作为一个参数交给 ssh；AK/SK 由服务器上的文件里读，不经过本地命令行
cat > "$TMP_DIR/refresh.exp" <<'EXPECT'
#!/usr/bin/expect -f
set timeout 180
set password $env(nnbdc_server_pwd)
spawn ssh -p $env(UP_PORT) -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 \
    $env(UP_USER)@$env(UP_HOST) $env(REMOTE_CMD)
expect {
    "password:" { send "$password\r"; exp_continue }
    "yes/no"    { send "yes\r"; exp_continue }
    eof
}
catch wait result
exit [lindex $result 3]
EXPECT

md5_of() {
    if command -v md5 >/dev/null 2>&1; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi
}

FAILED=0
for REL in "$@"; do
    REL="${REL#./}"
    LOCAL="$PROJECT_ROOT/$REL"
    REMOTE="$WEB_ROOT/$REL"
    URL="https://$SITE_HOST/$REL"

    echo ""
    echo "=============================================================="
    echo " 发布 $REL"
    echo "=============================================================="

    if [ ! -f "$LOCAL" ]; then
        echo "❌ 本地文件不存在: $LOCAL"
        FAILED=1
        continue
    fi
    LOCAL_MD5="$(md5_of "$LOCAL")"
    echo "  本地: $(wc -c < "$LOCAL" | tr -d ' ') 字节  md5 ${LOCAL_MD5:0:12}"

    # --- 1. 上传到源站 ---
    echo "  [1/3] 上传到源站 $REMOTE ..."
    if ! UP_LOCAL="$LOCAL" UP_REMOTE="$REMOTE" UP_HOST="$SERVER_HOST" UP_USER="$SERVER_USER" \
         UP_PORT="$SERVER_PORT" expect -f "$TMP_DIR/upload.exp" > "$TMP_DIR/upload.log" 2>&1; then
        echo "❌ 上传失败："
        tail -5 "$TMP_DIR/upload.log"
        FAILED=1
        continue
    fi

    # 源站立即核对，确认覆盖成功（失败要立刻暴露，不能等到 CDN 校验才含糊）
    ORIGIN_MD5="$(curl -s -m 20 "http://$SERVER_HOST/$REL" -H "Host: $SITE_HOST" | md5 -q)"
    if [ "$ORIGIN_MD5" != "$LOCAL_MD5" ]; then
        echo "❌ 源站内容与本地不一致（上传未生效），期望 ${LOCAL_MD5:0:12}，实际 ${ORIGIN_MD5:0:12}"
        FAILED=1
        continue
    fi
    echo "        ✅ 源站已是最新"

    # --- 2. 刷新 CDN ---
    echo "  [2/3] 刷新阿里云 CDN 缓存 ..."
    REMOTE_CMD="eval \"\$(grep -E 'ALIBABA_CLOUD_(ACCESS_KEY_|REGION_ID)' $CDN_CRED_FILE)\"; aliyun cdn RefreshObjectCaches --ObjectPath '$URL' --ObjectType File --region $CDN_REGION"
    if ! REMOTE_CMD="$REMOTE_CMD" UP_HOST="$SERVER_HOST" UP_USER="$SERVER_USER" UP_PORT="$SERVER_PORT" \
         expect -f "$TMP_DIR/refresh.exp" > "$TMP_DIR/refresh.log" 2>&1; then
        echo "❌ CDN 刷新调用失败："
        tail -5 "$TMP_DIR/refresh.log"
        FAILED=1
        continue
    fi
    # aliyun CLI 的 JSON 经 expect 的 pty 会夹带回车符；用 sed 取数字最稳（BSD grep 的 \+ 不可靠）
    TASK_ID="$(tr -d '\r' < "$TMP_DIR/refresh.log" | sed -n 's/.*RefreshTaskId[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -1)"
    # 注意：macOS 自带 bash 3.2（本脚本的 #!/bin/bash）解析「裸 $VAR 紧跟中文」时，
    # 会把该中文字符的首字节当成变量名的一部分 —— 变量展开为空、字符还被截断。
    # 所以变量后面接中文时必须写成 ${VAR}（花括号）或补一个空格。全仓库别的脚本同理。
    if [ -n "$TASK_ID" ]; then
        echo "        ✅ 刷新任务已提交（RefreshTaskId: ${TASK_ID}）"
    else
        echo "        ✅ 刷新任务已提交"
    fi

    # --- 3. 校验公网内容 ---
    echo "  [3/3] 校验公网内容 $URL ..."
    OK=false
    for i in $(seq 1 "$VERIFY_RETRIES"); do
        sleep "$VERIFY_WAIT"
        REMOTE_MD5="$(curl -s -m 20 "$URL" | md5 -q)"
        if [ "$REMOTE_MD5" = "$LOCAL_MD5" ]; then
            echo "        ✅ 公网已生效（第 ${i} 次探测，md5 ${REMOTE_MD5:0:12}）"
            OK=true
            break
        fi
    done

    if [ "$OK" != true ]; then
        echo "❌ 公网内容与本地不一致：期望 ${LOCAL_MD5:0:12}，实际 ${REMOTE_MD5:0:12}"
        echo "   可能原因：CDN 刷新尚未完成、或该 URL 命中了不同的缓存键。"
        echo "   处理：稍后重跑本命令，或到阿里云 CDN 控制台确认刷新任务 $TASK_ID 的状态。"
        FAILED=1
    fi
done

echo ""
if [ "$FAILED" = "0" ]; then
    echo "🎉 全部发布完成（源站 + CDN 均已校验通过）"
else
    echo "❌ 有文件发布失败，请按上方提示处理"
    exit 1
fi
