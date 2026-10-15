#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把渲染用的帧打包成 App 资源：归一化 + 压分辨率 + 量化。

配套经验见 .agents/skills/sprite-walk-animation/SKILL.md。

做三件事，都是为了让 Dart 侧**只剩一个缩放系数**、不用重实现任何修正逻辑：

1. **把全部校正烘死进图**：剥烘焙阴影、绕脚底扶正、背面帧的水平镜像，
   全都在这里做完。Dart 拿到的是已经站正、已经镜像好的成品帧。
2. **归一化到统一画布**：所有姿态共用同一个缩放系数（全体中位身高），
   横向按轮廓质心对齐、纵向底边对齐。这样换姿势时不会忽大忽小、不会左右跳。
   ——这正是 Python 侧 `ref_h` 共享缩放与质心锚点做的事，烘进图里就不用再搬一遍。
3. **压掉分辨率过剩与色彩精度**：原图 1280×1280 而手机上一只怪只显示约 160 逻辑像素，
   等于按 8 倍高度存储。缩到显示高度的 3 倍再量化到 256 色（含 alpha）。

用法（在仓库根目录）：
    .venv/bin/python tools/sprite_anim/pack_app_assets.py
"""

import os
import sys

import numpy as np
from PIL import Image

SRC = 'assets/images/monster/cutout'
OUT = 'app/assets/images/monster'
RENDERER = 'tools/sprite_anim/render_anim.py'

# 角色在资源里的高度（像素）。手机上约显示 160 逻辑像素，3 倍屏 → 480。
TARGET_H = 480
QUANT_COLORS = 256
BG_SIZE = (1280, 720)     # 背景：横屏 16:9。手机横屏逻辑尺寸约 844×390，
                          # 3 倍屏就是 2532×1170，1280×720 够清晰也够小。

# 动画真正用到的姿态。名字 → (源文件名, 是否水平镜像)。
# 顺序即 Dart 侧循环数组里的顺序，两边必须一致。
POSES = {
    'front_stand':       ('xiaochanguai_行走正面14_橙黄双叶版', False),
    'front_leg_r_mid':   ('xiaochanguai_行走正面_右腿抬中_橙黄双叶版', False),
    'front_leg_r_high':  ('xiaochanguai_行走正面_右腿抬高_橙黄双叶版', False),
    'front_leg_l_mid':   ('xiaochanguai_行走正面_左腿抬中_橙黄双叶版', False),
    'front_leg_l_high':  ('xiaochanguai_行走正面_左腿抬高_橙黄双叶版', False),
    'back_stand_a':      ('xiaochanguai_行走背面01_橙黄双叶版', False),
    'back_stand_b':      ('xiaochanguai_行走背面08_橙黄双叶版', False),
    'back_leg_mid':      ('xiaochanguai_行走背面_右腿抬中_橙黄双叶版', False),
    'back_leg_mid_mirror': ('xiaochanguai_行走背面_右腿抬中_橙黄双叶版', True),
    'back_leg_high':     ('xiaochanguai_行走背面_右腿抬高_橙黄双叶版', False),
    'back_leg_high_mirror': ('xiaochanguai_行走背面_右腿抬高_橙黄双叶版', True),
    'pout':              ('xiaochanguai_瘪嘴站立_橙黄双叶版', False),
    'cry':               ('xiaochanguai_捂脸要哭_橙黄双叶版', False),
}


def _load_renderer():
    ns = {}
    src = open(RENDERER, encoding='utf-8').read().split('if __name__')[0]
    exec(compile(src, RENDERER, 'exec'), ns)
    return ns


def _prepare(renderer, name, flip):
    """取一帧，并把它在 Python 渲染时做的全部校正都应用上。"""
    path = os.path.join(SRC, POSES[name][0] + '.png')
    im = renderer['strip_ground_shadow'](Image.open(path).convert('RGBA'))
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return renderer['de_lean'](im)


def _metrics(im):
    m = np.asarray(im.getchannel('A')) > 60
    ys = np.where(m.any(axis=1))[0]
    xs = np.where(m.any(axis=0))[0]
    w = m.sum(axis=0).astype(np.float64)
    centroid = (w * np.arange(m.shape[1])).sum() / w.sum()
    return int(ys.min()), int(ys.max()), int(xs.min()), int(xs.max()), centroid


def pack():
    renderer = _load_renderer()
    os.makedirs(OUT, exist_ok=True)

    frames = {n: _prepare(renderer, n, f) for n, (_, f) in POSES.items()}
    heights = [_metrics(im)[1] - _metrics(im)[0] + 1 for im in frames.values()]
    ref_h = float(np.median(heights))
    scale = TARGET_H / ref_h
    print(f'姿态 {len(frames)} 张；共享中位身高 {ref_h:.0f}px → 统一缩放 {scale:.4f}')

    # 先算出统一画布：以「质心到底边的最大左右伸出量」为准，四周各留 12%
    half = max(max(abs(_metrics(im)[2] - _metrics(im)[4]),
                   abs(_metrics(im)[3] - _metrics(im)[4])) for im in frames.values())
    half = int(half * scale * 1.12) + 4
    canvas_w, canvas_h = half * 2, int(TARGET_H * 1.12)
    print(f'统一画布 {canvas_w}×{canvas_h}')

    total = 0
    for name, im in frames.items():
        m = _metrics(im)
        nw, nh = max(1, round((m[3] - m[2] + 1) * scale)), max(1, round((m[1] - m[0] + 1) * scale))
        crop = im.crop((m[2], m[0], m[3] + 1, m[1] + 1)).resize((nw, nh), Image.LANCZOS)
        # 横向按质心对齐、纵向底边对齐 —— 与 Python 侧 paste_char 的锚点语义一致
        cx = (m[4] - m[2]) * scale
        dst = Image.new('RGBA', (canvas_w, canvas_h), (0, 0, 0, 0))
        dst.paste(crop, (round(canvas_w / 2 - cx), canvas_h - nh - int(TARGET_H * 0.04)), crop)
        q = dst.quantize(colors=QUANT_COLORS, method=Image.FASTOCTREE)
        out = os.path.join(OUT, name + '.png')
        q.save(out, optimize=True)
        total += os.path.getsize(out)
        print(f'  {name:24s} {nw:4d}×{nh:<4d} → {os.path.getsize(out)/1024:6.1f} KB')

    # 背景：直接复用 Python 场景的绘制函数，保证与视频里是同一张桥面。
    # 视口横竖（render_anim.py 的 LANDSCAPE）一改，这里自动跟着变。
    bg = renderer['build_background']().convert('RGB').resize(BG_SIZE, Image.LANCZOS)
    bg_path = os.path.join(OUT, 'bg_bridge.jpg')
    bg.save(bg_path, quality=88, optimize=True)
    total += os.path.getsize(bg_path)
    print(f'  {"bg_bridge.jpg":24s} {BG_SIZE[0]:4d}×{BG_SIZE[1]:<4d} → {os.path.getsize(bg_path)/1024:6.1f} KB')

    print(f'\n合计 {total/1024:.0f} KB（原始抠底帧为 {sum(os.path.getsize(os.path.join(SRC, POSES[n][0]+".png")) for n in POSES)/1024/1024:.0f} MB 量级）')


if __name__ == '__main__':
    sys.exit(pack())
