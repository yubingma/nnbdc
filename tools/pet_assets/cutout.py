#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把生成的宠物图抠成透明底 PNG。

用 rembg（u2net 模型）去背后按不透明像素紧裁，并可选补一圈透明内边距，
便于直接作为 App 资源使用。首次运行会自动下载 u2net 模型（约 176 MB）。

用法：
  .venv/bin/python tools/pet_assets/cutout.py <输入图> [更多输入图...] [--pad 16] [--out-dir 目录]
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image
from rembg import new_session, remove


def cutout(image, session, pad):
    """去背 → 紧裁 → 补透明边距，返回 RGBA 图。"""
    rgba = remove(image.convert("RGBA"), session=session)
    alpha = np.asarray(rgba.getchannel("A"))
    rows = np.flatnonzero(alpha.max(axis=1) > 0)
    cols = np.flatnonzero(alpha.max(axis=0) > 0)
    if rows.size == 0 or cols.size == 0:
        return rgba

    cropped = rgba.crop((cols[0], rows[0], cols[-1] + 1, rows[-1] + 1))
    canvas = Image.new("RGBA", (cropped.width + pad * 2, cropped.height + pad * 2), (0, 0, 0, 0))
    canvas.paste(cropped, (pad, pad))
    return canvas


def main():
    parser = argparse.ArgumentParser(description="宠物图抠透明底")
    parser.add_argument("inputs", nargs="+", help="输入图片路径")
    parser.add_argument("--pad", type=int, default=16, help="补出的透明边距像素")
    parser.add_argument("--out-dir", default=None, help="输出目录，默认与原图同目录")
    args = parser.parse_args()

    session = new_session("u2net")
    for path in args.inputs:
        if not os.path.isfile(path):
            print(f"跳过（不存在）：{path}", file=sys.stderr)
            continue
        out_dir = args.out_dir or os.path.dirname(path)
        os.makedirs(out_dir, exist_ok=True)
        stem = os.path.splitext(os.path.basename(path))[0]
        out_path = os.path.join(out_dir, f"{stem}.cut.png")
        result = cutout(Image.open(path), session, args.pad)
        result.save(out_path)
        print(f"已抠图 {out_path} ({result.width}x{result.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
