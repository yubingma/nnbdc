#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""记忆守护兽形象生成（阿里云百炼 DashScope · 通义万相文生图）。

功能：
  - 同步提交 text2image 任务并下载成图（万相文生图默认走同步返回，无需轮询）
  - 一次可出多张候选（--n），用于人工挑选
  - API Key 从 ~/.zprofile 读取，不硬编码、不回显

用法示例：
  python3 tools/pet_assets/gen_pet.py \
      --prompt "一只圆润的半透明凝胶小守护兽……" \
      --out assets/images/pet/guardian_base.png
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

ENDPOINT = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis"
MODEL = "wan2.2-t2i-flash"
NEGATIVE_PROMPT = (
    "文字, 字母, 水印, 签名, 多只生物, 重复角色, 畸形肢体, 多余眼睛, "
    "低分辨率, 模糊, 杂乱背景, 真实照片"
)


def load_api_key(zprofile=None):
    """从 ~/.zprofile 读取 dashscope_api_key。"""
    zprofile = zprofile or os.path.expanduser("~/.zprofile")
    with open(zprofile, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    matched = re.search(r"(?m)^\s*(?:export\s+)?dashscope_api_key\s*=\s*(.*)\s*$", text)
    if not matched:
        raise RuntimeError(f"在 {zprofile} 里没找到 dashscope_api_key")
    return matched.group(1).strip().strip('"').strip("'")


def generate(api_key, prompt, size, count, seed, model):
    """提交一次文生图请求，返回图片 URL 列表。"""
    body = {
        "model": model,
        "input": {"prompt": prompt, "negative_prompt": NEGATIVE_PROMPT},
        "parameters": {
            "size": size,
            "n": count,
            "prompt_extend": False,
            "watermark": False,
        },
    }
    if seed >= 0:
        body["parameters"]["seed"] = seed
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as err:
        raise RuntimeError(f"提交失败 HTTP {err.code}: {err.read().decode('utf-8', 'replace')[:500]}")

    metrics = payload.get("task_metrics") or {}
    if metrics.get("FAILED"):
        raise RuntimeError(f"生图失败: {json.dumps(payload, ensure_ascii=False)[:500]}")
    results = (payload.get("output") or {}).get("results") or []
    urls = [item["url"] for item in results if item.get("url")]
    if not urls:
        raise RuntimeError(f"返回里没有图片: {json.dumps(payload, ensure_ascii=False)[:500]}")
    return urls


def download(url, path):
    """把成图下载到本地（成图链接 24h 失效，必须立即落盘）。"""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as response, open(path, "wb") as out:
        out.write(response.read())
    return os.path.getsize(path)


def main():
    parser = argparse.ArgumentParser(description="记忆守护兽形象生成（通义万相文生图）")
    parser.add_argument("--prompt", required=True, help="画面描述")
    parser.add_argument("--out", required=True, help="输出路径；--n>1 时自动加 -1/-2 后缀")
    parser.add_argument("--size", default="1024*1024", help="画布尺寸，例如 1024*1024 / 1280*720")
    parser.add_argument("--n", type=int, default=1, help="候选张数（1~4）")
    parser.add_argument("--seed", type=int, default=-1, help="随机种子，固定后便于复现")
    parser.add_argument("--model", default=MODEL, help=f"生图模型，默认 {MODEL}")
    parser.add_argument("--url-only", action="store_true", help="只打印图片链接，不下载")
    args = parser.parse_args()

    api_key = load_api_key()
    urls = generate(api_key, args.prompt, args.size, args.n, args.seed, args.model)

    if args.url_only:
        for url in urls:
            print(url)
        return 0

    stem, ext = os.path.splitext(args.out)
    ext = ext or ".png"
    for index, url in enumerate(urls, start=1):
        path = args.out if len(urls) == 1 else f"{stem}-{index}{ext}"
        size = download(url, path)
        print(f"已保存 {path} ({size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
