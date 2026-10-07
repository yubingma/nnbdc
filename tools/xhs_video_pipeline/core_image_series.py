#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
词核心图系列竖屏短视频生成器（小红书 9:16）

一集一个单词：先抛出几个看似毫不相干的释义 → 念出「核心意象」与它背后的那一个意象
→ 逐条把「什么现象 → 就是哪个释义」讲成完整的一句话 → 金句收尾。

时长不手写：每段长度由配音的实际时长反推（段首单词发音 + 中文讲解 + 尾巴留白），
所以改文案不需要再手调时间轴。

用法：
    python3 tools/xhs_video_pipeline/core_image_series.py \
        tools/xhs_video_pipeline/episodes/ci01_spring.json

词核心图放在 tmp/xhs_video_pipeline/core_images/ 下（取自生产服务器
/var/www/html/img/core_images/），脚本 JSON 里 core_art 只写文件名即可。
"""

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

from xhs_common import (
    FONT_CN, FONT_CN_BOLD, FONT_CN_REG, FONT_EN, FONT_EN_NUM, FONT_IPA,
    FONT_LATIN, FONT_LATIN_BOLD, FONT_LATIN_MED, FPS, H, OUT_DIR, THEMES, resolve_voice,
    SFX_DIR, W, ImageLayer, Layer, TimedLayer, duration_of, encode_video, fetch_tts,
    PHOTO_ALBUM, fetch_word_audio, fit_font, font, hex2rgb, import_to_photos,
    load_line_art, make_background, resolve_music,
    synth_bgm, teaser_chip,
)

ROOT_DIR = Path(__file__).resolve().parents[2]
TMP_DIR = ROOT_DIR / "tmp" / "xhs_video_pipeline"
CORE_IMG_DIR = TMP_DIR / "core_images"

TAIL = 0.45                # 每段末尾留给观众反应的静默
GAP = 0.45                 # 两条释义讲解之间的最小间隔

# 辐射图几何：核心意象居中偏上，释义散布在它四周，箭头由中心向外生长
HUB = (W / 2, 648)         # 核心意象（中心枢纽）位置
WORD_Y, PHON_Y = 300, 378  # 常驻词头（首帧即出现）
HOOK_ART, HOOK_ART_Y = 320, 700      # 片头里的核心意象
# 收尾也放一次核心意象：这一屏是记忆锚点，把图重新摆出来，"记住一个意象"这话才有指代对象
OUTRO_ART, OUTRO_ART_Y = 190, 530
OUTRO_QUOTE_Y, OUTRO_ASK_Y, OUTRO_CHIP_Y = 760, 1015, 1185
SLOGAN_Y = 1524              # 底部标语。原来它上面压着自绘进度条，现在那条已去掉
HOOK_CARD_Y, HOOK_CARD_GAP, HOOK_LINE_Y = 1010, 140, 1424
ART_BOX = 300              # 辐射段里核心意象的边长（≤4 个节点时）
ART_BOX_MANY = 220         # 节点 ≥5 个时核心意象要缩小，给四周腾地方
NODE_MAX_W = 252           # 单个释义节点内文字的换行宽度（≤4 个节点时）
NODE_MAX_W_MANY = 200      # 节点 ≥5 个时收窄，避免左右两侧撞到画布边缘
RING_CY = 944                 # 环形布局的圆心比 V 形更低：否则顶部节点会顶到单词词头
RING_RX, RING_RY = 380, 380   # 节点 ≥4 个时绕核心意象一圈的椭圆半径
HOOK_GRID_Y, HOOK_GRID_ROW, HOOK_GRID_COL = 1035, 145, 310   # 片头释义卡超过 3 张时改用网格
ARROW_BEND = 46            # 贝塞尔箭头的弯曲幅度
LEAD = 0.30                # 段落开头留白，也是每条释义"画面出现 = 开口念"的对齐点
JOIN_GAP = 0.10            # 「关联逻辑」与「就是X」两段配音之间的停顿
# 收尾：整屏一次性出现（不逐条显现），金句**要念出来**，提问与引导不念。
# 金句是整屏唯一的记忆锚点，不念的话这屏一闪而过、等于白做；提问与引导则不需要念——
# 屏幕上写着，念一遍只是拖时间。所以这一屏的时长由金句的实际配音长度决定。
OUTRO_AT = 0.00                   # 三块内容同时出现的时刻
OUTRO_FADE = 0.15                 # 只做几乎察觉不到的软化，避免硬切的突兀感
OUTRO_TAIL = 0.45                 # 金句念完后再留一点，让视线有余裕扫完提问
NODE_MEAN_Y = 52           # 节点内：释义基线到节点顶边的距离
NODE_REL_Y = 98            # 节点内：第一条关联文字到顶边的距离
NODE_REL_LH = 42           # 节点内：关联文字行距

# 各节点相对核心意象的偏移。三节点的 V 形排布能让三条箭头都保有足够长度——
# 若改用同心环，左右两条箭头会被核心意象和节点本身挤成零长度。
_SLOTS = {
    1: [(0, 700)],
    2: [(-380, 352), (380, 352)],
    3: [(-380, 352), (0, 752), (380, 352)],
}
# 4 个及以上一律走环形：手工排的 4 节点版本（2+2）会让底部两个节点左右重叠，
# 而且节点宽度随关联文字长短变化，手工排布没法自适应。
RING_FROM = 4

# 收尾不放任何声音：那一屏只有字，再来一记盖章声是多余的。
SFX_BY_TYPE = {"hook": "magic.mp3", "core": "bubble-pop.wav",
               "radiate": "bubble-pop.wav"}


# ---------------------------------------------------------------- 时间轴规划

def voice_kwargs(cfg):
    """单集脚本里声明的配音音色。写编号（「1号」~「4号」）或引擎音色名都行。"""
    kw = {"voice": resolve_voice(cfg.get("voice", "Cherry")),
          "model": cfg.get("voice_model", "qwen3-tts-flash")}
    if cfg.get("voice_instructions"):
        kw["instructions"] = cfg["voice_instructions"]
    return kw


def plan(cfg, word_dur, work):
    """按配音实际时长反推每段长度，就地写回 dur / _at，并返回段落起点。"""
    vk = voice_kwargs(cfg)
    starts, clock = [], 0.0
    for si, s in enumerate(cfg["segments"]):
        guard = 0.02 + word_dur + 0.20 if s.get("word_intro") else 0.30
        if s["type"] == "radiate":
            # 关联逻辑与「就是X」分成两段合成：这样"念到第几个字"的时刻是精确的，
            # 逐字高亮才能和语音真正对上，而不是按字数比例估算。
            s["_tts"], needs = [], []
            for k, it in enumerate(s["items"]):
                rel = fetch_tts(it["relation"] + "，", work, f"{si}_{k}_rel", **vk)
                mean = fetch_tts(f"就是{it['meaning']}。", work, f"{si}_{k}_mean", **vk)
                s["_tts"].append((rel, mean))
                needs.append(duration_of(rel) + JOIN_GAP + duration_of(mean))
            s["_rel_dur"] = [duration_of(p[0]) for p in s["_tts"]]
            # 每条念完就上下一条，不做等距。等距要用「最长那条」当统一间隔，
            # 只要有一条被念慢了（TTS 并不稳定：同样 7 个字实测有 1.60s 也有 4.08s），
            # 四条之间的空档会全被它撑开，白拖好几秒。
            at, s["_at"] = LEAD, []
            for need in needs:
                s["_at"].append(at)
                at += need + GAP
            dur = at - GAP + TAIL
        elif s["type"] == "outro":
            s["_tts"] = [fetch_tts(s["say"], work, f"{si}_quote", **vk)]   # 只念金句
            dur = guard + duration_of(s["_tts"][0]) + OUTRO_TAIL
        else:
            s["_tts"] = [fetch_tts(s["say"], work, f"{si}_{s['type']}", **vk)]
            dur = guard + duration_of(s["_tts"][0]) + TAIL
        s["dur"] = s.get("dur") or dur
        starts.append(clock)
        clock += s["dur"]
    return starts, clock


def build_audio(cfg, starts, total, work, word):
    """装配音轨。越界与配音重叠都在这里直接报错，不静默截断。"""
    audio = []
    for si, s in enumerate(cfg["segments"]):
        t0, seg_end = starts[si], starts[si] + s["dur"]
        guard = 0.02 + duration_of(word) + 0.20 if s.get("word_intro") else 0.30
        clips = []
        if s.get("word_intro"):
            clips.append({"path": word, "at": t0 + 0.02, "kind": "word"})

        if s["type"] == "radiate":
            # 每个箭头长出去时各响一声气泡音，给动作打拍子。
            # 这声音只有 0.08s，音量给低了根本听不出来。
            pop = SFX_DIR / SFX_BY_TYPE["radiate"]
            for k, (rel, mean) in enumerate(s["_tts"]):
                at = t0 + s["_at"][k]
                clips.append({"path": rel, "at": at, "kind": "voice"})
                clips.append({"path": mean, "at": at + duration_of(rel) + JOIN_GAP,
                              "kind": "voice"})
                if pop.exists():
                    clips.append({"path": pop, "at": at, "gain": 1.0, "kind": "sfx"})
        else:
            name = SFX_BY_TYPE.get(s["type"])
            sfx = SFX_DIR / name if name else None
            if sfx and sfx.exists():
                clips.append({"path": sfx, "at": t0 + 0.04, "gain": 0.24, "kind": "sfx"})
            if s["_tts"]:
                clips.append({"path": s["_tts"][0], "at": t0 + guard, "kind": "voice"})

        for c in clips:
            if c.get("kind") == "word":
                continue                      # 段首单词发音允许贴着段头
            end = c["at"] + duration_of(c["path"])
            if end > min(seg_end, total) + 0.02:
                raise SystemExit(
                    f"第 {si + 1} 段（{s['type']}）音频超时：{c['path'].name} "
                    f"{c['at']:.2f}s 起播、{end:.2f}s 结束，超出段末 {seg_end:.2f}s。")
        audio.extend(clips)

    voices = sorted((c for c in audio if c.get("kind") == "voice"), key=lambda c: c["at"])
    for a, b in zip(voices, voices[1:]):
        a_end = a["at"] + duration_of(a["path"])
        if b["at"] < a_end - 0.05:
            raise SystemExit(
                f"配音重叠：{a['path'].name} 到 {a_end:.2f}s，但 {b['path'].name} "
                f"{b['at']:.2f}s 就开口了。")
    return audio


# ---------------------------------------------------------------- 画面元素

def _text_w(fnt, text):
    bbox = fnt.getbbox(text)
    return bbox[2] - bbox[0]


_PUNCT = "，。、；：！？）】"


def wrap_cn(text, fnt, max_w):
    """中文按宽度折行：优先在标点后断开，避免把一个词从中间劈开。"""
    chunks, cur = [], ""
    for ch in text:
        cur += ch
        if ch in _PUNCT:
            chunks.append(cur)
            cur = ""
    if cur:
        chunks.append(cur)

    lines, line = [], ""
    for ck in chunks:
        if line and _text_w(fnt, line + ck) > max_w:
            lines.append(line)
            line = ck
        else:
            line += ck
        while _text_w(fnt, line) > max_w and len(line) > 1:   # 单块仍超宽就逐字硬断
            cut = len(line) - 1
            while cut > 1 and _text_w(fnt, line[:cut]) > max_w:
                cut -= 1
            lines.append(line[:cut])
            line = line[cut:]
    if line:
        lines.append(line)
    return lines


def uses_ring(count):
    """节点数 ≥ RING_FROM 时走环形布局。

    节点位置与核心意象位置**必须共用这一个判断**——曾经两处各写一遍（这里写 RING_FROM、
    渲染处写死 5），结果 4 个节点时出现「节点按环形排在 944、核心意象却还留在 V 形的 648」，
    顶部节点直接压住了核心意象。判断只留一处，就不会再错位。
    """
    return count >= RING_FROM


def node_positions(count):
    """把 count 条释义散布在核心意象四周，返回各节点中心坐标。

    ≤4 个走手工排定的 V 形（箭头长度有保证）；≥5 个改用环形均布——
    手工排布在这么多节点下会互相打架，环形至少保证两两不重叠。
    """
    if count in _SLOTS:
        return [(HUB[0] + dx, HUB[1] + dy) for dx, dy in _SLOTS[count]]
    if uses_ring(count):
        return [(HUB[0] + RING_RX * math.cos(math.pi / 2 + 2 * math.pi * i / count),
                 RING_CY + RING_RY * math.sin(math.pi / 2 + 2 * math.pi * i / count))
                for i in range(count)]
    step = math.pi / (count - 1)          # 兜底：沿下半圆均布
    return [(HUB[0] - 380 * math.cos(step * i), HUB[1] + 380 + 320 * math.sin(step * i))
            for i in range(count)]


def node_size(meaning, lines, f_meaning, f_rel):
    w = max(max(_text_w(f_rel, t) for t in lines), _text_w(f_meaning, meaning)) + 76
    return w, 46 + 42 * len(lines) + 34


def _rect_exit(half_w, half_h, ux, uy):
    """沿 (ux,uy) 方向从矩形中心走到边框的距离。"""
    tx = half_w / abs(ux) if abs(ux) > 1e-6 else float("inf")
    ty = half_h / abs(uy) if abs(uy) > 1e-6 else float("inf")
    return min(tx, ty)


def arrow_geometry(node, node_half, art_half, hub=None):
    """箭头贴着核心意象边框外侧起步，精确停在释义节点边框外 14px 处。"""
    hub = hub or HUB
    dx, dy = node[0] - hub[0], node[1] - hub[1]
    dist = math.hypot(dx, dy) or 1.0
    ux, uy = dx / dist, dy / dist
    start = _rect_exit(*art_half, ux, uy) + 12
    reach = _rect_exit(*node_half, ux, uy) + 14
    p0 = (hub[0] + ux * start, hub[1] + uy * start)
    p1 = (node[0] - ux * reach, node[1] - uy * reach)
    ctrl = ((p0[0] + p1[0]) / 2 - uy * ARROW_BEND,
            (p0[1] + p1[1]) / 2 + ux * ARROW_BEND)
    return p0, ctrl, p1


def draw_arrow(d, p0, ctrl, p1, progress, color, width=5):
    """把二次贝塞尔曲线沿 t∈[0, progress] 画出来，末端带箭头。"""
    if progress <= 0.01:
        return
    steps = max(2, int(36 * progress))
    pts = []
    for i in range(steps + 1):
        t = progress * i / steps
        mt = 1 - t
        pts.append((mt * mt * p0[0] + 2 * mt * t * ctrl[0] + t * t * p1[0],
                    mt * mt * p0[1] + 2 * mt * t * ctrl[1] + t * t * p1[1]))
    d.line(pts, fill=color, width=width, joint="curve")
    tip, prev = pts[-1], pts[max(0, len(pts) - 3)]
    ang = math.atan2(tip[1] - prev[1], tip[0] - prev[0])
    head = 22
    d.polygon([tip,
               (tip[0] - head * math.cos(ang - 0.42), tip[1] - head * math.sin(ang - 0.42)),
               (tip[0] - head * math.cos(ang + 0.42), tip[1] - head * math.sin(ang + 0.42))],
              fill=color)


def node_top(cx, cy, size):
    return cx - size[0] / 2, cy - size[1] / 2


def radiate_node_bg(d, cx, cy, size, alpha, accent):
    w, h = size
    x0, y0 = cx - w / 2, cy - h / 2
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=26,
                        fill=(255, 255, 255, int(13 * alpha)),
                        outline=accent + (int(120 * alpha),), width=2)


def radiate_meaning(d, cx, cy, meaning, size, f_meaning, alpha, accent, spoken, pal):
    """释义文字。念到「就是X」时整块点亮并垫一层高亮底。"""
    x0, y0 = node_top(cx, cy, size)
    if spoken:
        mw = _text_w(f_meaning, meaning)
        d.rounded_rectangle([cx - mw / 2 - 22, y0 + NODE_MEAN_Y - 32,
                             cx + mw / 2 + 22, y0 + NODE_MEAN_Y + 32], radius=16,
                            fill=accent + (int(52 * alpha),))
    d.text((cx, y0 + NODE_MEAN_Y), meaning, font=f_meaning,
           fill=(accent if spoken else pal["ink"]) + (int(252 * alpha),), anchor="mm")


def radiate_karaoke(d, cx, cy, lines, offsets, size, text_len, f_rel, alpha,
                    t, t0, spoken_dur, pal):
    """关联逻辑文字逐字点亮：念到第几个字，第几个字就变亮。"""
    x0, y0 = node_top(cx, cy, size)
    done = 0.0
    if spoken_dur > 0:
        done = min(1.0, max(0.0, (t - t0) / spoken_dur)) * text_len
    for li, line in enumerate(lines):
        lw = _text_w(f_rel, line)
        x = cx - lw / 2
        for i, ch in enumerate(line):
            cw = _text_w(f_rel, ch)
            hot = (offsets[li] + i) < done
            d.text((x, y0 + NODE_REL_Y + NODE_REL_LH * li), ch, font=f_rel,
                   fill=(pal["ink"] if hot else pal["ink_faint"]) + (int(alpha),), anchor="lm")
            x += cw


def hook_card(d, cx, y, text, alpha, fnt, pal):
    bbox = fnt.getbbox(text)
    w = (bbox[2] - bbox[0]) + 130
    # 卡片底色 = 主题文字色兑一点透明度：深色主题下是白色薄雾，浅色主题下是黑色薄雾
    d.rounded_rectangle([cx - w / 2, y - 68, cx + w / 2, y + 68], radius=30,
                        fill=pal["ink"] + (int(14 * alpha),),
                        outline=pal["ink_faint"] + (int(130 * alpha),), width=2)
    d.text((cx, y), text, font=fnt, fill=pal["ink"] + (int(248 * alpha),), anchor="mm")


# ---------------------------------------------------------------- 渲染

def render(cfg, core_art, audio, out_path, bgm_path, starts, total, quiet=False):
    accent = hex2rgb(cfg.get("accent", "#6EE7B7"))
    pal = THEMES[cfg.get("theme", "dark")]
    bg = make_background(accent, cfg.get("theme", "dark"))
    segments = cfg["segments"]

    f_series = font(FONT_CN, 32, FONT_CN_REG)
    f_idx = font(FONT_LATIN, 38, FONT_LATIN_MED)
    f_small = font(FONT_CN, 34, FONT_CN_REG)
    f_label = font(FONT_CN, 40, FONT_CN_REG)
    f_word_hdr = fit_font(cfg["word"], FONT_EN, FONT_EN_NUM, 88, W - 200)
    f_phon_hdr = font(FONT_IPA, 38)
    f_hook = font(FONT_CN, 96, FONT_CN_BOLD)
    f_core_cn = font(FONT_CN, 78, FONT_CN_BOLD)
    f_meaning = font(FONT_CN, 56, FONT_CN_BOLD)
    f_rel = font(FONT_CN, 30, FONT_CN_REG)

    n_items = max((len(sg["items"]) for sg in segments if sg["type"] == "radiate"), default=0)
    many = uses_ring(n_items)
    art_ring = core_art.copy()
    art_ring.thumbnail((ART_BOX_MANY if many else ART_BOX,) * 2, Image.LANCZOS)
    node_max_w = NODE_MAX_W_MANY if many else NODE_MAX_W
    art_hook = core_art.copy()
    art_hook.thumbnail((HOOK_ART, HOOK_ART), Image.LANCZOS)

    layers_by_seg = []
    for s in segments:
        L, dur = [], s["dur"]
        kind = s["type"]

        if kind == "hook":
            line = s["line"]
            L.append(ImageLayer(art_hook, (W / 2, HOOK_ART_Y), 0.0, dur=3.4,
                                scale_from=0.93, glow=accent + (60,), fade_in=False))
            cards = s["cards"]
            if len(cards) <= 3:                       # 三张以内沿用竖排
                L.append(Layer(lambda d, e, dy, t=cards[0]: d.text(
                    (W / 2, 0 + dy), "", font=f_small,
                    fill=pal["ink_dim"] + (0,), anchor="mm"), -1.0, dur=0.4))
                for i, text in enumerate(cards):
                    L.append(Layer(lambda d, e, dy, t=text, y=HOOK_CARD_Y + HOOK_CARD_GAP * i:
                                   hook_card(d, W / 2, y + dy, t, e, f_hook, pal),
                                   -1.0, dur=0.4, rise=0))
            else:                                     # 四张以上改用网格
                per_row = 3 if len(cards) >= 5 else 2  # 4 张排成 2+2，3+1 会很不平衡
                rows = [cards[i:i + per_row] for i in range(0, len(cards), per_row)]
                f_grid = font(FONT_CN, 68, FONT_CN_BOLD)
                for r, row in enumerate(rows):
                    for c, text in enumerate(row):
                        x = W / 2 + (c - (len(row) - 1) / 2) * HOOK_GRID_COL
                        y = HOOK_GRID_Y + r * HOOK_GRID_ROW
                        L.append(Layer(lambda d, e, dy, t=text, xx=x, yy=y:
                                       hook_card(d, xx, yy + dy, t, e, f_grid, pal),
                                       -1.0, dur=0.4, rise=0))
            L.append(Layer(lambda d, e, dy, t=line: d.text(
                (W / 2, HOOK_LINE_Y + dy), t, font=f_small,
                fill=pal["ink_dim"] + (int(240 * e),), anchor="mm"), 1.30, dur=0.55))

        elif kind == "core":
            core_label, core_text = "核心意象", cfg["core_text"]
            sub = cfg["core_sub"]
            L.append(ImageLayer(core_art, (W / 2, 740), 0.10, dur=0.85,
                                rise=26, scale_from=0.82, glow=accent + (90,)))
            L.append(Layer(lambda d, e, dy, t=core_label: d.text(
                (W / 2, 1130 + dy), t, font=f_label,
                fill=pal["ink_dim"] + (int(245 * e),), anchor="mm"), dur * 0.36, dur=0.5))
            L.append(Layer(lambda d, e, dy, t=core_text: d.text(
                (W / 2, 1250 + dy), t, font=f_core_cn,
                fill=accent + (int(255 * e),), anchor="mm"), dur * 0.36 + 0.15, dur=0.55, rise=30))
            L.append(Layer(lambda d, e, dy, t=sub: d.text(
                (W / 2, 1390 + dy), t, font=f_small,
                fill=pal["ink_faint"] + (int(235 * e),), anchor="mm"), dur * 0.62, dur=0.55))

        elif kind == "radiate":
            items = s["items"]
            nodes = node_positions(len(items))
            # 核心意象常驻中心，释义绕它一圈，箭头从中心逐条长出去
            ring = uses_ring(len(items))
            hub_pt = (HUB[0], RING_CY) if ring else HUB
            L.append(ImageLayer(art_ring, hub_pt, 0.05, dur=0.45, glow=accent + (70,)))
            for i, item in enumerate(items):
                node = nodes[i]
                lines = wrap_cn(item["relation"], f_rel, node_max_w)
                offsets, acc_len = [], 0
                for ln in lines:
                    offsets.append(acc_len)
                    acc_len += len(ln)
                size = node_size(item["meaning"], lines, f_meaning, f_rel)
                p0, ctrl, p1 = arrow_geometry(node, (size[0] / 2, size[1] / 2),
                                              (art_ring.width / 2, art_ring.height / 2), hub=hub_pt)
                at = s["_at"][i]
                rel_dur = s["_rel_dur"][i]
                mean_at = at + rel_dur + JOIN_GAP
                L.append(Layer(lambda d, e, dy, a=p0, c=ctrl, b=p1: draw_arrow(
                    d, a, c, b, e, accent + (235,)), at, dur=0.45, rise=0))
                L.append(Layer(lambda d, e, dy, nd=node, sz=size: radiate_node_bg(
                    d, nd[0], nd[1] + dy, sz, e, accent), at, dur=0.42, rise=26))
                # at / rel_dur / mean_at 必须用默认参数绑死：它们是循环变量，
                # 晚绑定会让所有节点的逐字高亮都按最后一条的时间走（表现为完全不高亮）。
                L.append(TimedLayer(lambda d, e, dy, t, it=item, nd=node, sz=size, mt=mean_at:
                                    radiate_meaning(d, nd[0], nd[1] + dy, it["meaning"],
                                                    sz, f_meaning, e, accent,
                                                    t >= mt, pal),
                                    at, dur=0.42, rise=26))
                L.append(TimedLayer(lambda d, e, dy, t, ln=lines, off=offsets, nd=node, sz=size,
                                    txt=item["relation"], t0=at, rd=rel_dur:
                                    radiate_karaoke(d, nd[0], nd[1] + dy, ln, off, sz,
                                                    len(txt), f_rel, 245 * e,
                                                    t, t0, rd, pal),
                                    at, dur=0.42, rise=26))

        elif kind == "outro":
            rows = s["line"].split("\n")
            ask, cta = s["ask"], s["cta"]
            f_q = fit_font(max(rows, key=len), FONT_CN, FONT_CN_BOLD, 88, W - 170)
            f_ask = fit_font(ask, FONT_CN, FONT_CN_BOLD, 58, W - 170)
            art_outro = core_art.copy()
            art_outro.thumbnail((OUTRO_ART, OUTRO_ART), Image.LANCZOS)
            L.append(ImageLayer(art_outro, (W / 2, OUTRO_ART_Y), OUTRO_AT,
                                dur=OUTRO_FADE, glow=accent + (80,)))
            for i, txt in enumerate(rows):
                y = OUTRO_QUOTE_Y + (i - (len(rows) - 1) / 2) * 122
                L.append(Layer(lambda d, e, dy, t=txt, yy=y: d.text(
                    (W / 2, yy + dy), t, font=f_q,
                    fill=accent + (int(255 * e),), anchor="mm"), OUTRO_AT, dur=OUTRO_FADE, rise=0))
            L.append(Layer(lambda d, e, dy, t=ask: d.text(
                (W / 2, OUTRO_ASK_Y + dy), t, font=f_ask,
                fill=pal["ink"] + (int(250 * e),), anchor="mm"), OUTRO_AT, dur=OUTRO_FADE, rise=0))
            L.append(Layer(lambda d, e, dy, t=cta: teaser_chip(
                d, W / 2, OUTRO_CHIP_Y + dy, t, f_small, e, pal["ink"]), OUTRO_AT, dur=OUTRO_FADE))
        layers_by_seg.append(L)

    def draw_chrome(img, t):
        d = ImageDraw.Draw(img)
        d.text((80, 146), f"{cfg['series']} · {cfg['episode']}", font=f_series,
               fill=pal["ink_faint"], anchor="lm")
        d.text((W - 80, 146), cfg.get("position", ""), font=f_idx,
               fill=pal["ink_faint"], anchor="rm")
        # 单词拼写与音标全集常驻：封面取第一帧，这里必须是全不透明
        d.text((W / 2, WORD_Y), cfg["word"], font=f_word_hdr,
               fill=pal["ink"] + (240,), anchor="mm")
        d.text((W / 2, PHON_Y), cfg["phonetic"], font=f_phon_hdr,
               fill=pal["phon"] + (220,), anchor="mm")

        # 不画进度条，也不画百分比：小红书播放页底部本来就有一条进度条，
        # 再画一条是重复，而且两条离得近会互相打架。底部只留标语。
        d.text((W / 2, SLOGAN_Y), cfg["slogan"], font=f_small,
               fill=pal["ink_faint"], anchor="mm")

    n_frames = int(round(total * FPS))

    def frames():
        for f in range(n_frames):
            t = f / FPS
            seg = max(i for i, st in enumerate(starts) if t >= st)
            img = bg.copy()
            for lay in layers_by_seg[seg]:
                lay.render(img, t - starts[seg])
            draw_chrome(img, t)
            yield img.convert("RGB").tobytes()

    encode_video(frames(), n_frames, total, audio, out_path, bgm_path, quiet=quiet)
    return total


# ---------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("episode_json")
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-bgm", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--to-photos", action="store_true",
                    help="出片后直接导入 macOS「照片」，开 iCloud 即同步到手机相册")
    args = ap.parse_args()

    cfg = json.loads(Path(args.episode_json).read_text(encoding="utf-8"))
    ep = cfg["episode"]
    work = TMP_DIR / ep / "audio"
    work.mkdir(parents=True, exist_ok=True)

    art_path = Path(cfg["core_art"])
    if not art_path.is_absolute():
        art_path = CORE_IMG_DIR / art_path
    if not art_path.exists():
        raise SystemExit(f"找不到词核心图：{art_path}")
    core_art = load_line_art(art_path, box=620, theme=cfg.get("theme", "dark"))
    vk = voice_kwargs(cfg)
    print(f"· {ep} 《{cfg['series']}》 {cfg['word']} = {cfg['core_text']}"
          f"（词核心图 {core_art.width}×{core_art.height}）")
    print(f"· 配音音色：{vk['voice']}（{vk['model']}"
          f"{'，带语气指令' if 'instructions' in vk else ''}）")

    word = fetch_word_audio(cfg["word"], work / f"{cfg['word']}.mp3")
    starts, total = plan(cfg, duration_of(word), work)
    print(f"· 时长按配音自动反推：合计 {total:.1f}s")
    audio = build_audio(cfg, starts, total, work, word)
    if not args.quiet:
        for s, st in zip(cfg["segments"], starts):
            print(f"    [{s['type']:7}] {st:5.2f}s → {st + s['dur']:5.2f}s  ({s['dur']:.2f}s)")
        for c in sorted(audio, key=lambda c: c["at"]):
            print(f"      {c['at']:6.2f}s → {c['at'] + duration_of(c['path']):6.2f}s  {c['path'].name}")

    # 默认不配乐：垫乐只留人声与音效，听感更干净。想要垫乐就在单集脚本里写 music 字段。
    bgm = None
    if cfg.get("music") and not args.no_bgm:
        music = resolve_music(cfg["music"])
        tag = hashlib.md5(json.dumps(music, sort_keys=True).encode()).hexdigest()[:8]
        bgm = synth_bgm(TMP_DIR / ep / f"bgm_{tag}.wav", total + 0.5, profile=music)
        if not args.quiet:
            print(f"· 配乐：{cfg['music']} → {music}")
    elif not args.quiet:
        print("· 配乐：无（只保留人声与箭头音效）")
    out = Path(args.out) if args.out else OUT_DIR / f"{ep}_{cfg['word']}_core.mp4"
    out.parent.mkdir(parents=True, exist_ok=True)
    render(cfg, core_art, audio, out, bgm, starts, total, quiet=args.quiet)
    print(f"✅ 成片 {out}  时长 {total:.1f}s  大小 {out.stat().st_size / 1024 / 1024:.1f}MB")
    if args.to_photos:
        n = import_to_photos([out])
        print(f"📱 已导入「照片」专辑「{PHOTO_ALBUM}」：{n} 项")


if __name__ == "__main__":
    main()
