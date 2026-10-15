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
    # 桥面半宽占视口宽度的比例。2026-10-15 加宽：为了桥上能并排站下更多小怪、
    # 桥头能站下更多我方小宠物（原来底端 66%，底端桥宽只够并排 2~3 只）。
    BRIDGE_TOP_HALF = 0.10
    BRIDGE_BOT_HALF = 0.38
    # 角色行进轨道。GROUND_DEFEAT 是「走到全程约一半、被打倒」的位置——
    # 需求是「小馋怪走到大约屏幕一半距离时已经被打倒 3 次」，所以走到这里就结束推进，
    # 后面的哭与逃跑都在这个位置上发生。
    # 进场起点与出场终点都必须在**画面之外**：可见的画布纵向范围约 y 106~1092
    # （手机横屏下 BoxFit.cover 会裁掉上下各约 9%）。原来起点 300、终点 200 都在画面内，
    # 于是小怪是「凭空出现」、逃跑完又跳回起点闪一下。改成屏外→屏外，接缝自然看不见。
    GROUND_FAR = 40             # 出发点（画面之外的远处）
    GROUND_DEFEAT = 580         # 被打倒处
    GROUND_LIFT = 500           # 最后一下被弹起的高度
    GROUND_SETTLE = 575         # 哭的时候落定的位置
    GROUND_FLEE_END = 30        # 跑远的终点（同样在画面之外）
    # 透视斜坡的起点跟着下移到画面之外，远处的小怪才会「由小变大」地走进来；
    # 原来斜坡从 y=240 才开始，240 以上是一段恒定的 0.22，走进来时大小不变。
    SCALE_Y0, SCALE_Y1 = 60, 920
    SCALE_S0, SCALE_S1 = 0.15, 0.52
else:
    W, H = 1080, 1920
    BRIDGE_TOP_HALF = 0.20
    BRIDGE_BOT_HALF = 0.476
    GROUND_FAR = 420
    GROUND_DEFEAT = 700
    GROUND_LIFT = 620
    GROUND_SETTLE = 695
    GROUND_FLEE_END = 320
    SCALE_Y0, SCALE_Y1 = 380, 1180
    SCALE_S0, SCALE_S1 = 0.30, 0.78

# 角色的基准身高（画布像素）：实际身高 = 本值 × 透视缩放。
# 900 → 620 → 430：配合加宽的桥面，让「每排五六只」放得下。
CHAR_BASE = 430
# 与角色同比例缩放的特效尺寸倍率。角色变小了，坚果 / 星芒 / 眼泪 / 尘土也得跟着变小，
# 否则它们相对角色会显得越来越大——这类「绝对像素」的尺寸最容易漏。
FX = CHAR_BASE / 900.0

FPS = 30
DURATION = 6.8
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

# ---- 时间线 ----
# 三次命中都在「走到全程一半」之前发生：T_HIT3 就是走到 GROUND_DEFEAT 的时刻。
# 间距 0.8 秒（比原来一次命中的节奏密得多），对应「投掷频率高一点」。
T_HIT1 = 1.00
T_HIT2 = 1.80
T_HIT3 = 2.60
T_IMPACT = T_HIT3          # 第三下即打倒；后续衔接沿用原名
T_CRY = 3.15
T_FLEE = 3.95
T_END = 6.80
HITS = (T_HIT1, T_HIT2, T_HIT3)
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
# 投掷节奏：每次「抬手 0.30 秒 → 挥出脱手 → 收手 0.24 秒」，三次脱手时刻与
# 三次命中一一对齐（坚果飞 0.42 秒）。总时长与命中间隔一致，所以看起来是连着投。
ALLY_WINDUP_LEAD = 0.30   # 抬手提前量
ALLY_THROW_HOLD = 0.24    # 挥出姿势保持
NUT_FLIGHT = 0.42         # 坚果飞行时间
NUT_LAUNCHES = tuple(h - NUT_FLIGHT for h in HITS)   # (0.58, 1.38, 2.18)


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
        im = Image.open(os.path.join(src, fn)).convert('RGBA')
        # 只对小馋怪剥烘焙阴影。**我方小宠物不能剥**：它的身体是淡蓝色，
        # 而 strip_ground_shadow 的判据是「低饱和 + 够亮 + 从画布外边可达就删」，
        # 手臂边缘只有细描边挡不住洪泛，结果手臂与身体连接的那一整段被吃掉，
        # 只剩外侧一小块悬在那里——看起来就是「小手挥出时有一段被截掉了」。
        # 它本来也没有烘焙阴影（是平色背景抠出来的），这一步对它没有意义。
        if not k.startswith('ally'):
            im = strip_ground_shadow(im)
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


def fx_impact(frame, x, y, k, scale=1.0):
    if k <= 0 or k >= 1:
        return
    r = lerp(26, 235, ease_out_back(min(1.0, k * 1.4))) * scale
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


def pose_blend(t, front=True):
    hz = WALK_HZ if t < T_IMPACT else WALK_HZ * 2.0
    if not front:
        # 后排没被打到：正面走到头，直接转身退回去，不瘪嘴也不哭
        return walk_weights(t, 'back' if t >= T_FLEE else 'front', hz)
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


# ---------------------------------------------------------------- 怪群与宠物队

CYCLE = DURATION          # 一只小怪走完「压上来 → 挨三下 → 哭 → 逃」的时长＝整个循环

# 每一只小怪：(相位偏移（占整个循环的比例）, 横向偏移（占该处桥面半宽的比例）,
#              深度抖动（画布像素）, 尺寸抖动)
#
# 相位错开 => 「一排接一排」地压上来；横向、深度、尺寸三样都加抖动 => 不至于排得太整齐。
# 数值是手调的：错落但不至于挤成一团，横向尽量铺开但不越出桥面（横向单位是「半宽的比例」，
# 所以深处的小怪自然收拢、近处的自然铺开，和透视是一致的）。
MONSTERS = [
    (0.00, -0.62, -60, 1.00), (0.05, 0.10, 130, 0.94), (0.09, 0.58, -100, 1.05),
    (0.16, -0.30, 70, 0.97), (0.21, 0.44, -140, 1.02), (0.26, -0.72, 30, 0.92),
    (0.33, 0.22, 100, 1.06), (0.38, -0.48, -80, 0.95), (0.44, 0.66, 150, 1.01),
    (0.52, -0.12, -120, 0.98), (0.58, -0.66, 90, 1.04), (0.63, 0.36, -40, 0.93),
    (0.71, -0.36, 120, 1.00), (0.77, 0.54, -110, 0.96), (0.84, -0.06, 50, 1.03),
    (0.91, 0.28, -90, 0.99),
]
#
# 深度抖动给得很大（±150）：只给小抖动的话，十几只全挤在桥的上半段，
# 桥头与怪群之间空出一大片，画面上「压过来」的势头就没了。

# ---- 我方小队 ----
# 编成前后两排，整体可以左右移动（App 里由左下/右下两个按钮控制）。
# 每项：(相对小队中心的横向偏移（占视口宽）, 深度偏移（画布像素）, 尺寸抖动)
# 后排更远、更高、略小；前排更近、更低、略大——这样两排才看得出纵深。
ALLY_ROWS = [
    [(-0.034, -58, 0.97), (0.034, -50, 1.03)],                    # 后排 2 只
    [(-0.055, 20, 1.04), (0.000, 28, 0.98), (0.055, 14, 1.06)],    # 前排 3 只
]
ALLY_RATIO = 0.55          # 相对同位置小怪的大小（原来 0.85，用户要求再小一圈）
SQUAD_SWING = 0.11         # 参考视频里小队左右巡航的幅度（占视口宽）；App 里由摇杆控制
SQUAD_LIMIT = 0.24         # 小队中心能移到的最远处：再往外就出桥了
SQUAD_HZ = 0.20            # 巡航频率

# 谁能被打到：只有「最前排」的小怪。后排被前排挡着，打不到。
# 判定用深度抖动 dj —— 它本来就是「比平均更靠前/更靠后」的意思，正好当排次用。
FRONT_ROW_DJ = 0.0         # dj > 此值算最前排


def bridge_half(y):
    """某一深度处桥面的半宽（画布像素）。

    小怪的横向偏移是「该处桥面半宽的比例」，乘它才不会站到水里去；
    深处桥面窄、小怪自然收拢，近处宽、自然铺开——这本身就是透视的一部分。
    """
    k = min(1.0, max(0.0, y / CANVAS[1]))
    return W * lerp(BRIDGE_TOP_HALF, BRIDGE_BOT_HALF, k)


def unit_state(tt, front=True):
    """某只小怪在「它自己的时间」tt 上的全部状态。

    [front] 为假表示它在后排、打不到：那它就不会有挨打的挤压回弹，也不会哭，
    只是走上来再退回去——否则会出现「没被打中却在哭」的矛盾。

    抽成纯函数是这次重构的关键：十几只小怪跑的是**同一条时间线**，只是各自错开相位，
    所以「一排接一排」与「混乱」都只是相位和横向偏移的差别，不必为每只再写一套逻辑。
    下面这些辅助函数（track / scale_at_ground / pose_blend / ease_out_elastic）本来就都是
    对 t 的纯函数，直接喂 tt 即可。
    """
    if tt < T_IMPACT:
        gy = track(tt, [(0, GROUND_FAR), (T_HIT3, GROUND_DEFEAT)])
    elif tt < T_FLEE:
        gy = track(tt, [(T_HIT3, GROUND_DEFEAT), (T_HIT3 + .10, GROUND_LIFT),
                        (T_HIT3 + .34, GROUND_SETTLE - 8),
                        (T_CRY, GROUND_SETTLE), (T_FLEE, GROUND_SETTLE)])
    else:
        gy = track(tt, [(T_FLEE, GROUND_SETTLE), (T_END, GROUND_FLEE_END)])

    approaching = tt < T_IMPACT
    walking = tt >= T_FLEE
    turn_sq = 1.0
    if T_FLEE <= tt < T_FLEE + TURN * 1.6:
        k = (tt - T_FLEE) / (TURN * 1.6)
        turn_sq = max(0.52, abs(math.cos(k * math.pi)))

    sq_x, sq_y, rot = 1.0, 1.0, 0.0
    for _i, _hit in (enumerate(HITS) if front else ()):
        if not (_hit <= tt < _hit + 0.75):
            continue
        k = (tt - _hit) / 0.75
        e = ease_out_elastic(k, amp=0.55, period=0.36)
        amp = 1.0 if _i == len(HITS) - 1 else 0.45
        sq_y *= lerp(1.0, 0.80, e * (1 - k) * 1.35 * amp)
        sq_x *= lerp(1.0, 1.16, e * (1 - k) * 1.35 * amp)
        rot += math.sin(k * math.pi * 3) * 5 * (1 - k) * amp
    if approaching:
        bob = -BOB_SQUASH * math.cos(2 * math.pi * WALK_HZ * 2 * tt)
        sq_y *= 1 + bob
        sq_x *= 1 - bob * 0.55
    if walking:
        rot += LEAN_FLEE * math.sin(2 * math.pi * (WALK_HZ * 2.0) * tt)
    sq_x *= turn_sq

    return {'gy': gy, 'approaching': approaching, 'walking': walking,
            'sq_x': sq_x, 'sq_y': sq_y, 'rot': rot,
            'shake': math.sin(tt * math.pi * 2 * 19) * 3.2
            if (front and T_CRY <= tt < T_FLEE) else 0.0}


def draw_unit(canvas, assets, ref_h, anchor, tt, x, depth_jit, size_jit, front=True):
    """把一只小怪按「它自己的时间」画出来。返回 (脚底行, 身高, 中心x) 供调用方定位特效。"""
    st = unit_state(tt, front)
    gy = st['gy'] + depth_jit
    h = CHAR_BASE * scale_at_ground(gy) * size_jit
    cx = x + st['shake']
    draw_ground_shadow(canvas, cx, gy, h * 0.62, 0.0)
    for pname, wgt in pose_blend(tt, front).items():
        if wgt <= 0.001:
            continue
        img, bb = assets[pname]
        paste_char(canvas, img, bb, anchor[pname], (cx, gy), h, ref_h[pname],
                   sx=st['sq_x'], sy=st['sq_y'], rot=st['rot'], alpha=wgt)

    # 飙泪：向两旁喷出去的弹道。
    #
    # 时间线调整：原来只哭到 T_FLEE+0.3，现在一路飙到逃跑途中——转身跑远还拖着
    # 一条泪迹，喜感主要来自这里。
    #
    # 关键：每颗泪珠按**它出生那一刻小怪的位置**算，而不是按小怪当前位置。
    # 按当前位置画的话泪珠会黏在脸上跟着跑；按出生位置画，跑动时泪珠会留在身后，
    # 自然拉成一条轨迹。unit_state() 是纯函数，所以这件事可以直接算，不需要粒子表。
    # 背对镜头时，眼睛在脑袋的**背面**——泪珠必须被脑袋挡住，
    # 只有飞出轮廓之外的那一段才看得见。无条件画在最上层的话，
    # 看起来就像「从后脑勺飙出来的眼泪」。
    _back = tt >= T_FLEE + TURN
    _head_cx = cx
    _head_cy = gy - h * 0.50
    _head_rx = h * 0.42
    _head_ry = h * 0.52

    for _i in (range(30) if front else ()):
        birth = T_CRY + _i * 0.09
        if birth > tt:
            break
        age = tt - birth
        if age > 0.65:
            continue
        _st = unit_state(birth, front)
        _gy = _st['gy'] + depth_jit
        _hh = CHAR_BASE * scale_at_ground(_gy) * size_jit
        _side = -1 if _i % 2 == 0 else 1
        # 起点在**眼角外侧**：两眼各从自己那一侧出发，否则会像从两眼之间冒出来
        _ex = x + _st['shake'] + _side * _hh * 0.10
        _ey = _gy - _hh * 0.62
        # 横向每秒 1.9 个身高（从眼角算最远约 1.33 个身高）——必须明显超出脑袋轮廓
        # （横向半径 0.42 身高），否则背对镜头时整段都被挡住、等于看不见。
        # 纵向先上抛、再被"重力"拉回来。
        _tx = _ex + _side * _hh * 1.9 * age
        _ty = _ey - _hh * (1.2 * age - 3.2 * age * age)
        if _back:
            _u = (_tx - _head_cx) / _head_rx
            _v = (_ty - _head_cy) / _head_ry
            if _u * _u + _v * _v < 1.0:
                continue                            # 还在脑袋后面，看不见
        fx_tear(canvas, _tx, _ty, 20 * FX, 1 - age / 0.7)

    if st['approaching'] or st['walking']:
        for i in range(2):
            ph = (tt * 2.2 + i * 0.5) % 1.0
            fx_dust(canvas, cx + (i * 2 - 1) * h * 0.22, gy, (11 - ph * 5) * FX, 1 - ph)
    return gy, h, cx


def squad_members(squad_x=0.0):
    """小队全部成员：(画布横向x, 脚底行, 身高, 第几排)。

    整体跟着 [squad_x]（占视口宽的比例）左右平移——这就是左右按钮改的那个量。
    两排各自有深度偏移，所以画出来有前后纵深。
    """
    out = []
    for ri, row in enumerate(ALLY_ROWS):
        for (rx, rdj, rsj) in row:
            gy = ALLY_GROUND + rdj
            h = CHAR_BASE * scale_at_ground(gy) * ALLY_RATIO * rsj
            out.append((MARGIN + W / 2 + W * (squad_x + rx), gy, h, ri))
    return out


# ---------------------------------------------------------------- 玩法模拟
#
# 为什么不再是「每只小怪按相位跑固定时间线」：
#   需求是「弹丸竖直向前飞、撞到最前面的小怪就停、只有它正在哭才穿透」。
#   那挨打与哭就必须**由命中触发**——否则会出现「弹丸打中 A，却是 B 在哭」的矛盾。
#   于是小怪从纯函数时间线改成一台状态机，弹丸由命中驱动它。

NUT_SPEED = 1150          # 弹丸向上飞的速度（画布像素/秒）
SHOT_INTERVAL = 0.40      # 每隔多久有一发，轮流由小队成员投出
MOB_WALK_SPEED = 96       # 小怪朝镜头走的速度
MOB_FLEE_SPEED = 215      # 逃跑速度
RECOIL_TIME = 0.34        # 被打退一下的时长
CRY_TIME = 0.80           # 原地哭的时长
HITS_TO_CRY = 3           # 挨几下会哭
HOLD_GY = 470             # 走到这附近就停下来对峙，不再往镜头压
                          # 每只再按自己的深度抖动错开，天然形成前后几排


class Mob:
    """一只小怪：walk（走上来）→ 被打退若干次 → cry（哭）→ flee（跑回去）→ 重新来。"""

    def __init__(self, lane, dj, sj, gy0):
        self.lane, self.dj, self.sj = lane, dj, sj
        self.gy0 = gy0
        self.gy = gy0
        self.hits = 0
        self.state = 'walk'
        self.timer = 0.0
        self.since_hit = 99.0        # 距上次挨打多久，用来算挤压回弹
        self.walk_t = 0.0            # 走路循环的累计时间（喂常量 0 腿就不动）
        # 各自停在哪：抖动 dj 本来就是「比平均更靠前」的意思，用它错开正好
        self.hold_gy = HOLD_GY + dj * 0.6

    def ground(self):
        return self.gy + self.dj

    def x(self):
        return MARGIN + W / 2 + self.lane * bridge_half(self.ground())

    def height(self):
        return CHAR_BASE * scale_at_ground(self.ground()) * self.sj

    def transparent(self):
        """正在哭或逃跑的小怪不挡弹丸——需求里那句「除非正在哭，否则不要穿透」。"""
        return self.state in ('cry', 'flee')

    def hit(self):
        self.hits += 1
        self.since_hit = 0.0
        if self.hits >= HITS_TO_CRY:
            self.state, self.timer = 'cry', CRY_TIME
        else:
            self.state, self.timer = 'recoil', RECOIL_TIME

    def step(self, dt):
        self.since_hit += dt
        if self.state in ('walk', 'flee', 'hold'):
            self.walk_t += dt
        if self.state == 'walk':
            self.gy += MOB_WALK_SPEED * dt
            if self.ground() >= self.hold_gy:
                self.state = 'hold'          # 到位置了，停下来对峙（走路循环继续，脚下不位移）
        elif self.state == 'hold':
            pass
        elif self.state == 'recoil':
            self.timer -= dt
            if self.timer <= 0:
                self.state = 'hold' if self.ground() >= self.hold_gy else 'walk'
        elif self.state == 'cry':
            self.timer -= dt
            if self.timer <= 0:
                self.state = 'flee'
        elif self.state == 'flee':
            self.gy -= MOB_FLEE_SPEED * dt
            if self.ground() < GROUND_FLEE_END - 60:
                self.gy, self.hits, self.state, self.timer = self.gy0, 0, 'walk', 0.0


def make_mobs():
    """开局：按 MONSTERS 的相位把十几只小怪错开铺在桥面上，避免一开始空场。"""
    mobs = []
    for (phase, lane, dj, sj) in MONSTERS:
        gy0 = GROUND_FAR + (GROUND_DEFEAT - GROUND_FAR) * phase
        mobs.append(Mob(lane, dj, sj, gy0))
    return mobs


def mob_pose(m):
    """小怪这一刻该出什么姿势。"""
    if m.state == 'cry':
        return {'cry': 1.0}
    if m.state == 'flee':
        return walk_weights(m.walk_t, 'back', WALK_HZ)
    if m.state == 'recoil':
        return {'pout': 1.0}
    return walk_weights(m.walk_t, 'front', WALK_HZ)   # walk 与 hold 都是正面走路循环


def mob_squash(m):
    """挨打那一下的挤压回弹（弹性曲线，越往后越平）。"""
    if m.since_hit > 0.62:
        return 1.0, 1.0
    k = m.since_hit / 0.62
    e = ease_out_elastic(k, amp=0.55, period=0.36)
    w = e * (1 - k) * 1.35 * (1.0 if m.hits >= HITS_TO_CRY else 0.6)
    return lerp(1.0, 1.16, w), lerp(1.0, 0.80, w)


def nut_schedule(squad_x=0.0):
    """把「最前排小怪的三次命中」摊平成一张投掷表。

    与小怪时代的区别有两点，都是需求带来的：
      1. **只有最前排的小怪**（dj > FRONT_ROW_DJ）会被打到——后排被前排挡着；
      2. 每一次命中挑「**同列最近**」的那只小宠物来投，而不是轮流派。
         这样弹道才是朝正前方（屏幕上方）出去的，而不是四散乱飞；
         也正好对应「投掷武器的范围在队形正上方」。
    """
    members = squad_members(squad_x)
    events = []
    for i, (phase, lane, dj, sj) in enumerate(MONSTERS):
        if dj <= FRONT_ROW_DJ:
            continue
        for j, hit in enumerate(HITS):
            st_hit = unit_state(hit, True)
            gy_hit = st_hit['gy'] + dj
            tx = MARGIN + W / 2 + lane * bridge_half(gy_hit)
            ai = min(range(len(members)), key=lambda k: abs(members[k][0] - tx))
            events.append({'gh': (phase * CYCLE + hit) % CYCLE, 'mi': i, 'hj': j, 'ai': ai})
    events.sort(key=lambda e: e['gh'])
    return events


def ally_pose_for(t, events, ai):
    """第 ai 只小宠物这一刻出哪一帧。

    它的投掷时刻来自投掷表（哪几次命中轮到它），抬手提前 ALLY_WINDUP_LEAD 秒。
    一律用「环形距离」判断，否则跨循环边界的那几次投掷会漏掉抬手动作。
    """
    for e in events:
        if e['ai'] != ai:
            continue
        launch = (e['gh'] - NUT_FLIGHT) % CYCLE
        if (t - (launch - ALLY_WINDUP_LEAD)) % CYCLE < ALLY_WINDUP_LEAD:
            return 'ally_windup'
        if (t - launch) % CYCLE < ALLY_THROW_HOLD:
            return 'ally_throw'
    return 'ally_stand'


def draw_joystick(canvas, squad_x, lo=-0.34, hi=0.34):
    """左下角的移动摇杆（王者荣耀那种）。

    App 里它是真正可按的控件（见 monster_sprite.dart 的 _joystick）；这里画出来只是
    为了让参考视频与 App 的画面一致。右下角**故意留空**——将来放道具栏。
    """
    d = ImageDraw.Draw(canvas, 'RGBA')
    r = 62                      # 底盘半径
    knob = 26                   # 杆的半径
    cx = MARGIN + 22 + r
    cy = CANVAS[1] - 16 - r
    # 杆按推杆量偏移（参考视频里让 squad_x 线性映射过去，视觉上与 App 一致）
    k = max(-1.0, min(1.0, squad_x / hi if hi else 0.0))
    d.ellipse([cx - r, cy - r, cx + r, cy + r],
              fill=(28, 34, 48, 108), outline=(255, 255, 255, 102), width=4)
    kx = cx + k * r * 0.62
    d.ellipse([kx - knob, cy - knob, kx + knob, cy + knob],
              fill=(255, 255, 255, 78), outline=(255, 255, 255, 216), width=4)
    # 中间的左右箭头
    for sign in (-1, 1):
        a = 11
        bx = kx + sign * 6
        d.polygon([(bx - sign * a, cy - a), (bx - sign * a, cy + a), (bx + sign * a, cy)],
                  fill=(255, 255, 255, 225))


def ally_pose_at(t, ai, n):
    """第 ai 只小宠物这一刻出哪一帧。

    开火是「每 SHOT_INTERVAL 一发、轮流由小队成员投出」，所以它自己的开火时刻
    就是所有满足 索引 ≡ ai (mod n) 的时刻。抬手提前 0.18 秒，挥出保持 0.22 秒。
    """
    k = int(math.floor(t / SHOT_INTERVAL))
    last = k - ((k - ai) % n)          # 不大于 k 且与 ai 同余的最大索引
    if last >= 0 and t - last * SHOT_INTERVAL < 0.22:
        return 'ally_throw'
    if (last + n) * SHOT_INTERVAL - t <= 0.18:
        return 'ally_windup'
    return 'ally_stand'


def draw_mob(canvas, assets, ref_h, anchor, m):
    """按状态机画一只小怪（含挨打的挤压、哭时的飙泪）。"""
    g = m.ground()
    h = m.height()
    cx = m.x()
    if m.state == 'cry':
        cx += math.sin(m.timer * math.pi * 2 * 19) * 3.2      # 哭的时候左右抖
    sx, sy = mob_squash(m)
    draw_ground_shadow(canvas, cx, g, h * 0.62, 0.0)
    for pname, wgt in mob_pose(m).items():
        if wgt <= 0.001:
            continue
        img, bb = assets[pname]
        paste_char(canvas, img, bb, anchor[pname], (cx, g), h, ref_h[pname],
                   sx=sx, sy=sy, rot=0.0, alpha=wgt)

    # 飙泪：向两旁喷出去，按出生时刻的位置算弹道（转身跑远时会拖出泪迹）
    if m.state == 'cry' or (m.state == 'flee' and m.hits >= HITS_TO_CRY):
        for _i in (range(30) if m.state == 'cry' else range(30)):
            birth = CRY_TIME * 0 + _i * 0.09
            # 出生时刻用「进入哭的时长」倒推：这里直接用当前状态近似，
            # 泪珠的横向弹道仍然向两旁，飞出去后不再跟头
            age = _i * 0.09
            if age > 0.65:
                continue
            side = -1 if _i % 2 == 0 else 1
            tx = cx + side * h * 0.10 + side * h * 1.9 * age
            ty = (g - h * 0.62) - h * (1.2 * age - 3.2 * age * age)
            u = (tx - cx) / (h * 0.42)
            v = (ty - (g - h * 0.50)) / (h * 0.52)
            if m.state == 'flee' and u * u + v * v < 1.0:
                continue
            fx_tear(canvas, tx, ty, 20 * FX, 0.9 * (1 - age / 0.7))
    return cx


def render():
    os.makedirs(OUTDIR, exist_ok=True)
    bg = build_background()
    assets, ref_h, anchor = load_assets()
    mobs = make_mobs()
    projs, stars = [], []
    shot_t, shot_idx = 0.0, 0
    dt = 1 / FPS

    for fi in range(N_FRAMES):
        t = fi / FPS
        canvas = bg.copy().convert('RGBA')

        # ---- 小队位置（参考视频里缓慢巡航，示意摇杆效果；App 里由玩家控制）
        squad_x = SQUAD_LIMIT * 0.8 * math.sin(2 * math.pi * 0.10 * t)
        members = squad_members(squad_x)

        # ---- 开火：每 SHOT_INTERVAL 一发，轮流由小队成员投出
        shot_t += dt
        if shot_t >= SHOT_INTERVAL:
            shot_t -= SHOT_INTERVAL
            ai = shot_idx % len(members)
            shot_idx += 1
            axx, ayy, ah, _ri = members[ai]
            projs.append({'x': axx + ah * 0.18, 'y': ayy - ah * 0.62, 'ai': ai,
                          'trail': [], 'born': t})

        # ---- 弹丸竖直向前飞；撞到最前面的、没在哭的小怪就停下（不穿透）
        for pr in list(projs):
            pr['y'] -= NUT_SPEED * dt
            pr['trail'].append((pr['x'], pr['y']))
            if len(pr['trail']) > 5:
                pr['trail'].pop(0)
            hit = None
            for m in mobs:
                if m.transparent():
                    continue
                h = m.height()
                if abs(pr['x'] - m.x()) > h * 0.46:
                    continue
                g = m.ground()
                if g - h <= pr['y'] <= g and (hit is None or g > hit.ground()):
                    hit = m
            if hit is not None:
                hit.hit()
                stars.append({'x': pr['x'], 'y': pr['y'], 'age': 0.0,
                              'big': hit.hits >= HITS_TO_CRY})
                projs.remove(pr)
            elif pr['y'] < GROUND_FAR - 260:
                projs.remove(pr)

        for m in mobs:
            m.step(dt)

        # ---- 小怪：从远到近画，近的盖住远的
        for m in sorted(mobs, key=lambda m: m.ground()):
            draw_mob(canvas, assets, ref_h, anchor, m)

        # ---- 我方小队
        for ai, (axx, ayy, ah, _ri) in enumerate(members):
            bob = -0.022 * math.cos(2 * math.pi * 0.9 * t + ai * 1.3)
            p = ally_pose_at(t, ai, len(members))
            img, bb = assets[p]
            draw_ground_shadow(canvas, axx, ayy, ah * 0.62, 0.0)
            paste_char(canvas, img, bb, anchor[p], (axx, ayy), ah, ref_h[p],
                       sx=1 - bob * 0.55, sy=1 + bob)

        # ---- 弹丸（竖直上升 + 短尾迹）
        for pr in projs:
            for j, (tx_, ty_) in enumerate(pr['trail']):
                fx_nut(canvas, tx_, ty_, 0, (8 + j * 3) * FX)
            fx_nut(canvas, pr['x'], pr['y'], 0, 22 * FX)

        # ---- 命中星芒
        for st_ in list(stars):
            st_['age'] += dt
            k = st_['age'] / 0.42
            if k >= 1:
                stars.remove(st_)
                continue
            fx_impact(canvas, st_['x'], st_['y'], k, FX * (1.0 if st_['big'] else 0.6))

        draw_joystick(canvas, squad_x)
        canvas.convert('RGB').save(f'{OUTDIR}/f{fi:04d}.png')

    encode(N_FRAMES)


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
