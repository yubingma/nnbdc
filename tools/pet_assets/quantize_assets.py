#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把随包发布的宠物素材缩到显示所需分辨率并量化成 256 色，压缩发版体积。

真正的大头不是色彩精度，而是**分辨率过剩**：素材原始高度 1116px，而完成页里宠物
只显示约 116 逻辑像素高，等于按 9 倍高度存储。实测（在 3 倍屏尺寸下与真彩原图比较）
缩到 348px 再量化，色差与真彩几乎无差别，体积只剩两成。

这个脚本要同时处理三个必须一起正确的问题，任何一个处理错都会在真机上肉眼可见：

1. **分辨率过剩** → 缩放到显示高度的 3 倍（348px）。
2. **量化必须保留透明度** → 直接对 RGBA 做 `quantize(FASTOCTREE)`，PIL 会把 alpha
   一并纳入分色，写成带透明度的 P 模式 PNG，体积最小且正确。
   ⚠️ 绝不能走「RGB 取色 + putalpha + convert('P')」：`putalpha` 作用在 P 模式图上
   只是设置**单个**透明索引，渐变透明的边缘与整块透明区域会被填成实色——实测身体层
   的脸部会变成一块实心椭圆，整只宠物破图。
3. **身体层与情绪图必须同色** → 两者在脸部椭圆处互补拼接，若各自取色，同一种肤色
   会被映射到两个近似色，拼缝处浮出一圈可见轮廓（放大后肉眼可辨）。
   做法：先用**共享调色板**把身体层与情绪图都渲染成同一套颜色，再把「已量化的情绪图」
   合成进身体层的脸部空洞——这样身体层在脸部就与情绪图完全同色，之后各自量化也不会
   产生接缝。合成不影响闪烁：眨眼时情绪层淡出，露出的是身体层里同样的一张脸。

用法：
  .venv/bin/python tools/pet_assets/quantize_assets.py \
      --dir app/assets/images/pet --backup assets/images/pet/full
"""

import argparse
import io
import os
import shutil
import sys

from PIL import Image

COLORS = 256
# 完成页里宠物的显示高度（逻辑像素）与目标倍率
DISPLAY_HEIGHT = 116
SCALE = 3
# 身体层与情绪图的文件名（脸部互补拼接的那两张，必须同色处理）
BODY_LAYER = "layers/guardian_gel_正面_身体层.png"
FACE_LAYER = "moods/mood_excited.png"


def collect_pngs(root):
    targets = []
    for current, _, files in os.walk(root):
        for name in sorted(files):
            if name.lower().endswith(".png"):
                targets.append(os.path.join(current, name))
    return sorted(targets)


def resize_to_height(image, target_height):
    if not target_height or image.height <= target_height:
        return image
    width = max(1, round(image.width * target_height / image.height))
    return image.resize((width, target_height), Image.LANCZOS)


def build_shared_palette(images, colors):
    """把所有图拼成一张长图统一取色，得到一套共用调色板。"""
    small = [resize_to_height(image, 220) for image in images]
    width = max(piece.width for piece in small)
    height = sum(piece.height for piece in small)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    y = 0
    for piece in small:
        canvas.paste(piece, (0, y), piece)
        y += piece.height
    return canvas.convert("RGB").quantize(colors=colors, method=Image.FASTOCTREE)


def render_with_palette(image, palette):
    """用共享调色板渲染一遍（只改颜色，保留原始 alpha）。"""
    import numpy as np

    indexed = image.convert("RGB").quantize(palette=palette, dither=Image.NONE).convert("RGBA")
    array = np.asarray(indexed).copy()
    array[:, :, 3] = np.asarray(image.getchannel("A"))
    return Image.fromarray(array, "RGBA")


def to_paletted(image, colors):
    """落成带透明度的 P 模式图，并写回文件。"""
    return image.quantize(colors=colors, method=Image.FASTOCTREE)


def main():
    parser = argparse.ArgumentParser(description="宠物素材缩放 + 量化（保透明度、无接缝）")
    parser.add_argument("--dir", required=True, help="要处理的素材目录（原地覆盖）")
    parser.add_argument("--backup", default=None, help="把真彩原图备份到此目录")
    parser.add_argument("--colors", type=int, default=COLORS, help="调色板颜色数，默认 256")
    parser.add_argument(
        "--height",
        type=int,
        default=DISPLAY_HEIGHT * SCALE,
        help=f"目标高度像素，默认显示高度的 {SCALE} 倍 = {DISPLAY_HEIGHT * SCALE}",
    )
    parser.add_argument("--dry-run", action="store_true", help="只报告体积，不覆盖文件")
    args = parser.parse_args()

    targets = collect_pngs(args.dir)
    if not targets:
        print(f"目录里没有 PNG：{args.dir}", file=sys.stderr)
        return 1

    if args.backup:
        for path in targets:
            relative = os.path.relpath(path, args.dir)
            backup_path = os.path.join(args.backup, relative)
            os.makedirs(os.path.dirname(backup_path), exist_ok=True)
            if not os.path.exists(backup_path):
                shutil.copy2(path, backup_path)

    # 统一缩放到目标高度
    loaded = {}
    for path in targets:
        relative = os.path.relpath(path, args.dir)
        loaded[relative] = resize_to_height(Image.open(path).convert("RGBA"), args.height)

    # 1) 取共享调色板
    palette = build_shared_palette(list(loaded.values()), args.colors)

    # 2) 身体层与情绪图先按共享调色板对齐颜色，再把情绪图合进身体层的脸部空洞
    body_key = next((key for key in loaded if key.endswith(BODY_LAYER)), None)
    face_key = next((key for key in loaded if key.endswith(FACE_LAYER)), None)
    if body_key and face_key:
        aligned_body = render_with_palette(loaded[body_key], palette)
        aligned_face = render_with_palette(loaded[face_key], palette)
        filled_body = aligned_body.copy()
        filled_body.alpha_composite(aligned_face)
        loaded[body_key] = filled_body

    # 3) 逐张量化落盘
    before_total = 0
    after_total = 0
    for relative, image in sorted(loaded.items()):
        path = os.path.join(args.dir, relative)
        before_total += os.path.getsize(path)
        paletted = to_paletted(image, args.colors)
        buffer = io.BytesIO()
        paletted.save(buffer, format="PNG", optimize=True)
        data = buffer.getvalue()
        after_total += len(data)
        if not args.dry_run:
            with open(path, "wb") as fh:
                fh.write(data)
        print(f"{relative:<52}{os.path.getsize(path) // 1024:>6}K → {len(data) // 1024:>5}K")

    saved = 100 - 100 * after_total / before_total if before_total else 0
    print(f"\n合计 {before_total // 1024}K → {after_total // 1024}K，省 {saved:.0f}%")
    if args.backup:
        print(f"真彩原图已备份到 {args.backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
