#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把宠物定稿图拆成动画用的分层素材。

输出三样东西：
  1. <名字>_身体层.png     —— 五官被抹掉的身体，用于呼吸/弹跳/挤压/旋转
  2. <名字>_眼睛层.png     —— 整张定稿图，眨眼时整层淡出即可露出身体层
  3. <名字>_光核层.png     —— 只保留内部发光核的透明层，用于发光脉冲

因为身体层与眼睛层来自同一张图，叠回去就是原图，所以叠层不会有任何缝隙或色差。

用法：
  .venv/bin/python tools/pet_assets/export_layers.py \
      --base assets/images/pet/guardian_gel_正面.png --out-dir app/assets/images/pet/layers
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageChops

# 与 make_moods.py 保持一致的五官坐标（扫描定位得来）
BASE_HEIGHT = 1116
LEFT_EYE = (161, 434, 44, 58)
RIGHT_EYE = (422, 434, 44, 58)
MOUTH_BOX = (240, 440, 330, 500)
FACE_SKIN = (196, 240, 208)
FACE_BOX = (96, 350, 486, 560)   # 整张脸的范围，眼睛层与身体层在这块区域互补
# 内部发光核区域（相对图宽高的比例），只保留这块的亮部作为光核层
CORE_BOX = (0.36, 0.52, 0.66, 0.78)


def face_mask(size, ratio):
    """脸部区域的椭圆遮罩，用于把眼睛层与身体层切成互补的两块。"""
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    x0, y0, x1, y1 = FACE_BOX
    draw.ellipse((x0 * ratio, y0 * ratio, x1 * ratio, y1 * ratio), fill=255)
    return mask


def erase_face(image):
    """把图切成互补的两层：眼睛层（脸部椭圆内）与身体层（椭圆外）。

    掩膜必须是**二元**的，不做羽化：羽化过的掩膜会让两层在过渡带上都变成
    半透明，叠加后的颜色是两层的加权混合，与原图对不上，实测脸上会浮出一圈
    可见的轮廓线。硬边掩膜下两层 alpha 互补，叠回去与原图像素一致。

    身体层不做任何「补脸」修补：脸部整块归眼睛层，所以不需要在身体层上画
    扁平肤色补丁（那会引入原图里不存在的颜色）。
    """
    size = image.size
    ratio = image.height / BASE_HEIGHT
    mask = face_mask(size, ratio)
    inverse = ImageChops.invert(mask)

    alpha = image.getchannel("A")
    eyes_layer = image.copy()
    eyes_layer.putalpha(ImageChops.multiply(alpha, mask))
    body_layer = image.copy()
    body_layer.putalpha(ImageChops.multiply(alpha, inverse))
    return body_layer, eyes_layer


def extract_core(image):
    """抽出内部发光核：只保留中心区域的明亮像素，四周羽化。"""
    width, height = image.size
    box = (round(CORE_BOX[0] * width), round(CORE_BOX[1] * height), round(CORE_BOX[2] * width), round(CORE_BOX[3] * height))
    core = image.crop(box).convert("RGBA")
    pixels = core.load()
    for y in range(core.height):
        for x in range(core.width):
            r, g, b, a = pixels[x, y]
            brightness = (r + g + b) / 3
            alpha = 0 if brightness < 150 else min(255, int((brightness - 150) * 3.2))
            if a == 0:
                alpha = 0
            pixels[x, y] = (r, g, b, min(alpha, a))
    core = core.filter(ImageFilter.GaussianBlur(6))
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    layer.paste(core, (box[0], box[1]), core)
    return layer


def check_roundtrip(base, body, eyes):
    """校验「身体层 + 眼睛层」与定稿图一致。"""
    recombined = body.copy()
    recombined.alpha_composite(eyes)
    diff = ImageChops.difference(recombined.convert("RGBA"), base.convert("RGBA"))
    bbox = diff.getbbox()
    return bbox


def main():
    parser = argparse.ArgumentParser(description="导出宠物动画分层素材")
    parser.add_argument("--base", required=True, help="定稿图（透明底）")
    parser.add_argument("--out-dir", required=True, help="输出目录")
    parser.add_argument("--name", default=None, help="输出文件名前缀，默认取输入文件名")
    args = parser.parse_args()

    base = Image.open(args.base).convert("RGBA")
    prefix = args.name or os.path.splitext(os.path.basename(args.base))[0]
    os.makedirs(args.out_dir, exist_ok=True)

    body, eyes = erase_face(base)
    core = extract_core(base)

    outputs = {
        "身体层": body,
        "眼睛层": eyes,
        "光核层": core,
    }
    for label, image in outputs.items():
        path = os.path.join(args.out_dir, f"{prefix}_{label}.png")
        image.save(path)
        print(f"已保存 {path} ({image.width}x{image.height})")

    bbox = check_roundtrip(base, body, eyes)
    if bbox:
        print(f"⚠️ 叠层与原图不一致，差异范围 {bbox}", file=sys.stderr)
        return 1
    print("叠层校验通过：身体层 + 眼睛层 = 原图（像素完全一致）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
