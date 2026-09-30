#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把抠好的宠物图归一化成「同高同画布」的三视图交付物。

输入若干张已去背的 RGBA 图（各视角一张），统一缩放到同一高度、居中放进同一块
透明画布，输出逐个视角的 PNG 与一张带标注的三视图设定表。
这样各视角的体型比例一致，可直接交给矢量/动效环节复刻。

用法：
  .venv/bin/python tools/pet_assets/normalize_views.py \
      --view 正面=tmp/pet_assets/gel_front-1.cut.png \
      --view 侧面=tmp/pet_assets/gel_side-1.cut.png \
      --view 背面=tmp/pet_assets/gel_back-1.cut.png \
      --out-dir assets/images/pet --name guardian_gel
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

LABEL_FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def normalize(images, target_height):
    """按统一高度缩放并居中，返回 (图, 该图名称) 列表与统一画布尺寸。"""
    scaled = []
    for name, image in images:
        ratio = target_height / image.height
        scaled.append((name, image.resize((max(1, round(image.width * ratio)), target_height), Image.LANCZOS)))

    gap = round(target_height * 0.12)
    canvas_w = sum(image.width for _, image in scaled) + gap * (len(scaled) + 1)
    canvas_h = target_height + gap * 2

    placed = []
    x = gap
    for name, image in scaled:
        placed.append((name, image, x))
        x += image.width + gap
    return placed, (canvas_w, canvas_h)


def main():
    parser = argparse.ArgumentParser(description="宠物三视图归一化")
    parser.add_argument("--view", action="append", required=True, metavar="名称=路径",
                        help="视角名与图片路径，可重复；顺序即拼接顺序")
    parser.add_argument("--out-dir", required=True, help="输出目录")
    parser.add_argument("--name", required=True, help="输出文件名前缀")
    parser.add_argument("--height", type=int, default=900, help="统一高度（像素）")
    parser.add_argument("--icon-size", type=int, default=0, help="改为方形图标模式：输出 N×N 居中透明图标")
    args = parser.parse_args()

    views = []
    for item in args.view:
        if "=" not in item:
            print(f"参数格式应为 名称=路径：{item}", file=sys.stderr)
            return 1
        name, path = item.split("=", 1)
        if not os.path.isfile(path):
            print(f"图片不存在：{path}", file=sys.stderr)
            return 1
        views.append((name, Image.open(path).convert("RGBA")))

    placed, (canvas_w, canvas_h) = normalize(views, args.height)
    os.makedirs(args.out_dir, exist_ok=True)

    if args.icon_size:
        side = args.icon_size
        for name, image, _ in placed:
            ratio = (side * 0.82) / image.height
            resized = image.resize((max(1, round(image.width * ratio)), round(image.height * ratio)), Image.LANCZOS)
            icon = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            icon.paste(resized, ((side - resized.width) // 2, (side - resized.height) // 2), resized)
            path = os.path.join(args.out_dir, f"{name}.png")
            icon.save(path)
            print(f"已保存 {path} ({icon.width}x{icon.height})")
        return 0

    for name, image, x in placed:
        single = Image.new("RGBA", (image.width, canvas_h), (0, 0, 0, 0))
        single.paste(image, (0, (canvas_h - image.height) // 2), image)
        path = os.path.join(args.out_dir, f"{args.name}_{name}.png")
        single.save(path)
        print(f"已保存 {path} ({single.width}x{single.height})")

    sheet = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    for _, image, x in placed:
        sheet.paste(image, (x, (canvas_h - image.height) // 2), image)
    sheet_path = os.path.join(args.out_dir, f"{args.name}_三视图.png")
    sheet.save(sheet_path)
    print(f"已保存 {sheet_path} ({sheet.width}x{sheet.height})")

    try:
        font = ImageFont.truetype(LABEL_FONT, max(18, args.height // 40))
    except OSError:
        font = ImageFont.load_default()
    preview = Image.new("RGB", (canvas_w + 80, canvas_h + 90), (18, 20, 24))
    preview.paste(sheet, (40, 20), sheet)
    draw = ImageDraw.Draw(preview)
    for name, image, x in placed:
        draw.text((x - 20, canvas_h + 34), name, fill=(200, 206, 216), font=font)
    preview_path = os.path.join(args.out_dir, f"{args.name}_三视图_深色底预览.png")
    preview.save(preview_path)
    print(f"已保存 {preview_path} ({preview.width}x{preview.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
