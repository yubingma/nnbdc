#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从生产服务器取「词核心图」到本地缓存。

词核心图由服务端批量生成后落在 /var/www/html/img/core_images/core_<wordId>.jpeg，
数据库 word_core_image 里只存相对路径。本脚本按单词查出路径，再把图 scp 下来，
统一放到 tmp/xhs_video_pipeline/core_images/，供视频生成脚本使用。

用法：
    python3 tools/xhs_video_pipeline/fetch_core_images.py spring charge run
    python3 tools/xhs_video_pipeline/fetch_core_images.py --episode tools/xhs_video_pipeline/episodes/ci01_spring.json

只读：仅 SELECT 本地库 + scp 拉取远程文件，绝不写生产库、绝不在服务器上留东西。
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
DEST_DIR = ROOT_DIR / "tmp" / "xhs_video_pipeline" / "core_images"
REMOTE_DIR = "/var/www/html/img/core_images"


def profile_value(name):
    """从 ~/.zprofile 读取变量（不回显值）。"""
    if os.environ.get(name):
        return os.environ[name]
    for line in (Path.home() / ".zprofile").read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip().removeprefix("export ").strip()
        if line.startswith(f"{name}="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def lookup(words):
    """查本地 bdc 库，返回 {单词: 服务器文件名}。"""
    quoted = ",".join("'" + w.replace("'", "''") + "'" for w in words)
    sql = (f"select word, image_url from word_core_image "
           f"where word in ({quoted}) and image_url is not null and image_url <> ''")
    out = subprocess.run(["psql", "-d", "bdc", "-t", "-A", "-F", "\t", "-c", sql],
                         check=True, capture_output=True).stdout.decode()
    found = {}
    for line in out.strip().splitlines():
        if "\t" in line:
            word, url = line.split("\t", 1)
            found[word] = Path(url).name
    return found


def remote_pull(names, dest):
    """用 sshpass 批量拉取；密码只经环境变量传递，不进 argv。"""
    user = profile_value("PROD_DB_SSH_USER") or "root"
    host = profile_value("PROD_DB_SSH_HOST")
    password = profile_value("nnbdc_server_pwd") or profile_value("PROD_DB_SSH_PASSWORD")
    if not (host and password):
        raise SystemExit("缺少生产服务器连接信息（~/.zprofile 的 PROD_DB_SSH_HOST / nnbdc_server_pwd）")
    env = {**os.environ, "SSHPASS": password}
    opts = ["-o", "StrictHostKeyChecking=no",
            "-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no"]
    if not shutil.which("sshpass"):
        raise SystemExit("未安装 sshpass：brew install sshpass")
    missing = []
    for word, name in names.items():
        if (dest / name).exists():
            continue
        src = f"{user}@{host}:{REMOTE_DIR}/{name}"
        r = subprocess.run(["sshpass", "-e", "scp", *opts, src, str(dest / name)],
                           env=env, capture_output=True)
        if r.returncode != 0:
            missing.append(word)
    return missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("words", nargs="*", help="单词拼写")
    ap.add_argument("--episode", help="也可以直接给单集脚本 JSON，自动取出其中的 core_art / word")
    args = ap.parse_args()

    words = list(args.words)
    if args.episode:
        cfg = json.loads(Path(args.episode).read_text(encoding="utf-8"))
        words.append(cfg["word"])
    if not words:
        raise SystemExit("至少给一个单词，或用 --episode 指定单集脚本")

    DEST_DIR.mkdir(parents=True, exist_ok=True)
    names = lookup(sorted(set(words)))
    for w in sorted(set(words)):
        if w not in names:
            print(f"⚠️  {w}：库里没有可用的词核心图（未生成或不适用）")
    if names:
        missing = remote_pull(names, DEST_DIR)
        for w, n in names.items():
            if w in missing:
                print(f"❌ {w}：远程取图失败")
            else:
                print(f"✅ {w} → {DEST_DIR / n}")
    print(f"\n词核心图缓存目录：{DEST_DIR}")


if __name__ == "__main__":
    sys.exit(main())
