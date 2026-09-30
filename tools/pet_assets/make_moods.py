#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在锁定的宠物底图上本地改表情，生成四个情绪状态图。

做法：把眼睛区域用脸部的正常肤色盖掉，再重新画上眼睛与嘴；身体、轮廓、发光核
完全不动，因此四张状态图的躯干像素级一致，可直接做动画帧对齐。
「精神饱满」直接复用底图（它是定稿表情）。

用法：
  .venv/bin/python tools/pet_assets/make_moods.py \
      --base assets/images/pet/guardian_gel_正面.png --out-dir app/assets/images/pet/moods
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

# 五官坐标由像素扫描定位（阈值得出：左眼 x121~201、右眼 x381~462、鼻嘴 x276~307，密集行 y370~498）
BASE_HEIGHT = 1116
LEFT_EYE = (161, 434, 42, 56)     # x, y, 半宽, 半高
RIGHT_EYE = (422, 434, 42, 56)
MOUTH_BOX = (248, 452, 322, 492)
FACE_SKIN = (196, 240, 208)
EYE_DARK = (26, 34, 34, 255)


def scaled(points, ratio):
    return [(round(x * ratio), round(y * ratio)) for x, y in points]


def erase_face(image):
    """把眼睛与嘴用脸部肤色盖掉，返回可重画的画布。"""
    canvas = image.convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    ratio = canvas.height / BASE_HEIGHT
    for cx, cy, rx, ry in (LEFT_EYE, RIGHT_EYE):
        x, y = round(cx * ratio), round(cy * ratio)
        box = (x - round(rx * ratio), y - round(ry * ratio), x + round(rx * ratio), y + round(ry * ratio))
        draw.ellipse(box, fill=FACE_SKIN + (255,))
    x0, y0, x1, y1 = MOUTH_BOX
    draw.rectangle((x0 * ratio, y0 * ratio, x1 * ratio, y1 * ratio), fill=FACE_SKIN + (255,))
    return canvas.filter(ImageFilter.GaussianBlur(1.2))


def draw_eyes(draw, ratio, style):
    """style: open 开心大眼 / closed 昏睡闭眼 / teary 委屈泪眼 / wide 饥饿期待大眼。"""
    for cx, cy, rx, ry in (LEFT_EYE, RIGHT_EYE):
        x, y = round(cx * ratio), round(cy * ratio)
        r = round(rx * ratio)
        h = round(ry * ratio)
        if style == "closed":
            draw.arc((x - r, y - h // 2, x + r, y + h), start=195, end=345, fill=EYE_DARK, width=max(4, round(8 * ratio)))
            continue
        if style == "happy_arc":
            draw.arc((x - r, y - h // 2, x + r, y + h), start=200, end=340, fill=EYE_DARK, width=max(5, round(9 * ratio)))
            continue

        if style == "wide":
            rw, rh = round(r * 1.12), round(h * 1.10)
        elif style == "teary":
            rw, rh = round(r * 0.92), round(h * 1.06)
        else:
            rw, rh = r, h
        draw.ellipse((x - rw, y - rh, x + rw, y + rh), fill=EYE_DARK)
        hl = max(4, round((16 if style == "wide" else 12) * ratio))
        ox = round(16 * ratio)
        oy = round(14 * ratio)
        draw.ellipse((x - rw + ox, y - rh + oy, x - rw + ox + hl * 2, y - rh + oy + hl * 2), fill=(255, 255, 255, 240))
        if style == "teary":
            for tx, ty in ((x - rw - round(10 * ratio), y + rh - round(4 * ratio)),
                           (x + rw + round(10 * ratio), y + rh - round(4 * ratio)),
                           (x - rw - round(4 * ratio), y + rh + round(18 * ratio))):
                draw.ellipse((tx - round(10 * ratio), ty - round(10 * ratio), tx + round(10 * ratio), ty + round(10 * ratio)), fill=(168, 224, 255, 240))
            draw.arc((x - r, y - h, x + r, y + h + round(10 * ratio)), start=195, end=345, fill=(214, 245, 255, 210), width=max(3, round(4 * ratio)))


def draw_mouth(draw, ratio, style):
    x0, y0, x1, y1 = MOUTH_BOX
    cx = round((x0 + x1) / 2 * ratio)
    cy = round((y0 + y1) / 2 * ratio)
    w = round((x1 - x0) / 2 * ratio)
    h = round((y1 - y0) / 2 * ratio)
    line = max(3, round(5 * ratio))
    if style == "smile":
        draw.arc((cx - w, cy - h, cx + w, cy + h), start=25, end=155, fill=(30, 46, 42, 255), width=line)
    elif style == "grin":
        draw.arc((cx - round(w * 1.35), cy - round(h * 1.2), cx + round(w * 1.35), cy + round(h * 1.2)), start=25, end=155, fill=(30, 46, 42, 255), width=line)
        draw.ellipse((cx - round(w * 0.42), cy + round(h * 0.15), cx + round(w * 0.42), cy + round(h * 1.15)), fill=(70, 40, 46, 255))
        draw.ellipse((cx - round(w * 0.2), cy + round(h * 0.62), cx + round(w * 0.2), cy + round(h * 1.05)), fill=(244, 150, 160, 255))
    elif style == "open":
        mw, mh = round(w * 0.42), round(h * 0.55)
        draw.ellipse((cx - mw, cy - mh, cx + mw, cy + mh), fill=EYE_DARK)
        draw.ellipse((cx - mw // 2, cy + mh // 4, cx + mw // 2, cy + mh), fill=(240, 150, 160, 255))
    elif style == "frown":
        mw, mh = round(w * 0.5), round(h * 0.4)
        draw.arc((cx - mw, cy + round(h * 0.35), cx + mw, cy + round(h * 0.35) + mh * 2), start=200, end=340, fill=(30, 46, 42, 255), width=line)
    elif style == "tiny":
        draw.arc((cx - round(w * 0.45), cy - round(h * 0.3), cx + round(w * 0.45), cy + round(h * 0.6)), start=30, end=150, fill=(30, 46, 42, 255), width=line)


def add_elements(image, ratio, mood):
    """加情绪小元素：睡眠泡泡 / 泪滴 / 口水 / 腮红。"""
    draw = ImageDraw.Draw(image)
    if mood == "sleepy":
        bx, by = round(452 * ratio), round(132 * ratio)
        for i, r in enumerate((16, 11, 7)):
            rr = round(r * ratio)
            px, py = bx + i * round(30 * ratio), by - i * round(34 * ratio)
            draw.ellipse((px, py, px + rr * 2, py + rr * 2), outline=(226, 248, 240, 235), width=max(2, round(4 * ratio)))
    elif mood == "hungry":
        x, y = round(340 * ratio), round(516 * ratio)
        r = round(11 * ratio)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(198, 242, 255, 235))
        bx, by = round(196 * ratio), round(300 * ratio)
        for i, r in enumerate((10, 7)):
            rr = round(r * ratio)
            px, py = bx + i * round(24 * ratio), by - i * round(28 * ratio)
            draw.ellipse((px, py, px + rr * 2, py + rr * 2), outline=(226, 248, 240, 225), width=max(2, round(3 * ratio)))
    elif mood == "happy":
        for cx, cy in ((104, 504), (478, 504)):
            x, y = round(cx * ratio), round(cy * ratio)
            rx, ry = round(40 * ratio), round(22 * ratio)
            draw.ellipse((x - rx, y - ry, x + rx, y + ry), fill=(250, 160, 175, 170))
    return image


def main():
    parser = argparse.ArgumentParser(description="本地合成四个情绪状态图")
    parser.add_argument("--base", required=True, help="锁定的宠物底图（正面）")
    parser.add_argument("--out-dir", required=True, help="输出目录")
    args = parser.parse_args()

    base = Image.open(args.base).convert("RGBA")
    ratio = base.height / BASE_HEIGHT
    os.makedirs(args.out_dir, exist_ok=True)

    plans = {
        "happy": ("happy_arc", "grin"),
        "hungry": ("wide", "open"),
        "sad": ("teary", "frown"),
        "sleepy": ("closed", "tiny"),
    }
    for mood, (eye_style, mouth_style) in plans.items():
        canvas = erase_face(base)
        draw = ImageDraw.Draw(canvas)
        draw_eyes(draw, ratio, eye_style)
        draw_mouth(draw, ratio, mouth_style)
        canvas = add_elements(canvas, ratio, mood)
        path = os.path.join(args.out_dir, f"mood_{mood}.png")
        canvas.save(path)
        print(f"已保存 {path} ({canvas.width}x{canvas.height})")

    excited = os.path.join(args.out_dir, "mood_excited.png")
    base.save(excited)
    print(f"已保存 {excited}（精神饱满：直接复用定稿表情）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
