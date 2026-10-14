"""去掉 AI 生成图的水印与平色背景，输出透明底 RGBA。

配套经验见 .agents/skills/sprite-walk-animation/SKILL.md（第 2 节）。
关键点：水印位置固定可硬编码删除；背景用「与四角背景色的最大通道差」做阈值，
再用自写的扫描线洪泛保证只删与边框连通的区域（PIL 的 ImageDraw.floodfill 在 L 模式下
是**静默空操作**，用了会得到一张完全错误的图，这是本流程最早踩的坑）。
"""
import os
import sys

import numpy as np
from PIL import Image

SRC = 'assets/images/monster'
OUT = 'assets/images/monster/cutout'

# 水印固定区域（x0, y0, x1, y1）。已逐张目视核对：框内只有水印与背景，不含角色。
WM_BOX = (1035, 1195, 1272, 1258)

T_BG = 16.0       # 与背景色的最大通道差在此以内 = 背景（JPEG 噪声 99 分位为 8，留足余量）。
                  # 不追求连画师画的落地投影一起抹掉：实测投影是 (255,218,192) 这种饱和
                  # 桃色，与半透明气泡、水洼在颜色上无法区分；阈值抬到 50 时气泡与水洼
                  # 会一起消失、角色右缘还会被啃出缺口。所以投影作为画面内容原样保留。
T_EDGE_LO = 8.0   # 羽化带起点
T_EDGE_HI = 50.0  # 羽化带终点（完全实心）
BAND = 2          # 只在这条宽度的边界带上做羽化，绝不侵入角色内部


def flood_from_border(allowed: np.ndarray) -> np.ndarray:
    """扫描线连通域填充：从整条图像边框出发，只吃 allowed 的像素。"""
    h, w = allowed.shape
    filled = np.zeros((h, w), bool)
    stack: list[tuple[int, int]] = []
    for x in range(w):
        if allowed[0, x]:
            stack.append((x, 0))
        if allowed[h - 1, x]:
            stack.append((x, h - 1))
    for y in range(h):
        if allowed[y, 0]:
            stack.append((0, y))
        if allowed[y, w - 1]:
            stack.append((w - 1, y))

    while stack:
        x, y = stack.pop()
        if filled[y, x] or not allowed[y, x]:
            continue
        row_a, row_f = allowed[y], filled[y]
        xl = x
        while xl > 0 and row_a[xl - 1] and not row_f[xl - 1]:
            xl -= 1
        xr = x
        while xr < w - 1 and row_a[xr + 1] and not row_f[xr + 1]:
            xr += 1
        row_f[xl:xr + 1] = True
        for ny in (y - 1, y + 1):
            if not 0 <= ny < h:
                continue
            run = allowed[ny, xl:xr + 1] & ~filled[ny, xl:xr + 1]
            if run.any():
                idx = np.flatnonzero(run)
                starts = idx[np.concatenate(([True], np.diff(idx) > 1))]
                for i in starts:
                    stack.append((xl + int(i), ny))
    return filled



def _selftest() -> None:
    """自检：确保连通域填充真的在填、且真的被屏障挡住（防再次出现静默空操作）。"""
    m = np.ones((7, 7), bool)
    m[3, 3] = False
    f = flood_from_border(m)
    assert f[0, 0] and not f[3, 3] and int(f.sum()) == 48, int(f.sum())

    m2 = np.ones((5, 5), bool)
    m2[1:4, 1:4] = False      # 被完全包住的内部空洞，不与任何边框相连
    f2 = flood_from_border(m2)
    assert int(f2.sum()) == 16 and not f2[2, 2], int(f2.sum())

    m3 = np.zeros((4, 4), bool)
    assert int(flood_from_border(m3).sum()) == 0


def process(path: str) -> Image.Image:
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)

    edge = np.concatenate([
        rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3),
        rgb[:, :8].reshape(-1, 3), rgb[:, -8:].reshape(-1, 3),
    ])
    bg = np.median(edge, axis=0)

    # 1) 去水印：先体检再覆盖，区域异常就直接失败暴露
    x0, y0, x1, y1 = WM_BOX
    box_diff = np.abs(rgb[y0:y1, x0:x1] - bg).max(axis=2)
    ratio = float((box_diff > 25).mean())
    if ratio > 0.20:
        raise AssertionError(
            f'{os.path.basename(path)} 的水印框内异常像素占比 {ratio:.1%}，'
            f'该区域可能压到了角色，拒绝盲覆盖，请重新核对 WM_BOX。')
    rgb[y0:y1, x0:x1] = bg

    d = np.abs(rgb - bg).max(axis=2)

    # 2) 抠底：只有"与边框连通"的背景/阴影才透明。
    #    不用形态学开运算去"封缝"——1px 级的缝会被两侧膨胀重新盖住，根本封不住，
    #    且对这张近白角色图也无济于事（见文件头 note）。
    allowed = d <= T_BG
    bg_conn = flood_from_border(allowed)
    frac = float(bg_conn.mean())
    if not 0.10 < frac < 0.92:
        raise AssertionError(f'{os.path.basename(path)} 背景占比 {frac:.1%} 异常，抠底结果不可信。')

    alpha = np.ones(d.shape, np.float32)
    alpha[bg_conn] = 0.0

    # 只在边界带上羽化，用颜色距离给出过渡；角色内部一律实心
    band = np.zeros_like(bg_conn)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        for _ in range(BAND):
            band |= np.roll(bg_conn, (dy, dx), (0, 1))
    band &= ~bg_conn
    band[0, :] = band[-1, :] = band[:, 0] = band[:, -1] = False
    ramp = np.clip((d - T_EDGE_LO) / (T_EDGE_HI - T_EDGE_LO), 0.0, 1.0)
    alpha[band] = ramp[band]

    # 3) 反解底色污染（alpha 太小时不反解，否则会把噪声放大成脏点）
    a = alpha[..., None]
    mix = (alpha > 0.30) & (alpha < 1.0)
    fixed = (rgb - (1.0 - a) * bg) / np.clip(a, 1e-6, 1.0)
    rgb = np.where(mix[..., None], fixed, rgb)
    rgb = np.clip(rgb, 0, 255)

    out = np.concatenate([rgb, (alpha * 255)[..., None]], axis=2).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')


def main() -> None:
    _selftest()
    os.makedirs(OUT, exist_ok=True)
    files = sorted(f for f in os.listdir(SRC)
                   if f.endswith('.jpg') or f.endswith('.png'))
    if not files:
        sys.exit(f'{SRC} 下没有待处理的源图')
    for f in files:
        img = process(os.path.join(SRC, f))
        img.save(os.path.join(OUT, os.path.splitext(f)[0] + '.png'))
        opa = np.asarray(img)[..., 3]
        print(f'{f[:34]:36s} 实心 {float((opa > 250).mean()):6.2%}  '
              f'羽化带 {float(((opa > 8) & (opa < 250)).mean()):6.2%}')


if __name__ == '__main__':
    main()
