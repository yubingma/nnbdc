#!/usr/bin/env bash
# 安装 tools/git-hooks/ 下的钩子到 .git/hooks/（幂等）。
# 让被跟踪的那份成为单一真源：新 clone 不再丢失 pre-push 全量测试门禁。
# 用法：bash tools/install_git_hooks.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SRC_DIR="$REPO_ROOT/tools/git-hooks"
DST_DIR="$REPO_ROOT/.git/hooks"

if [ ! -d "$SRC_DIR" ]; then
    echo "❌ 找不到钩子源目录：$SRC_DIR" >&2
    exit 1
fi
mkdir -p "$DST_DIR"

# core.hooksPath 非空时 git 不读 .git/hooks，装了也不会生效
hooks_path="$(git config --get core.hooksPath || true)"
if [ -n "$hooks_path" ]; then
    echo "⚠️  检测到 core.hooksPath=$hooks_path —— 钩子不会从 .git/hooks 读取，装了也不生效。" >&2
    echo "    请先执行 git config --unset core.hooksPath 后再安装。" >&2
fi

installed=0
for src in "$SRC_DIR"/*; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    dst="$DST_DIR/$name"

    if [ -L "$dst" ]; then
        echo "✔ $name 已安装（符号链接），跳过"
        chmod +x "$src"
        continue
    fi

    if [ -e "$dst" ]; then
        bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
        mv "$dst" "$bak"
        echo "↩ 原有 $name 已备份为 $(basename "$bak")"
    fi

    ln -s "../../tools/git-hooks/$name" "$dst"
    chmod +x "$src"
    echo "✔ 已安装 $name → tools/git-hooks/$name"
    installed=$((installed + 1))
done

echo
if [ "$installed" -eq 0 ]; then
    echo "无需变更，所有钩子均已就位。"
else
    echo "安装完成（$installed 个）。"
fi
echo "验证：ls -l .git/hooks/pre-push && bash -n .git/hooks/pre-push"
