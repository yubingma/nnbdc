#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把成片导入 macOS「照片」，便于手机端直接发布小红书。

开 iCloud 照片的话，导入后会自动同步到手机相册，不用再 AirDrop 或传微信。
统一归到专辑「小红书 · 词核心图」，不会混进你的照片流。

用法：
    python3 tools/xhs_video_pipeline/to_photos.py                      # 导入 design/ui/video/ 里最新的那条 mp4
    python3 tools/xhs_video_pipeline/to_photos.py a.mp4 b.mp4          # 导入指定文件
    python3 tools/xhs_video_pipeline/to_photos.py --list               # 只看看会导入什么

注意：Photos 不去重，同一个文件导入两次会出现两条。
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from xhs_common import OUT_DIR, PHOTO_ALBUM, import_to_photos  # noqa: E402


def newest_video():
    vids = sorted(OUT_DIR.glob("*.mp4"), key=lambda p: p.stat().st_mtime, reverse=True)
    return vids[0] if vids else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", help="要导入的 mp4；不给则取最新一条成片")
    ap.add_argument("--album", default=PHOTO_ALBUM)
    ap.add_argument("--list", action="store_true", help="只列出待导入的文件，不执行")
    args = ap.parse_args()

    files = [Path(f) for f in args.files]
    if not files:
        latest = newest_video()
        if latest is None:
            raise SystemExit(f"{OUT_DIR} 下没有 mp4")
        files = [latest]

    for f in files:
        if not f.exists():
            raise SystemExit(f"文件不存在：{f}")
    if args.list:
        print(f"将导入「照片」专辑「{args.album}」：")
        for f in files:
            print(f"  {f}  ({f.stat().st_size / 1024 / 1024:.1f}MB)")
        return

    n = import_to_photos(files, album=args.album)
    print(f"📱 已导入「照片」专辑「{args.album}」：{n} 项")
    for f in files:
        print(f"   {f.name}")


if __name__ == "__main__":
    main()
