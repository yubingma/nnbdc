#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""小馋怪 · 受击与被打哭 动画预览（本地 2D 序列帧）。

素材：5 张原始姿势 + 用火山方舟 Seedream 4.0 图生图补出的 4 张走路分解帧
（正面左/右腿一组，背面一组）。有了真正的走路帧，「朝镜头走来」与「转身跑掉」
两个方向都不用再拿侧视图硬顶。

关键约束：同一走路循环的两帧必须共用同一个参考高度。若按各自轮廓高度逐帧缩放，
抬腿那一帧轮廓更矮、会被放大，走起来就会一鼓一鼓地「喘气」。
"""
import math
import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- 视口（横屏 / 竖屏）
#
# 与构图有关的量全部集中在这里，横竖屏只切这一个开关。App 侧
# （app/lib/widget/monster_sprite.dart）有一份对账的镜像常量，两边必须同时改。
#
# 横屏不是「把竖屏那张桥裁一裁」：视口从 9:16 变成 16:9 之后，
#   ① 竖屏那张 1080×1920 的背景在 cover 下会被裁成中间一条竖缝；
#   ② 桥面在视口里的合理比例变了——横屏要留出两侧水面（也正好是放 UI 的地方）；
#   ③ 纵向可视范围只有原来的一半多，角色行进的轨道与透视缩放要整套重定。
LANDSCAPE = True
if LANDSCAPE:
    W, H = 1920, 1080
    # 桥面半宽占视口宽度的比例。实测三档（底端占屏 51% / 66% / 80%）后取中间：
    # 51% 时桥只占中间窄窄一条、两侧大片空蓝、构图发虚；80% 时水面几乎没了，
    # 而两侧水面正是放答案箱和 HUD 的地方。66% 桥成为主舞台，两侧仍留得住余地。
    BRIDGE_TOP_HALF = 0.075
    BRIDGE_BOT_HALF = 0.33
    GROUND_FAR, GROUND_NEAR = 300, 860   # 角色行进轨道两端（脚底所在的行）
    GROUND_BOUNCE = 740         # 被打中时被弹到的位置
    GROUND_SETTLE = 845         # 战斗段落定的位置
    SCALE_Y0, SCALE_Y1 = 240, 920        # 透视缩放的斜坡区间
    SCALE_S0, SCALE_S1 = 0.22, 0.52      # 斜坡两端的缩放
else:
    W, H = 1080, 1920
    BRIDGE_TOP_HALF = 0.165
    BRIDGE_BOT_HALF = 0.476
    GROUND_FAR, GROUND_NEAR = 420, 980
    GROUND_BOUNCE = 862
    GROUND_SETTLE = 960
    SCALE_Y0, SCALE_Y1 = 380, 1180
    SCALE_S0, SCALE_S1 = 0.30, 0.78

FPS = 30
DURATION = 8.8
N_FRAMES = int(DURATION * FPS)
MARGIN = 60
CANVAS = (W + MARGIN * 2, H + MARGIN * 2)

ASSETS = 'assets/images/monster/cutout'
OUTDIR = 'tmp/xiaochanguai_anim'
POSES = {'pout': 'xiaochanguai_瘪嘴站立_橙黄双叶版.png',
         'cry': 'xiaochanguai_捂脸要哭_橙黄双叶版.png',
         # 我方小宠物（站在桥头、背对镜头、投掷坚果）
         'ally_stand': 'ally_stand.png',
         'ally_windup': 'ally_windup.png',
         'ally_throw': 'ally_throw.png'}

# 我方三帧来自另一个目录（assets/images/ally），不跟小馋怪混在一起。
ALLY_ASSETS = 'assets/images/ally'
# 正面走路循环：8 帧，左右对称、腿高有渐变，且**全部禁用镜像**。
#
# 为什么最终放弃了镜像：镜像会把**视线一起翻过去**。原来的循环里位置 1-4 视线偏左、
# 5-8（F03/F04 的镜像）视线偏右，一个循环视线从左翻到右、永远不正对镜头——
# 首轮反馈的「视线始终没有转向正面、感觉不太舒服」就是它，同时镜像也让身体朝向左右翻。
# 现在改成分别生成「正脸 + 视线朝前」的左腿帧和右腿帧（实测左脚 7.0%/13.5%、
# 右脚 9.2%/12.2%，且这几帧的瞳孔都居中正视），着地帧取同样正脸的 F14。
#
# 定这个循环的依据是**量出来的**（剥掉烘焙阴影后才能量准）：
#   F03 右腿离地 6.3% ｜ F04 右腿离地 9.2% ｜ F06 左腿只离地 3.6%
# 也就是说 AI 给的那 16 帧里只有 3 帧真有抬腿，而且**左右严重不对称**（9.2% vs 3.6%，
# 差 2.5 倍）——走起来就是瘸的，这才是「姿势不自然」的真正根因，不是帧数也不是频率。
#
# 让模型补一张「左腿抬高」的帧试过了：连生成 4 张，它只给到 4%，或者干脆抬成右腿，
# 就是抬不高。所以改成**把 F04（右腿高抬）水平镜像**当作左腿版本——
# 实测镜像后左腿离地同样是 9.2%，左右完全对称；角色本身近似左右对称，
# 镜像后只有那条小尾巴换了边，肉眼几乎看不出。
#
# 循环按「抬腿高度」排：着地 → 6.3% → 9.2% → 6.3% → 着地 →（换左腿）…
# 上升段与下降段共用同一张 6.3% 的帧：腿本来就是从同一组高度上上下下。
CURATED_FRONT = [
    ('xiaochanguai_行走正面14_橙黄双叶版', False),
    ('xiaochanguai_行走正面_右腿抬中_橙黄双叶版', False),
    ('xiaochanguai_行走正面_右腿抬高_橙黄双叶版', False),
    ('xiaochanguai_行走正面_右腿抬中_橙黄双叶版', False),
    ('xiaochanguai_行走正面14_橙黄双叶版', False),
    ('xiaochanguai_行走正面_左腿抬中_橙黄双叶版', False),
    ('xiaochanguai_行走正面_左腿抬高_橙黄双叶版', False),
    ('xiaochanguai_行走正面_左腿抬中_橙黄双叶版', False),
]

CURATED_BACK = [
    ('xiaochanguai_行走背面01_橙黄双叶版', False),
    ('xiaochanguai_行走背面_右腿抬中_橙黄双叶版', False),
    ('xiaochanguai_行走背面_右腿抬高_橙黄双叶版', False),
    ('xiaochanguai_行走背面_右腿抬中_橙黄双叶版', False),
    ('xiaochanguai_行走背面08_橙黄双叶版', False),
    ('xiaochanguai_行走背面_右腿抬中_橙黄双叶版', True),
    ('xiaochanguai_行走背面_右腿抬高_橙黄双叶版', True),
    ('xiaochanguai_行走背面_右腿抬中_橙黄双叶版', True),
]


def _pick_walk_frames(cn, want=None):
    """点名要哪几帧、按什么顺序成环，以及是否水平镜像。顺序即相位顺序。"""
    spec = CURATED_FRONT if cn == '正面' else CURATED_BACK
    return [(base + '.png', flip) for base, flip in spec]


WALK_SETS = {}
FLIP = {}
for _d, _cn in (('front', '正面'), ('back', '背面')):
    _picked = _pick_walk_frames(_cn)
    for _n, (_f, _flip) in enumerate(_picked, 1):
        POSES[f'{_d}{_n:02d}'] = _f
        FLIP[f'{_d}{_n:02d}'] = _flip
    WALK_SETS[_d] = [f'{_d}{i:02d}' for i in range(1, len(_picked) + 1)]
    print(f'{_cn}走路帧：{len(_picked)} 帧')
# 每秒完成的整套走路循环数（一套 = 两步）。这是步频的唯一旋钮：
# 步/秒 = 2 × WALK_HZ。原来取 0.95（= 1.9 步/秒），对这个圆滚滚的小短腿过于急促，
# 看起来像在原地捣腿；降到 0.5（= 1 步/秒）才是从容的小碎步。
# 走路时脚必须始终踩死在地面上。以下三件事都会让脚在地上蹭，必须分清：
#   整体上下平移 → 脚离地；绕底座中心整体旋转 → 底座变跷跷板，一只脚下沉一只脚翘起；
#   整体横向平移 → 两只脚一起横着蹭。
# 正确做法是把起伏做在「以脚底为支点的挤压拉伸」上：脚不动，身体自己起伏。
BOB_SQUASH = 0.030     # 每步一次的挤压拉伸幅度（占身高比例）
LEAN_APPROACH = 0.0    # 走近时不做整体旋转（之前正是它读成「一只脚在滑地」）
SWAY_APPROACH = 0.0
LEAN_FLEE = 3.5        # 逃跑段观感尚可，保留轻微摇摆
SWAY_FLEE = 0.008
WALK_HZ = 1.05         # 走近：每秒腿循环数（8 帧 = 2 步 → 2.1 步/秒）
#
# 步频必须和「走近的时长、走过的距离」一起定，单看步频没有意义。
# 判据是**每步前进的距离**：它应当和腿长同量级，超过就是滑冰。
# 这只角色的腿长约为身高的 10%（屏幕上约 40~70px）。
# 原来：2.2 秒走 560px、1.8 步/秒 → 每步 141px，是腿长的 2~3 倍，所以「脚步不扎实、像打滑」。
# 现在：3.4 秒走 560px、2.1 步/秒 → 每步 78px，降到原来的 55%，与腿长同量级。
# 顺便，姿势播放速率 = 8 × WALK_HZ = 8.4 帧/秒，比原来更快、更顺。

T_IMPACT = 3.40
T_CRY = 3.95
T_FLEE = 6.20
T_END = 8.80
TURN = 0.30            # 转身时长

# ---- 我方小宠物（站在桥头、背对镜头、用小短手投掷坚果）----
# 它站在离镜头最近的位置，所以画在最后（盖在小馋怪上面），符合纵深。
# 尺寸另乘一个比例：它本来就是个头更小的宠物，不按透视的等比放大，
# 否则会比小馋怪还大、把画面堵住。
# 脚底所在的行。不能贴到画布最底：App 侧背景走 BoxFit.cover，
# 在比 16:9 更宽的屏幕上会上下各裁掉约 9%，贴底的话脚会被切掉。
ALLY_GROUND = 950
# 横向位置：略偏桥面左侧。正中央会挡住从中间压过来的小馋怪，偏开一点两边都看得清；
# 偏左后投掷手（画面右侧那只）到小馋怪的弧线也更短、更自然。
ALLY_OFFSET_X = -0.12
ALLY_RATIO = 0.85      # 相对同位置小馋怪的大小
ALLY_WINDUP = 2.28     # 抬手蓄力开始
ALLY_RELEASE = 2.56    # 挥出、坚果脱手
ALLY_RECOVER = 2.95    # 收回站立
NUT_LAUNCH = 2.60      # 坚果起飞（略晚于挥出）


def smoothstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def ease_out_back(x, s=1.7):
    x = min(1.0, max(0.0, x))
    return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2


def ease_out_elastic(x, amp=0.5, period=0.32):
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    return 1 + amp * (2 ** (-10 * x)) * math.sin((x - period / 4) * (2 * math.pi) / period)


def lerp(a, b, t):
    return a + (b - a) * t


def track(t, keys):
    if t <= keys[0][0]:
        return keys[0][1]
    if t >= keys[-1][0]:
        return keys[-1][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            return lerp(v0, v1, (t - t0) / max(1e-6, t1 - t0))
    return keys[-1][1]


def _lean_of(alpha):
    """量一帧「身体相对脚底画歪了」的程度：上半身中心与脚底中心的横向偏移（占身高比）。

    实测这组迈步帧里上半身中心只晃 15px、脚底中心晃 93px（角色高约 900px）——这个错位
    是烤进图里的，横向锚点取哪一头都只是把它在「头晃」和「脚晃」之间挪，两头都看得出来。
    """
    m = alpha > 60
    ys = np.where(m.any(axis=1))[0]
    top, bot = int(ys.min()), int(ys.max())
    h = bot - top + 1
    up = m[top:top + int(h * 0.55)]
    ux = np.where(up.any(axis=0))[0]
    lo = m[bot - int(h * 0.12):bot + 1]
    lx = np.where(lo.any(axis=0))[0]
    if len(ux) == 0 or len(lx) == 0:
        return 0.0, 0.0, bot
    return ((ux.min() + ux.max()) / 2.0 - (lx.min() + lx.max()) / 2.0) / h, \
           (lx.min() + lx.max()) / 2.0, bot


def de_lean(im):
    """绕脚底旋转，把「身体相对脚底画歪了」扶正。

    为什么非做不可：实测这组迈步帧里上半身中心只晃 15px、**脚底中心晃 93px**
    （F04 脚底 686、它的镜像 593，角色高约 900px）。这个错位是烤进图里的，
    横向锚点取哪一头都只是把它在「头晃」和「脚晃」之间挪，两头都会看得出来——
    首轮反馈的「走过来时身体左转右转」就是它。

    角度靠**直接搜索**而不是公式或系数：这个倾斜指标对旋转是非线性的
    （同一个系数会让 F03 修好、F08 反而更歪），迭代重测还会发散。
    所以干脆在 ±8° 内逐个角度试、取让偏移绝对值最小的那个，不依赖任何假设。
    """
    lean, bc, bot = _lean_of(np.asarray(im.getchannel('A')))
    if abs(lean) < 0.004:
        return im
    best_theta, best_abs = 0.0, abs(lean)
    for step in range(-16, 17):
        theta = step * 0.5
        if theta == 0.0:
            continue
        cand = im.rotate(theta, resample=Image.BICUBIC, center=(bc, bot))
        l, _, _ = _lean_of(np.asarray(cand.getchannel('A')))
        if abs(l) < best_abs:
            best_abs, best_theta = abs(l), theta
    return im.rotate(best_theta, resample=Image.BICUBIC, center=(bc, bot)) if best_theta else im


def body_anchor(alpha):
    """横向锚点：**轮廓水平质心**（alpha 重心）。

    为什么用它：判断「身体有没有左右摆」唯一有意义的量就是质心。
    曾经用过「脚底中心」，但那是个假指标——单脚抬起时它量到的是**支撑脚**的位置，
    左右脚交替支撑时它本来就会来回跳（实测 124~151px），那不是滑动，是正常的重心交替；
    照着它调只会把真正的摆动掩盖掉。实测三种锚点下的身体摆幅：
    脚底 47.8px、上半身 44.8px、**质心 0.5px**。
    """
    m = alpha > 60
    w = m.sum(axis=0).astype(np.float64)
    if w.sum() <= 0:
        return float(m.shape[1] / 2.0)
    return float((w * np.arange(m.shape[1])).sum() / w.sum())


def load_assets():
    data, bbox_h, anchor = {}, {}, {}
    for k, fn in POSES.items():
        src = ALLY_ASSETS if k.startswith('ally') else ASSETS
        im = strip_ground_shadow(Image.open(os.path.join(src, fn)).convert('RGBA'))
        if FLIP.get(k):
            # 镜像整张图之后再算外框与锚点，下游逻辑就不用为镜像做特殊处理
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        if k.startswith(('front', 'back')):
            im = de_lean(im)
        alpha = np.asarray(im.getchannel('A'))
        bb = im.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox()
        data[k] = (im, bb)
        bbox_h[k] = bb[3] - bb[1]
        anchor[k] = body_anchor(alpha)
    ref = dict(bbox_h)
    for frames in WALK_SETS.values():
        shared = float(np.median([bbox_h[f] for f in frames]))
        for f in frames:
            ref[f] = shared
    return data, ref, anchor


def paste_char(frame, pose_img, bbox, anchor_x, feet, height, ref_h,
               sx=1.0, sy=1.0, rot=0.0, alpha=1.0):
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    base = height / ref_h                      # 用本组参考高度换算，不用本帧轮廓高度
    nw, nh = max(1, int(round(bw * base * sx))), max(1, int(round(bh * base * sy)))
    crop = pose_img.crop(bbox).resize((nw, nh), Image.LANCZOS)
    if alpha < 1.0:
        crop.putalpha(crop.getchannel('A').point(lambda v: int(v * alpha)))
    # 水平方向按上半身质心对齐，而不是按外框中心：
    # 让质心正好落回 feet[0] 这条竖线上，迈步时身体就不会左右漂。
    px, py = (anchor_x - bbox[0]) * base * sx, nh
    if rot:
        # 绕「脚底支点」旋转：身体左右摇，脚始终踩在原地不动
        crop = crop.rotate(rot, resample=Image.BICUBIC, expand=True)
        c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        dx, dy = px - nw / 2, py - nh / 2
        px = crop.width / 2 + c * dx + s_ * dy
        py = crop.height / 2 - s_ * dx + c * dy
    frame.alpha_composite(crop, (int(feet[0] - px), int(feet[1] - py)))


# ---------------------------------------------------------------- 场景

def build_background():
    img = Image.new('RGB', CANVAS, (86, 150, 190))
    d = ImageDraw.Draw(img)
    ox = MARGIN
    for y in range(CANVAS[1]):
        k = y / CANVAS[1]
        d.line([(0, y), (CANVAS[0], y)],
               fill=(int(lerp(58, 108, k)), int(lerp(126, 178, k)), int(lerp(176, 206, k))))
    rng = np.random.default_rng(7)
    for _ in range(260):
        wy, wx = int(rng.uniform(0, CANVAS[1])), int(rng.uniform(0, CANVAS[0]))
        wl = int(rng.uniform(18, 90))
        a = int(lerp(26, 12, wy / CANVAS[1]))
        wob = Image.new('RGBA', (wl + 2, 4), (255, 255, 255, 0))
        ImageDraw.Draw(wob).line([(1, 2), (wl, 2)], fill=(255, 255, 255, a), width=2)
        img.paste(wob, (wx, wy), wob)

    bxl = ox + W / 2 - W * BRIDGE_BOT_HALF
    bxr = ox + W / 2 + W * BRIDGE_BOT_HALF
    txl = ox + W / 2 - W * BRIDGE_TOP_HALF
    txr = ox + W / 2 + W * BRIDGE_TOP_HALF
    top_y, bot_y = 0, CANVAS[1]
    d.polygon([(txl, top_y), (txr, top_y), (bxr, bot_y), (bxl, bot_y)], fill=(206, 199, 189))
    for i in range(1, 46):
        k = (i / 46.0) ** 1.9
        y = int(lerp(top_y, bot_y, k))
        w = lerp(txr - txl, bxr - bxl, k) / 2
        d.line([(ox + W / 2 - w, y), (ox + W / 2 + w, y)], fill=(189, 181, 170), width=2)

    for side in (-1, 1):
        x0 = txl if side < 0 else txr
        x1 = bxl if side < 0 else bxr
        wtop = max(6, int((txr - txl) * 0.055))
        wbot = max(26, int((bxr - bxl) * 0.055))
        d.polygon([(x0, top_y), (x0 + side * wtop, top_y),
                   (x1 + side * wbot, bot_y), (x1, bot_y)], fill=(150, 120, 92))
        d.polygon([(x0 + side * wtop, top_y), (x0 + side * (wtop + 6), top_y),
                   (x1 + side * (wbot + 18), bot_y), (x1 + side * wbot, bot_y)],
                  fill=(126, 99, 74))

    glow = Image.new('RGBA', CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(
        [(txl, H * .55), (txr, H * .55), (bxr, bot_y), (bxl, bot_y)],
        fill=(255, 236, 200, 22))
    haze = Image.new('RGBA', CANVAS, (0, 0, 0, 0))
    hd = ImageDraw.Draw(haze)
    for y in range(int(H * 0.30)):
        hd.line([(0, y), (CANVAS[0], y)],
                fill=(206, 228, 240, int(78 * (1 - y / (H * 0.30)) ** 1.6)))
    return Image.alpha_composite(Image.alpha_composite(img.convert('RGBA'), glow), haze).convert('RGB')


def scale_at_ground(y_screen):
    """透视：越靠下（离镜头越近）越大。斜坡区间与两端缩放由视口档位决定。"""
    k = min(1.0, max(0.0, (y_screen - SCALE_Y0) / (SCALE_Y1 - SCALE_Y0)))
    return lerp(SCALE_S0, SCALE_S1, k)


# ---------------------------------------------------------------- 特效

def fx_dust(frame, x, y, r, alpha):
    if alpha <= 0 or r <= 0:
        return
    layer = Image.new('RGBA', (int(r * 2.6), int(r * 2.6)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse([r * .1, r * .9, r * 1.5, r * 1.9], fill=(236, 228, 214, int(150 * alpha)))
    ld.ellipse([r * 1.1, r * .7, r * 2.5, r * 1.8], fill=(236, 228, 214, int(110 * alpha)))
    ld.ellipse([r * .5, r * .5, r * 2.0, r * 1.6], fill=(246, 240, 230, int(90 * alpha)))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.22))
    frame.alpha_composite(layer, (int(x - layer.width / 2), int(y - layer.height * 0.72)))


def fx_impact(frame, x, y, k):
    if k <= 0 or k >= 1:
        return
    r = lerp(26, 235, ease_out_back(min(1.0, k * 1.4)))
    a = 1.0 - k
    layer = Image.new('RGBA', (int(r * 2.4), int(r * 2.4)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    cx = cy = layer.width / 2
    pts = [(cx + math.cos(math.pi * 2 * i / 16) * r * (.42 if i % 2 else 1.0),
            cy + math.sin(math.pi * 2 * i / 16) * r * (.42 if i % 2 else 1.0)) for i in range(16)]
    ld.polygon(pts, fill=(255, 240, 170, int(230 * a)))
    ld.polygon([(p[0] * .62 + cx * .38, p[1] * .62 + cy * .38) for p in pts],
               fill=(255, 255, 245, int(240 * a)))
    ld.ellipse([cx - r * .95, cy - r * .95, cx + r * .95, cy + r * .95],
               outline=(255, 255, 255, int(170 * a)), width=max(2, int(10 * a)))
    layer = layer.filter(ImageFilter.GaussianBlur(2.5))
    frame.alpha_composite(layer, (int(x - cx), int(y - cy)))


def fx_tear(frame, x, y, r, alpha):
    if alpha <= 0:
        return
    layer = Image.new('RGBA', (int(r * 3), int(r * 4)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse([r, r * 1.2, r * 2, r * 3], fill=(150, 214, 246, int(225 * alpha)))
    ld.ellipse([r * 1.05, r, r * 1.95, r * 2], fill=(150, 214, 246, int(225 * alpha)))
    ld.ellipse([r * 1.25, r * 1.5, r * 1.6, r * 2.1], fill=(255, 255, 255, int(200 * alpha)))
    layer = layer.filter(ImageFilter.GaussianBlur(1.0))
    frame.alpha_composite(layer, (int(x - layer.width / 2), int(y - layer.height / 2)))


def fx_speed(frame, x, y, r, alpha, vertical=False):
    if alpha <= 0:
        return
    layer = Image.new('RGBA', (int(r * 3), int(r * 1.2)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for i in range(3):
        yy = layer.height * (0.25 + i * 0.26)
        ld.line([(0, yy), (r * (0.7 + 0.3 * i), yy)],
                fill=(255, 255, 255, int(120 * alpha)), width=max(2, int(6 * alpha)))
    layer = layer.filter(ImageFilter.GaussianBlur(2.0))
    if vertical:
        layer = layer.transpose(Image.ROTATE_90)
    frame.alpha_composite(layer, (int(x - layer.width / 2), int(y - layer.height / 2)))


def fx_nut(frame, x, y, ang, r):
    layer = Image.new('RGBA', (int(r * 3), int(r * 3)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    c = layer.width / 2
    ld.ellipse([c - r, c - r * .82, c + r, c + r * .82], fill=(196, 140, 84, 255),
               outline=(126, 84, 46, 255), width=max(2, int(r * .18)))
    ld.arc([c - r * .7, c - r * .6, c + r * .7, c + r * .6], 200, 340,
           fill=(126, 84, 46, 255), width=max(2, int(r * .14)))
    layer = layer.rotate(ang, resample=Image.BICUBIC, expand=False)
    frame.alpha_composite(layer, (int(x - c), int(y - c)))


# ---------------------------------------------------------------- 阴影剥离

def _flood_seeds(allowed, seeds):
    """从指定种子出发的扫描线连通域填充。"""
    h, w = allowed.shape
    out = np.zeros((h, w), bool)
    stack = list(seeds)
    while stack:
        x, y = stack.pop()
        if out[y, x] or not allowed[y, x]:
            continue
        row_a, row_o = allowed[y], out[y]
        xl = x
        while xl > 0 and row_a[xl - 1] and not row_o[xl - 1]:
            xl -= 1
        xr = x
        while xr < w - 1 and row_a[xr + 1] and not row_o[xr + 1]:
            xr += 1
        row_o[xl:xr + 1] = True
        for ny in (y - 1, y + 1):
            if 0 <= ny < h:
                run = allowed[ny, xl:xr + 1] & ~out[ny, xl:xr + 1]
                if run.any():
                    idx = np.flatnonzero(run)
                    starts = idx[np.concatenate(([True], np.diff(idx) > 1))]
                    for i in starts:
                        stack.append((xl + int(i), ny))
    return out


def strip_ground_shadow(im):
    """剥掉素材自带的那圈落地阴影。

    非做不可：影子是画在角色图里的，角色一离地影子就跟着飞，而且它会跟着身体一起
    缩放变形。剥掉后改由 draw_ground_shadow 在地面单独画一个椭圆影。

    判据：**从图像外边界出发、经「透明区 ∪ 低饱和亮色区」能走到的低饱和像素，就是阴影。**
    身体内部的浅奶油色被橙色描边整个包住，从外面根本走不进去，所以不会被误删。

    踩过的两个坑，都留在这里以免重犯：
      ① 只按「低饱和 + 够亮」判定，会把身体下腹的浅色区一起删掉，肚子被挖穿；
      ② 只从轮廓最底边做一次种子洪泛，**阴影被两条腿隔成左右两瓣**，单一洪泛到不了外侧，
         结果地上一整片浅色椭圆留在那儿——放大看就是脚下一个发亮的大椭圆。
    """
    a = np.asarray(im).astype(np.float32).copy()
    al = a[..., 3] > 60
    rgb = a[..., :3] / 255.0
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    cand = al & (sat < 0.34) & (mx > 0.70)
    allowed = cand | (~al)
    h, w = allowed.shape
    seeds = ([(x, 0) for x in range(w) if allowed[0, x]]
             + [(x, h - 1) for x in range(w) if allowed[h - 1, x]]
             + [(0, y) for y in range(h) if allowed[y, 0]]
             + [(w - 1, y) for y in range(h) if allowed[y, w - 1]])
    if seeds:
        reach = _flood_seeds(allowed, seeds)
        a[cand & reach, 3] = 0

    # ③ 只保留「最大的那个不透明连通体」。
    # 阴影最核心的一圈偏暗、饱和度也高，不满足上面的候选判据，于是残留成一片**与角色
    # 不连通的淡斑**。危害不止是难看：外框是按 alpha 取的，残留会把外框撑大——
    # 实测「右腿抬中」那帧 alpha>40 的外框是 1153×1161，而真正角色只有 996×873。
    # 外框一虚大，之后所有"按外框对齐/缩放"的步骤全跟着错（角色被缩小、还被抬离地面）。
    # 角色本身是完整一块，所以"只留最大连通体"是干净且不会误伤的判据。
    al2 = a[..., 3] > 60
    if al2.any():
        ys, xs = np.where(al2)
        lab = _flood_seeds(al2, [(int(xs[0]), int(ys[0]))])
        # 要删的是「最大连通体之外的**全部**不透明像素」——残留斑的不透明度只有 40~60，
        # 不在 al2 里，所以不能只比 al2 的差集（那样会算成 0、整段被跳过，等于没修）。
        outside = (a[..., 3] > 0) & ~lab
        dropped, total = int(outside.sum()), int((a[..., 3] > 0).sum())
        if dropped:
            assert dropped < total * 0.08, (
                f'被丢掉的像素占 {dropped / total:.1%}，超过 8%——'
                '说明角色被切成了多块，不能再按「单个连通体」处理')
            a[outside, 3] = 0
    return Image.fromarray(a.astype(np.uint8), 'RGBA')


def draw_ground_shadow(frame, x, ground_y, width, h_frac):
    """程序化落地影：始终贴地，腾空越高越小越淡。"""
    k = 1.0 - 0.45 * h_frac
    alpha = 0.42 * (1.0 - 0.58 * h_frac)
    if alpha <= 0.01 or width <= 1:
        return
    w = max(2, int(width * k))
    h = max(2, int(width * 0.20 * k))
    layer = Image.new('RGBA', (w * 2, h * 2), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([w * 0.5, h * 0.5, w * 1.5, h * 1.5],
                                  fill=(92, 72, 58, int(255 * alpha)))
    layer = layer.filter(ImageFilter.GaussianBlur(max(2, h * 0.45)))
    frame.alpha_composite(layer, (int(x - w), int(ground_y - h)))


# ---------------------------------------------------------------- 时间线

def walk_weights(t, direction, hz):
    """6 帧走路循环：纯定格播放（精灵动画的常规做法）。

    绝对不能在相邻帧之间做交叉淡入：alpha_composite 是 source-over，
    下层那一帧会以残余不透明度整只透出来，看起来就是凭空多出一个身体的「重影」。
    要让它更顺，正确做法是补更多分解帧，而不是靠叠加过渡去糊。
    """
    frames = WALK_SETS[direction]
    n = len(frames)
    return {frames[int((t * hz * n) % n)]: 1.0}


def pose_blend(t):
    hz = WALK_HZ if t < T_IMPACT else WALK_HZ * 2.0
    if t < T_IMPACT:
        return walk_weights(t, 'front', WALK_HZ)
    if t < T_IMPACT + 0.18:
        k = smoothstep((t - T_IMPACT) / 0.18)
        w = {p: v * (1 - k) for p, v in walk_weights(t, 'front', WALK_HZ).items()}
        w['pout'] = k
        return w
    if t < T_CRY:
        return {'pout': 1.0}
    if t < T_CRY + 0.22:
        k = smoothstep((t - T_CRY) / 0.22)
        return {'pout': 1 - k, 'cry': k}
    if t < T_FLEE:
        return {'cry': 1.0}
    if t < T_FLEE + TURN:
        k = smoothstep((t - T_FLEE) / TURN)
        w = {p: v * k for p, v in walk_weights(t, 'back', hz).items()}
        w['cry'] = 1 - k
        return w
    return walk_weights(t, 'back', hz)


def ally_pose(t):
    """我方小宠物当前该出哪一帧：站立 → 抬手蓄力 → 挥出 → 收回。

    投掷动作必须和坚果脱手对齐（NUT_LAUNCH）：早了自己先动、晚了坚果凭空出现。
    """
    if t < ALLY_WINDUP:
        return 'ally_stand'
    if t < ALLY_RELEASE:
        return 'ally_windup'
    if t < ALLY_RECOVER:
        return 'ally_throw'
    return 'ally_stand'


def render():
    os.makedirs(OUTDIR, exist_ok=True)
    bg = build_background()
    assets, ref_h, anchor = load_assets()
    rng = np.random.default_rng(11)
    tears, dusts = [], []

    for fi in range(N_FRAMES):
        t = fi / FPS
        canvas = bg.copy().convert('RGBA')

        approaching = t < T_IMPACT
        gx = MARGIN + W / 2
        hop_h = 0.0          # 当前腾空高度（占角色高度比例）
        air = False

        if approaching:
            gy = track(t, [(0, GROUND_FAR), (T_IMPACT, GROUND_NEAR)])
        elif t < T_FLEE:
            gy = track(t, [(T_IMPACT, GROUND_NEAR), (T_IMPACT + .10, GROUND_BOUNCE),
                           (T_IMPACT + .34, GROUND_SETTLE - 8),
                           (T_CRY, GROUND_SETTLE), (T_FLEE, GROUND_SETTLE)])
        else:
            gy = track(t, [(T_FLEE, GROUND_SETTLE), (T_END, GROUND_FAR)])

        fleeing = t >= T_FLEE
        walking = fleeing          # 逃跑仍用背面走路循环

        # 转身：横向压扁再弹回
        turn_sq = 1.0
        if T_FLEE <= t < T_FLEE + TURN * 1.6:
            k = (t - T_FLEE) / (TURN * 1.6)
            turn_sq = max(0.52, abs(math.cos(k * math.pi)))

        sq_x, sq_y, rot = 1.0, 1.0, 0.0
        if T_IMPACT <= t < T_IMPACT + 0.75:
            k = (t - T_IMPACT) / 0.75
            e = ease_out_elastic(k, amp=0.55, period=0.36)
            sq_y = lerp(1.0, 0.80, e * (1 - k) * 1.35)
            sq_x = lerp(1.0, 1.16, e * (1 - k) * 1.35)
            rot = math.sin(k * math.pi * 3) * 5 * (1 - k)
        sway = 0.0
        if approaching:
            # 走路起伏只做在「以脚底为支点的挤压拉伸」上：脚不动，身体自己起伏。
            # 整体上下平移会让脚离地、整体旋转会让底座翘成跷跷板，两者都会被读成打滑。
            bob = -BOB_SQUASH * math.cos(2 * math.pi * WALK_HZ * 2 * t)
            sq_y *= 1 + bob
            sq_x *= 1 - bob * 0.55
        sway = 0.0 if approaching else sway
        if walking:
            ph = 2 * math.pi * (WALK_HZ * 2.0) * t
            rot += LEAN_FLEE * math.sin(ph)
            sway = SWAY_FLEE * math.sin(ph)
        sq_x *= turn_sq

        shake_x = math.sin(t * math.pi * 2 * 19) * 3.2 if T_CRY <= t < T_FLEE else 0.0
        ground_y = gy
        height = 900 * scale_at_ground(ground_y)
        char_y = ground_y + sway * 0.0
        char_x = gx + shake_x

        # 落地影：贴地、随腾空变淡变小；角色则被抬高到 char_y
        draw_ground_shadow(canvas, char_x, ground_y, height * 0.62, 0.0)

        for pname, wgt in pose_blend(t).items():
            if wgt <= 0.001:
                continue
            img, bb = assets[pname]
            paste_char(canvas, img, bb, anchor[pname], (char_x, char_y), height,
                       ref_h[pname], sx=sq_x, sy=sq_y, rot=rot, alpha=wgt)

        # ---- 我方小宠物：站在桥头（离镜头最近），所以画在小馋怪之后、盖在它上面。
        # 它只做一件事——到点用小短手把坚果扔出去；坚果的起点就是它的手。
        ally_h = 900 * scale_at_ground(ALLY_GROUND) * ALLY_RATIO
        ally_x = MARGIN + W / 2 + W * ALLY_OFFSET_X
        ally_y = ALLY_GROUND
        ally_bob = -0.022 * math.cos(2 * math.pi * 0.9 * t)     # 站着也别是死的
        aimg, abb = assets[ally_pose(t)]
        paste_char(canvas, aimg, abb, anchor[ally_pose(t)], (ally_x, ally_y), ally_h,
                   ref_h[ally_pose(t)], sx=1 - ally_bob * 0.55, sy=1 + ally_bob)
        draw_ground_shadow(canvas, ally_x, ally_y, ally_h * 0.62, 0.0)

        if fi % 6 == 0 and (approaching or walking):
            dusts.append([char_x + rng.uniform(-26, 26), ground_y,
                          rng.uniform(8, 15), 0.0, 0.45])
        if T_CRY <= t < T_FLEE and fi % 4 == 0:
            for s in (-1, 1):
                tears.append([gx + s * height * 0.075, ground_y - height * 0.62,
                              s * rng.uniform(90, 190), rng.uniform(-260, -150), 0.0])

        keep = []
        for p in tears:
            p[4] += 1 / FPS
            if p[4] <= 0.9:
                p[0] += p[2] / FPS
                p[1] += p[3] / FPS
                p[3] += 1500 / FPS
                fx_tear(canvas, p[0], p[1], 16, 1 - p[4] / 0.9)
                keep.append(p)
        tears = keep

        keep = []
        for p in dusts:
            p[3] += 1 / FPS
            if p[3] <= p[4]:
                kk = p[3] / p[4]
                fx_dust(canvas, p[0] - (40 if t >= T_FLEE else -20) * kk, p[1] + 10 * kk,
                        p[2] * (0.6 + kk), 1 - kk)
                keep.append(p)
        dusts = keep

        if NUT_LAUNCH <= t < T_IMPACT:
            # 坚果从我方小宠物的手飞向小馋怪。起点改成它的手之后，之前那下挤压与星芒
            # 才有来由——原来坚果是从画面外凭空出现的。
            k = (t - NUT_LAUNCH) / (T_IMPACT - NUT_LAUNCH)
            hx = ally_x + ally_h * 0.30
            hy = ally_y - ally_h * 0.62
            tx, ty = gx, ground_y - height * 0.45
            nx = lerp(hx, tx, k)
            ny = lerp(hy, ty, k) - H * 0.13 * math.sin(math.pi * k)   # 抛一条弧线
            for j in range(3):
                fx_nut(canvas, nx + j * 26, ny + j * 20, k * 900 + j * 40, 17 - j * 3)
            fx_nut(canvas, nx, ny, k * 900, 20)
        if T_IMPACT <= t < T_IMPACT + 0.42:
            fx_impact(canvas, gx + 60, ground_y - height * 0.55, (t - T_IMPACT) / 0.42)
        if t >= T_FLEE + TURN:
            fx_speed(canvas, gx, ground_y - height * 0.45, H * 0.078,
                     (1 - (t - T_FLEE) / 2.4) * 0.9, vertical=True)

        if T_IMPACT <= t < T_IMPACT + 0.38:
            k = (t - T_IMPACT) / 0.38
            amp = 22 * (1 - k) ** 2
            ox, oy = MARGIN + int(math.sin(t * 137) * amp), MARGIN + int(math.cos(t * 191) * amp)
        else:
            ox = oy = MARGIN
        canvas.convert('RGB').crop((ox, oy, ox + W, oy + H)).save(
            os.path.join(OUTDIR, f'f{fi:04d}.png'))
    return N_FRAMES


def encode(n):
    mp4 = os.path.join(OUTDIR, 'xiaochanguai_hit_and_cry.mp4')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(FPS),
                    '-i', os.path.join(OUTDIR, 'f%04d.png'),
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18',
                    '-movflags', '+faststart', mp4], check=True)
    gif = os.path.join(OUTDIR, 'xiaochanguai_hit_and_cry.gif')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp4,
                    '-vf', 'fps=20,scale=540:-1:flags=lanczos,split[a][b];'
                           '[a]palettegen=max_colors=200[p];[b][p]paletteuse=dither=bayer:bayer_scale=3',
                    gif], check=True)
    return mp4, gif


if __name__ == '__main__':
    n = render()
    mp4, gif = encode(n)
    print(f'{n} 帧 → {mp4} ({os.path.getsize(mp4)/1024/1024:.1f} MB), {gif}')
