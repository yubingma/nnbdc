#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""按「生成 → 逐个量 → 挑」的闭环，补出指定动作的帧。

配套经验见 .agents/skills/sprite-walk-animation/SKILL.md（第 3、4 节）。
这是整条流程里最关键的一环：**AI 一次画不对动作时，不要靠肉眼反复重生成，
而是把「动作是否到位」变成一个可量的数（本脚本量的是左右脚各自的离地高度占身高比），
生成一批、逐张量、只留达标的**。同一个提示词反复生成，模型对左右侧的服从度差别很大
（实测：让它抬左腿，有时给 4%、有时干脆抬成右腿；背面则能稳定给到 6~7%）。
用法：改 PROMPT / REF / 达标阈值后直接 `python3 tools/sprite_anim/gen_pose.py`。
"""
import base64
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

import numpy as np
from PIL import Image

OUTDIR = 'tmp/xiaochanguai_gen'
URL = 'https://ark.cn-beijing.volces.com/api/v3/images/generations'
MODEL = 'doubao-seedream-4-0-250828'
REF = 'assets/images/monster/cutout/xiaochanguai_行走正面01_橙黄双叶版.png'

STYLE = (
    '一只圆滚滚的黄色小怪物，头顶有两片橙色叶子形状的小辫子，额前两只很小的白色圆角，'
    '身体是奶油黄渐变的圆胖蛋形，轮廓有一圈细橙色描边，四肢又短又圆，身上有淡淡的浅色斑点。'
    '儿童绘本卡通贴纸风格，柔和均匀的光照，扁平上色加轻微渐变，无粗黑线条。'
    '纯净的浅米色背景，角色居中，全身完整入镜，四周留出空白。'
)
SHOT = ('同一只角色正面朝着镜头，正在走路：左前腿抬离地面、抬到最高点，右前腿踩地支撑，'
        '身体略向右倾；抬起的左腿要明显离地、离地高度与右腿抬起时相当，'
        '两条腿的轮廓底部差距清晰可见。表情是馋嘴的期待感，不哭不笑。')


def ark_image(prompt, ref_path, size='1280x1280'):
    key = re.search(r'export\s+VOLC_API_KEY\s*=\s*"?([^"\n]+)"?',
                    open(os.path.expanduser('~/.zprofile'), encoding='utf-8', errors='ignore').read()
                    ).group(1).strip()
    ref = Image.open(ref_path).convert('RGBA')
    canvas = Image.new('RGB', ref.size, (255, 255, 255))
    canvas.paste(ref, (0, 0), ref)
    canvas.thumbnail((1024, 1024), Image.LANCZOS)
    buf = io.BytesIO()
    canvas.save(buf, 'PNG')
    body = {'model': MODEL, 'prompt': prompt,
            'image': 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode(),
            'size': size, 'response_format': 'url', 'watermark': False}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={'Authorization': 'Bearer ' + key,
                                          'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=420) as r:
        return json.loads(r.read())['data'][0]['url']


def measure(im):
    """剥阴影后量左右脚各自的离地高度（占身高比）。"""
    src = open('tools/sprite_anim/render_anim.py', encoding='utf-8').read().split('if __name__')[0]
    ns = {}
    exec(compile(src, 'anim', 'exec'), ns)
    a = np.asarray(ns['strip_ground_shadow'](im)).astype(np.uint8)
    m = a[..., 3] > 60
    ys = np.where(m.any(axis=1))[0]
    top, bot = int(ys.min()), int(ys.max())
    h = bot - top + 1
    xs = np.where(m.any(axis=0))[0]
    cx = (int(xs.min()) + int(xs.max())) // 2
    lo = bot - int(h * 0.35)

    def low(x0, x1):
        r = np.where(m[lo:bot + 1, x0:x1].any(axis=1))[0]
        return (lo + r.max()) if len(r) else lo
    return (bot - low(int(xs.min()), cx)) / h, (bot - low(cx, int(xs.max()) + 1)) / h


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    results = []
    for k in range(4):
        try:
            raw = urllib.request.urlopen(ark_image(STYLE + SHOT, REF), timeout=300).read()
            path = os.path.join(OUTDIR, f'leftleg_{k}.png')
            open(path, 'wb').write(raw)
            l, r = measure(Image.open(path).convert('RGBA'))
            results.append((path, l, r))
            print(f'  {path}: 左脚离地 {l:.1%}  右脚离地 {r:.1%}')
        except urllib.error.HTTPError as e:
            print(f'  leftleg_{k}: HTTP {e.code} {e.read().decode()[:150]}')
        except Exception as e:
            print(f'  leftleg_{k}: {type(e).__name__} {e}')
    ok = [x for x in results if x[1] > 0.07 and x[2] < 0.02]
    print(f'\n达标（左脚离地 >7% 且右脚着地）的候选：{len(ok)} 张')
    for p, l, r in ok:
        print(f'  {p}  左 {l:.1%} / 右 {r:.1%}')


if __name__ == '__main__':
    main()
