#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Wan3.0-video 视频生成模块（阿里云百炼 DashScope）。

功能：
  - 提交 文生视频 (T2V) / 图生视频首帧 (first_frame) / 参考生视频 任务
  - 轮询任务状态直至 SUCCEEDED / FAILED
  - 下载成片到本地

依赖：仅 Python 标准库（urllib / base64 / json）。API Key 从 ~/.zprofile 读取，
不硬编码、不回显。

用法示例：
  # 图生视频（用本地截图做首帧，base64 直传）
  python3 wan3.py --prompt "..." --first-frame design/ui/png/study_preview.png \
      --duration 10 --resolution 720P --ratio 9:16 --out /tmp/wan3_demo.mp4

  # 文生视频
  python3 wan3.py --prompt "..." --duration 5 --resolution 480P --ratio adaptive --out /tmp/a.mp4

  # 参考生视频（多素材，url 或 base64）
  python3 wan3.py --prompt "..." \
      --media '{"type":"reference_image","url":"https://x/a.png"}' \
      --media '{"type":"reference_image","url":"https://x/b.png"}' \
      --duration 8 --resolution 720P --ratio adaptive --out /tmp/r.mp4
"""

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

# 老 DashScope endpoint（已验证可直接路由 wan3.0-video）。如需指定地域/workspace，
# 可改用 https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/... ，见 SKILL.md。
DEFAULT_ENDPOINT = "https://dashscope.aliyuncs.com/api/v1"

PROMPT_MAX = 20000
MODELS = ("wan3.0-video", "wan3.0-video-prime")


def load_api_key(zprofile=None):
    """从 ~/.zprofile 读取 dashscope_api_key，返回字符串；找不到返回 None。

    只解析 `export dashscope_api_key=...`（支持带引号 / 单双引号 / 无引号）。
    """
    zprofile = zprofile or os.path.expanduser("~/.zprofile")
    try:
        with open(zprofile, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return None
    m = re.search(r"(?m)^\s*(?:export\s+)?dashscope_api_key\s*=\s*(.*)\s*$", text)
    if not m:
        return None
    raw = m.group(1).strip()
    # 去掉成对的引号
    for q in ('"', "'"):
        if len(raw) >= 2 and raw[0] == q and raw[-1] == q:
            raw = raw[1:-1]
            break
    return raw or None


def _local_file_to_base64_url(path):
    """把本地图片文件编码为 wan3.0 可接受的 data URL。"""
    p = os.path.abspath(path)
    ext = os.path.splitext(p)[1].lower().lstrip(".")
    mime = {
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "bmp": "image/bmp", "webp": "image/webp",
    }.get(ext, "image/png")
    with open(p, "rb") as fh:
        data = base64.b64encode(fh.read()).decode("ascii")
    return f"data:{mime};base64,{data}"


def resolve_media_url(value):
    """输入可以是本地图片路径（自动转 base64）、data URL、或普通 URL。"""
    if not value:
        return value
    if value.startswith("data:") or value.startswith(("http://", "https://", "oss://")):
        return value
    # 本地文件路径
    if os.path.isfile(value):
        return _local_file_to_base64_url(value)
    # 既不是 URL 也不是存在的本地文件，原样返回（让服务端校验）
    return value


def _post(endpoint, key, path, payload):
    url = endpoint.rstrip("/") + path
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
            "X-DashScope-Async": "enable",
        },
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _get(endpoint, key, path):
    url = endpoint.rstrip("/") + path
    req = urllib.request.Request(url, method="GET", headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def submit(endpoint, key, *, model="wan3.0-video", prompt=None, media=None,
           resolution="480P", ratio="adaptive", duration=5, prompt_extend=True,
           audio=True, watermark=False, seed=-1):
    """提交一次视频生成任务，返回 task_id 字符串。"""
    if model not in MODELS:
        raise ValueError(f"model 必须是 {'/'.join(MODELS)}，收到 {model!r}")
    if not prompt and not media:
        raise ValueError("prompt 与 media 至少提供一个")
    inp = {}
    if prompt:
        inp["prompt"] = prompt[:PROMPT_MAX]
    if media:
        inp["media"] = media
    payload = {"model": model, "input": inp,
               "parameters": {
                   "resolution": resolution,
                   "ratio": ratio,
                   "duration": int(duration),
                   "prompt_extend": bool(prompt_extend),
                   "audio": bool(audio),
                   "watermark": bool(watermark),
                   "seed": int(seed),
               }}
    data = _post(endpoint, key, "/services/aigc/video-generation/video-synthesis", payload)
    out = data.get("output", {})
    task_id = out.get("task_id")
    if not task_id:
        raise RuntimeError(f"提交失败: {data}")
    return task_id


def poll(endpoint, key, task_id, interval=15, timeout=1800, log=print):
    """轮询任务，直到 SUCCEEDED/FAILED/CANCELED。返回最终 dict（含 video_url）。"""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        data = _get(endpoint, key, "/tasks/" + task_id)
        out = data.get("output", {})
        status = out.get("task_status")
        last = data
        if status == "SUCCEEDED":
            return last
        if status in ("FAILED", "CANCELED"):
            raise RuntimeError(f"任务{status}: {data}")
        log(f"[poll] {task_id[:8]} status={status}")
        time.sleep(interval)
    raise TimeoutError(f"任务 {task_id} 轮询超时（>{timeout}s），最后一次状态：{last}")


def download(url, out_path):
    """下载视频到本地。"""
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=300) as resp, open(out_path, "wb") as fh:
        fh.write(resp.read())
    return os.path.abspath(out_path)


def generate_once(endpoint, key, out_path, prompt=None, media=None, **kwargs):
    """提交 + 轮询 + 下载，一步到位。返回本地文件路径。"""
    task_id = submit(endpoint, key, prompt=prompt, media=media, **kwargs)
    print(f"已提交任务 task_id={task_id}")
    result = poll(endpoint, key, task_id)
    out = result.get("output", {})
    url = out.get("video_url")
    if not url:
        raise RuntimeError(f"任务成功但无 video_url: {result}")
    download(url, out_path)
    return os.path.abspath(out_path)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Wan3.0-video 生成")
    ap.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    ap.add_argument("--model", default="wan3.0-video", choices=list(MODELS))
    ap.add_argument("--prompt", default=None)
    ap.add_argument("--first-frame", default=None,
                    help="本地图或 URL，作为视频首帧（图生视频）")
    ap.add_argument("--media", action="append", default=None,
                    help='json 字符串，如 {"type":"reference_image","url":"..."}，可多次')
    ap.add_argument("--duration", type=int, default=5)
    ap.add_argument("--resolution", default="480P", choices=["480P", "720P", "1080P"])
    ap.add_argument("--ratio", default="adaptive")
    ap.add_argument("--prompt-extend", type=int, default=1)
    ap.add_argument("--audio", type=int, default=1)
    ap.add_argument("--watermark", type=int, default=0)
    ap.add_argument("--seed", type=int, default=-1)
    ap.add_argument("--out", required=True, help="输出本地视频文件路径")
    ap.add_argument("--poll-interval", type=int, default=15)
    ap.add_argument("--zprofile", default=None)
    args = ap.parse_args(argv)

    key = load_api_key(args.zprofile)
    if not key:
        print("错误：未在 ~/.zprofile 找到 dashscope_api_key", file=sys.stderr)
        return 2

    media = list(args.media or [])
    if args.first_frame:
        media.insert(0, {
            "type": "first_frame",
            "url": resolve_media_url(args.first_frame),
        })
    for i, m in enumerate(media):
        if not isinstance(m, dict):
            m2 = json.loads(m)
            media[i] = m2
        media[i]["url"] = resolve_media_url(media[i].get("url"))

    try:
        out = generate_once(
            args.endpoint, key, args.out,
            prompt=args.prompt,
            media=media or None,
            model=args.model,
            resolution=args.resolution,
            ratio=args.ratio,
            duration=args.duration,
            prompt_extend=bool(args.prompt_extend),
            audio=bool(args.audio),
            watermark=bool(args.watermark),
            seed=args.seed,
        )
        print("完成:", out)
        return 0
    except Exception as e:  # noqa: BLE001
        print(f"失败：{e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
