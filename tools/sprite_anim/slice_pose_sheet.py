#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 AI 一次生成的多姿势大图切成单帧。

配套经验见 .agents/skills/sprite-walk-animation/SKILL.md（第 2 节）。
关键点：**绝不能写死行列数**——模型不会遵守「每行几个」的要求（实测要 6 个给 8 个、
要 12 个给 16 个），必须自动探测行/列，并按「整行空白」切分。
切完还要统一缩放系数并做离群校正，否则各帧大小不一，动画里会一跳一跳。
"""
import numpy as np
from PIL import Image

SHEETS = {
    'front': ('tmp/xiaochanguai_gen/walk12b_front.png', 'xiaochanguai_行走正面{:02d}_橙黄双叶版'),
    'back': ('tmp/xiaochanguai_gen/walk12b_back.png', 'xiaochanguai_行走背面{:02d}_橙黄双叶版'),
}
DST_DIR = 'assets/images/monster'
T_BG = 16.0
T_SOLID = 45.0
OUT = 1280
TARGET_H = 950
FEET_Y = 1140


def runs_of(flags):
    out, start = [], None
    for i, v in enumerate(flags):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(flags)))
    return out


def drop_long_lines(mask, frac=0.5):
    """清掉贯穿大半幅的横线（地面基准线），按单行最长连续段判断。"""
    w = mask.shape[1]
    for y in range(mask.shape[0]):
        rs = runs_of(mask[y])
        if rs and max(b - a for a, b in rs) > frac * w:
            mask[y] = False
    return mask


def bands_with_fragments(mask2d, axis, min_main=150, frag_gap=120):
    """先认主体块，再把窄碎片按最近间隙吸附过去（碎片可能在左也可能在右）。"""
    raw = runs_of(mask2d.any(axis=axis))
    mains = [s for s in raw if s[1] - s[0] >= min_main]
    for f in [s for s in raw if s[1] - s[0] < min_main]:
        best, best_gap = None, 10 ** 9
        for j, m in enumerate(mains):
            gap = min(abs(f[0] - m[1]), abs(m[0] - f[1]))
            if gap < best_gap:
                best_gap, best = gap, j
        if best is not None and best_gap < frag_gap:
            m = mains[best]
            mains[best] = (min(m[0], f[0]), max(m[1], f[1]))
    mains.sort()
    if not mains:
        raise AssertionError('没有识别到任何块')
    return mains


def main():
    for tag, (path, nametpl) in SHEETS.items():
        sheet = Image.open(path).convert('RGB')
        rgb = np.asarray(sheet).astype(np.float32)
        bg = np.median(np.concatenate([rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3)]), axis=0)
        fg_full = drop_long_lines(np.abs(rgb - bg).max(axis=2) > T_BG)
        fg_solid = drop_long_lines(np.abs(rgb - bg).max(axis=2) > T_SOLID)

        row_bands = bands_with_fragments(fg_solid, 1, min_main=120, frag_gap=200)
        print(f'[{tag}] 行带 {len(row_bands)} 个：{row_bands}')

        frames, solid_h = [], []
        for (ry0, ry1), (rx0, rx1) in [(rb, (0, sheet.width)) for rb in row_bands]:
            sub_full = fg_full[ry0:ry1]
            sub_solid = fg_solid[ry0:ry1]
            col_bands = bands_with_fragments(sub_solid, 0)
            edges = [0] + [(a[1] + b[0]) // 2 for a, b in zip(col_bands, col_bands[1:])] + [sheet.width]
            print(f'   行 {ry0}-{ry1} 分列 {len(col_bands)} 个：{col_bands}')
            for x0, x1 in zip(edges, edges[1:]):
                part_full = sub_full[:, x0:x1]
                part_solid = sub_solid[:, x0:x1]
                if not part_full.any():
                    raise AssertionError(f'{tag}: 分区 [{x0},{x1}) 内没有前景')
                ys, xs = np.where(part_full)
                arr = np.asarray(sheet.crop((x0 + xs.min(), ry0 + ys.min(),
                                             x0 + xs.max() + 1, ry0 + ys.max() + 1))).copy()
                keep = part_full[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
                arr[~keep] = tuple(int(v) for v in bg)
                frames.append(Image.fromarray(arr))
                sy = np.where(part_solid.any(axis=1))[0]
                solid_h.append(int(sy.max() - sy.min() + 1))

        ref_h = float(np.median(solid_h))
        base = TARGET_H / ref_h
        scales = [base * (ref_h / h) if abs(h - ref_h) / ref_h > 0.05 else base for h in solid_h]
        print(f'[{tag}] 共 {len(frames)} 帧，实心高度 {solid_h} 中位数 {ref_h:.0f}；'
              f'共用缩放 {base:.3f}，离群校正 {sum(s != base for s in scales)} 帧')

        for i, (c, sc) in enumerate(zip(frames, scales), 1):
            w, h = max(1, round(c.width * sc)), max(1, round(c.height * sc))
            canvas = Image.new('RGB', (OUT, OUT), tuple(int(v) for v in bg))
            canvas.paste(c.resize((w, h), Image.LANCZOS), (OUT // 2 - w // 2, FEET_Y - h))
            canvas.save(f'{DST_DIR}/{nametpl.format(i)}.png')
        print(f'   → 已写出 {len(frames)} 帧到 {DST_DIR}')


if __name__ == '__main__':
    main()
